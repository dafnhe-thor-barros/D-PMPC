function thermal_data = thermal_model(p, P_comp, xi, dt, T_j_init, T_rad_init, use_taylor)
% THERMAL_MODEL - Rede térmica nodal de 2 nós (Silício + Radiador Bifacial LHP)
% com rejeição radiativa não-linear de Stefan-Boltzmann, estagiamento de área
% no eclipse via válvulas de bypass e modelo afim linearizado de Taylor.
%
% Implementação 100% vetorizada para alta performance em GNU Octave.
%
% Equações Físicas Implementadas:
%   EQ-17: C_th_j * dT_j/dt = P_comp - (T_j - T_rad) / R_th_j_rad
%   EQ-18: C_th_rad * dT_rad/dt = (T_j - T_rad) / R_th_j_rad + Q_env - eps * sigma * A_rad * (T_rad^4 - T_space^4)
%   EQ-19: T_rad^4 \approx 4 * T_bar^3 * T_rad - 3 * T_bar^4 (Taylor em T_bar = 337.0 K)
%   EQ-20: Espaço de estados afim contínuo e discretizado
%
% Entradas:
%   p          - Estrutura de parâmetros do sistema (parameters.m)
%   P_comp     - Potência computacional dos nós [W] [N_t x N_sat]
%   xi         - Sinal binário de eclipse [N_t x N_sat] (1 = Sol, 0 = Eclipse)
%   dt         - Passo de tempo de integração [s] (padrão: p.mpc.dt)
%   T_j_init   - [Opcional] Temperatura inicial da junção [K] (padrão: 345.0 K)
%   T_rad_init - [Opcional] Temperatura inicial do radiador [K] (padrão: 337.0 K)
%   use_taylor - [Opcional] Booleano (padrão: false). Se true, usa modelo afim de Taylor
%
% Saídas (estrutura thermal_data):
%   .T_j          - Temperatura de junção do silício [K] [N_t x N_sat]
%   .T_j_degC     - Temperatura de junção [°C] [N_t x N_sat]
%   .T_rad        - Temperatura dos painéis radiadores [K] [N_t x N_sat]
%   .T_rad_degC   - Temperatura dos radiadores [°C] [N_t x N_sat]
%   .A_rad        - Área radiativa efetiva instantânea [m^2] [N_t x N_sat]
%   .Q_env        - Carga térmica ambiental incidente [W] [N_t x N_sat]
%   .Q_rad        - Taxa instantânea de calor irradiado [W] [N_t x N_sat]
%   .T_j_max      - Pico máximo de temperatura da junção [K e °C]
%   .T_j_min      - Temperatura mínima da junção [K e °C]
%   .delta_T_j    - Amplitude de oscilação térmica (swing) [K ou °C]
%   .ss_sun       - Ponto de equilíbrio estático analítico em sol
%   .ss_ecl       - Ponto de equilíbrio estático analítico em eclipse
%   .linear_model - Matrizes A, B, E, d do modelo afim linearizado em tempo contínuo

[N_t, N_sat] = size(P_comp);

if nargin < 4 || isempty(dt)
    dt = p.mpc.dt;
end

if nargin < 5 || isempty(T_j_init)
    T_j_init = repmat(345.0, 1, N_sat); % ~71.85 °C
elseif isscalar(T_j_init)
    T_j_init = repmat(T_j_init, 1, N_sat);
end

if nargin < 6 || isempty(T_rad_init)
    T_rad_init = repmat(p.thermal.T_rad_nom, 1, N_sat); % 337.0 K
elseif isscalar(T_rad_init)
    T_rad_init = repmat(T_rad_init, 1, N_sat);
end

if nargin < 7 || isempty(use_taylor)
    use_taylor = false;
end

