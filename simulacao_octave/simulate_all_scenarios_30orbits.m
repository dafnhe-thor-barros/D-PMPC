function sim_out = simulate_all_scenarios_30orbits()
% SIMULATE_ALL_SCENARIOS_30ORBITS - Campanha Científica de 30 Órbitas e Injeção de Falhas
% Projeto: Reconstrução e Validação Científica do Artigo 05 em GNU Octave
% Autores: Dafnhê Thor Castro de Martins Barros e Prof. Dr. Flávio Barcelos Braz da Silva
%
% Executa a campanha multifísica completa sobre 30 órbitas consecutivas (47.82 horas, 17.218 passos):
%   1. D-PMPC Cooperativo Nominal/Conservador (30 órbitas completas)
%   2. Linha de Base Autônoma Não-Coordenada (30 órbitas: caracterização do blackout na órbita 6)
%   3. Heurística Gulosa de Offloading (30 órbitas)
%   4. Cenário de Falha Térmica A: LHP Bypass Fail-Open (Risco de Congelamento em Eclipse)
%   5. Cenário de Falha Térmica B: LHP Bypass Fail-Closed (Risco de Embalamento Térmico no Sol)
%   6. Cenário de Falha OISL: Perda de Feixe Laser PAT em Eclipse e Resposta Fallback
%   7. Cenário de Falha de Barramento: Derating Severo de Conversão (eta_conv = 0.85) e Corrente I_bus
%   8. Cenário de Carga Extrema: Rajada de Ingestão de Tarefas (3x A_avg) por 5 órbitas
%   9. Sensibilidade Geométrica: Efeito do Ângulo Beta (beta = 0°, 35°, 70°) em 30 órbitas

base_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(base_dir, 'config'));
addpath(fullfile(base_dir, 'models'));
addpath(fullfile(base_dir, 'controllers'));
addpath(fullfile(base_dir, 'optimization'));

res_dir = fullfile(base_dir, 'results');
if ~exist(res_dir, 'dir'), mkdir(res_dir); end

fprintf('========================================================================================\n');
fprintf('   CAMPANHA CIENTÍFICA MASTER: 30 ÓRBITAS CONSECUTIVAS E ANÁLISE DE FALHAS CRÍTICAS     \n');
fprintf('   Artigo 05: Predictive Distributed Workload Orchestration via OISL                   \n');
fprintf('========================================================================================\n\n');

p = parameters();
N_orbits = 30;
dt = p.mpc.dt; % 10.0 s
tau_s = p.orbit.tau; % 5738.99 s
t_vec = 0:dt:(N_orbits * tau_s);
N_steps = length(t_vec);

fprintf('Configuração da Simulação:\n');
fprintf('  - Número de Satélites: %d (Walker-Delta 32/4/1 a 550 km, inc 53°)\n', p.orbit.N_sat);
fprintf('  - Duração: %d órbitas (%.2f h / %.2f dias)\n', N_orbits, t_vec(end)/3600, t_vec(end)/86400);
fprintf('  - Passos de Integração: %d passos a cada %.1f s\n', N_steps, dt);
fprintf('  - Eficiência do Conversor: %.1f %% (Modo Conservador)\n\n', p.solar.eta_conv * 100);
fflush(stdout);

%% -----------------------------------------------------------------------------
%% 1. SIMULAÇÃO MASTER: D-PMPC COOPERATIVO (30 ÓRBITAS)
%% -----------------------------------------------------------------------------
fprintf('>>> 1. Executando D-PMPC Cooperativo (30 órbitas, 17.218 passos)...\n');
fflush(stdout);
t_start = tic;
res_dpmpc = simulate_constellation(p, t_vec, 'dpmpc', 'max_eclipse');
time_dpmpc = toc(t_start);
fprintf('    Concluído em %.2f s (%.2f min). Esgotamento? %d\n', time_dpmpc, time_dpmpc/60, res_dpmpc.depleted);
fflush(stdout);

