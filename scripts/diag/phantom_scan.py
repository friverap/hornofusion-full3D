#!/usr/bin/env python3
"""Velocidad fantasma frente a caras cerradas por F2.8 (C-064, WS-K3).

Por snapshot: receptoras cerradas = celdas de lecho (alpha_s >= ALPHA_BED)
con hueco ws_liq_room <= ROOM_EPS (vista condensada: acero + escoria).
Aproximacion fantasma = vecina con liquido (alpha_l >= 1e-2) cuya velocidad
de centro apunta HACIA la receptora; u_ph = esa proyeccion.
Eventos = snapshots con max|p| > P_PEAK (agrupados si distan <= GAP pasos).
Precursor local = u_ph > U_PH en un snapshot ANTERIOR (<= WIN pasos) a
<= DIST celdas (Chebyshev, theta periodico) de la celda de max|p| del evento.
Control = mismo test en snapshots quietos (max|p| < P_QUIET).
Uso: phantom_scan.py DIR [DIR...]   (campos HDF5 en orden [k,j,i])
     phantom_scan.py --stream DIR PIDFILE  escanea cada snapshot al cerrarse, guarda
         el resumen en DIR/phantom/<paso>.npz y borra el HDF5 (salvo pasos
         multiplos de 500 y el ultimo); con --stream la evaluacion lee esos
         resumenes, asi que da lo mismo que sobre los HDF5.
"""
import glob, os, re, sys, time
import numpy as np, h5py

ALPHA_BED, ALPHA_PORE_GAS, ROOM_EPS = 1e-2, 1.5e-2, 1e-4
P_PEAK, P_QUIET, U_PH, WIN, DIST, GAP = 3e5, 1e5, 5.0, 50, 2, 5

def load(f):
    with h5py.File(f, 'r') as h:
        g = h['fields']
        d = {k: g[k][()] for k in ('alpha_solid', 'alpha_liquid', 'alpha_slag', 'pressure',
                                   'velocity_r_liquid', 'velocity_th_liquid', 'velocity_z_liquid')}
        d['ct'] = h['mesh/cell_type'][()]
    return d

def scan(d):
    a_s, a_l = d['alpha_solid'], d['alpha_liquid'] + d['alpha_slag']
    fl = d['ct'] != 0
    pf = ALPHA_PORE_GAS * np.clip((a_s - 0.5 * ALPHA_BED) / (0.5 * ALPHA_BED), 0, 1)
    room = np.where(a_s >= ALPHA_BED, np.maximum(1 - a_s - pf, 0) - a_l, 1.0)
    closed = fl & (a_s >= ALPHA_BED) & (room <= ROOM_EPS)
    u = {0: d['velocity_z_liquid'], 1: d['velocity_th_liquid'], 2: d['velocity_r_liquid']}
    uph = np.zeros_like(a_s)                       # en la receptora: max aproximacion
    nk, nj, ni = a_s.shape
    for ax in range(3):
        for s in (-1, 1):                          # vecina en idx + s
            if ax == 1:                            # theta periodico
                un = np.roll(u[ax], -s, 1); aln = np.roll(a_l, -s, 1); fln = np.roll(fl, -s, 1)
            else:
                un = np.zeros_like(a_s); aln = np.zeros_like(a_s); fln = np.zeros_like(fl)
                n = a_s.shape[ax]
                src = [slice(None)] * 3; dst = [slice(None)] * 3
                if s == 1: src[ax], dst[ax] = slice(1, n), slice(0, n - 1)
                else:      src[ax], dst[ax] = slice(0, n - 1), slice(1, n)
                un[tuple(dst)] = u[ax][tuple(src)]; aln[tuple(dst)] = a_l[tuple(src)]
                fln[tuple(dst)] = fl[tuple(src)]
            approach = np.where(fln & (aln >= 1e-2), -s * un, 0.0)
            uph = np.maximum(uph, np.where(closed, approach, 0.0))
    pabs = np.where(fl, np.abs(d['pressure']), 0.0)
    kp = np.unravel_index(np.argmax(pabs), pabs.shape)
    return pabs.max(), kp, uph, int(closed.sum())

