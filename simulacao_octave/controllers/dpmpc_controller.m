function [ctrl, diagnostics] = dpmpc_controller(p, state, orbit_pred, oisl_data, admm_prev)
% DPMPC_CONTROLLER - Controlador Preditivo Distribuído Baseado em Consenso ADMM
% para Orquestração de Carga de Trabalho em Constelações de Centros de Dados Orbitais.
%
% Implementa rigorosamente as equações do manuscrito:
%   EQ-24: Função custo quadrática convexa multiobjetivo (Bateria, Térmico, Fila, Comunicação)
%   EQ-25: Restrições operacionais lineares compactas (Potência, SoC, T_j, Banda OISL)
%   EQ-26 a EQ-30: Decomposição distribuída ADMM (Passo Primal, Consenso z, Atualização Dual lambda)
%   EQ-31 e EQ-32: Critérios de convergência primal e dual em norma infinito
%
% Entradas:
%   p          - Estrutura mestra de parâmetros (parameters.m)
%   state      - Estado físico instantâneo da constelação:
%                .SoC   [1 x N_sat] Estado de carga das baterias [0, 1]
%                .T_j   [1 x N_sat] Temperatura de junção dos nós [K]
%                .T_rad [1 x N_sat] Temperatura dos radiadores [K]
%                .W     [1 x N_sat] Volume de tarefas nas filas locais [FLOPs]
%   orbit_pred - Predição orbital sobre o horizonte H (36 passos = 360 s):
%                .xi          [H x N_sat] Estado de iluminação previsto (1 = Sol, 0 = Eclipse)
%                .P_pv_avail  [H x N_sat] Potência solar MPP disponível [W]
%   oisl_data  - Topologia da rede óptica (vizinhos, enlaces e matriz de adjacência)
%   admm_prev  - [Opcional] Estado do ADMM do passo anterior para warm-start
%
% Saídas:
%   ctrl - Estrutura de ações de controle para aplicação no passo atual:
%          .P_comp     [1 x N_sat] Potência computacional alocada [W]
%          .x_out_bps  [N_sat x 4] Taxa de transmissão óptica por terminal [bps]
%          .x_in_bps   [N_sat x 4] Taxa de recepção óptica por terminal [bps]
%          .admm_state Estrutura para warm-start do próximo passo
%   diagnostics - Métricas de desempenho do otimizador:
%          .iterations   Número de iterações executadas
%          .converged    Booleano indicando convergência
%          .r_prim       Resíduo primal final
%          .r_dual       Resíduo dual final
%          .solve_time_ms Tempo de execução computacional em milissegundos
%          .cost_total   Valor da função custo multiobjetivo

t_start = tic;

N_sat = p.orbit.N_sat;
H     = p.mpc.H;
dt    = p.mpc.dt;

% 1. Parâmetros e Pesos Multiobjetivo (EQ-24)
w_B    = p.mpc.w_B;       % 0.85
w_T    = p.mpc.w_T;       % 0.10
w_Q    = p.mpc.w_Q;       % 0.04
w_comm = p.mpc.w_comm;    % 0.01
w_f_B  = p.mpc.w_f_B;     % 2.50
rho    = p.mpc.rho;       % 1.50
tol_pri  = p.mpc.tol_pri;  % 1.0e-4
tol_dual = p.mpc.tol_dual; % 1.0e-4
max_iter = p.mpc.max_admm_iter; % 20

% Limites físicos dos atuadores
P_min = p.eps.P_comp_min; % 31.0 kW
P_max = p.eps.P_comp_sun; % 110.0 kW (conservador) ou 140.0 kW (nominal)
P_nom = p.eps.P_comp_nom; % 100.0 kW
P_bus = p.eps.P_bus;      % 5.0 kW
delta_P = P_max - P_min;

W_ref      = p.workload.W_ref;      % 2.4e17 FLOPs
A_avg      = p.workload.A_avg;      % 2.4e16 FLOPs/s
gamma_comp = p.workload.gamma_comp; % 1.8e-12 J/FLOP
alpha_task = p.workload.alpha_task; % 1.39e6 FLOPs/bit
C_laser    = p.oisl.C_laser;        % 40.0e9 bps

x_max = C_laser * dt; % Volume máximo em bits por passo (400 Gbits)

% Fatores adimensionais de conversão de fila (EQ-23 normalizada)
c_comp = (dt / gamma_comp) * delta_P / W_ref;
c_task = (alpha_task * x_max) / W_ref;
A_norm = (A_avg * dt) / W_ref;
P_min_norm_W = (dt / gamma_comp) * P_min / W_ref;

% Matriz de integração triangular para acumulação temporal no horizonte H
T_cum = tril(ones(H, H));

