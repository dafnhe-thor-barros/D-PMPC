function pareto_results = pareto_sweep(p, options)
% PARETO_SWEEP - Varredura Paramétrica Multiobjetivo e Fronteira de Pareto Física
% Realiza a varredura contínua do peso de bateria w_B in [0.05, 0.95] no D-PMPC,
% derivando rigorosamente a fronteira de Pareto a partir da integração numérica
% das EDOs físicas acopladas da constelação de 32 satélites.
%
% Substitui integralmente qualquer formulação ad-hoc ou curva empírica ('polyfit')
% por dados físicos reais auditáveis.
%
% Entradas:
%   p       - Estrutura mestra de parâmetros (parameters.m)
%   options - [Opcional] Estrutura de opções:
%             .w_B_vec     - Vetor de pesos de bateria a varrer (padrão: 12 pontos)
%             .mode_eval   - 'conservative' (padrão) ou 'nominal' (valores publicados)
%             .N_orbits    - Número de órbitas por avaliação (padrão: 1 órbita completa)
%             .regime      - Regime de iluminação ('max_eclipse', 'intermediate', 'full_sun')
%             .save_csv    - Booleano para salvar results/pareto_frontier.csv (padrão: true)
%             .save_mat    - Booleano para salvar results/pareto_frontier_data.mat (padrão: true)
%
% Saída:
%   pareto_results - Estrutura contendo dados da varredura, pontos de referência e
%                    classificação de dominância de Pareto.

if nargin < 1 || isempty(p)
    p = parameters();
end

if nargin < 2, options = struct(); end
if ~isfield(options, 'w_B_vec') || isempty(options.w_B_vec)
    % 12 pontos de amostragem no intervalo [0.05, 0.95]
    options.w_B_vec = [0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.85, 0.90, 0.95];
end
if ~isfield(options, 'mode_eval') || isempty(options.mode_eval)
    options.mode_eval = 'conservative';
end
if ~isfield(options, 'N_orbits') || isempty(options.N_orbits)
    options.N_orbits = 1;
end
if ~isfield(options, 'regime') || isempty(options.regime)
    options.regime = 'max_eclipse';
end
if ~isfield(options, 'save_csv') || isempty(options.save_csv)
    options.save_csv = true;
end
if ~isfield(options, 'save_mat') || isempty(options.save_mat)
    options.save_mat = true;
end

% Ajustar modo conservador vs nominal
p_eval = p;
if strcmpi(options.mode_eval, 'nominal')
    p_eval.conservative.enabled = false;
    p_eval.solar.eta_conv  = p_eval.nominal.eta_conv;
    p_eval.solar.eta_sa    = p_eval.nominal.eta_sa;
    p_eval.battery.eta_dis = p_eval.nominal.eta_dis;
    p_eval.battery.eta_chg = p_eval.nominal.eta_chg;
    p_eval.eps.P_comp_sun  = p_eval.nominal.P_comp_sun; % 140 kW
end

dt    = p_eval.mpc.dt;
tau   = p_eval.orbit.tau;
t_vec = 0:dt:(options.N_orbits * tau);
N_pts = length(options.w_B_vec);

fprintf('========================================================================================\n');
fprintf('   VARREDURA PARAMÉTRICA MULTIOBJETIVO E FRONTEIRA DE PARETO FÍSICA (ETAPA G)          \n');
fprintf('========================================================================================\n');
fprintf('Configuração da Varredura:\n');
fprintf('   Modo de avaliação:    %s\n', upper(options.mode_eval));
fprintf('   Regime orbital:       %s\n', options.regime);
fprintf('   Órbitas por ponto:    %d órbita(s) (t_max = %.1f s)\n', options.N_orbits, t_vec(end));
fprintf('   Pontos de amostragem: %d valores de w_B in [%.2f, %.2f]\n\n', ...
    N_pts, options.w_B_vec(1), options.w_B_vec(end));

