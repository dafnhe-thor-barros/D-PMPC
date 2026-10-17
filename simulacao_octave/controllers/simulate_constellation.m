function sim_results = simulate_constellation(p, t_vec, mode, regime)
% SIMULATE_CONSTELLATION - Simulador em Malha Fechada da Constelação Orbital
% Executa a propagação física temporal completa das equações de estado acopladas:
%   - Órbita e Geometria 3D de Eclipse (EQ-01 a EQ-08)
%   - Modelo Fotovoltaico e Balanço de Barramento HVDC (EQ-09 a EQ-10)
%   - EDO Eletroquímica de Bateria e Envelhecimento (EQ-11 a EQ-16)
%   - EDO Térmica Não-Linear com Stefan-Boltzmann e LHP (EQ-17 a EQ-20)
%   - Rede Óptica OISL e Fator de Carga dos Enlaces (EQ-21 a EQ-22)
%   - Conservação de Tarefas e Filas Neurais (EQ-23)
%   - Controlador D-PMPC via ADMM ou Linha de Base Autônoma
%
% Entradas:
%   p      - Estrutura de parâmetros (parameters.m)
%   t_vec  - Vetor de tempo de simulação [s] (ex: 0:10:(5*tau))
%   mode   - 'dpmpc' (cooperativo) ou 'uncoordinated' (linha de base autônoma)
%   regime - 'max_eclipse' (padrão), 'intermediate' ou 'full_sun'
%
% Saída:
%   sim_results - Estrutura completa com séries temporais e métricas consolidadas

if nargin < 3 || isempty(mode)
    mode = 'dpmpc';
end
if nargin < 4 || isempty(regime)
    regime = 'max_eclipse';
end

N_t   = length(t_vec);
dt    = t_vec(2) - t_vec(1);
N_sat = p.orbit.N_sat;
H     = p.mpc.H;

% 1. Propagação orbital global e rede física de enlaces OISL
orbit_data   = orbit_model(p, t_vec);
eclipse_data = eclipse_model(p, orbit_data, regime);
solar_data   = solar_power_model(p, eclipse_data.xi);
oisl_data    = oisl_network_model(p, orbit_data, dt);

% 2. Capacidade nominal de bateria de acordo com a arquitetura
if strcmpi(mode, 'uncoordinated')
    E_nom_active = p.battery.E_nom_base; % 250 kWh (900 MJ) na linha de base
    E_nom_kWh    = p.battery.E_nom_base_kWh;
else
    E_nom_active = p.battery.E_nom;      % 125 kWh (450 MJ) no D-PMPC cooperativo
    E_nom_kWh    = p.battery.E_nom_kWh;
end

% 3. Alocação de matrizes de estados e variáveis de saída [N_t x N_sat]
P_comp_log   = zeros(N_t, N_sat);
P_pv_used_log= zeros(N_t, N_sat);
P_curtail_log= zeros(N_t, N_sat);
P_b_log      = zeros(N_t, N_sat);
P_oisl_log   = zeros(N_t, N_sat);
SoC_log      = zeros(N_t, N_sat);
T_j_log      = zeros(N_t, N_sat);
T_rad_log    = zeros(N_t, N_sat);
A_rad_log    = zeros(N_t, N_sat);
W_log        = zeros(N_t, N_sat);

% Logs específicos de OISL e ADMM
tx_rate_log  = zeros(N_t, N_sat); % Throughput total TX por satélite [bps]
rx_rate_log  = zeros(N_t, N_sat); % Throughput total RX por satélite [bps]
admm_iter_log= zeros(N_t, 1);
admm_time_log= zeros(N_t, 1);

% 4. Condições Iniciais Físicas
SoC_curr   = ones(1, N_sat);            % 100% SoC inicial
T_j_curr   = p.thermal.T_j_target * ones(1, N_sat); % 65.0 °C (338.15 K)
T_rad_curr = p.thermal.T_rad_nom * ones(1, N_sat);  % 63.85 °C (337.0 K)
A_rad_curr = p.thermal.A_rad_eff * ones(1, N_sat);  % 228.4 m^2 inicial
W_curr = (p.workload.A_avg * 0.042) * ones(1, N_sat); % 1.008e15 FLOPs (42.0 ms de backlog nominal)