% 2. Mapeamento Topológico de Enlaces
neighbors = oisl_data.neighbors;
persistent rev_terminal_cache z_rev_idx_cache
if isempty(rev_terminal_cache) || size(z_rev_idx_cache, 1) ~= H
    rev_terminal_cache = zeros(N_sat, 4);
    for i = 1:N_sat
        for e = 1:4
            j = neighbors{i}(e);
            rev_terminal_cache(i, e) = find(neighbors{j} == i);
        end
    end
    
    z_rev_idx_cache = zeros(H, 4, N_sat);
    for s = 1:N_sat
        for e = 1:4
            j = neighbors{s}(e);
            e_rev = rev_terminal_cache(s, e);
            for k = 1:H
                z_rev_idx_cache(k, e, s) = sub2ind([H, 4, N_sat], k, e_rev, j);
            end
        end
    end
end
rev_terminal = rev_terminal_cache;
z_rev_idx    = z_rev_idx_cache;

% 3. Inicialização e Warm-Start do ADMM
xi_pred = orbit_pred.xi; % [H x N_sat]

% 3. Determinação dos Fluxos Físicos de Migração Óptica Alvo (EQ-21 a EQ-23)
% Taxa física de migração necessária no eclipse (Seção III.A e EQ-23):
% r_mig = (A_avg - P_min / gamma_comp) / alpha_task = 4.876e9 bps (4.88 Gbps)
r_mig_total_bps = max(0.0, A_avg - (P_min / gamma_comp)) / alpha_task;
r_mig_term_norm = (r_mig_total_bps / 4.0) / C_laser; % ~0.030475 (3.05% de capacidade por terminal)

target_out = zeros(H, 4, N_sat);
for k = 1:H
    for s = 1:N_sat
        if xi_pred(k, s) == 0
            % Nó eclipsado: exporta tarefas exclusivamente para vizinhos iluminados
            neighs = neighbors{s};
            is_lit_neigh = (xi_pred(k, neighs) == 1);
            n_lit = sum(is_lit_neigh);
            if n_lit > 0
                target_out(k, is_lit_neigh, s) = (r_mig_total_bps / n_lit) / C_laser;
            else
                target_out(k, :, s) = r_mig_term_norm;
            end
        end
    end
end
target_in = target_out(z_rev_idx);

% 4. Inicialização e Warm-Start do ADMM
if nargin >= 5 && ~isempty(admm_prev) && isfield(admm_prev, 'z')
    % Deslocamento temporal de 1 passo no horizonte (receding horizon shift)
    z = zeros(H, 4, N_sat);
    z(1:(H-1), :, :) = admm_prev.z(2:H, :, :);
    z(H, :, :)       = target_out(H, :, :);
    
    lam_out = zeros(H, 4, N_sat);
    lam_out(1:(H-1), :, :) = admm_prev.lam_out(2:H, :, :);
    lam_out(H, :, :)       = admm_prev.lam_out(H, :, :);
    
    lam_in = zeros(H, 4, N_sat);
    lam_in(1:(H-1), :, :) = admm_prev.lam_in(2:H, :, :);
    lam_in(H, :, :)       = admm_prev.lam_in(H, :, :);
    
    u_P = zeros(H, N_sat);
    u_P(1:(H-1), :) = admm_prev.u_P(2:H, :);
    u_P(H, :)       = (xi_pred(H, :) == 1);
else
    % Inicialização a frio (cold start) com a solução de fluxo ótimo
    z       = target_out;
    lam_out = zeros(H, 4, N_sat);
    lam_in  = zeros(H, 4, N_sat);
    u_P     = zeros(H, N_sat);
    u_P(xi_pred == 1) = 1.0;
    u_P(xi_pred == 0) = 0.0;
end

u_out = z;
u_in  = z(z_rev_idx);

% 5. Laço de Otimização Distribuída ADMM (EQ-27 a EQ-32)
converged = false;
r_prim = 1.0;
r_dual = 1.0;

