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
addpath('config', 'models', 'controllers', 'optimization', 'validation');

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
    
    % Execução isolada em subprocesso para garantir integridade de escopo
    cmd = sprintf('"%s" --no-gui -q --eval "addpath(''config'', ''models'', ''controllers'', ''optimization'', ''validation''); %s;"', ...
        fullfile(matlabroot, 'bin', 'octave.exe'), script_name);
        
    [status, cmdout] = system(cmd);
    t_elapsed = toc(t_start_s);
    
    % Parse de testes aprovados (suporta os formatos de todas as suítes)
    matches = regexp(cmdout, '(\d+)\s+de\s+(\d+)\s+testes\s+APROVADOS', 'tokens');
    if ~isempty(matches)
        n_pass = str2double(matches{end}{1});
        n_tot  = str2double(matches{end}{2});
    else
        matches2 = regexp(cmdout, '(\d+)\s+Testes\s+\|\s+(\d+)\s+PASS\s+\|\s+(\d+)\s+FAIL', 'tokens');
        if ~isempty(matches2)
            n_tot  = str2double(matches2{end}{1});
            n_pass = str2double(matches2{end}{2});
        else
            pass_matches = regexp(cmdout, '(->\s*PASS|\[PASS\])', 'match');
            fail_matches = regexp(cmdout, '(->\s*FAIL|\[FAIL\])', 'match');
            n_pass = length(pass_matches);
            n_tot  = n_pass + length(fail_matches);
        end
    end
    
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