% Gravação inicial
SoC_log(1, :)   = SoC_curr;
T_j_log(1, :)   = T_j_curr;
T_rad_log(1, :) = T_rad_curr;
A_rad_log(1, :) = A_rad_curr;
W_log(1, :)     = W_curr;

admm_state = [];

% Constantes auxiliares
C_total   = p.thermal.C_th_rad + p.thermal.C_th_j; % Capacitância térmica total do sistema [J/K]
R_th      = p.thermal.R_th_j_rad;
eps_sigma = p.thermal.epsilon_rad * p.const.sigma_SB;
T_space4  = p.const.T_space^4;
tau_valve = 30.0; % Constante de tempo das válvulas de bypass (UNRES-04)
h_sub     = dt / 4.0;
alpha_v   = 1.0 - exp(-h_sub / tau_valve);

inv_Ctotal = 1.0 / C_total;

gamma_comp = p.workload.gamma_comp;
alpha_task = p.workload.alpha_task;
A_avg      = p.workload.A_avg;
eta_conv   = p.solar.eta_conv;
eta_dis    = p.battery.eta_dis;
eta_chg    = p.battery.eta_chg;
P_bus      = p.eps.P_bus;

% 5. Laço Principal de Simulação Temporal em Malha Fechada
for k = 1:(N_t - 1)
    xi_now = eclipse_data.xi(k, :);
    
    % --- DETERMINAÇÃO DAS AÇÕES DE CONTROLE ---
    if strcmpi(mode, 'dpmpc')
        % Montar predição orbital para os próximos H passos
        k_end = min(k + H - 1, N_t);
        H_act = k_end - k + 1;
        
        orbit_pred.xi = eclipse_data.xi(k:k_end, :);
        orbit_pred.P_pv_avail = solar_data.P_pv_avail(k:k_end, :);
        
        if H_act < H
            deficit = H - H_act;
            orbit_pred.xi = [orbit_pred.xi; eclipse_data.xi(1:deficit, :)];
            orbit_pred.P_pv_avail = [orbit_pred.P_pv_avail; solar_data.P_pv_avail(1:deficit, :)];
        end
        
        state_curr.SoC   = SoC_curr;
        state_curr.T_j   = T_j_curr;
        state_curr.T_rad = T_rad_curr;
        state_curr.W     = W_curr;
        
        [ctrl, diag] = dpmpc_controller(p, state_curr, orbit_pred, oisl_data, admm_state);
        admm_state = ctrl.admm_state;
        
        P_comp_step = ctrl.P_comp;
        x_out_step  = ctrl.x_out_bps;
        x_in_step   = ctrl.x_in_bps;
        
        admm_iter_log(k) = diag.iterations;
        admm_time_log(k) = diag.solve_time_ms;
    else
        % Linha de base autônoma: computação constante em 100 kW sem migração OISL
        P_comp_step = repmat(p.eps.P_comp_nom, 1, N_sat);
        x_out_step  = zeros(N_sat, 4);
        x_in_step   = zeros(N_sat, 4);
    end
    
    P_comp_log(k, :) = P_comp_step;
    tx_rate_log(k, :) = sum(x_out_step, 2)';
    rx_rate_log(k, :) = sum(x_in_step, 2)';
    
    % --- SUBSISTEMA DE COMUNICAÇÃO ÓPTICA (EQ-21) ---
    P_oisl_step = 4.0 * (p.oisl.P_pat + p.oisl.P_laser_tx) + p.oisl.kappa_comm * sum(x_out_step, 2)';
    P_oisl_log(k, :) = P_oisl_step;
    
    % --- BALANÇO DE BARRAMENTO HVDC E BATERIA (EQ-10 a EQ-12) ---
    P_pv_avail_step = solar_data.P_pv_avail(k, :);
    P_bus_net_step  = eta_conv * P_pv_avail_step;
    P_load_step     = P_comp_step + P_oisl_step + P_bus;
    
    P_b_unconstrained = P_load_step - P_bus_net_step;
    
    P_b_step       = zeros(1, N_sat);
    P_curtail_step = zeros(1, N_sat);
    P_pv_used_step = zeros(1, N_sat);
    dSoC_dt        = zeros(1, N_sat);
    
    for s = 1:N_sat
        if P_b_unconstrained(s) >= 0.0
            % Modo Descarga
            P_b_step(s)       = P_b_unconstrained(s);
            P_pv_used_step(s) = P_pv_avail_step(s);
            P_curtail_step(s) = 0.0;
            dSoC_dt(s) = - (P_b_step(s) / eta_dis) / E_nom_active;
        else
            % Modo Carga
            P_surplus = -P_b_unconstrained(s);
            if SoC_curr(s) < 1.0
                P_b_step(s) = -P_surplus;
                dSoC_dt(s)  = (P_surplus * eta_chg) / E_nom_active;
                P_pv_used_step(s) = P_load_step(s) / eta_conv + (P_surplus / eta_conv);
                P_curtail_step(s) = max(0.0, P_pv_avail_step(s) - P_pv_used_step(s));
            else
                % Bateria em 100% SoC
                P_b_step(s)       = 0.0;
                dSoC_dt(s)        = 0.0;
                P_pv_used_step(s) = P_load_step(s) / eta_conv;
                P_curtail_step(s) = max(0.0, P_pv_avail_step(s) - P_pv_used_step(s));
            end
        end
    end
    
    P_b_log(k, :)       = P_b_step;
    P_pv_used_log(k, :) = P_pv_used_step;
    P_curtail_log(k, :) = P_curtail_step;
    
    % Integração do SoC (com saturação física em [0, 1])
    SoC_curr = max(0.0, min(1.0, SoC_curr + dSoC_dt * dt));
    SoC_log(k + 1, :) = SoC_curr;
    
    % --- CONSERVAÇÃO DE TAREFAS NA FILA (EQ-23) ---
    dW_proc = (P_comp_step / gamma_comp) * dt;
    dW_arr  = A_avg * dt;
    dW_mig  = alpha_task * (sum(x_in_step, 2)' - sum(x_out_step, 2)') * dt;
    
    W_curr = max(0.0, W_curr - dW_proc + dW_arr + dW_mig);
    W_log(k + 1, :) = W_curr;
    
    % --- SUBSISTEMA TÉRMICO NÃO-LINEAR COM STEFAN-BOLTZMANN (EQ-17 e EQ-18) ---
    if strcmpi(mode, 'dpmpc')
        % Estagiamento LHP passivo termostático:
        % O condensador só estagia para A_rad_stage (58.5 m^2) se em eclipse COM carga baixa (P_comp <= 35 kW).
        % Se a potência computacional for elevada (> 35 kW) ou em luz solar (xi == 1),
        % as válvulas de bypass abrem para rejeitar o excesso de calor dissipado.
        is_low_pwr_ecl = (xi_now == 0) & (P_comp_step <= 35.0e3);
        A_target_step = p.thermal.A_rad_stage .* is_low_pwr_ecl + ...
            p.thermal.A_rad_eff .* (~is_low_pwr_ecl);
    else
        A_target_step = repmat(p.thermal.A_rad_eff, 1, N_sat);
    end
    
    Q_env_step = p.thermal.Q_env_ecl + ...
        (p.thermal.Q_env_sun - p.thermal.Q_env_ecl) .* (xi_now == 1);
    
    trad = T_rad_curr;
    ar   = A_rad_curr;
    
    % Integração RK4 do radiador (capacitância combinada C_total)
    for sub = 1:4
        ar = ar + (A_target_step - ar) * alpha_v;
        
        dtrad1 = (P_comp_step + Q_env_step - eps_sigma .* ar .* (trad.^4 - T_space4)) * inv_Ctotal;
        
        trad2  = trad + 0.5 * h_sub * dtrad1;
        dtrad2 = (P_comp_step + Q_env_step - eps_sigma .* ar .* (trad2.^4 - T_space4)) * inv_Ctotal;
        
        trad3  = trad + 0.5 * h_sub * dtrad2;
        dtrad3 = (P_comp_step + Q_env_step - eps_sigma .* ar .* (trad3.^4 - T_space4)) * inv_Ctotal;
        
        trad4  = trad + h_sub * dtrad3;
        dtrad4 = (P_comp_step + Q_env_step - eps_sigma .* ar .* (trad4.^4 - T_space4)) * inv_Ctotal;
        
        trad   = trad + (h_sub / 6.0) * (dtrad1 + 2.0*dtrad2 + 2.0*dtrad3 + dtrad4);
    end
    
    T_rad_curr = trad;
    A_rad_curr = ar;
    % Quasi-equilíbrio térmico da junção (LHP de acoplamento rápido tau = 0.326 s)
    T_j_curr   = T_rad_curr + P_comp_step * R_th;
    
    T_j_log(k + 1, :)   = T_j_curr;
    T_rad_log(k + 1, :) = T_rad_curr;
    A_rad_log(k + 1, :) = A_rad_curr;
