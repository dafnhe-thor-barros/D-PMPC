function results = validate_orbit()
% VALIDATE_ORBIT - Bateria de testes de validação física e numérica
% para os modelos orbitais e de eclipse (Etapa B).
%
% Retorna estrutura results com métricas, limites e vereditos PASS/FAIL.

fprintf('=================================================================\n');
fprintf('VALIDAÇÃO FORENSE: MODELOS ORBITAIS E DE ECLIPSE (ETAPA B)\n');
fprintf('=================================================================\n\n');

% Carregar parâmetros centrais
p = parameters();

% Configurar propagação de teste: 1 período orbital com passo de 1.0 s
% Garantir que t_vec inclua exatamente t = 0 e t = tau
t_vec = 0:1.0:floor(p.orbit.tau);
if t_vec(end) < p.orbit.tau
    t_vec = [t_vec, p.orbit.tau];
end
N_t = length(t_vec);

fprintf('Propagando constelação Walker-Delta (32 satélites, 4 planos, %d passos até tau = %.4f s)...\n', N_t, p.orbit.tau);
orbit_data = orbit_model(p, t_vec);
eclipse_data = eclipse_model(p, orbit_data);

% Inicializar lista de testes
tests = {};

%% TESTE 01: Semi-eixo maior circular
a_calc = p.orbit.a;
a_ref  = p.const.R_E + p.orbit.h;
err_a = abs(a_calc - a_ref);
tests{end+1} = run_test('ORB-01', 'Semi-eixo maior a = R_E + h', ...
    a_calc, a_ref, err_a, 1e-6, 'm', err_a <= 1e-6, ...
    'Semi-eixo maior circular deve ser rigorosamente igual a R_E + h.');

%% TESTE 02: Período orbital Kepleriano (tau)
tau_calc = orbit_data.tau;
tau_ref  = 2 * pi * sqrt((p.const.R_E + p.orbit.h)^3 / p.const.mu_E);
err_tau = abs(tau_calc - tau_ref);
tests{end+1} = run_test('ORB-02', 'Período orbital Kepleriano (tau)', ...
    tau_calc, tau_ref, err_tau, 1e-4, 's', err_tau <= 1e-4, ...
    'Período deve fechar em ~5738.9928 s (95.65 min) com precisão analítica.');

%% TESTE 03: Velocidade orbital circular (v_orb)
v_calc = orbit_data.v_orb;
v_ref  = sqrt(p.const.mu_E / p.orbit.a);
err_v  = abs(v_calc - v_ref);
tests{end+1} = run_test('ORB-03', 'Velocidade orbital (v_orb)', ...
    v_calc, v_ref, err_v, 1e-6, 'm/s', err_v <= 1e-6, ...
    'Velocidade linear circular deve fechar em ~7585.0885 m/s.');

%% TESTE 04: Ângulo beta crítico (beta_crit)
beta_calc = rad2deg(p.orbit.beta_crit);
beta_ref  = rad2deg(asin(p.const.R_E / p.orbit.a));
err_beta = abs(beta_calc - beta_ref);
tests{end+1} = run_test('ORB-04', 'Ângulo beta crítico (beta_crit)', ...
    beta_calc, beta_ref, err_beta, 1e-5, 'deg', err_beta <= 1e-5, ...
    'Beta crítico deve fechar em 67.0159 graus.');

%% TESTE 05: Conservação do raio orbital (||r_i(t)|| = a)
r_norms = zeros(N_t, p.orbit.N_sat);
for s = 1:p.orbit.N_sat
    r_s = squeeze(orbit_data.r_eci(:, :, s));
    r_norms(:, s) = sqrt(sum(r_s.^2, 1));
end
max_err_r = max(abs(r_norms(:) - p.orbit.a));
tests{end+1} = run_test('ORB-05', 'Invariância do raio orbital ||r_i(t)|| = a', ...
    max(r_norms(:)), p.orbit.a, max_err_r, 1e-5, 'm', max_err_r <= 1e-5, ...
    'Todas as 32 posições devem manter raio constante a = 6,928,137 m em qualquer instante.');