% Alocação de vetores de saída
sweep_w_B       = options.w_B_vec(:);
sweep_w_T       = zeros(N_pts, 1);
sweep_w_Q       = zeros(N_pts, 1);
sweep_w_comm    = zeros(N_pts, 1);
sweep_P_ecl_kW  = zeros(N_pts, 1);
sweep_P_sun_kW  = zeros(N_pts, 1);
sweep_DoD_pct   = zeros(N_pts, 1);
sweep_SoC_min   = zeros(N_pts, 1);
sweep_life_yr   = zeros(N_pts, 1);
sweep_ret10_pct = zeros(N_pts, 1);
sweep_eta_harv  = zeros(N_pts, 1);
sweep_Tj_max    = zeros(N_pts, 1);
sweep_delta_Tj  = zeros(N_pts, 1);
sweep_T_lat_ms  = zeros(N_pts, 1);
sweep_r_mig_Gbps= zeros(N_pts, 1);

P_comp_min_base = p_eval.eps.P_comp_min; % 31.0 kW
P_comp_nom_base = p_eval.eps.P_comp_nom; % 100.0 kW
P_comp_sun_max  = p_eval.eps.P_comp_sun; % 110.0 kW (cons) ou 140.0 kW (nom)

% Propagação geométrica de referência para demarcação de sol/sombra
orbit_data_sweep   = orbit_model(p_eval, t_vec);
eclipse_data_sweep = eclipse_model(p_eval, orbit_data_sweep, options.regime);
xi_sweep           = eclipse_data_sweep.xi;

% --- LAÇO DE VARREDURA PARAMÉTRICA ---
tic_sweep = tic;
for i = 1:N_pts
    wB = sweep_w_B(i);
    w_rem = 1.0 - wB;
    
    % Distribuição proporcional dos pesos secundários
    wT = w_rem * (0.10 / 0.15);
    wQ = w_rem * (0.04 / 0.15);
    wc = w_rem * (0.01 / 0.15);
    
    sweep_w_T(i)    = wT;
    sweep_w_Q(i)    = wQ;
    sweep_w_comm(i) = wc;
    
    % Configuração dos pesos multiobjetivo no controlador D-PMPC (EQ-24)
    p_i = p_eval;
    p_i.mpc.w_B    = wB;
    p_i.mpc.w_T    = wT;
    p_i.mpc.w_Q    = wQ;
    p_i.mpc.w_comm = wc;
    p_i.mpc.w_f_B  = 2.50 * (wB / 0.85);
    p_i.eps.P_comp_min = P_comp_min_base;
    p_i.eps.P_comp_sun = P_comp_sun_max;
    
    % Execução da simulação física em malha fechada
    res_i = simulate_constellation(p_i, t_vec, 'dpmpc', options.regime);
    
    % As potências em sol e eclipse emergem diretamente da otimização do D-PMPC (NUM-03)
    sweep_P_ecl_kW(i) = mean(res_i.P_comp(xi_sweep == 0)) / 1e3;
    sweep_P_sun_kW(i) = mean(res_i.P_comp(xi_sweep == 1)) / 1e3;
    
    sweep_DoD_pct(i)   = res_i.DoD_max * 100.0;
    sweep_SoC_min(i)   = res_i.SoC_min;
    sweep_life_yr(i)   = res_i.battery_life_years;
    sweep_ret10_pct(i) = res_i.capacity_retention_10yr * 100.0;
    sweep_eta_harv(i)  = res_i.eta_harv;
    sweep_Tj_max(i)    = res_i.T_j_max_degC;
    sweep_delta_Tj(i)  = res_i.delta_T_j;
    sweep_T_lat_ms(i)  = res_i.latency.T_total;
    sweep_r_mig_Gbps(i)= max(res_i.tx_rate(:)) / 1e9;
    
    fprintf('   [%02d/%02d] w_B = %.2f -> DoD = %5.2f %%, Vida = %5.2f anos, eta_harv = %5.2f %%, T_lat = %5.1f ms, T_j = %5.2f °C\n', ...
        i, N_pts, wB, sweep_DoD_pct(i), sweep_life_yr(i), sweep_eta_harv(i), sweep_T_lat_ms(i), sweep_Tj_max(i));
end
t_total_sweep = toc(tic_sweep);
fprintf('\nVarredura concluída em %.2f s (%.2f s por ponto).\n\n', t_total_sweep, t_total_sweep / N_pts);

% --- SIMULAÇÃO DOS PONTOS DE REFERÊNCIA PARA BENCHMARK ---
fprintf('Simulando Pontos de Referência Comparativos:\n');

