#!/usr/bin/env python3
"""Medida pre-registrada de H22/H23 (WS-K11): la FIRMA del cambio de f28.

Firma = (pasos con m_gas_cells_nolink > 0) >= 1 Y (pasos con p_max >= 100
kPa) >= 20, contados sin el paso 1 tras el reinicio (filas con step > P0+1,
P0 = primera fila de audit.csv). Prerrequisito: cero '[CG] AVISO'.

H22: controles fh 285 / 290 / 295 s con las claves apagadas (M, N, O)
     predicen SIN firma; SOPORTADA si ninguno la tiene.
H23: fuera de muestra en 300 s: P (fh 300 s, f28 encendida) predice firma y
     Q (jb 300 s, mismas claves que su escritor) predice sin firma;
     SOPORTADA si P la tiene y Q no.
Con --todos imprime la firma de los brazos anteriores (muestra de
construccion; no decide).

Uso: python3 research/ws/WS-K11/scripts/h22.py [--todos]
"""
import csv
import sys

B = "campaigns/b1/"
H = {
    "H22": [("k11_m_dt025_fh285_off", False), ("k11_n_dt025_fh290_off", False),
            ("k11_o_dt025_fh295_off", False)],
    "H23": [("k11_p_dt025_fh300_f28", True), ("k11_q_dt025_jb300", False)],
}
PREVIOS = ["k11_a_dt025_s280_off", "k11_b_dt025_fh290_on", "k10b_dt025", "k11_f_dt025_fh280_f28",
           "k11_g_dt025_a236_f28", "k11_i_dt025_fh285_f28", "k11_j_dt025_fh295_f28",
           "k11_c_dt025_jb280", "k11_e_dt025_jb280_otp", "k11_h_dt025_fh280_otp",
           "k11_k_dt025_jb285", "k11_l_dt025_jb295", "k11_dt025_s290", "k11_d_dt025_s300"]


def firma(d):
    r = list(csv.DictReader(open(B + d + "/audit.csv")))
    p0 = int(r[0]["step"])
    r = [x for x in r if int(x["step"]) > p0 + 1]
    nl = sum(float(x["m_gas_cells_nolink"]) > 0 for x in r)
    p1 = sum(float(x["p_max"]) >= 1e5 for x in r)
    av = open(B + d + "/run.log", errors="replace").read().count("[CG] AVISO")
    f = nl >= 1 and p1 >= 20
    print(f"== {d} (P0 {p0}, {len(r)} filas): nolink {nl}; p_max >= 100 kPa {p1}; "
          f"max p_max {max(float(x['p_max']) for x in r)/1e3:.0f} kPa; max u_gas_max "
          f"{max(float(x['u_gas_max']) for x in r):.1f} m/s; [CG] AVISO {av} -> {'FIRMA' if f else 'sin firma'}")
    return f, av


if "--todos" in sys.argv:
    for d in PREVIOS:
        firma(d)
for h, brazos in H.items():
    ok, fallida = True, False
    for d, predice in brazos:
        f, av = firma(d)
        fallida |= av > 0
        ok &= f == predice
    print(f"{h}: {'FALLIDA (prerrequisito: [CG] AVISO)' if fallida else ('SOPORTADA' if ok else 'REFUTADA')}")