% Parâmetros térmicos centrais
C_j     = p.thermal.C_th_j;        % [J/K] (4500 J/K)
C_rad   = p.thermal.C_th_rad;      % [J/K] (110000 J/K)
R_th    = p.thermal.R_th_j_rad;    % [K/W] (7.25e-5 K/W)
eps_rad = p.thermal.epsilon_rad;   % [-] (0.91)
sigma   = p.const.sigma_SB;        % [W/(m^2 K^4)] (5.67037e-8)
T_space = p.const.T_space;         % [K] (3.0 K)
T_bar   = p.thermal.T_rad_nom;     % [K] (337.0 K) ponto de Taylor

% Áreas radiativas e constantes
A_eff_sun  = p.thermal.A_rad_eff;   % [m^2] (228.4 m^2 em sol)
A_eff_ecl  = p.thermal.A_rad_stage; % [m^2] (58.5 m^2 estagiado em eclipse)
tau_valve  = 30.0;                 % [s] Constante de tempo das válvulas de bypass (UNRES-04)

% Cargas térmicas ambientais
Q_env_sun  = p.thermal.Q_env_sun;  % [W] (12000 W)
Q_env_ecl  = p.thermal.Q_env_ecl;  % [W] (4500 W)

% Pré-cálculo de inversos para evitar divisões no laço temporal
inv_Cj_Rth   = 1.0 / (C_j * R_th);
inv_Cj       = 1.0 / C_j;
inv_Crad_Rth = 1.0 / (C_rad * R_th);
inv_Crad     = 1.0 / C_rad;
eps_sigma    = eps_rad * sigma;
T_space4     = T_space^4;

% Alocação de matrizes de trajetória
T_j   = zeros(N_t, N_sat);
T_rad = zeros(N_t, N_sat);
A_rad = zeros(N_t, N_sat);
Q_rad = zeros(N_t, N_sat);

% Pré-computar alvos de área e cargas ambientais
A_target  = A_eff_ecl + (A_eff_sun - A_eff_ecl) .* (xi == 1);
Q_env_all = Q_env_ecl + (Q_env_sun - Q_env_ecl) .* (xi == 1);

% Condições iniciais vetorizadas [1 x N_sat]
T_j(1, :)   = T_j_init;
T_rad(1, :) = T_rad_init;
A_rad(1, :) = A_target(1, :);

% Sub-passos de integração RK4 vetorizada para garantir estabilidade da dinâmica rápida
sub_steps = 4; % Com dt = 2.0 s, h_sub = 0.5 s (estável e exato para RK4 de 4a ordem)
h_sub = dt / sub_steps;
alpha_valve = 1.0 - exp(-h_sub / tau_valve);

% Estado vetorizado de trabalho
tj   = T_j_init;
trad = T_rad_init;
a_r  = A_target(1, :);

% Laço temporal 100% vetorizado em N_sat (zero laços aninhados por satélite)
if ~use_taylor
    % === PLANTA FÍSICA NÃO-LINEAR (STEFAN-BOLTZMANN T^4) ===
    for k = 1:(N_t - 1)
        p_c = P_comp(k, :);
        q_e = Q_env_all(k, :);
        a_t = A_target(k, :);
        
        for sub = 1:sub_steps
            a_r = a_r + (a_t - a_r) * alpha_valve;
            
            % Estágio k1
            q_cond1 = (tj - trad) * inv_Cj_Rth;
            dtj1 = p_c * inv_Cj - q_cond1;
            dtrad1 = (tj - trad) * inv_Crad_Rth + (q_e - eps_sigma .* a_r .* (trad.^4 - T_space4)) * inv_Crad;
            
            % Estágio k2
            tj2 = tj + 0.5 * h_sub * dtj1;
            trad2 = trad + 0.5 * h_sub * dtrad1;
            q_cond2 = (tj2 - trad2) * inv_Cj_Rth;
            dtj2 = p_c * inv_Cj - q_cond2;
            dtrad2 = (tj2 - trad2) * inv_Crad_Rth + (q_e - eps_sigma .* a_r .* (trad2.^4 - T_space4)) * inv_Crad;
            
            % Estágio k3
            tj3 = tj + 0.5 * h_sub * dtj2;
            trad3 = trad + 0.5 * h_sub * dtrad2;
            q_cond3 = (tj3 - trad3) * inv_Cj_Rth;
            dtj3 = p_c * inv_Cj - q_cond3;
            dtrad3 = (tj3 - trad3) * inv_Crad_Rth + (q_e - eps_sigma .* a_r .* (trad3.^4 - T_space4)) * inv_Crad;
            
            % Estágio k4
            tj4 = tj + h_sub * dtj3;
            trad4 = trad + h_sub * dtrad3;
            q_cond4 = (tj4 - trad4) * inv_Cj_Rth;
            dtj4 = p_c * inv_Cj - q_cond4;
            dtrad4 = (tj4 - trad4) * inv_Crad_Rth + (q_e - eps_sigma .* a_r .* (trad4.^4 - T_space4)) * inv_Crad;
            
            % Atualização RK4
            tj   = tj + (h_sub / 6.0) * (dtj1 + 2.0*dtj2 + 2.0*dtj3 + dtj4);
            trad = trad + (h_sub / 6.0) * (dtrad1 + 2.0*dtrad2 + 2.0*dtrad3 + dtrad4);
        end
        
        T_j(k + 1, :)   = tj;
        T_rad(k + 1, :) = trad;
        A_rad(k + 1, :) = a_r;
        Q_rad(k, :)     = eps_sigma .* a_r .* (trad.^4 - T_space4);
    end
