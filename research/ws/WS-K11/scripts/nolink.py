"""WS-K11 (C-275): celdas nolink frente a presión, por corrida.

Para cada audit.csv (sin el paso 1 tras el reinicio): distribución de
m_gas_cells_nolink, número de tramos con nolink, pasos con p_max >= 100 kPa
y filas de nivel centinela de B1 (u_gas_max >= 299 m/s o p_max >= 300 kPa)
que llevan nolink, y el orden (primer paso nolink frente a la primera fila
centinela). Solo lectura.

Uso: python3 research/ws/WS-K11/scripts/nolink.py [dir ...]
"""
import collections
import csv
import sys

DEF = ['k7v4_long', 'k11_f_dt025_fh280_f28', 'k11_g_dt025_a236_f28',
       'k11_i_dt025_fh285_f28', 'k11_j_dt025_fh295_f28']


def main(dirs):
    for d in dirs:
        a = list(csv.DictReader(open(f'campaigns/b1/{d}/audit.csv')))
        p0 = int(a[0]['step'])
        r = [x for x in a if int(x['step']) > p0 + 1]
        nl = [int(float(x['m_gas_cells_nolink'])) for x in r]
        p = [float(x['p_max']) for x in r]
        u = [float(x['u_gas_max']) for x in r]
        hp = [i for i in range(len(r)) if p[i] >= 1e5]
        st = [i for i in range(len(r)) if u[i] >= 299 or p[i] >= 3e5]
        tramos = sum(1 for i in range(len(nl)) if nl[i] > 0 and (i == 0 or nl[i - 1] == 0))
        dist = sorted(collections.Counter(v for v in nl if v > 0).items())
        n1 = next((r[i]['step'] for i in range(len(r)) if nl[i] > 0), None)
        s1 = next((r[i]['step'] for i in st), None)
        print(f'{d}: pasos nolink {sum(v > 0 for v in nl)}, max {max(nl)}, tramos {tramos}, '
              f'dist {dist}')
        print(f'   p>=100 kPa {len(hp)} (con nolink {sum(nl[i] > 0 for i in hp)}); '
              f'centinela B1 {len(st)} (con nolink {sum(nl[i] > 0 for i in st)}); '
              f'1er nolink {n1}, 1a centinela {s1}')


if __name__ == '__main__':
    main(sys.argv[1:] or DEF)