def near(uph, kp):
    k, j, i = kp; nk, nj, ni = uph.shape
    ks = slice(max(k - DIST, 0), k + DIST + 1); is_ = slice(max(i - DIST, 0), i + DIST + 1)
    js = [(j + o) % nj for o in range(-DIST, DIST + 1)]
    return uph[ks][:, js][:, :, is_].max()

def step_of(f):
    return int(re.search(r'(\d{8})\.(h5|npz)$', f).group(1))

def save(f, s, out):
    np.savez_compressed(os.path.join(out, '%08d.npz' % step_of(f)), pmax=s[0], kp=np.array(s[1]),
                        uph=s[2].astype(np.float32), nclosed=s[3])

def stream(dd, pidfile):
    out = os.path.join(dd, 'phantom'); os.makedirs(out, exist_ok=True)
    def alive():
        try: os.kill(int(open(pidfile).read()), 0); return True
        except Exception: return False
    while True:
        running = alive()
        files = sorted(glob.glob(dd.rstrip('/') + '/eaf3d_*.h5'))
        done = files if not running else files[:-1]   # el ultimo puede estar escribiendose
        for f in done:
            if os.path.exists(os.path.join(out, '%08d.npz' % step_of(f))): continue
            save(f, scan(load(f)), out)
            if step_of(f) % 500 and f != files[-1]: os.remove(f)
        if not running: break
        time.sleep(5)

def summaries(dd):
    npz = sorted(glob.glob(os.path.join(dd, 'phantom', '*.npz')))
    if npz:
        S = []
        for f in npz:
            z = np.load(f); S.append((float(z['pmax']), tuple(int(x) for x in z['kp']), z['uph'], int(z['nclosed'])))
        return [step_of(f) for f in npz], S
    files = sorted(glob.glob(dd.rstrip('/') + '/eaf3d_*.h5'))
    return [step_of(f) for f in files], [scan(load(f)) for f in files]

def main(dirs):
    tot_ev = tot_pre = tot_q = tot_qpre = 0
    for dd in dirs:
        steps, S = summaries(dd)
        files = steps
        uglob = [s[2].max() for s in S]
        peaks = [n for n, s in enumerate(S) if s[0] > P_PEAK]
        events = [n for n in peaks if not any(0 < steps[n] - steps[m] <= GAP for m in peaks if m < n)]
        print(f'== {dd}  snapshots {len(files)}  pasos {steps[0]}-{steps[-1]}  eventos {len(events)}')
        for n in events:
            prev = [m for m in range(n) if 0 < steps[n] - steps[m] <= WIN]
            if not prev:
                print(f'   evento paso {steps[n]} max|p| {S[n][0]:.3g} kp {S[n][1]}: SIN snapshots previos (excluido)'); continue
            u_loc = max(near(S[m][2], S[n][1]) for m in prev)
            hit = u_loc > U_PH; tot_ev += 1; tot_pre += hit
            print(f'   evento paso {steps[n]} max|p| {S[n][0]:.3g} celda[k,j,i] {S[n][1]} previos {len(prev)} '
                  f'u_ph_local_max {u_loc:.2f} -> {"PRECURSOR" if hit else "no"}')
        quiet = [n for n, s in enumerate(S) if s[0] < P_QUIET]
        for n in quiet:
            prev = [m for m in range(n) if 0 < steps[n] - steps[m] <= WIN]
            if not prev: continue
            tot_q += 1; tot_qpre += max(near(S[m][2], S[n][1]) for m in prev) > U_PH
        print(f'   u_ph global max {max(uglob):.2f}  receptoras cerradas (medio) {np.mean([s[3] for s in S]):.1f}')
    print(f'TOTAL eventos {tot_ev}  con precursor {tot_pre} ({100*tot_pre/max(tot_ev,1):.1f} %)  '
          f'control quieto {tot_q} con precursor {tot_qpre} ({100*tot_qpre/max(tot_q,1):.1f} %)')

if __name__ == '__main__':
    if sys.argv[1] == '--stream':
        stream(sys.argv[2], sys.argv[3])
    else:
        main(sys.argv[1:])