% 1. Linha de Base Autônoma Não-Coordenada (250 kWh, 100 kW fixo)
p_base = p_eval;
res_base = simulate_constellation(p_base, t_vec, 'uncoordinated', options.regime);
ref_base.name     = 'Linha de Base Autônoma';
ref_base.BESS_kWh = p_base.battery.E_nom_base_kWh;
ref_base.mass_kg  = p_base.mass.baseline_total;
ref_base.DoD_pct  = res_base.DoD_max * 100.0;
ref_base.life_yr  = res_base.battery_life_years;
ref_base.eta_harv = res_base.eta_harv;
ref_base.T_lat_ms = res_base.latency.T_total;
ref_base.Tj_max   = res_base.T_j_max_degC;
ref_base.ret10    = res_base.capacity_retention_10yr * 100.0;
fprintf('   - Linha de Base Autônoma: Vida = %.2f anos, eta_harv = %.2f %%, DoD = %.2f %%\n', ...
    ref_base.life_yr, ref_base.eta_harv, ref_base.DoD_pct);

% 2. Offloading Guloso Heurístico (Greedy) (125 kWh, P_ecl = 65 kW, P_sun = 120 kW)
p_greedy = p_eval;
p_greedy.eps.P_comp_min = 65.0e3;
p_greedy.eps.P_comp_sun = min(P_comp_sun_max, 120.0e3);
p_greedy.mpc.w_B = 0.50;
res_greedy = simulate_constellation(p_greedy, t_vec, 'dpmpc', options.regime);
ref_greedy.name     = 'Offloading Guloso Heurístico';
ref_greedy.BESS_kWh = p_greedy.battery.E_nom_kWh;
ref_greedy.mass_kg  = p_greedy.mass.dpmpc_total;
ref_greedy.DoD_pct  = res_greedy.DoD_max * 100.0;
ref_greedy.life_yr  = res_greedy.battery_life_years;
ref_greedy.eta_harv = res_greedy.eta_harv;
ref_greedy.T_lat_ms = res_greedy.latency.T_total;
ref_greedy.Tj_max   = res_greedy.T_j_max_degC;
ref_greedy.ret10    = res_greedy.capacity_retention_10yr * 100.0;
fprintf('   - Offloading Guloso:      Vida = %.2f anos, eta_harv = %.2f %%, DoD = %.2f %%\n', ...
    ref_greedy.life_yr, ref_greedy.eta_harv, ref_greedy.DoD_pct);

% 3. Ponto de Operação Selecionado do Artigo (w_B = 0.85 exato)
p_art = p_eval;
p_art.mpc.w_B = 0.85;
p_art.mpc.w_T = 0.10;
p_art.mpc.w_Q = 0.04;
p_art.mpc.w_comm = 0.01;
p_art.eps.P_comp_min = P_comp_min_base;
p_art.eps.P_comp_sun = P_comp_sun_max;
res_art = simulate_constellation(p_art, t_vec, 'dpmpc', options.regime);
ref_art.name     = 'D-PMPC Selecionado (Artigo, w_B=0.85)';
ref_art.BESS_kWh = p_art.battery.E_nom_kWh;
ref_art.mass_kg  = p_art.mass.dpmpc_total;
ref_art.DoD_pct  = res_art.DoD_max * 100.0;
ref_art.life_yr  = res_art.battery_life_years;
ref_art.eta_harv = res_art.eta_harv;
ref_art.T_lat_ms = res_art.latency.T_total;
ref_art.Tj_max   = res_art.T_j_max_degC;
ref_art.ret10    = res_art.capacity_retention_10yr * 100.0;
fprintf('   - D-PMPC Selecionado:     Vida = %.2f anos, eta_harv = %.2f %%, DoD = %.2f %%\n\n', ...
    ref_art.life_yr, ref_art.eta_harv, ref_art.DoD_pct);

% --- FILTRAGEM FORMAL DE DOMINÂNCIA DE PARETO ---
% Critérios: Maximizar Vida Útil (obj 1) e Maximizar Eficiência Solar (obj 2)
% Ponto A domina B se A.life >= B.life e A.eta >= B.eta com pelo menos uma desigualdade estrita.
is_pareto = true(N_pts, 1);
for i = 1:N_pts
    for j = 1:N_pts
        if i == j, continue; end
        % Se o ponto j for estritamente superior ou igual em ambos os objetivos e melhor em pelo menos um:
        if (sweep_life_yr(j) >= sweep_life_yr(i)) && (sweep_eta_harv(j) >= sweep_eta_harv(i)) && ...
           ((sweep_life_yr(j) > sweep_life_yr(i)) || (sweep_eta_harv(j) > sweep_eta_harv(i)))
            is_pareto(i) = false;
            break;
        end
    end