end

% Preencher último passo das variáveis instantâneas
P_comp_log(end, :)   = P_comp_log(end - 1, :);
P_pv_used_log(end, :)= P_pv_used_log(end - 1, :);
P_curtail_log(end, :)= P_curtail_log(end - 1, :);
P_b_log(end, :)      = P_b_log(end - 1, :);
P_oisl_log(end, :)   = P_oisl_log(end - 1, :);
tx_rate_log(end, :)  = tx_rate_log(end - 1, :);
rx_rate_log(end, :)  = rx_rate_log(end - 1, :);

% 6. Métricas Finais Consolidadas
sim_results.time_s     = t_vec;
sim_results.time_min   = t_vec / 60.0;
sim_results.time_hours = t_vec / 3600.0;
sim_results.mode       = mode;

sim_results.P_comp     = P_comp_log;
sim_results.P_b        = P_b_log;
sim_results.P_pv_avail = solar_data.P_pv_avail;
sim_results.P_pv_used  = P_pv_used_log;
sim_results.P_curtail  = P_curtail_log;
sim_results.P_oisl     = P_oisl_log;
sim_results.tx_rate    = tx_rate_log;
sim_results.rx_rate    = rx_rate_log;

sim_results.SoC        = SoC_log;
sim_results.SoC_min    = min(SoC_log(:));
sim_results.DoD_max    = 1.0 - sim_results.SoC_min;

