function batt_data = battery_model(p, P_load, P_bus_net, dt, SoC_init, E_nom)
% BATTERY_MODEL - Modelo eletroquímico e dinâmico de armazenamento de energia (BESS),
% balanço de potência no barramento HVDC e degradação de capacidade (LFP/NMC).
%
% Entradas:
%   p         - Estrutura de parâmetros do sistema (parameters.m)
%   P_load    - Demanda elétrica total dos nós [W] [N_t x N_sat] (P_comp + P_oisl + P_bus)
%   P_bus_net - Geração solar líquida disponível no barramento [W] [N_t x N_sat]
%   dt        - Passo de integração temporal [s]
%   SoC_init  - [Opcional] Estado de carga inicial [1 x N_sat] ou escalar (padrão: 1.0)
%   E_nom     - [Opcional] Capacidade nominal da bateria [J] (padrão: p.battery.E_nom)
%
% Saídas (estrutura batt_data):
%   .SoC                - Trajetória temporal do Estado de Carga [N_t x N_sat]
%   .P_b                - Potência nos terminais da bateria [W] (+ descarga, - carga)
%   .P_curtail          - Potência solar excedente descartada/curtailed [W]
%   .DoD                - Profundidade de descarga por ciclo [1 x N_sat] (fração)
%   .DoD_pct            - Profundidade de descarga por ciclo [%]
%   .SoC_min            - Estado de carga mínimo atingido [1 x N_sat]
%   .SoC_max            - Estado de carga máximo atingido [1 x N_sat]
%   .N_cycles           - Vida útil admissível em ciclos até 80% EOL (Eq. 16)
%   .life_years_cyclic  - Vida cíclica projetada em anos (sem envelhecimento temporal)
%   .loss_cal_10yr      - Perda de capacidade de calendário em 10 anos (Eq. 14)
%   .loss_cyc_10yr      - Perda cíclica acumulada ao longo de 10 anos
%   .retention_10yr     - Retenção de capacidade após 10 anos (superposição total)
%   .energy_balance_err - Erro absoluto de conservação de energia no barramento [W]

[N_t, N_sat] = size(P_load);

if nargin < 4 || isempty(dt)
    dt = p.mpc.dt;
end

if nargin < 5 || isempty(SoC_init)
    SoC_init = repmat(p.battery.SoC_init, 1, N_sat);
elseif isscalar(SoC_init)
    SoC_init = repmat(SoC_init, 1, N_sat);
end

if nargin < 6 || isempty(E_nom)
    E_nom = p.battery.E_nom; % [J]
end

eta_dis = p.battery.eta_dis;
eta_chg = p.battery.eta_chg;

% Alocação de memória
SoC = zeros(N_t, N_sat);
P_b = zeros(N_t, N_sat);
P_curtail = zeros(N_t, N_sat);

SoC(1, :) = SoC_init;

% Integração temporal de Coulomb counting com limites de saturação física
for k = 1:(N_t - 1)
    % Demanda líquida no barramento HVDC (Convenção: + déficit/descarga, - excedente/carga)
    P_dem = P_load(k, :) - P_bus_net(k, :);
    
    for s = 1:N_sat
        p_dem_s = P_dem(s);
        soc_curr = SoC(k, s);
        
        if p_dem_s >= 0.0
            % Regime de DESCARGA (fornecimento de energia para suprir déficit solar)
            % Potência exigida das células químicas internas:
            p_cell = p_dem_s / eta_dis;
            
            % Variação de SoC:
            d_soc = - (p_cell * dt) / E_nom;
            
            % Verificação de corte por limite mínimo (depleção completa):
            if (soc_curr + d_soc) < 0.0
                % Bateria esgotada: entrega apenas o residual disponível
                p_cell_max = (soc_curr * E_nom) / dt;
                p_b_delivered = p_cell_max * eta_dis;
                d_soc = -soc_curr;
                P_b(k, s) = p_b_delivered;
            else
                P_b(k, s) = p_dem_s;
            end
            
            P_curtail(k, s) = 0.0;
            SoC(k + 1, s) = max(soc_curr + d_soc, 0.0);
            
        else
            % Regime de RECARGA (absorção de excedente fotovoltaico)
            p_surplus = -p_dem_s; % [W] Potência excedente disponível no barramento
            
            % Energia máxima que a bateria aceita até atingir 100% de SoC:
            e_room = (1.0 - soc_curr) * E_nom; % [J]
            p_chg_cell_max = e_room / (eta_chg * dt); % [W]
            
            % Potência real absorvida nos terminais:
            p_chg_term = min(p_surplus, p_chg_cell_max);
            
            % Potência química injetada nas células:
            p_chem = p_chg_term * eta_chg;
            d_soc = + (p_chem * dt) / E_nom;
            
            P_b(k, s) = -p_chg_term;
            % Excedente solar que não cabe na bateria é descartado/curtailed:
            P_curtail(k, s) = p_surplus - p_chg_term;
            
            SoC(k + 1, s) = min(soc_curr + d_soc, 1.0);
        end
    end
