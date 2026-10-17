# Reproducibility Guide for Reviewers — Artigo 05 (IEEE)

**Paper Title:** *Predictive Distributed Workload Orchestration via Optical Inter-Satellite Links for Thermal-Energy Balancing in Orbital Data Center Constellations*  
**Authors:** Dafnhê Thor Castro de Martins Barros and Prof. Dr. Flávio Barcelos Braz da Silva  
**Affiliation:** Graduate Program in Control and Automation Engineering (PROPECAUT), Federal Institute of Espírito Santo (IFES), Campus Serra, Brazil.  
**Tested Environments:** GNU Octave 11.3.0 (x86_64-w64-mingw32) and MATLAB R2023b+.

---

## 1. Package Contents

This package contains the complete numerical reproduction framework and the compiled paper PDF:

* `Artigo_05_IEEE.pdf` — The compiled 9-page IEEE format paper manuscript.
* `simulate_all_scenarios_30orbits.m` — **Master 30-Orbit Simulation Script** (evaluates 30 consecutive orbits, 47.82 hours, 17,218 steps per node, including failure modes and beta angles).
* `main_simulation.m` — Standard baseline comparative simulation script.
* `config/` — Astrodynamical, battery, thermal, and OISL parameter files (`load_constants.m`, `get_nominal_params.m`, `get_conservative_params.m`).
* `models/` — Multi-physical subsystems:
  - `orbital/`: Walker-Delta Keplerian propagation, beta-angle dynamics, and cylindrical eclipse calculations.
  - `battery/`: Coulombic SoC tracking and non-linear Arrhenius-Miner capacity degradation kinetics.
  - `thermal/`: Stefan-Boltzmann radiative cooling and Loop Heat Pipe (LHP) active bypass staging.
  - `oisl/`: Coherent DP-QPSK 40 Gbps link budget, pointing power, and propagation delays.
* `optimization/` — Distributed D-PMPC controller solved via Alternating Direction Method of Multipliers (ADMM).
* `controllers/` — Autonomous uncoordinated baseline controller and reactive offloading heuristics.
* `validation/` — Formal test suite (`run_all_tests.m`) containing 88 rigorous verification tests across 6 validation suites.
* `visualization/` — Plot generation script (`generate_all_figures.m`) reproducing all paper figures at 300 DPI publication quality.
* `results/` — Pre-generated CSV tables, figure files, and binary simulation results.

---

## 2. Requirements & Setup

1. **GNU Octave** (version 7.3.0 or higher; tested on Octave 11.3.0) or **MATLAB** (R2022b or higher).
2. No proprietary toolboxes are required. All QP optimization and ADMM routines use native vector operations and standard linear solvers.

---

## 3. How to Run the Reproduction Scripts

Open Octave or MATLAB in the `simulacao_octave` directory:

### Step A: Execute the Full 30-Orbit Scientific Simulation Campaign
In the Octave/MATLAB command prompt:
```matlab
simulate_all_scenarios_30orbits
```
* **Execution Time:** ~3 to 4 minutes.
* **Outputs Generated in `results/`:**
  - `simulation_30orbits_master.mat`: Full binary database containing all state variables for all 32 satellites across 30 orbits (17,218 steps).
  - `tabela_30_orbitas_evolucao.csv`: Orbit-by-orbit evolution table (proving zero secular drift $\Delta SoC_{drift} = 0.0000\%$ and baseline blackout on orbit 6).

### Step B: Run the Master Validation Test Suite
To verify model correctness and physical boundary assertions:
```matlab
cd validation
run_all_tests
cd ..
```
* **Expected Output:** **88 / 88 tests passed (100.0%)** across all 6 test suites:
  1. Unit tests (models, kinematics, thermal, BESS, OISL).
  2. ADMM convergence and optimality tests.
  3. Energy conservation and Stefan-Boltzmann balance tests.
  4. Integration tests (30-orbit multi-agent propagation).
  5. Regression and sensitivity tests.
  6. Performance benchmarks and latency tests.

### Step C: Regenerate Paper Figures (Figures 1 to 6)
To re-render all publication figures from the simulation data:
```matlab
cd visualization
generate_all_figures
cd ..
```
* High-resolution figures (`figura1_...` through `figura6_...`) will be saved in `results/`.

---

## 4. Key Physical Metric Verification

Upon execution of `simulate_all_scenarios_30orbits.m`, the console will report:
* **D-PMPC Minimum SoC:** $80.3708\%$ (constant across all 30 orbits).
* **D-PMPC Mean Secular Drift:** $0.0000\%$.
* **D-PMPC Projected Battery Life:** $10.59\text{ to }11.80\text{ years}$ ($> 10\text{ years}$ EOL threshold).
* **Uncoordinated Baseline Depletion:** Exactly at $t = 539.0\text{ min} = 8.98\text{ h}$ (Orbit 6), with remaining 24 orbits in complete blackout.
* **Peak Silicon Junction Temperature:** Confined to $74.32^\circ\text{C}$ ($< 85.0^\circ\text{C}$ limit).
* **Fail-Closed LHP Bypass Temperature:** Peaks at $183.20^\circ\text{C}$ in sunlight.
* **Fail-Open LHP Bypass Temperature:** Drops to $-38.88^\circ\text{C}$ in eclipse.
* **Average Task Completion Latency:** $214.88\text{ ms}$.

For questions or assistance regarding reproduction, please contact: `dafnhe.thor@msn.com`.