% Vida útil estimada da bateria (EQ-16 calibrada)
N_ref   = p.battery.N_ref;
DoD_ref = p.battery.DoD_ref;
v_eff   = p.battery.v_eff;
k_cal   = p.battery.k_cal;

cycles_per_year = 365.25 * 24.0 * 3600.0 / p.orbit.tau; % ~5500 ciclos/ano
N_cycles_model = N_ref * ((DoD_ref / max(0.01, sim_results.DoD_max))^v_eff);
life_cycle_yr = N_cycles_model / cycles_per_year;

% Retenção de capacidade após 10 anos (EQ-13 a EQ-16)
delta_C_cyc_10yr = (10.0 * cycles_per_year / N_cycles_model) * 0.20;
delta_C_cal_10yr = k_cal * sqrt(10.0);
cap_retention_10yr = max(0.0, 1.0 - (delta_C_cyc_10yr + delta_C_cal_10yr));

sim_results.N_cycles           = N_cycles_model;
sim_results.battery_life_years = life_cycle_yr;
sim_results.capacity_retention_10yr = cap_retention_10yr;

% Métricas térmicas
sim_results.T_j          = T_j_log;
sim_results.T_j_degC     = T_j_log - 273.15;
sim_results.T_rad        = T_rad_log;
sim_results.T_rad_degC   = T_rad_log - 273.15;
sim_results.A_rad        = A_rad_log;
sim_results.T_j_max_degC = max(sim_results.T_j_degC(:));
sim_results.T_j_min_degC = min(sim_results.T_j_degC(:));
sim_results.delta_T_j    = sim_results.T_j_max_degC - sim_results.T_j_min_degC;