end

% Último passo para registro de potência
P_dem_last = P_load(end, :) - P_bus_net(end, :);
for s = 1:N_sat
    if P_dem_last(s) >= 0.0
        P_b(end, s) = P_dem_last(s);
        P_curtail(end, s) = 0.0;
    else
        p_surplus = -P_dem_last(s);
        e_room = (1.0 - SoC(end, s)) * E_nom;
        p_chg_term = min(p_surplus, e_room / (eta_chg * dt));
        P_b(end, s) = -p_chg_term;
        P_curtail(end, s) = p_surplus - p_chg_term;
    end
end

% 2. Métricas de ciclagem e profundidade de descarga (DoD)
SoC_min = min(SoC, [], 1);
SoC_max = max(SoC, [], 1);
DoD = SoC_max - SoC_min;
DoD_pct = DoD * 100.0;

% 3. Modelo calibrado de degradação cíclica (Eq. 16 do artigo)
% N_cycles(DoD) = N_ref * (DoD_ref / DoD)^v_eff
N_ref = p.battery.N_ref;
DoD_ref = p.battery.DoD_ref;
v_eff = p.battery.v_eff;

% Evitar divisão por zero caso DoD seja estritamente nulo
DoD_safe = max(DoD, 1e-4);
N_cycles = N_ref .* (DoD_ref ./ DoD_safe).^v_eff;

% Conversão de ciclos em anos de serviço orbital:
% f_orb = 86400 / tau [órbitas/dia] -> orbits_per_year = f_orb * 365.25
orbits_per_year = (86400.0 / p.orbit.tau) * 365.25; % ~5496.6 órbitas/ano
life_years_cyclic = N_cycles ./ orbits_per_year;

% 4. Modelo difusivo de envelhecimento de calendário (Eq. 14 do artigo)
% Delta_C_cal(t) = k_cal * sqrt(t_years)
k_cal = p.battery.k_cal; % 0.011 ano^-0.5
loss_cal_10yr = k_cal * sqrt(10.0); % ~0.034785 (3.48%)

% Perda cíclica acumulada ao longo de 10 anos (10 * orbits_per_year ciclos):
% Delta_C_cyc(10 yr) = 0.20 * (10 * orbits_per_year) / N_cycles
cycles_10yr = 10.0 * orbits_per_year;
loss_cyc_10yr = 0.20 .* (cycles_10yr ./ N_cycles);

% Superposição total de capacidade retida após 10 anos:
retention_10yr = 1.0 - (loss_cyc_10yr + loss_cal_10yr);

% 5. Teste de balanço de energia instantâneo no barramento (Conservação de Kirchhoff)
% eta_conv * P_pv + P_b = P_load + P_curtail (onde P_b < 0 em recarga e P_curtail >= 0)
bus_residual = abs((P_bus_net + P_b) - (P_load + P_curtail));
energy_balance_err = max(bus_residual(:));

% Montagem da estrutura de saída
batt_data.SoC                = SoC;
batt_data.P_b                = P_b;
batt_data.P_curtail          = P_curtail;
batt_data.DoD                = DoD;
batt_data.DoD_pct            = DoD_pct;
batt_data.SoC_min            = SoC_min;
batt_data.SoC_max            = SoC_max;
batt_data.N_cycles           = N_cycles;
batt_data.life_years_cyclic  = life_years_cyclic;
batt_data.loss_cal_10yr      = loss_cal_10yr;
batt_data.loss_cyc_10yr      = loss_cyc_10yr;
batt_data.retention_10yr     = retention_10yr;
batt_data.retention_10yr_pct = retention_10yr * 100.0;
batt_data.energy_balance_err = energy_balance_err;

end
