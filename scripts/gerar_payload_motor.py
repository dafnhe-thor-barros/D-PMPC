#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generates 02_payload_motor.json and executes motor_matematico.py
for zero-trust numerical plug-in validation of Artigo 05 (IEEE Transactions).
"""

import json
import os
import subprocess

payload = {
    "operation": "batch",
    "operations": [
        {
            "id": "Eq_01_Orbital_Period",
            "operation": "plug_in",
            "expression": "2 * pi * sqrt((R_E + h)**3 / mu)",
            "substitutions": {
                "R_E": 6378.137,
                "h": 550.0,
                "mu": 398600.4418,
                "pi": 3.141592653589793
            },
            "reported_value": 5738.9,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_02_Orbital_Velocity",
            "operation": "plug_in",
            "expression": "sqrt(mu / (R_E + h))",
            "substitutions": {
                "R_E": 6378.137,
                "h": 550.0,
                "mu": 398600.4418
            },
            "reported_value": 7.585,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_03_Critical_Beta_Angle",
            "operation": "plug_in",
            "expression": "deg(asin(R_E / (R_E + h)))",
            "substitutions": {
                "R_E": 6378.137,
                "h": 550.0
            },
            "reported_value": 67.01,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_04_Eclipse_Duration_Beta0",
            "operation": "plug_in",
            "expression": "(tau / pi) * acos(sqrt((R_E + h)**2 - R_E**2) / (R_E + h))",
            "substitutions": {
                "tau": 5738.9,
                "R_E": 6378.137,
                "h": 550.0,
                "pi": 3.141592653589793
            },
            "reported_value": 2137.6,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_05_Solar_Array_Power",
            "operation": "plug_in",
            "expression": "A_sa * eta_sa * S_0 * (1 - gamma_T * (T_sa - 298.15))",
            "substitutions": {
                "A_sa": 420.0,
                "eta_sa": 0.32,
                "S_0": 1361.0,
                "gamma_T": 0.0018,
                "T_sa": 320.0
            },
            "reported_value": 175722.0,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_06_OISL_Power_FullRate",
            "operation": "plug_in",
            "expression": "P_pat + P_laser_tx + kappa_comm * R",
            "substitutions": {
                "P_pat": 35.0,
                "P_laser_tx": 15.0,
                "kappa_comm": 1.2e-9,
                "R": 40e9
            },
            "reported_value": 98.0,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_07_OISL_Power_AvgRate",
            "operation": "plug_in",
            "expression": "P_pat + P_laser_tx + kappa_comm * R",
            "substitutions": {
                "P_pat": 35.0,
                "P_laser_tx": 15.0,
                "kappa_comm": 1.2e-9,
                "R": 32e9
            },
            "reported_value": 88.4,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_08_DoD_Stress_Reduction",
            "operation": "plug_in",
            "expression": "((DoD_uncoord - DoD_dpmpc) / DoD_uncoord) * 100",
            "substitutions": {
                "DoD_uncoord": 52.0,
                "DoD_dpmpc": 18.0
            },
            "reported_value": 65.38,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_09_Battery_Lifetime_Gain",
            "operation": "plug_in",
            "expression": "((life_dpmpc - life_uncoord) / life_uncoord) * 100",
            "substitutions": {
                "life_uncoord": 3.1,
                "life_dpmpc": 11.8
            },
            "reported_value": 280.65,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_10_Thermal_Swing_Reduction",
            "operation": "plug_in",
            "expression": "((deltaT_uncoord - deltaT_dpmpc) / deltaT_uncoord) * 100",
            "substitutions": {
                "deltaT_uncoord": 24.2,
                "deltaT_dpmpc": 11.8
            },
            "reported_value": 51.24,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_11_Latency_Reduction",
            "operation": "plug_in",
            "expression": "((lat_uncoord - lat_dpmpc) / lat_uncoord) * 100",
            "substitutions": {
                "lat_uncoord": 1420.0,
                "lat_dpmpc": 215.0
            },
            "reported_value": 84.86,
            "rel_tolerance": 0.005
        },
        {
            "id": "Eq_12_Stefan_Boltzmann_Flux",
            "operation": "plug_in",
            "expression": "eps * sigma * A_rad * (T_rad**4 - T_space**4)",
            "substitutions": {
                "eps": 0.91,
                "sigma": 5.670374419e-8,
                "A_rad": 60.0,
                "T_rad": 356.4,
                "T_space": 3.0
            },
            "reported_value": 49830.0,
            "rel_tolerance": 0.01
        }
    ]
}

payload_path = r"C:\ZZ - Antigravity\Mestrado\01 - Artigos\Artigo 05\02_payload_motor.json"
out_path = r"C:\ZZ - Antigravity\Mestrado\01 - Artigos\Artigo 05\02_relatorio_motor.json"

with open(payload_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)

print(f"Payload written to {payload_path}")

motor_script = r"C:\ZZ - Antigravity\Mestrado\skill_v6_extracted\scripts\motor_matematico.py"
cmd = ["python", motor_script, "--input", payload_path, "--out", out_path]
res = subprocess.run(cmd, capture_output=True, text=True)
print("Motor output:")
print(res.stdout)
if res.stderr:
    print("Motor stderr:", res.stderr)

with open(out_path, "r", encoding="utf-8") as f:
    report = json.load(f)
print("\nMotor Report Summary:")
print("Status:", report.get("status"))
for op in report.get("results", []):
    print(f"[{op.get('status')}] {op.get('id')}: reported={op.get('reported_value')}, calculated={op.get('calculated_value')}, rel_err={op.get('relative_error_percent')}%")
