#!/usr/bin/env python3
"""Medida pre-registrada de H19-H21 (WS-K11). Misma definicion de pico que
h15.py y h17.py: en los pasos P0+2..P0+10, max u_gas_max >= 200 m/s o max
p_max >= 300 kPa, con P0 el paso del reinicio (primera fila de audit.csv).
Prerrequisito por brazo: cero '[CG] AVISO' en run.log.

H19: G (estado de A en 280.06 s, escrito por eaf3d_k10b_opt sin f28, con
     f28 encendida) predice pico.
H20: I, J (fh 285 / 295 s, f28 encendida) predicen pico; K, L (jb 285 /
     295 s, mismas claves que su escritor) predicen sin pico. SOPORTADA
     solo si los cuatro cumplen su prediccion.
H21: H (fh 280 s, solo la presion total encendida) predice sin pico.

Uso: python3 research/ws/WS-K11/scripts/h19.py  (rutas fijas de campaigns/b1)
"""
import csv

B = "campaigns/b1/"
BRAZOS = {
    "H19": [("k11_g_dt025_a236_f28", True)],
    "H20": [("k11_i_dt025_fh285_f28", True), ("k11_j_dt025_fh295_f28", True),
            ("k11_k_dt025_jb285", False), ("k11_l_dt025_jb295", False)],
    "H21": [("k11_h_dt025_fh280_otp", False)],
}


def medir(d):
    rows = list(csv.DictReader(open(B + d + "/audit.csv")))
    p0 = int(rows[0]["step"])
    r = [x for x in rows if int(x["step"]) > p0]
    w = [x for x in r if p0 + 2 <= int(x["step"]) <= p0 + 10]
    um = max(float(x["u_gas_max"]) for x in w)
    pm = max(float(x["p_max"]) for x in w)
    mx = max(r[1:], key=lambda x: float(x["p_max"]))
    n = len(r) - 1
    q = [sum(float(x["p_max"]) >= 1e5 for x in r[1:][i * n // 4:(i + 1) * n // 4]) for i in range(4)]
    nl = sum(float(x["m_gas_cells_nolink"]) > 0 for x in r[1:])
    av = open(B + d + "/run.log", errors="replace").read().count("[CG] AVISO")
    pico = um >= 200 or pm >= 3e5
    print(f"== {d} (P0 {p0}): pasos {p0+2}-{p0+10}: max u_gas_max {um:.1f} m/s, max p_max {pm/1e3:.0f} kPa"
          f" -> {'pico' if pico else 'sin pico'}; ventana: max p_max {float(mx['p_max'])/1e3:.0f} kPa en"
          f" {mx['step']}; n {n}; pasos >= 100 kPa por cuartos {q}; nolink {nl}; [CG] AVISO {av}")
    return pico, av


for h, brazos in BRAZOS.items():
    ok, fallida = True, False
    for d, predice in brazos:
        pico, av = medir(d)
        fallida |= av > 0
        ok &= pico == predice
    v = "FALLIDA (prerrequisito: [CG] AVISO)" if fallida else ("SOPORTADA" if ok else "REFUTADA")
    print(f"{h}: {v}")