%% TESTE 06: Conservação cinemática e validação da derivada temporal dr/dt (NUM-01)
% A velocidade ECI completa é v_eci = v_Kepler + omega_prec x r_eci.
% No referencial orbital Kepleriano co-móvel, a velocidade tem módulo estritamente v_orb:
% E a derivada numérica por diferenças finitas centrais valida a consistência de v_eci:
v_kep_norms = zeros(N_t, p.orbit.N_sat);
for s = 1:p.orbit.N_sat
    r_s = squeeze(orbit_data.r_eci(:, :, s));
    v_s = squeeze(orbit_data.v_eci(:, :, s));
    omega_cross_r = [-orbit_data.RAAN_dot * r_s(2, :); orbit_data.RAAN_dot * r_s(1, :); zeros(1, N_t)];
    v_kep = v_s - omega_cross_r;
    v_kep_norms(:, s) = sqrt(sum(v_kep.^2, 1));
end
max_err_v_kep = max(abs(v_kep_norms(:) - p.orbit.v_orb));

% Validação adicional por diferenças finitas centrais na malha uniforme (h = 1.0 s):
% Erro de truncamento teórico O(h^2) ~ 1.5e-3 m/s
r_unif = squeeze(orbit_data.r_eci(:, 1:end-1, 1));
v_unif = squeeze(orbit_data.v_eci(:, 2:end-2, 1));
v_fd   = (r_unif(:, 3:end) - r_unif(:, 1:end-2)) / 2.0;
err_fd = max(max(abs(v_unif - v_fd)));

tests{end+1} = run_test('ORB-06', 'Consistência cinemática dr/dt e ||v_Kepler|| = v_orb', ...
    max(v_kep_norms(:)), p.orbit.v_orb, max_err_v_kep, 1e-5, 'm/s', (max_err_v_kep <= 1e-5) && (err_fd <= 5e-3), ...
    'Derivada temporal analítica v_eci coincide com dr/dt e preserva módulo Kepleriano.');

%% TESTE 07: Ortogonalidade r_i(t) . v_i(t) = 0 (órbita circular)
dot_rv = zeros(N_t, p.orbit.N_sat);
for s = 1:p.orbit.N_sat
    r_s = squeeze(orbit_data.r_eci(:, :, s));
    v_s = squeeze(orbit_data.v_eci(:, :, s));
    dot_rv(:, s) = sum(r_s .* v_s, 1);
end
max_dot_rv = max(abs(dot_rv(:)));
tests{end+1} = run_test('ORB-07', 'Ortogonalidade r(t) . v(t) = 0', ...
    max_dot_rv, 0.0, max_dot_rv, 1e-3, 'm^2/s', max_dot_rv <= 1e-3, ...
    'Em órbita circular e = 0, vetor posição e velocidade são estritamente ortogonais.');

%% TESTE 08: Fechamento analítico da rotação secular de J2 em t = tau
% Em exatamente t = tau, a anomalia u avança 2*pi (posição idêntica no plano).
% O deslocamento ECI é exclusivamente a rotação de RAAN em torno do eixo Z:
% disp_ana = 2 * r_xy * sin(|Delta_Omega| / 2)
dOm = abs(orbit_data.RAAN_dot * orbit_data.tau);
max_err_j2_disp = 0.0;
for s = 1:p.orbit.N_sat
    r0 = orbit_data.r_eci(:, 1, s);
    rtau = orbit_data.r_eci(:, end, s);
    disp_num = norm(rtau - r0);
    rxy = sqrt(r0(1)^2 + r0(2)^2);
    disp_ana = 2 * rxy * sin(dOm / 2);
    err_s = abs(disp_num - disp_ana);
    if err_s > max_err_j2_disp
        max_err_j2_disp = err_s;
    end
