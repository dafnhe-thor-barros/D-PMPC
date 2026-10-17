function p = parameters()
% PARAMETERS - Definição centralizada de parâmetros, constantes e hipóteses
% para a simulação em GNU Octave da constelação de Centros de Dados Orbitais (ODC).
%
% Classificação de Origem dos Parâmetros:
%   [1] Valor fornecido pelo artigo ou por arquivo do projeto.
%   [2] Constante física documentada (CODATA, IAU, IERS).
%   [3] Especificação de componente ou sistema com fonte identificável.
%   [4] Hipótese de modelagem explicitamente declarada / Diretriz de conservadorismo.
%   [5] UNRESOLVED_PARAMETER (parâmetro ausente, estimado com justificativa física).
%
% Sistema de Unidades: SI (m, kg, s, W, J, K, rad) salvo indicação explícita.

p = struct();

%% 1. Metadados do Projeto
p.meta.project = 'Simulacao ODC - Artigo 05 IEEE LATAMT';
p.meta.title = 'Predictive Distributed Workload Orchestration via OISL for ODC Constellations';
p.meta.authors = 'Dafnhe Thor C. M. Barros e Flavio Barcelos Braz da Silva';
p.meta.octave_version_required = '6.0.0';
p.meta.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');

%% 2. Modo Conservador de Rendimentos de Segurança [Diretriz do Usuário - Origem 4]
% Redução ultraconservadora de eta_conv de 0.985 para 0.90 (-8.63%),
% aplicando a mesma redução proporcional a todos os demais rendimentos.
p.conservative.enabled           = true;
p.conservative.eta_conv_nominal  = 0.985; % [1] Valor nominal do artigo
p.conservative.eta_conv          = 0.900; % [4] Ultraconservador de segurança
p.conservative.derate_ratio      = p.conservative.eta_conv / p.conservative.eta_conv_nominal; % ~0.9137056

% Rendimentos nominais do artigo (para rastreabilidade)
p.nominal.eta_conv = 0.985;
p.nominal.eta_sa   = 0.320;
p.nominal.eta_dis  = 0.960;
p.nominal.eta_chg  = 0.940;
p.nominal.P_comp_sun = 140.0e3; % [W] Carga computacional em luz

%% 3. Constantes Físicas Documentadas [Origem: 2]
p.const.mu_E     = 3.986004418e14;   % [m^3/s^2] Parâmetro gravitacional padrão da Terra (EGM2008)
p.const.R_E      = 6378137.0;        % [m] Raio equatorial médio da Terra (WGS-84)
p.const.J2       = 1.08263e-3;       % [-] Segundo harmônico zonal do potencial gravitacional terrestre
p.const.c        = 299792458.0;      % [m/s] Velocidade da luz no vácuo
p.const.sigma_SB = 5.670374419e-8;   % [W/(m^2 K^4)] Constante de Stefan-Boltzmann
p.const.S0       = 1361.0;           % [W/m^2] Constante solar AM0 (Kopp & Lean, 2011)
p.const.R_gas    = 8.314462618;      % [J/(mol K)] Constante universal dos gases
p.const.T_space  = 3.0;              % [K] Temperatura efetiva de radiação do espaço profundo

%% 4. Geometria e Dinâmica Orbital LEO [Origens: 1, 2, 4]
p.orbit.h         = 550.0e3;         % [m] Altitude orbital circular [1]
p.orbit.a         = p.const.R_E + p.orbit.h; % [m] Semi-eixo maior (6,928,137 m) [1]
p.orbit.inc       = deg2rad(53.0);   % [rad] Inclinação orbital (53.0 graus) [1]
p.orbit.inc_deg   = 53.0;            % [deg]
p.orbit.N_sat     = 32;              % [-] Número total de satélites na constelação [1]
p.orbit.P         = 4;               % [-] Número de planos orbitais igualmente espaçados [1]
p.orbit.S_per_P   = p.orbit.N_sat / p.orbit.P; % [-] Satélites por plano (8) [1]
p.orbit.F         = 1;               % [-] Parâmetro de fase relativo de Walker [1]
p.orbit.delta_RAAN= 2 * pi / p.orbit.P; % [rad] Espaçamento nodal entre planos (90 deg) [1]