else
    % === MODELO AFIM LINEARIZADO DE TAYLOR EM TORNO DE T_bar = 337 K ===
    for k = 1:(N_t - 1)
        p_c = P_comp(k, :);
        q_e = Q_env_all(k, :);
        a_t = A_target(k, :);
        
        for sub = 1:sub_steps
            a_r = a_r + (a_t - a_r) * alpha_valve;
            
            K_r = 4.0 * eps_sigma .* a_r * (T_bar^3);
            d_r = 3.0 * eps_sigma .* a_r * (T_bar^4) + eps_sigma .* a_r * T_space4;
            
            % Estágio k1
            q_cond1 = (tj - trad) * inv_Cj_Rth;
            dtj1 = p_c * inv_Cj - q_cond1;
            dtrad1 = (tj - trad) * inv_Crad_Rth + (q_e - K_r .* trad + d_r) * inv_Crad;
            
            % Estágio k2
            tj2 = tj + 0.5 * h_sub * dtj1;
            trad2 = trad + 0.5 * h_sub * dtrad1;
            q_cond2 = (tj2 - trad2) * inv_Cj_Rth;
            dtj2 = p_c * inv_Cj - q_cond2;
            dtrad2 = (tj2 - trad2) * inv_Crad_Rth + (q_e - K_r .* trad2 + d_r) * inv_Crad;
            
            % Estágio k3
            tj3 = tj + 0.5 * h_sub * dtj2;
            trad3 = trad + 0.5 * h_sub * dtrad2;
            q_cond3 = (tj3 - trad3) * inv_Cj_Rth;
            dtj3 = p_c * inv_Cj - q_cond3;
            dtrad3 = (tj3 - trad3) * inv_Crad_Rth + (q_e - K_r .* trad3 + d_r) * inv_Crad;
            
            % Estágio k4
            tj4 = tj + h_sub * dtj3;
            trad4 = trad + h_sub * dtrad3;
            q_cond4 = (tj4 - trad4) * inv_Cj_Rth;
            dtj4 = p_c * inv_Cj - q_cond4;
            dtrad4 = (tj4 - trad4) * inv_Crad_Rth + (q_e - K_r .* trad4 + d_r) * inv_Crad;
            
            % Atualização RK4
            tj   = tj + (h_sub / 6.0) * (dtj1 + 2.0*dtj2 + 2.0*dtj3 + dtj4);
            trad = trad + (h_sub / 6.0) * (dtrad1 + 2.0*dtrad2 + 2.0*dtrad3 + dtrad4);
        end
        
        T_j(k + 1, :)   = tj;
        T_rad(k + 1, :) = trad;
        A_rad(k + 1, :) = a_r;
        Q_rad(k, :)     = eps_sigma .* a_r .* (trad.^4 - T_space4);
    end