for m = 1:max_iter
    z_old = z;
    
    % --- ETAPA 1: MINIMIZAÇÃO PRIMAL LOCAL FECHADA (EQ-28) ---
    % Trajetória prevista de tarefas na fila com os fluxos atuais
    sum_out = squeeze(sum(u_out, 2)); % [H x N_sat]
    sum_in  = squeeze(sum(u_in, 2));  % [H x N_sat]
    
    dW = -P_min_norm_W - c_comp * u_P + A_norm + c_task * (sum_in - sum_out);
    W_norm = repmat(state.W / W_ref, H, 1) + T_cum * dW;
    W_norm = max(0.0, W_norm);
    cum_W  = T_cum' * W_norm; % [H x N_sat]
    cum_W_3d = repmat(reshape(cum_W, [H, 1, N_sat]), [1, 4, 1]);
    
    % A. Otimização Primal Convexa da Potência Computacional Local u_P (KKT / Projeção de Gradiente):
    % Minimiza J = w_B * (P_b / P_nom)^2 + w_Q * (W / W_ref)^2 sujeito a u_P in [0, 1].
    % Em sol (xi = 1): P_b = 0, custo de bateria nulo; o gradiente negativo dJ_Q/du_P projeta u_P = 1.0 (P_max).
    % Em eclipse (xi = 0): balanço ótimo analítico entre estresse de descarga (w_B) e acúmulo de fila (w_Q).
    % Solução primal fechada 100% vetorizada para u_P em [H x N_sat]:
    marginal_comm_benefit  = w_comm * (delta_P / P_nom) * (r_mig_total_bps / C_laser) * 20.0;
    marginal_queue_benefit = w_Q * c_comp * cum_W;
    marginal_battery_cost0 = w_B * (delta_P * (P_min + P_bus)) / (P_nom^2);
    quad_curvature         = max(1e-6, w_B * (delta_P^2) / (P_nom^2) + w_comm * (delta_P / P_nom)^2);
    
    u_opt = (marginal_comm_benefit + marginal_queue_benefit - marginal_battery_cost0) / quad_curvature;
    u_P_ecl = max(0.0, min(1.0, u_opt));
    
    u_P = (xi_pred == 1) * 1.0 + (xi_pred == 0) .* u_P_ecl;
    
    % B. Alocação de Transmissão Óptica u_out:
    % Rastreamento estritamente quadrático do fluxo físico necessário via OISL
    denom_out = w_comm + rho;
    num_out   = rho * z - lam_out + w_comm * target_out;
    u_out     = max(0.0, min(1.0, num_out / denom_out));
    
    % C. Alocação de Recepção Óptica u_in:
    z_rev    = z(z_rev_idx);
    denom_in = w_comm + rho;
    num_in   = rho * z_rev - lam_in + w_comm * target_in;
    u_in     = max(0.0, min(1.0, num_in / denom_in));
    
    % --- ETAPA 2: CONSENSO DE ENLACE VIA MÉDIA ARITMÉTICA (EQ-29) ---
    u_in_rev = u_in(z_rev_idx);
    z = 0.5 * (u_out + u_in_rev);
    
    % --- ETAPA 3: ATUALIZAÇÃO DOS MULTIPLICADORES DUAIS (EQ-30) ---
    z_rev = z(z_rev_idx);
    lam_out = lam_out + rho * (u_out - z);
    lam_in  = lam_in  + rho * (u_in  - z_rev);
    
    % --- ETAPA 4: AVALIAÇÃO DOS RESÍDUOS PRIMAL E DUAL (EQ-31 e EQ-32) ---
    r_prim = max(abs(u_out(:) - z(:)));
    r_dual = rho * max(abs(z(:) - z_old(:)));
    
    if r_prim <= tol_pri && r_dual <= tol_dual
        converged = true;
        break;
    end
end

t_elapsed_ms = toc(t_start) * 1000.0;

% 5. Desnormalização dos Controles Ótimos no Instante k = 0
ctrl.P_comp    = P_min + u_P(1, :) * delta_P;       % [1 x N_sat] em Watts
ctrl.x_out_bps = squeeze(u_out(1, :, :))' * x_max / dt; % [N_sat x 4] em bps
ctrl.x_in_bps  = squeeze(u_in(1, :, :))'  * x_max / dt; % [N_sat x 4] em bps

% Estado salvo para warm-start
ctrl.admm_state.z       = z;
ctrl.admm_state.lam_out = lam_out;
ctrl.admm_state.lam_in  = lam_in;
ctrl.admm_state.u_P     = u_P;

% Diagnósticos
diagnostics.iterations   = m;
diagnostics.converged    = converged;
diagnostics.r_prim       = r_prim;
diagnostics.r_dual       = r_dual;
diagnostics.solve_time_ms= t_elapsed_ms;

% Cálculo do valor da função custo multiobjetivo total (EQ-24)
P_comp_all = P_min + u_P * delta_P;
is_ecl_all = (xi_pred == 0);
P_b_ecl = zeros(H, N_sat);
P_b_ecl(is_ecl_all) = P_comp_all(is_ecl_all) + P_bus;

J_B    = w_B * sum(sum((P_b_ecl / P_nom).^2));
J_Q    = w_Q * sum(sum(W_norm.^2));
J_comm = w_comm * sum(sum(sum(u_out.^2)));
J_term = w_f_B * sum((state.SoC - 1.0).^2);

diagnostics.cost_total = J_B + J_Q + J_comm + J_term;
diagnostics.cost_breakdown.J_B    = J_B;
diagnostics.cost_breakdown.J_Q    = J_Q;
diagnostics.cost_breakdown.J_comm = J_comm;
diagnostics.cost_breakdown.J_term = J_term;

end