% Grandezas orbitais derivadas analiticamente
p.orbit.tau       = 2 * pi * sqrt(p.orbit.a^3 / p.const.mu_E); % [s] (~5738.99 s = 95.65 min) [1, 2]
p.orbit.tau_min   = p.orbit.tau / 60.0; % [min] (~95.65 min)
p.orbit.v_orb     = sqrt(p.const.mu_E / p.orbit.a); % [m/s] (~7585.09 m/s) [1, 2]
p.orbit.beta_crit = asin(p.const.R_E / p.orbit.a); % [rad] (~67.016 deg) [1, 2]
p.orbit.beta_crit_deg = rad2deg(p.orbit.beta_crit); % [deg]
p.orbit.beta_sim  = 0.0;             % [rad] Ângulo beta da simulação nominal (pior caso: beta = 0) [4]

% Duração analítica do eclipse para beta = 0
p.orbit.t_ecl_nominal = (p.orbit.tau / pi) * acos(sqrt(p.orbit.a^2 - p.const.R_E^2) / p.orbit.a); % [s] (~2136.69 s = 35.61 min) [1, 2]
p.orbit.t_sun_nominal = p.orbit.tau - p.orbit.t_ecl_nominal; % [s] (~3602.3 s = 60.04 min)

%% 5. Subsistema de Energia Solar Fotovoltaica (PV) [Origens: 1, 3, 4]
p.solar.A_sa      = 420.0;           % [m^2] Área ativa dos painéis fotovoltaicos GaAs [1]

% Aplicação do fator conservador proporcional
if p.conservative.enabled
    p.solar.eta_sa   = p.nominal.eta_sa * p.conservative.derate_ratio; % ~0.292386 (29.24%) [4]
    p.solar.eta_conv = p.conservative.eta_conv; % 0.900 (90.0%) [4]
else
    p.solar.eta_sa   = p.nominal.eta_sa;   % 0.320 (32.0%) [1]
    p.solar.eta_conv = p.nominal.eta_conv; % 0.985 (98.5%) [1]
end

p.solar.gamma_T   = 0.0018;          % [1/K] Coeficiente térmico de perda de potência [1, 3]
p.solar.T_ref     = 298.15;          % [K] Temperatura de referência STC (25 °C) [1]
p.solar.T_sa_nom  = 320.0;           % [K] Temperatura nominal de operação dos painéis (46.85 °C) [1]
p.solar.P_pv_stc  = p.solar.A_sa * p.solar.eta_sa * p.const.S0; % [W] (167.13 kW conservador vs 182.92 kW nominal)

%% 6. Barramento Elétrico e Subsistema de Bateria (EPS / BESS) [Origens: 1, 3, 4, 5]
p.eps.V_bus       = 400.0;           % [V] Tensão nominal do barramento HVDC [1]
p.eps.P_bus       = 5000.0;          % [W] Potência de consumo base da plataforma [1]
p.eps.P_comp_nom  = 100.0e3;         % [W] Potência nominal da carga útil computacional [1]
p.eps.P_comp_max  = 150.0e3;         % [W] Potência máxima teórica dos aceleradores [1]
p.eps.P_comp_min  = 31.0e3;          % [W] Potência mínima estrangulada em eclipse [1]

% Carga computacional sustentável em luz sob rendimentos conservadores:
% (Com P_bus_net = 144.5 kW, para recarregar a bateria em 1 h a computação em luz deve ser ~110 kW)
if p.conservative.enabled
    p.eps.P_comp_sun = 110.0e3;      % [W] Carga máxima sustentável em luz sob conservadorismo [4]
else
    p.eps.P_comp_sun = p.nominal.P_comp_sun; % 140.0 kW nominal do artigo [1]
end

p.eps.P_load_uncoord = p.eps.P_comp_nom + p.eps.P_bus; % [W] (105,000 W) Carga do baseline no eclipse [1]

p.battery.E_nom_kWh = 125.0;         % [kWh] Capacidade energética nominal do BESS cooperativo [1]
p.battery.E_nom     = p.battery.E_nom_kWh * 3.6e6; % [J] (450.0 MJ) [1]
p.battery.E_nom_base_kWh = 250.0;    % [kWh] Capacidade energética da linha de base autônoma [1]
p.battery.E_nom_base     = p.battery.E_nom_base_kWh * 3.6e6; % [J] (900.0 MJ) [1]

