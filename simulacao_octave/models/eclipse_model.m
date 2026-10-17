function eclipse_data = eclipse_model(p, orbit_data, sun_vector)
% ECLIPSE_MODEL - Determinação física tridimensional de eclipse (sombra terrestre)
% para a constelação Walker-Delta de ODCs.
%
% Entradas:
%   p           - Estrutura de parâmetros do sistema (gerada por parameters.m)
%   orbit_data  - Estrutura gerada por orbit_model.m contendo r_eci e tempos
%   sun_vector  - [Opcional] Vetor solar unitário s_hat em ECI [3 x 1] ou [3 x N_t]
%                 (padrão: equinócio com beta = 0 para o plano 1: s_hat = [1; 0; 0])
%
% Saídas (estrutura eclipse_data):
%   .xi         - Matriz de estado de iluminação [N_t x N_sat] (1 = Sol, 0 = Eclipse)
%   .s_hat      - Vetor solar unitário [3 x N_t]
%   .s_proj     - Projeção r . s_hat [N_t x N_sat] [m]
%   .d_perp     - Distância perpendicular ao eixo Sol-Terra [N_t x N_sat] [m]
%   .in_shadow  - Booleano de sombra [N_t x N_sat]
%   .t_ecl_num  - Duração numérica de eclipse por satélite [s] e [min]
%   .t_sun_num  - Duração numérica de luz por satélite [s] e [min]
%   .frac_lit   - Fração instantânea da constelação iluminada [N_t x 1]

N_t = length(orbit_data.t);
N_sat = p.orbit.N_sat;
R_E = p.const.R_E;
a = p.orbit.a;

% 1. Definição do vetor solar unitário em ECI ou regime de iluminação
is_full_sun = false;

if nargin < 3 || isempty(sun_vector)
    sun_vector = 'max_eclipse';
end

if ischar(sun_vector)
    switch lower(sun_vector)
        case {'max_eclipse', 'max_shadow', 'default'}
            % Por padrão, Sol alinhado no eixo X em ECI (delta_s = 0, alpha_s = 0)
            % Para o plano 1 com Omega = 0, resulta em beta = 0 (máximo eclipse absoluto)
            s_hat = repmat([1; 0; 0], 1, N_t);
        case {'intermediate', 'inter'}
            % Sol gerando ângulo beta = 45 deg para o Plano 1 (eclipse intermediário)
            inc = p.orbit.inc;
            beta_val = 45.0 * pi / 180.0;
            s_unit = [cos(beta_val); -sin(beta_val)*sin(inc); sin(beta_val)*cos(inc)];
            s_hat = repmat(s_unit / norm(s_unit), 1, N_t);
        case {'full_sun', 'total_insolation', 'no_eclipse'}
            % Insolação total: toda a constelação iluminada continuamente (100% sol, 0% sombra)
            s_hat = repmat([0; 0; 1], 1, N_t);
            is_full_sun = true;
        otherwise
            error('Regime de iluminação não reconhecido: %s', sun_vector);
    end
elseif isnumeric(sun_vector)
    if size(sun_vector, 2) == 1
        s_hat = repmat(sun_vector(:) / norm(sun_vector), 1, N_t);
    else
        s_hat = sun_vector ./ sqrt(sum(sun_vector.^2, 1));
    end
end

% 2. Avaliação da condição geométrica de eclipse cilíndrico (Eq. 3 e 4)
% Condição: r . s_hat < 0 (lado noturno) E ||r - (r . s_hat) s_hat|| <= R_E
xi = ones(N_t, N_sat);
s_proj = zeros(N_t, N_sat);
d_perp = zeros(N_t, N_sat);
in_shadow = false(N_t, N_sat);

if is_full_sun
    % Insolação total: nenhum satélite entra em sombra durante toda a simulação
    xi(:) = 1.0;
    in_shadow(:) = false;
    s_proj(:) = a;
    d_perp(:) = 2.0 * R_E;
else


for s = 1:N_sat
    r_s = squeeze(orbit_data.r_eci(:, :, s)); % [3 x N_t]
    
    % Projeção escalar ao longo do vetor solar: r . s_hat
    proj = sum(r_s .* s_hat, 1); % [1 x N_t]
    s_proj(:, s) = proj';
    
    % Componente perpendicular: r_perp = r - proj * s_hat
    r_perp = r_s - repmat(proj, 3, 1) .* s_hat;
    dist_perp = sqrt(sum(r_perp.^2, 1)); % [1 x N_t]
    d_perp(:, s) = dist_perp';
    
    % Condição de sombra umbra (cilíndrica)
    shadow_mask = (proj < 0) & (dist_perp <= R_E);
    in_shadow(:, s) = shadow_mask';
    
    % Estado de iluminação: 0 em sombra, 1 em luz
    xi(shadow_mask, s) = 0.0;
end
end

% 3. Fração instantânea de satélites iluminados na constelação
frac_lit = mean(xi, 2); % [N_t x 1]

% 4. Duração numérica de eclipse e luz ao longo de uma revolução (se simulado >= tau)
dt = orbit_data.t(2) - orbit_data.t(1);
t_ecl_num = zeros(1, N_sat);
t_sun_num = zeros(1, N_sat);

% Medição ao longo do primeiro período completo
idx_1tau = find(orbit_data.t <= orbit_data.tau);
if isempty(idx_1tau)
    idx_1tau = 1:N_t;
end

for s = 1:N_sat
    t_ecl_num(s) = sum(xi(idx_1tau, s) == 0) * dt;
    t_sun_num(s) = sum(xi(idx_1tau, s) == 1) * dt;
end

% 5. Montagem da estrutura de saída
eclipse_data.xi        = xi;
eclipse_data.s_hat     = s_hat;
eclipse_data.s_proj    = s_proj;
eclipse_data.d_perp    = d_perp;
eclipse_data.in_shadow = in_shadow;
eclipse_data.frac_lit  = frac_lit;
eclipse_data.t_ecl_num = t_ecl_num;
eclipse_data.t_sun_num = t_sun_num;
eclipse_data.t_ecl_min = t_ecl_num / 60.0;
eclipse_data.t_sun_min = t_sun_num / 60.0;

end