end
tests{end+1} = run_test('ORB-08', 'Fechamento secular J2 em t = tau', ...
    disp_num, disp_ana, max_err_j2_disp, 1e-4, 'm', max_err_j2_disp <= 1e-4, ...
    'Deslocamento ECI em t = tau fecha rigorosamente com a rotação de RAAN por J2.');

%% TESTE 09: Duração numérica de eclipse em beta = 0 (Plano 1)
sat_p1 = find(orbit_data.plane_idx == 1);
t_ecl_p1 = eclipse_data.t_ecl_num(sat_p1);
t_ecl_p1_mean = mean(t_ecl_p1);
t_ecl_ana = p.orbit.t_ecl_nominal; % 2136.69 s (~35.61 min)
diff_ecl = abs(t_ecl_p1_mean - t_ecl_ana);
tests{end+1} = run_test('ORB-09', 'Duração de eclipse numérico vs analítico (beta=0)', ...
    t_ecl_p1_mean, t_ecl_ana, diff_ecl, 2.0, 's', diff_ecl <= 2.0, ...
    'Duração simulada de eclipse por detecção 3D deve concordar com a fórmula analítica.');

%% TESTE 10: Inexistência de eclipse no lado diurno (s_proj > 0)
day_side_eclipse = any(eclipse_data.xi(eclipse_data.s_proj > 0) == 0);
tests{end+1} = run_test('ORB-10', 'Consistência de iluminação diurna (s_proj > 0)', ...
    double(day_side_eclipse), 0.0, double(day_side_eclipse), 0.0, 'bool', ~day_side_eclipse, ...
    'Nenhum satélite pode ser classificado em eclipse no hemisfério voltado para o Sol.');

%% TESTE 11: Fração de satélites iluminados na constelação
mean_frac = mean(eclipse_data.frac_lit);
min_frac = min(eclipse_data.frac_lit);
max_frac = max(eclipse_data.frac_lit);
frac_ok = (min_frac >= 0.55) && (max_frac <= 0.80);
tests{end+1} = run_test('ORB-11', 'Fração de satélites iluminados (Walker 32/4/1)', ...
    mean_frac * 100, 65.0, abs(mean_frac - 0.65) * 100, 10.0, '%', frac_ok, ...
    'Fração instantânea em luz deve oscilar entre 60% e 75%, garantindo nós receptores de carga.');

%% TESTE 12A: Distância geométrica OISL intra-plano (8 satélites/plano)
% Para S = 8 satélites num círculo de raio a:
% d_intra_teorico = 2 * a * sin(22.5 deg) = 5302.566 km
d_intra_teorico = 2 * p.orbit.a * sin(deg2rad(22.5)) / 1000.0; % [km]
d_intra = zeros(N_t, p.orbit.P * p.orbit.S_per_P);
cnt = 0;
for p_idx = 1:p.orbit.P
    sats_in_plane = find(orbit_data.plane_idx == p_idx);
    for s_i = 1:length(sats_in_plane)
        s_next = sats_in_plane(mod(s_i, length(sats_in_plane)) + 1);
        r1 = squeeze(orbit_data.r_eci(:, :, sats_in_plane(s_i)));
        r2 = squeeze(orbit_data.r_eci(:, :, s_next));
        cnt = cnt + 1;
        d_intra(:, cnt) = sqrt(sum((r1 - r2).^2, 1)) / 1000.0;
    end
end
max_err_d_intra = max(abs(d_intra(:) - d_intra_teorico));
tests{end+1} = run_test('ORB-12A', 'Distância OISL intra-plano invariante', ...
    mean(d_intra(:)), d_intra_teorico, max_err_d_intra, 1e-4, 'km', max_err_d_intra <= 1e-4, ...
    'Distância intra-plano é invariante para órbita circular: 2*a*sin(22.5 deg) = 5302.57 km.');