% Aplicação do fator conservador proporcional às eficiências de bateria
if p.conservative.enabled
    p.battery.eta_dis = p.nominal.eta_dis * p.conservative.derate_ratio; % ~0.877157 (87.72%) [4]
    p.battery.eta_chg = p.nominal.eta_chg * p.conservative.derate_ratio; % ~0.858883 (85.89%) [4]
else
    p.battery.eta_dis = p.nominal.eta_dis; % 0.960 (96.0%) [1]
    p.battery.eta_chg = p.nominal.eta_chg; % 0.940 (94.0%) [1]
end

p.battery.SoC_init  = 1.0;           % [-] Estado de carga inicial (100%) [4]
p.battery.SoC_min_safe = 0.20;       % [-] Limite físico inferior de segurança [4]
p.battery.SoC_min_mpc  = 0.70;       % [-] Limite inferior de restrição no D-PMPC [1]
p.battery.SoC_max      = 1.00;       % [-] Limite superior [1]

% Modelo de degradação da bateria (Arrhenius e Lei de Potência) [Origens: 1, 3, 5]
p.battery.N_ref     = 9912.0;        % [-] Ciclos de referência até 80% EOL a DoD_ref [1]
p.battery.DoD_ref   = 0.80;          % [-] Profundidade de descarga de referência (80%) [1]
p.battery.v_eff     = 1.26;          % [-] Expoente de estresse de ciclo de vida [1]
p.battery.k_cal     = 0.011;         % [1/ano^(0.5)] Taxa de crescimento de filme SEI de calendário [1]
p.battery.E_a       = 31.7e3;        % [J/mol] Energia de ativação de Arrhenius [1]
p.battery.T_b_nom   = 293.15;        % [K] Temperatura controlada das células (20 °C) [1]
p.battery.u_curr    = 0.5;           % [-] Fator de taxa de corrente cinético [1]
p.battery.v_order   = 1.8;           % [-] Ordem de reação de degradação de Arrhenius [1]
p.battery.A_deg     = 1.0;           % [UNRESOLVED_PARAMETER] Fator pré-exponencial contínuo [5]

%% 7. Subsistema Térmico e Radiadores (LHP + Stefan-Boltzmann) [Origens: 1, 3, 4, 5]
p.thermal.C_th_j     = 4.5e3;        % [J/K] Capacitância térmica do cluster de processamento [1]
p.thermal.C_th_rad   = 110.0e3;      % [J/K] Capacitância térmica das asas radiadoras [1]
p.thermal.R_th_j_rad = 0.0725e-3;    % [K/W] Resistência térmica equivalente do Loop Heat Pipe [1]
p.thermal.A_rad_geom = 114.2;        % [m^2] Área geométrica de dois painéis (5.7 m x 10 m cada) [1]
p.thermal.A_rad_eff  = 228.4;        % [m^2] Área radiativa efetiva bifacial (2 * A_rad_geom) [1]
p.thermal.A_rad_stage= 58.5;         % [m^2] Área estagiada do condensador LHP em eclipse [1]
p.thermal.epsilon_rad= 0.91;         % [-] Emissividade infravermelha dos radiadores compostos [1]
p.thermal.T_j_max    = 358.15;       % [K] Temperatura máxima de confiabilidade do silício (85.0 °C) [1]
p.thermal.T_j_target = 338.15;       % [K] Temperatura alvo de controle (65.0 °C) [1]
p.thermal.T_rad_nom  = 337.0;        % [K] Ponto de equilíbrio de Taylor para linearização (63.85 °C) [1]
p.thermal.Q_env_sun  = 12.0e3;       % [W] Fluxo ambiental absorvido em luz [1]
p.thermal.Q_env_ecl  = 4.5e3;        % [W] [UNRESOLVED_PARAMETER: estimado via radiação IR terrestre] [5]