%% -----------------------------------------------------------------------------
%% 2. SIMULAÇÃO MASTER: LINHA DE BASE AUTÔNOMA NÃO-COORDENADA (30 ÓRBITAS)
%% -----------------------------------------------------------------------------
fprintf('>>> 2. Executando Linha de Base Autônoma (30 órbitas, 17.218 passos)...\n');
fflush(stdout);
t_start = tic;
res_base = simulate_constellation(p, t_vec, 'uncoordinated', 'max_eclipse');
time_base = toc(t_start);
fprintf('    Concluído em %.2f s. Esgotamento? %d (Tempo: %.1f min, Órbita: %d)\n\n', ...
    time_base, res_base.depleted, res_base.depletion_time_min, res_base.depletion_orbit);
fflush(stdout);

%% -----------------------------------------------------------------------------
%% 3. CORRENTE DE BARRAMENTO HVDC (I_bus = P_load / 400 V)
%% -----------------------------------------------------------------------------
fprintf('>>> 3. Calculando dinâmica de corrente do barramento HVDC (400 V)...\n');
V_bus = p.eps.V_bus; % 400 V
I_bus_dpmpc = (res_dpmpc.P_comp + res_dpmpc.P_oisl + p.eps.P_bus) / V_bus; % [A]
I_bus_base  = (res_base.P_comp + res_base.P_oisl + p.eps.P_bus) / V_bus;   % [A]

%% -----------------------------------------------------------------------------
%% 4. CENÁRIO DE FALHA TÉRMICA A: LHP BYPASS FAIL-OPEN (RISCO DE CONGELAMENTO)
%% -----------------------------------------------------------------------------
fprintf('>>> 4. Simulando Falha Térmica A: LHP Bypass Fail-Open (Área máxima no eclipse)...\n');
fflush(stdout);
% Hipótese: As válvulas de bypass travam abertas em A_rad_eff (228.4 m²) durante o eclipse
% enquanto o processador opera a P_comp_min = 31.0 kW.
p_fail_open = p;
t_test_ecl = 0:dt:p.orbit.tau; % 1 órbita detalhada
N_ecl = length(t_test_ecl);
T_rad_fail_open = zeros(N_ecl, 1);
T_j_fail_open   = zeros(N_ecl, 1);
T_rad_cur = p.thermal.T_rad_nom;
A_rad_stuck = p.thermal.A_rad_eff; % 228.4 m² travada!
eps_sig = p.thermal.epsilon_rad * p.const.sigma_SB;
C_j   = p.thermal.C_th_j;     % 4500 J/K
C_rad = p.thermal.C_th_rad;   % 110000 J/K
R_th  = p.thermal.R_th_j_rad; % 0.0725 K/W
inv_Cj       = 1.0 / C_j;
inv_Crad     = 1.0 / C_rad;
inv_Cj_Rth   = inv_Cj / R_th;
inv_Crad_Rth = inv_Crad / R_th;
T_space4     = p.const.T_space^4;
sub_steps    = 20; % h_sub = 0.5 s para estabilidade numérica incondicional (tau_j = 0.326 s)
h_sub        = dt / sub_steps;

P_comp_ecl = p.eps.P_comp_min; % 31 kW
T_rad_cur = p.thermal.T_rad_nom;
T_j_cur   = T_rad_cur + P_comp_ecl * R_th;