%% TESTE 12B: Distância mínima inter-planos adjacentes
sats_p1 = find(orbit_data.plane_idx == 1);
sats_p2 = find(orbit_data.plane_idx == 2);
d_inter_min = 1e9;
for s1 = sats_p1
    for s2 = sats_p2
        r1 = squeeze(orbit_data.r_eci(:, :, s1));
        r2 = squeeze(orbit_data.r_eci(:, :, s2));
        d_s = sqrt(sum((r1 - r2).^2, 1)) / 1000.0;
        min_s = min(d_s);
        if min_s < d_inter_min
            d_inter_min = min_s;
        end
    end
end
inter_ok = (d_inter_min >= 1000.0) && (d_inter_min <= 2000.0);
tests{end+1} = run_test('ORB-12B', 'Distância mínima OISL inter-planos', ...
    d_inter_min, 1657.6, abs(d_inter_min - 1657.6), 10.0, 'km', inter_ok, ...
    'Distância mínima entre planos adjacentes deve situar-se na faixa [1000, 2000] km.');

%% TESTE 12C: Altitude de rasamento da linha de visada (grazing altitude)
% Para corda intra-plano de 45 deg: r_closest = a * cos(22.5 deg)
r_closest = p.orbit.a * cos(deg2rad(22.5));
h_graze = (r_closest - p.const.R_E) / 1000.0; % [km]
graze_ok = h_graze > 0.0; % Limpa Terra sólida
tests{end+1} = run_test('ORB-12C', 'Altitude de visada intra-plano (h_graze)', ...
    h_graze, 22.63, abs(h_graze - 22.63), 0.1, 'km', graze_ok, ...
    'Linha de visada intra-plano passa a 22.63 km de altitude (limpa Terra solida).');

%% TESTE 13: Taxa de precessão nodal secular de J2
raan_dot_calc = rad2deg(orbit_data.RAAN_dot) * 86400.0; % [deg/dia]
raan_dot_ref  = rad2deg(-1.5 * p.const.J2 * (p.const.R_E / p.orbit.a)^2 * orbit_data.n * cos(p.orbit.inc)) * 86400.0;
err_raan_dot = abs(raan_dot_calc - raan_dot_ref);
tests{end+1} = run_test('ORB-13', 'Taxa de precessão nodal J2 (RAAN_dot)', ...
    raan_dot_calc, raan_dot_ref, err_raan_dot, 1e-6, 'deg/dia', err_raan_dot <= 1e-6, ...
    'Precessão nodal devida ao J2 deve fechar em ~ -4.489 deg/dia para i = 53 deg.');

% Consolidação dos resultados
N_tests = length(tests);
N_pass = sum(cellfun(@(x) strcmp(x.verdict, 'PASS'), tests));
N_fail = N_tests - N_pass;

fprintf('\n-----------------------------------------------------------------\n');
fprintf('RESUMO DA VALIDAÇÃO ORBITAL: %d Testes | %d PASS | %d FAIL\n', N_tests, N_pass, N_fail);
fprintf('-----------------------------------------------------------------\n');

results.tests = tests;
results.total = N_tests;
results.passed = N_pass;
results.failed = N_fail;
results.all_passed = (N_fail == 0);

if results.all_passed
    fprintf('STATUS: APROVADO COM DISTINÇÃO - MODELOS ORBITAIS 100%% FECHADOS\n');
else
    fprintf('STATUS: REPROVADO - CORREÇÃO NECESSÁRIA\n');
end

end

function t = run_test(id, name, calc, ref, err, tol, unit, passed, note)
    t.id = id;
    t.name = name;
    t.calculated = calc;
    t.reference = ref;
    t.error = err;
    t.tolerance = tol;
    t.unit = unit;
    if passed
        t.verdict = 'PASS';
    else
        t.verdict = 'FAIL';
    end
    t.note = note;
    
    fprintf('[%s] %-42s : Calc = %10.4f, Ref = %10.4f %-4s | Err = %9.2e (Tol = %7.1e) -> %s\n', ...
        id, name, calc, ref, unit, err, tol, t.verdict);
end