%% 8. Subsistema de Comunicação Óptica Inter-Satélite (OISL) [Origens: 1, 3]
p.oisl.lambda        = 1550e-9;      % [m] Comprimento de onda portadora óptica (1550 nm banda C) [1]
p.oisl.C_laser       = 40.0e9;       % [bps] Capacidade máxima duplex por terminal (40 Gbps) [1]
p.oisl.n_terminals   = 4;            % [-] Número de terminais OISL por satélite [1]
p.oisl.P_pat         = 35.0;         % [W] Consumo elétrico do conjunto PAT por terminal [1]
p.oisl.P_laser_tx    = 15.0;         % [W] Consumo da bomba laser do transmissor por terminal [1]
p.oisl.kappa_comm    = 1.2e-9;       % [J/bit] Consumo do DSP óptico (1.2 nJ/bit) [1]
p.oisl.R_avg_nom     = 32.0e9;       % [bps] Taxa média operacional por terminal (32 Gbps) [1]
p.oisl.d_min         = 1000.0e3;     % [m] Distância mínima entre nós adjacentes (1000 km) [1]
p.oisl.d_max         = 4500.0e3;     % [m] Distância máxima entre nós adjacentes (4500 km) [1]

%% 9. Modelo de Carga de Trabalho e Filas de Tarefas [Origens: 1, 4, 5]
p.workload.gamma_comp = 1.8e-12;     % [J/FLOP] Intensidade energética dos aceleradores neurais [1]
p.workload.alpha_task = 1.39e6;      % [FLOPs/bit] Densidade computacional de tensores [1]
p.workload.A_avg      = 2.4e16;      % [FLOPs/s] Taxa média de ingestão de novas tarefas [1]
p.workload.W_ref      = 2.4e17;      % [FLOPs] [UNRESOLVED_PARAMETER: escala de normalização no MPC] [5]
p.workload.W_max      = 2.4e18;      % [FLOPs] [UNRESOLVED_PARAMETER: capacidade máxima do buffer] [5]
p.workload.block_size_bytes = 62.5e6; % [bytes] Tamanho do bloco de tensores (62.5 MB = 500 Mbits) [1]
p.workload.block_size_bits  = p.workload.block_size_bytes * 8.0; % [bits] (500 Mbits)

%% 10. Parâmetros do Controlador Preditivo Distribuído (D-PMPC / ADMM) [Origens: 1, 4]
p.mpc.dt              = 10.0;        % [s] Intervalo de amostragem temporal [1]
p.mpc.H               = 36;          % [-] Horizonte preditivo (36 passos = 360 s = 6.0 min) [1]
p.mpc.w_B             = 0.85;        % [-] Peso da penalidade de bateria no custo [1]
p.mpc.w_T             = 0.10;        % [-] Peso da penalidade térmica [1]
p.mpc.w_Q             = 0.04;        % [-] Peso da penalidade de fila de espera [1]
p.mpc.w_comm          = 0.01;        % [-] Peso da penalidade de comunicação OISL [1]
p.mpc.w_f_B           = 2.50;        % [-] Peso do custo terminal de estado de carga da bateria [1]
p.mpc.rho             = 1.50;        % [-] Parâmetro de penalidade aumentada do ADMM [1]
p.mpc.tol_pri         = 1.0e-4;      % [-] Tolerância de resíduo primal [1]
p.mpc.tol_dual        = 1.0e-4;      % [-] Tolerância de resíduo dual [1]
p.mpc.max_admm_iter   = 20;          % [-] Número máximo de iterações do ADMM por passo [4]

%% 11. Orçamento de Massa da Plataforma (Tabela III) [Origens: 1, 3]
p.mass.baseline_total = 5460.0;      % [kg] Massa seca total do satélite autônomo linha de base [1]
p.mass.dpmpc_total    = 4842.0;      % [kg] Massa seca total do satélite cooperativo D-PMPC [1]
p.mass.net_savings    = 618.0;       % [kg] Economia líquida de massa seca (11.32%) [1]
p.mass.battery_base   = 1560.0;      % [kg] Bateria de 250 kWh [1]
p.mass.battery_dpmpc  = 780.0;       % [kg] Bateria de 125 kWh [1]
p.mass.rad_base       = 660.0;       % [kg] Radiador no corpo [1]
p.mass.rad_dpmpc      = 754.0;       % [kg] Asas bifaciais desdobráveis [1]
p.mass.oisl_dpmpc     = 68.0;        % [kg] 4 terminais OISL [1]

end