end

% Último ponto para registro de radiação
Q_rad(end, :) = eps_sigma .* A_rad(end, :) .* (T_rad(end, :).^4 - T_space4);

% Conversão para graus Celsius
T_j_degC   = T_j - 273.15;
T_rad_degC = T_rad - 273.15;

% Métricas térmicas consolidadas
thermal_data.T_j        = T_j;
thermal_data.T_j_degC   = T_j_degC;
thermal_data.T_rad      = T_rad;
thermal_data.T_rad_degC = T_rad_degC;
thermal_data.A_rad      = A_rad;
thermal_data.Q_env      = Q_env_all;
thermal_data.Q_rad      = Q_rad;
thermal_data.T_j_max    = max(T_j(:));
thermal_data.T_j_min    = min(T_j(:));
thermal_data.T_j_max_degC = thermal_data.T_j_max - 273.15;
thermal_data.T_j_min_degC = thermal_data.T_j_min - 273.15;
thermal_data.delta_T_j  = thermal_data.T_j_max - thermal_data.T_j_min;

% Pontos de equilíbrio estático teóricos (analíticos):
% Sol (140 kW, 12 kW env, 228.4 m^2):
Q_total_sun_nom = 140.0e3 + Q_env_sun;
trad_ss_sun_nom = (Q_total_sun_nom / (eps_sigma * A_eff_sun) + T_space4)^(0.25);
tj_ss_sun_nom   = trad_ss_sun_nom + (140.0e3 * R_th);

% Eclipse nominal (31 kW, 4.5 kW env, 58.5 m^2 com estagiamento):
Q_total_ecl_nom = p.eps.P_comp_min + Q_env_ecl;
trad_ss_ecl_nom = (Q_total_ecl_nom / (eps_sigma * A_eff_ecl) + T_space4)^(0.25);
tj_ss_ecl_nom   = trad_ss_ecl_nom + (p.eps.P_comp_min * R_th);

% Eclipse sem estagiamento (área total 228.4 m^2 aberta):
trad_ss_ecl_nostage = (Q_total_ecl_nom / (eps_sigma * A_eff_sun) + T_space4)^(0.25);
tj_ss_ecl_nostage   = trad_ss_ecl_nostage + (p.eps.P_comp_min * R_th);

thermal_data.ss_sun.T_rad = trad_ss_sun_nom;
thermal_data.ss_sun.T_j   = tj_ss_sun_nom;
thermal_data.ss_sun.T_j_degC = tj_ss_sun_nom - 273.15;

thermal_data.ss_ecl.T_rad = trad_ss_ecl_nom;
thermal_data.ss_ecl.T_j   = tj_ss_ecl_nom;
thermal_data.ss_ecl.T_j_degC = tj_ss_ecl_nom - 273.15;

thermal_data.ss_ecl_nostage.T_rad = trad_ss_ecl_nostage;
thermal_data.ss_ecl_nostage.T_j   = tj_ss_ecl_nostage;
thermal_data.ss_ecl_nostage.T_j_degC = tj_ss_ecl_nostage - 273.15;

% Matrizes do modelo linear afim contínuo em torno de T_bar = 337.0 K e A_eff_sun:
K_r_nom = 4.0 * eps_sigma * A_eff_sun * (T_bar^3);
d_r_nom = 3.0 * eps_sigma * A_eff_sun * (T_bar^4) + eps_sigma * A_eff_sun * T_space4;

thermal_data.linear_model.A_th = [ ...
    -1.0 / (C_j * R_th),               1.0 / (C_j * R_th); ...
     1.0 / (C_rad * R_th), -1.0 / (C_rad * R_th) - K_r_nom / C_rad ...
];
thermal_data.linear_model.B_th = [1.0 / C_j; 0.0];
thermal_data.linear_model.E_th = [0.0; 1.0 / C_rad];
thermal_data.linear_model.d_th = [0.0; d_r_nom / C_rad];

end