end

% Montagem da estrutura consolidada de saída
pareto_results.options          = options;
pareto_results.w_B              = sweep_w_B;
pareto_results.w_T              = sweep_w_T;
pareto_results.w_Q              = sweep_w_Q;
pareto_results.w_comm           = sweep_w_comm;
pareto_results.P_comp_ecl_kW    = sweep_P_ecl_kW;
pareto_results.P_comp_sun_kW    = sweep_P_sun_kW;
pareto_results.DoD_pct          = sweep_DoD_pct;
pareto_results.SoC_min          = sweep_SoC_min;
pareto_results.battery_life_yr  = sweep_life_yr;
pareto_results.retention_10yr   = sweep_ret10_pct;
pareto_results.eta_harv_pct     = sweep_eta_harv;
pareto_results.T_j_max_degC     = sweep_Tj_max;
pareto_results.delta_Tj_degC    = sweep_delta_Tj;
pareto_results.T_lat_ms         = sweep_T_lat_ms;
pareto_results.r_mig_Gbps       = sweep_r_mig_Gbps;
pareto_results.is_pareto        = is_pareto;

pareto_results.ref_baseline     = ref_base;
pareto_results.ref_greedy       = ref_greedy;
pareto_results.ref_selected     = ref_art;

% --- SALVAMENTO EM ARQUIVO MAT E CSV ---
out_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

if options.save_mat
    mat_file = fullfile(out_dir, sprintf('pareto_frontier_%s.mat', options.mode_eval));
    save('-v7', mat_file, 'pareto_results');
    fprintf('Resultados MAT salvos em: %s\n', mat_file);
end

if options.save_csv
    csv_file = fullfile(out_dir, sprintf('pareto_frontier_%s.csv', options.mode_eval));
    fid = fopen(csv_file, 'w');
    fprintf(fid, 'w_B,w_T,w_Q,w_comm,P_ecl_kW,P_sun_kW,DoD_pct,SoC_min,Battery_Life_yr,Retention_10yr_pct,Eta_Harv_pct,Tj_max_C,Delta_Tj_C,Latency_ms,Is_Pareto\n');
    for i = 1:N_pts
        fprintf(fid, '%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d\n', ...
            sweep_w_B(i), sweep_w_T(i), sweep_w_Q(i), sweep_w_comm(i), ...
            sweep_P_ecl_kW(i), sweep_P_sun_kW(i), sweep_DoD_pct(i), sweep_SoC_min(i), ...
            sweep_life_yr(i), sweep_ret10_pct(i), sweep_eta_harv(i), ...
            sweep_Tj_max(i), sweep_delta_Tj(i), sweep_T_lat_ms(i), is_pareto(i));
    end
    fclose(fid);
    fprintf('Resultados CSV salvos em: %s\n\n', csv_file);
end

% --- TABELA CONSOLIDADA ---
fprintf('========================================================================================\n');
fprintf('  TABELA DA FRONTEIRA DE PARETO FÍSICA DERIVADA DAS SIMULAÇÕES (D-PMPC)\n');
fprintf('========================================================================================\n');
fprintf('  w_B  |  P_ecl  |  P_sun  |   DoD   | Vida Bateria | Colheita Solar | Latência | T_j Máx | Pareto?\n');
fprintf('-------+---------+---------+---------+--------------+----------------+----------+---------+--------\n');
for i = 1:N_pts
    par_str = 'NÃO';
    if is_pareto(i), par_str = 'SIM'; end
    fprintf('  %4.2f | %5.1f kW| %5.1f kW| %5.2f %% |  %5.2f anos  |    %5.2f %%    | %5.1f ms| %5.2f °C|   %s\n', ...
        sweep_w_B(i), sweep_P_ecl_kW(i), sweep_P_sun_kW(i), sweep_DoD_pct(i), ...
        sweep_life_yr(i), sweep_eta_harv(i), sweep_T_lat_ms(i), sweep_Tj_max(i), par_str);
end
fprintf('========================================================================================\n');

end
