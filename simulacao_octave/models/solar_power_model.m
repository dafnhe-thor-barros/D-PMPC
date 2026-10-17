function solar_data = solar_power_model(p, xi, theta_inc, T_sa)
% SOLAR_POWER_MODEL - Modelo físico da geração fotovoltaica espacial (GaAs).
%
% Entradas:
%   p         - Estrutura de parâmetros do sistema (parameters.m)
%   xi        - Estado de iluminação [N_t x N_sat] (1 = Sol, 0 = Eclipse)
%   theta_inc - [Opcional] Ângulo de incidência solar [rad] (padrão: 0, SADM ativo)
%   T_sa      - [Opcional] Temperatura dos painéis solares [K] (padrão: p.solar.T_sa_nom)
%
% Saídas (estrutura solar_data):
%   .P_pv_stc   - Potência nominal de pico em STC [W]
%   .P_pv_avail - Potência fotovoltaica disponível no MPP [W] [N_t x N_sat]
%   .P_bus_net  - Potência entregue ao barramento HVDC após conversor [W] [N_t x N_sat]
%   .T_sa       - Matriz de temperatura dos painéis solares [K]
%   .theta_inc  - Matriz de ângulo de incidência [rad]

[N_t, N_sat] = size(xi);

if nargin < 3 || isempty(theta_inc)
    theta_inc = zeros(N_t, N_sat); % SADM mantém alinhamento normal ideal cos(theta) = 1
end

if nargin < 4 || isempty(T_sa)
    % Temperatura nominal em luz; no eclipse, os painéis resfriam para ~180 K
    % mas xi = 0 anula a geração.
    T_sa = repmat(p.solar.T_sa_nom, N_t, N_sat);
end

% 1. Potência de pico nominal em condições padrão de teste (STC: 25 °C, cos=1, AM0)
P_pv_stc = p.solar.A_sa * p.solar.eta_sa * p.const.S0; % 182,918.4 W

% 2. Fator de temperatura: [1 - gamma_T * (T_sa - T_ref)]
temp_factor = 1.0 - p.solar.gamma_T * (T_sa - p.solar.T_ref);

% 3. Fator de incidência: max(cos(theta_inc), 0)
inc_factor = max(cos(theta_inc), 0.0);

% 4. Potência disponível no ponto de máxima potência (MPP):
% P_pv_avail = xi * A_sa * eta_sa * S0 * cos(theta_inc) * [1 - gamma_T*(T_sa - T_ref)]
P_pv_avail = xi .* (P_pv_stc .* inc_factor .* temp_factor);
P_pv_avail = max(P_pv_avail, 0.0); % Garantir não negatividade

% 5. Potência líquida entregue ao barramento HVDC de 400 V através do conversor
P_bus_net = p.solar.eta_conv * P_pv_avail;

% Montagem da estrutura de saída
solar_data.P_pv_stc   = P_pv_stc;
solar_data.P_pv_avail = P_pv_avail;
solar_data.P_bus_net  = P_bus_net;
solar_data.T_sa       = T_sa;
solar_data.theta_inc  = theta_inc;

end