% Filas de trabalho
sim_results.W            = W_log;
sim_results.W_max        = max(W_log(:));

% Eficiência de colheita solar formal (EQ-34)
total_solar_avail = sum(sum(solar_data.P_pv_avail)) * dt;
total_solar_used  = sum(sum(P_pv_used_log)) * dt;
sim_results.eta_harv = (total_solar_used / total_solar_avail) * 100.0;

% Decomposição de Latência (EQ-33)
% T_lat = T_queue + T_prop + T_tx + T_exec
mean_queue_flops = mean(W_log(:));
T_queue_ms = (mean_queue_flops / (mean(P_comp_log(:)) / gamma_comp)) * 1000.0;
T_prop_ms  = oisl_data.tau_prop_2hop * 1000.0; % 22.40 ms
T_tx_ms    = 15.60; % ms
T_exec_ms  = 135.0; % ms
sim_results.latency.T_queue = T_queue_ms;
sim_results.latency.T_prop  = T_prop_ms;
sim_results.latency.T_tx    = T_tx_ms;
sim_results.latency.T_exec  = T_exec_ms;
sim_results.latency.T_total = T_queue_ms + T_prop_ms + T_tx_ms + T_exec_ms;

sim_results.admm_diagnostics.mean_iter = mean(admm_iter_log(admm_iter_log > 0));
sim_results.admm_diagnostics.mean_time_ms = mean(admm_time_log(admm_time_log > 0));

% 7. Decomposição e Métricas por Órbita (para análise multi-órbita de 1 a N_orbits)
tau_s = p.orbit.tau;
N_orbits = max(1, round(t_vec(end) / tau_s));
orbit_metrics = struct();

for o = 1:N_orbits
    t_start_o = (o - 1) * tau_s;
    t_end_o   = o * tau_s;
    idx_o = find(t_vec >= t_start_o & t_vec <= t_end_o);
    if isempty(idx_o), continue; end
    
    orbit_metrics(o).orbit_idx       = o;
    orbit_metrics(o).SoC_min         = min(min(SoC_log(idx_o, :)));
    orbit_metrics(o).DoD_max         = 1.0 - orbit_metrics(o).SoC_min;
    orbit_metrics(o).SoC_end_min     = min(SoC_log(idx_o(end), :));
    orbit_metrics(o).SoC_end_mean    = mean(SoC_log(idx_o(end), :));
    orbit_metrics(o).T_j_max_degC    = max(max(sim_results.T_j_degC(idx_o, :)));
    orbit_metrics(o).T_j_min_degC    = min(min(sim_results.T_j_degC(idx_o, :)));
    orbit_metrics(o).W_max           = max(max(W_log(idx_o, :)));
    
    % Balanço de energia por satélite na órbita [kWh]
    E_dis_kWh = sum(max(0, P_b_log(idx_o, :)), 1) * (dt / 3600.0) / 1000.0;
    E_chg_kWh = sum(max(0, -P_b_log(idx_o, :)), 1) * (dt / 3600.0) / 1000.0;
    orbit_metrics(o).E_dis_mean_kWh  = mean(E_dis_kWh);
    orbit_metrics(o).E_chg_mean_kWh  = mean(E_chg_kWh);
    orbit_metrics(o).E_net_mean_kWh  = mean(E_chg_kWh) - mean(E_dis_kWh);
end

sim_results.N_orbits = N_orbits;
sim_results.orbit_metrics = orbit_metrics;
sim_results.regime = regime;

% 8. Diagnóstico de Esgotamento / Blackout de Bateria
is_depleted = any(SoC_log(:) <= 0.01);
sim_results.depleted = is_depleted;
if is_depleted
    [t_dep_idx, sat_dep] = find(SoC_log <= 0.01, 1, 'first');
    sim_results.depletion_time_min = t_vec(t_dep_idx) / 60.0;
    sim_results.depletion_orbit    = ceil(t_vec(t_dep_idx) / tau_s);
    sim_results.depletion_sat      = sat_dep;
else
    sim_results.depletion_time_min = Inf;
    sim_results.depletion_orbit    = Inf;
    sim_results.depletion_sat      = NaN;
end

end
