% RUN_ALL_TESTS - Master Test Runner and Certification Suite
% Projeto: Reconstrução e Validação Científica do Artigo 05 em GNU Octave
%
% Executa todas as 6 suítes de validação em sequência e consolida os resultados:
%   1. validate_orbit   (15/15 testes - Mecânica orbital e geometria solar 3D)
%   2. validate_energy  (16/16 testes - Painéis PV, barramento HVDC e bateria)
%   3. validate_thermal (13/13 testes - Radiação T^4, condensadores e LHP bypass)
%   4. validate_oisl    (17/17 testes - Rede laser óptica, filas e latência)
%   5. validate_dpmpc   (17/17 testes - Controle preditivo D-PMPC e ADMM em 5 órbitas)
%   6. validate_pareto  (10/10 testes - Fronteira de Pareto e dominância estrita)
%
% Total: 88 testes formais com rastreabilidade física rigorosa.

clear; clc;

% Resolução robusta de caminhos absolutos independente do diretório de chamada (6.1)
this_dir = fileparts(mfilename('fullpath'));
if isempty(this_dir)
    this_dir = pwd;
end
base_dir = fileparts(this_dir);
if ~exist(fullfile(base_dir, 'config'), 'dir')
    base_dir = fullfile(this_dir, '..');
end

addpath(fullfile(base_dir, 'config'));
addpath(fullfile(base_dir, 'models'));
addpath(fullfile(base_dir, 'controllers'));
addpath(fullfile(base_dir, 'optimization'));
addpath(fullfile(base_dir, 'validation'));

fprintf('========================================================================================\n');
fprintf('   SUITE MESTRA DE VALIDAÇÃO CIENTÍFICA E CERTIFICAÇÃO INTEGRADA (GNU OCTAVE)          \n');
fprintf('   Artigo 05: Predictive Distributed Workload Orchestration via OISL                   \n');
fprintf('========================================================================================\n\n');

test_scripts = {
    'validate_orbit',   'Mecânica Orbital e Geometria Solar/Sombra 3D';
    'validate_energy',  'Geração Solar Fotovoltaica, Barramento HVDC e Bateria';
    'validate_thermal', 'Balanço Térmico Radiativo T^4, Junção e LHP Bypass';
    'validate_oisl',    'Topologia de Rede OISL, Filas de Carga e Latência';
    'validate_dpmpc',   'Controlador D-PMPC, ADMM e Deriva Secular Nula em 5 Órbitas';
    'validate_pareto',  'Otimização Multiobjetivo e Fronteira de Pareto Física'
};

n_suites = size(test_scripts, 1);
results = cell(n_suites, 1);

t_start_total = tic;

for s = 1:n_suites
    script_name = test_scripts{s, 1};
    script_desc = test_scripts{s, 2};
    
    fprintf('>>> Executando Suíte [%d/%d]: %s (%s)...\n', s, n_suites, script_name, script_desc);
    fflush(stdout);
    
    t_start_s = tic;
    
    try
        res_raw = feval(script_name);
        if isfield(res_raw, 'passed')
            n_pass = res_raw.passed;
            n_tot  = res_raw.total;
        elseif isfield(res_raw, 'n_pass')
            n_pass = res_raw.n_pass;
            n_tot  = res_raw.n_tot;
        else
            n_pass = 0;
            n_tot  = 0;
        end
        status  = 0;
    catch err
        fprintf('    [ERRO DE EXECUÇÃO]: %s\n', err.message);
        n_pass  = 0;
        n_tot   = 0;
        status  = 1;
    end
    t_elapsed = toc(t_start_s);
    
    res.script = script_name;
    res.desc   = script_desc;
    res.status = status;
    res.n_pass = n_pass;
    res.n_tot  = n_tot;
    res.t_sec  = t_elapsed;
    res.pass   = (status == 0) && (n_pass == n_tot) && (n_tot > 0);
    results{s} = res;
    
    if res.pass
        fprintf('    [OK] %d/%d testes aprovados (%.2f s)\n\n', n_pass, n_tot, t_elapsed);
    else
        fprintf('    [FALHA] %d/%d testes aprovados (status=%d, %.2f s)\n\n', n_pass, n_tot, status, t_elapsed);
    end
    fflush(stdout);
end

t_total = toc(t_start_total);

%% PAINEL CONSOLIDADO DE CERTIFICAÇÃO FINAL
fprintf('========================================================================================\n');
fprintf('                      PAINEL CONSOLIDADO DE CERTIFICAÇÃO CIENTÍFICA                    \n');
fprintf('========================================================================================\n');
fprintf('ID | SUÍTE DE TESTE     | APROVADOS / TOTAL | TAXA   | TEMPO  | STATUS FINAL            \n');
fprintf('---+--------------------+-------------------+--------+--------+-------------------------\n');

tot_pass = 0;
tot_tests = 0;
all_passed = true;

for s = 1:n_suites
    r = results{s};
    tot_pass = tot_pass + r.n_pass;
    tot_tests = tot_tests + r.n_tot;
    
    rate = 0.0;
    if r.n_tot > 0, rate = (r.n_pass / r.n_tot) * 100.0; end
    
    if r.pass
        status_tag = '[APROVADO CIENTIFICAMENTE]';
    else
        status_tag = '[REPROVADO / INVESTIGAR]';
        all_passed = false;
    end
    
    fprintf('%02d | %-18s |    %2d   /   %2d    | %5.1f%% | %5.2fs | %s\n', ...
        s, r.script, r.n_pass, r.n_tot, rate, r.t_sec, status_tag);
end

fprintf('---+--------------------+-------------------+--------+--------+-------------------------\n');
fprintf('TOTAL INTEGRADO: %d de %d testes APROVADOS (Taxa Global: %.2f %%) | Tempo Total: %.2f s\n', ...
    tot_pass, tot_tests, (tot_pass / tot_tests) * 100.0, t_total);
fprintf('========================================================================================\n');

if all_passed
    fprintf('STATUS GERAL: SISTEMA 100%% VALIDADO E CONFORME COM OS RIGORES DA IEEE TRANSACTIONS.\n');
else
    fprintf('STATUS GERAL: FORAM DETECTADAS REPROVAÇÕES NA SUÍTE DE TESTES.\n');
end