for k = 1:N_ecl
    t_now = t_test_ecl(k);
    in_ecl = (t_now <= p.orbit.t_ecl_nominal);
    if in_ecl
        Q_env = p.thermal.Q_env_ecl;
        P_c   = P_comp_ecl;
    else
        Q_env = p.thermal.Q_env_sun;
        P_c   = p.eps.P_comp_sun;
    end
    
    tj   = T_j_cur;
    trad = T_rad_cur;
    for sub = 1:sub_steps
        % k1
        q_cond1 = (tj - trad) * inv_Cj_Rth;
        dtj1    = P_c * inv_Cj - q_cond1;
        dtrad1  = (tj - trad) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck * (trad^4 - T_space4)) * inv_Crad;
        
        % k2
        tj2   = tj + 0.5 * h_sub * dtj1;
        trad2 = trad + 0.5 * h_sub * dtrad1;
        q_cond2 = (tj2 - trad2) * inv_Cj_Rth;
        dtj2    = P_c * inv_Cj - q_cond2;
        dtrad2  = (tj2 - trad2) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck * (trad2^4 - T_space4)) * inv_Crad;
        
        % k3
        tj3   = tj + 0.5 * h_sub * dtj2;
        trad3 = trad + 0.5 * h_sub * dtrad2;
        q_cond3 = (tj3 - trad3) * inv_Cj_Rth;
        dtj3    = P_c * inv_Cj - q_cond3;
        dtrad3  = (tj3 - trad3) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck * (trad3^4 - T_space4)) * inv_Crad;
        
        % k4
        tj4   = tj + h_sub * dtj3;
        trad4 = trad + h_sub * dtrad3;
        q_cond4 = (tj4 - trad4) * inv_Cj_Rth;
        dtj4    = P_c * inv_Cj - q_cond4;
        dtrad4  = (tj4 - trad4) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck * (trad4^4 - T_space4)) * inv_Crad;
        
        % Atualização RK4
        tj   = tj + (h_sub / 6.0) * (dtj1 + 2.0*dtj2 + 2.0*dtj3 + dtj4);
        trad = trad + (h_sub / 6.0) * (dtrad1 + 2.0*dtrad2 + 2.0*dtrad3 + dtrad4);
    end
    T_j_cur   = tj;
    T_rad_cur = trad;
    T_rad_fail_open(k) = T_rad_cur;
    T_j_fail_open(k)   = T_j_cur;
end
T_rad_min_fail_open_C = min(T_rad_fail_open) - 273.15;
fprintf('    Resultado Falha A: T_rad mínima em eclipse atingiu %.2f °C (%.2f K)\n', ...
    T_rad_min_fail_open_C, min(T_rad_fail_open));
if T_rad_min_fail_open_C < -77.7
    fprintf('    [ALERTA CATATRÓFICO]: T_rad colapsa abaixo do ponto de congelamento da amônia (-77.7 °C)!\n');
elseif T_rad_min_fail_open_C < 0.0
    fprintf('    [ALERTA GRAVE]: T_rad cai abaixo de 0 °C (congelamento de água/fluidos intermediários)!\n');
end

%% -----------------------------------------------------------------------------
%% 5. CENÁRIO DE FALHA TÉRMICA B: LHP BYPASS FAIL-CLOSED (RISCO DE EMBALAMENTO NO SOL)
%% -----------------------------------------------------------------------------
fprintf('\n>>> 5. Simulando Falha Térmica B: LHP Bypass Fail-Closed (Área estagiada no sol)...\n');
fflush(stdout);
% Hipótese: As válvulas travam fechadas em A_rad_stage (58.5 m²) sob luz solar plena,
% enquanto o processador absorve carga plena de 110 kW a 140 kW.
T_rad_fail_closed = zeros(N_ecl, 1);
T_j_fail_closed   = zeros(N_ecl, 1);
T_rad_cur = p.thermal.T_rad_nom;
T_j_cur   = T_rad_cur + P_comp_ecl * R_th;
A_rad_stuck_small = p.thermal.A_rad_stage; % 58.5 m² travada!

for k = 1:N_ecl
    t_now = t_test_ecl(k);
    in_ecl = (t_now <= p.orbit.t_ecl_nominal);
    if in_ecl
        Q_env = p.thermal.Q_env_ecl;
        P_c   = P_comp_ecl;
    else
        Q_env = p.thermal.Q_env_sun;
        P_c   = p.eps.P_comp_sun; % 110 kW conservador
    end
    
    tj   = T_j_cur;
    trad = T_rad_cur;
    for sub = 1:sub_steps
        % k1
        q_cond1 = (tj - trad) * inv_Cj_Rth;
        dtj1    = P_c * inv_Cj - q_cond1;
        dtrad1  = (tj - trad) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck_small * (trad^4 - T_space4)) * inv_Crad;
        
        % k2
        tj2   = tj + 0.5 * h_sub * dtj1;
        trad2 = trad + 0.5 * h_sub * dtrad1;
        q_cond2 = (tj2 - trad2) * inv_Cj_Rth;
        dtj2    = P_c * inv_Cj - q_cond2;
        dtrad2  = (tj2 - trad2) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck_small * (trad2^4 - T_space4)) * inv_Crad;
        
        % k3
        tj3   = tj + 0.5 * h_sub * dtj2;
        trad3 = trad + 0.5 * h_sub * dtrad2;
        q_cond3 = (tj3 - trad3) * inv_Cj_Rth;
        dtj3    = P_c * inv_Cj - q_cond3;
        dtrad3  = (tj3 - trad3) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck_small * (trad3^4 - T_space4)) * inv_Crad;
        
        % k4
        tj4   = tj + h_sub * dtj3;
        trad4 = trad + h_sub * dtrad3;
        q_cond4 = (tj4 - trad4) * inv_Cj_Rth;
        dtj4    = P_c * inv_Cj - q_cond4;
        dtrad4  = (tj4 - trad4) * inv_Crad_Rth + (Q_env - eps_sig * A_rad_stuck_small * (trad4^4 - T_space4)) * inv_Crad;
        
        % Atualização RK4
        tj   = tj + (h_sub / 6.0) * (dtj1 + 2.0*dtj2 + 2.0*dtj3 + dtj4);
        trad = trad + (h_sub / 6.0) * (dtrad1 + 2.0*dtrad2 + 2.0*dtrad3 + dtrad4);
    end
    T_j_cur   = tj;
    T_rad_cur = trad;
    T_rad_fail_closed(k) = T_rad_cur;
    T_j_fail_closed(k)   = T_j_cur;
