function orbit_data = orbit_model(p, t_vec, sat_indices)
% ORBIT_MODEL - Propagação cinemática e posições tridimensionais (ECI)
% da constelação Walker-Delta de Centros de Dados Orbitais (ODC).
%
% Entradas:
%   p           - Estrutura de parâmetros do sistema (gerada por parameters.m)
%   t_vec       - Vetor de tempos de simulação [s] (1 x N_t)
%   sat_indices - [Opcional] Índices dos satélites a propagar (padrão: 1:N_sat)
%
% Saídas (estrutura orbit_data):
%   .t          - Vetor de tempos [s]
%   .a          - Semi-eixo maior [m]
%   .n          - Movimento médio [rad/s]
%   .tau        - Período orbital [s]
%   .v_orb      - Velocidade orbital [m/s]
%   .r_eci      - Posições ECI [m] (3 x N_t x N_sat)
%   .v_eci      - Velocidades ECI [m/s] (3 x N_t x N_sat)
%   .plane_idx  - Índice do plano orbital de cada satélite (1 a P)
%   .sat_in_p   - Índice do satélite dentro do seu plano (1 a S)
%   .RAAN       - Ângulo do nó ascendente Omega(t) para cada satélite [rad]
%   .u          - Argumento de latitude u(t) para cada satélite [rad]

if nargin < 3 || isempty(sat_indices)
    sat_indices = 1:p.orbit.N_sat;
end

N_t = length(t_vec);
N_sat_eval = length(sat_indices);

% 1. Parâmetros orbitais derivados
a = p.orbit.a;
mu = p.const.mu_E;
inc = p.orbit.inc;
n = sqrt(mu / a^3); % Movimento médio [rad/s]
tau = 2 * pi / n;   % Período Kepleriano [s]
v_orb = sqrt(mu / a); % Velocidade orbital [m/s]

% Taxa secular de precessão do nó ascendente devida ao J2 [rad/s] (Eq. 6)
J2 = p.const.J2;
R_E = p.const.R_E;
RAAN_dot = -1.5 * J2 * (R_E / a)^2 * n * cos(inc);

% 2. Alocação de memória
r_eci = zeros(3, N_t, p.orbit.N_sat);
v_eci = zeros(3, N_t, p.orbit.N_sat);
RAAN_mat = zeros(N_t, p.orbit.N_sat);
u_mat = zeros(N_t, p.orbit.N_sat);
plane_idx = zeros(1, p.orbit.N_sat);
sat_in_p = zeros(1, p.orbit.N_sat);

% 3. Mapeamento da constelação Walker-Delta i: N_sat / P / F
% N_sat = 32, P = 4, F = 1 -> S = 8 satélites por plano
P = p.orbit.P;
S = p.orbit.S_per_P;
F = p.orbit.F;

% Matriz de rotação em função da inclinação
cos_i = cos(inc);
sin_i = sin(inc);

for idx = 1:p.orbit.N_sat
    % Índices baseados em zero
    sat_id0 = idx - 1;
    p_id0 = floor(sat_id0 / S); % Plano 0 a P-1
    s_id0 = mod(sat_id0, S);   % Satélite 0 a S-1
    
    plane_idx(idx) = p_id0 + 1;
    sat_in_p(idx)  = s_id0 + 1;
    
    % RAAN inicial do plano p: Omega_0 = p * (2*pi / P)
    Omega_0 = p_id0 * (2 * pi / P);
    
    % Anomalia média inicial (em órbita circular u_0 = M_0):
    % M_0 = s * (2*pi / S) + p * F * (2*pi / N_sat)
    u_0 = s_id0 * (2 * pi / S) + p_id0 * F * (2 * pi / p.orbit.N_sat);
    
    % Evolução temporal para este satélite
    % u(t) = u_0 + n * t
    u_t = mod(u_0 + n * t_vec, 2 * pi);
    % RAAN(t) com precessão J2
    Omega_t = mod(Omega_0 + RAAN_dot * t_vec, 2 * pi);
    
    u_mat(:, idx) = u_t;
    RAAN_mat(:, idx) = Omega_t;
    
    % Coordenadas no plano orbital perifocal
    % x_orb = a * cos(u), y_orb = a * sin(u), z_orb = 0
    % vx_orb = -a*n * sin(u), vy_orb = a*n * cos(u), vz_orb = 0
    cos_u = cos(u_t);
    sin_u = sin(u_t);
    cos_Om = cos(Omega_t);
    sin_Om = sin(Omega_t);
    
    % Transformação para ECI:
    % X = a * (cos(Om)*cos(u) - sin(Om)*sin(u)*cos(i))
    % Y = a * (sin(Om)*cos(u) + cos(Om)*sin(u)*cos(i))
    % Z = a * (sin(u)*sin(i))
    r_eci(1, :, idx) = a * (cos_Om .* cos_u - sin_Om .* sin_u * cos_i);
    r_eci(2, :, idx) = a * (sin_Om .* cos_u + cos_Om .* sin_u * cos_i);
    r_eci(3, :, idx) = a * (sin_u * sin_i);
    
    % Velocidades ECI (derivada temporal analítica exata):
    % v_eci = v_Kepler + omega_prec x r_eci
    % onde omega_prec = [0; 0; RAAN_dot]
    v_kep_x = (a * n) * (-cos_Om .* sin_u - sin_Om .* cos_u * cos_i);
    v_kep_y = (a * n) * (-sin_Om .* sin_u + cos_Om .* cos_u * cos_i);
    v_kep_z = (a * n) * (cos_u * sin_i);
    
    r_x = r_eci(1, :, idx);
    r_y = r_eci(2, :, idx);
    
    v_eci(1, :, idx) = v_kep_x - RAAN_dot * r_y;
    v_eci(2, :, idx) = v_kep_y + RAAN_dot * r_x;
    v_eci(3, :, idx) = v_kep_z;
end

% 4. Montagem da estrutura de saída
orbit_data.t         = t_vec;
orbit_data.a         = a;
orbit_data.n         = n;
orbit_data.tau       = tau;
orbit_data.v_orb     = v_orb;
orbit_data.RAAN_dot  = RAAN_dot;
orbit_data.r_eci     = r_eci;
orbit_data.v_eci     = v_eci;
orbit_data.plane_idx = plane_idx;
orbit_data.sat_in_p  = sat_in_p;
orbit_data.RAAN      = RAAN_mat;
orbit_data.u         = u_mat;

end