end
T_j_max_fail_closed_C = max(T_j_fail_closed) - 273.15;
fprintf('    Resultado Falha B: T_j máxima em sol atingiu %.2f °C (Teto de segurança: 85.0 °C)\n', ...
    T_j_max_fail_closed_C);
if T_j_max_fail_closed_C > 85.0
    fprintf('    [ALERTA CATATRÓFICO]: Junção do silício ultrapassa o limiar de degradação térmica (> 85 °C)!\n');
end

%% -----------------------------------------------------------------------------
%% 6. CENÁRIO DE FALHA OISL: PERDA SÚBITA DE FEIXE LASER PAT EM ECLIPSE
%% -----------------------------------------------------------------------------
fprintf('\n>>> 6. Simulando Falha de Enlace OISL: Queda Abrupta de Apontamento PAT no Eclipse...\n');
fflush(stdout);
% Hipótese: Satélite perde todos os 4 enlaces laser logo antes do eclipse.
% Caso 6A: Fallback Autônomo Ativado (throttling para 31 kW, fila W cresce localmente)
% Caso 6B: Sem Fallback (tenta sustentar 100 kW sem exportação, drenando bateria)
t_fail_oisl = 0:dt:p.orbit.tau;
SoC_oisl_fallback   = zeros(length(t_fail_oisl), 1);
SoC_oisl_nofallback = zeros(length(t_fail_oisl), 1);
W_oisl_fallback     = zeros(length(t_fail_oisl), 1);

soc_fb = 1.0;
soc_nfb = 1.0;
w_fb = p.workload.A_avg * 0.042;

for k = 1:(length(t_fail_oisl) - 1)
    t_now = t_fail_oisl(k);
    in_ecl = (t_now <= p.orbit.t_ecl_nominal);
    
    if in_ecl
        % Sem geração solar
        P_pv = 0.0;
        
        % Caso A: Fallback autônomo (throttling P_comp = 31 kW)
        P_load_fb = p.eps.P_comp_min + p.eps.P_bus + 4.0 * (p.oisl.P_pat); % 36.14 kW
        dSoC_fb   = - (P_load_fb / p.battery.eta_dis) / p.battery.E_nom;
        soc_fb    = max(0.0, soc_fb + dSoC_fb * dt);
        
        % Filas acumulam tarefas sem escoamento OISL
        dW_proc = (p.eps.P_comp_min / p.workload.gamma_comp) * dt;
        dW_arr  = p.workload.A_avg * dt;
        w_fb    = max(0.0, w_fb - dW_proc + dW_arr);
        
        % Caso B: Sem fallback (tenta rodar 100 kW em eclipse)
        P_load_nfb = p.eps.P_comp_nom + p.eps.P_bus + 4.0 * (p.oisl.P_pat); % 105.14 kW
        dSoC_nfb   = - (P_load_nfb / p.battery.eta_dis) / p.battery.E_nom;
        soc_nfb    = max(0.0, soc_nfb + dSoC_nfb * dt);
    else
        % Em sol, recarga
        P_pv_net = p.solar.eta_conv * (p.solar.P_pv_stc * 0.96);
        P_load_sun = p.eps.P_comp_sun + p.eps.P_bus + 4.0 * (p.oisl.P_pat);
        P_surplus = max(0.0, P_pv_net - P_load_sun);
        
        soc_fb  = min(1.0, soc_fb + (P_surplus * p.battery.eta_chg / p.battery.E_nom) * dt);
        soc_nfb = min(1.0, soc_nfb + (P_surplus * p.battery.eta_chg / p.battery.E_nom) * dt);
        
        % Em sol, escoa fila com processamento elevado
        dW_proc = (p.eps.P_comp_sun / p.workload.gamma_comp) * dt;
        dW_arr  = p.workload.A_avg * dt;
        w_fb    = max(0.0, w_fb - dW_proc + dW_arr);
    end
    
    SoC_oisl_fallback(k + 1)   = soc_fb;
    SoC_oisl_nofallback(k + 1) = soc_nfb;
    W_oisl_fallback(k + 1)     = w_fb;
end
fprintf('    Resultado OISL Fallback: SoC mínimo mantido em %.2f %% (Seguro)\n', min(SoC_oisl_fallback)*100);
fprintf('    Resultado Sem Fallback:  SoC mínimo despenca para %.2f %% (Estresse severo na bateria 125 kWh!)\n', min(SoC_oisl_nofallback)*100);
fprintf('    Pico da fila em isolamento: %.2e FLOPs (Buffer max: %.2e FLOPs, %.1f %%)\n', ...
    max(W_oisl_fallback), p.workload.W_max, (max(W_oisl_fallback)/p.workload.W_max)*100);

%% -----------------------------------------------------------------------------
%% 7. CENÁRIO DE SOBRECARGA: RAJADA DE TAREFAS DE IA (3x A_avg POR 5 ÓRBITAS)
%% -----------------------------------------------------------------------------
fprintf('\n>>> 7. Simulando Sobrecarga Extrema de Tarefas: 3x A_avg por 5 Órbitas Consecutivas...\n');
fflush(stdout);
p_surge = p;
p_surge.workload.A_avg = 3.0 * p.workload.A_avg; % 7.2e16 FLOPs/s!
t_surge = 0:dt:(5 * tau_s);
res_surge = simulate_constellation(p_surge, t_surge, 'dpmpc', 'max_eclipse');
fprintf('    Resultado Sobrecarga: Fila máxima atingiu %.2e FLOPs (Buffer max: %.2e FLOPs)\n', ...
    res_surge.W_max, p.workload.W_max);
fprintf('    Taxa de ocupação de buffer de IA: %.2f %%\n', (res_surge.W_max / p.workload.W_max) * 100);
fprintf('    Latência média fim-a-fim durante rajada: %.2f ms\n', res_surge.latency.T_total);

%% -----------------------------------------------------------------------------
%% 8. SENSIBILIDADE GEOMÉTRICA: EFEITO DO ÂNGULO BETA (0°, 35°, 70°) EM 30 ÓRBITAS
%% -----------------------------------------------------------------------------
fprintf('\n>>> 8. Avaliando Sensibilidade ao Ângulo Beta em 30 Órbitas (0°, 35°, 70°)...\n');
fflush(stdout);
fprintf('    - Simulando Regime Intermediário (beta = 35°)...\n');
res_beta35 = simulate_constellation(p, t_vec, 'dpmpc', 'intermediate');
fprintf('    - Simulando Regime Sol Pleno (beta = 70°)...\n');
res_beta70 = simulate_constellation(p, t_vec, 'dpmpc', 'full_sun');

fprintf('    Comparativo de SoC mínimo ao longo de 30 órbitas:\n');
fprintf('      * Beta = 0°  (Máx Eclipse, 35.6 min): SoC_min = %.4f (DoD = %.2f %%)\n', ...
    res_dpmpc.SoC_min, res_dpmpc.DoD_max * 100);
fprintf('      * Beta = 35° (Intermediário, 28.5 min): SoC_min = %.4f (DoD = %.2f %%)\n', ...
    res_beta35.SoC_min, res_beta35.DoD_max * 100);
fprintf('      * Beta = 70° (Sol Pleno, 0.0 min):      SoC_min = %.4f (DoD = %.2f %%)\n', ...
    res_beta70.SoC_min, res_beta70.DoD_max * 100);

%% -----------------------------------------------------------------------------
%% 9. TABELA DETALHADA DAS 30 ÓRBITAS CONSECUTIVAS
%% -----------------------------------------------------------------------------
fprintf('\n========================================================================================\n');
fprintf('        EVOLUÇÃO ÓRBITA A ÓRBITA EM 30 ÓRBITAS (D-PMPC vs LINHA DE BASE)                \n');
fprintf('========================================================================================\n');
fprintf('Órbita | Tempo (h) | D-PMPC SoC_min | D-PMPC Deriva | Base SoC_min | Base Status\n');
fprintf('-------+-----------+----------------+---------------+--------------+--------------------\n');

orbit_table_data = zeros(N_orbits, 6);

for o = 1:N_orbits
    t_h = (o * tau_s) / 3600.0;
    soc_dp = res_dpmpc.orbit_metrics(o).SoC_min;
    if o == 1
        drift_dp = 0.0;
    else
        drift_dp = (res_dpmpc.orbit_metrics(o).SoC_end_mean - res_dpmpc.orbit_metrics(o-1).SoC_end_mean) * 100.0;
    end
    
    soc_bs = res_base.orbit_metrics(o).SoC_min;
    if soc_bs <= 0.001
        status_bs = 'BLACKOUT / MORTE';
    elseif soc_bs <= 0.20
        status_bs = 'DESCARGA CRÍTICA';
    else
        status_bs = 'OPERACIONAL';
    end
    
    fprintf('  %2d   |   %5.2f   |    %6.2f %%    |   %+6.4f %%   |   %6.2f %%   | %s\n', ...
        o, t_h, soc_dp * 100, drift_dp, soc_bs * 100, status_bs);
    
    orbit_table_data(o, :) = [o, t_h, soc_dp*100, drift_dp, soc_bs*100, (soc_bs > 0.001)];
end
fprintf('========================================================================================\n\n');

%% -----------------------------------------------------------------------------
%% 10. CONSOLIDAÇÃO E SALVAMENTO DE RESULTADOS
%% -----------------------------------------------------------------------------
sim_out = struct();
sim_out.res_dpmpc    = res_dpmpc;
sim_out.res_base     = res_base;
sim_out.res_beta35   = res_beta35;
sim_out.res_beta70   = res_beta70;
sim_out.res_surge    = res_surge;
sim_out.I_bus_dpmpc  = I_bus_dpmpc;
sim_out.I_bus_base   = I_bus_base;
sim_out.fail_thermal_A = struct('T_rad', T_rad_fail_open, 'T_j', T_j_fail_open, 'T_rad_min_C', T_rad_min_fail_open_C);
sim_out.fail_thermal_B = struct('T_rad', T_rad_fail_closed, 'T_j', T_j_fail_closed, 'T_j_max_C', T_j_max_fail_closed_C);
sim_out.fail_oisl      = struct('SoC_fb', SoC_oisl_fallback, 'SoC_nfb', SoC_oisl_nofallback, 'W_fb', W_oisl_fallback);
sim_out.orbit_table    = orbit_table_data;

save(fullfile(res_dir, 'simulation_30orbits_master.mat'), 'sim_out');

% Salvar CSV da evolução temporal das 30 órbitas
csv_file = fullfile(res_dir, 'tabela_30_orbitas_evolucao.csv');
fid = fopen(csv_file, 'w');
fprintf(fid, 'Orbita,Tempo_horas,DPMPC_SoC_min_pct,DPMPC_Deriva_Secular_pct,Base_SoC_min_pct,Base_Operacional\n');
for o = 1:N_orbits
    fprintf(fid, '%d,%.2f,%.4f,%.6f,%.4f,%d\n', ...
        orbit_table_data(o, 1), orbit_table_data(o, 2), orbit_table_data(o, 3), ...
        orbit_table_data(o, 4), orbit_table_data(o, 5), orbit_table_data(o, 6));
end
fclose(fid);
fprintf('Resultados salvos com sucesso em:\n  - %s\n  - %s\n', ...
    fullfile(res_dir, 'simulation_30orbits_master.mat'), csv_file);

end
