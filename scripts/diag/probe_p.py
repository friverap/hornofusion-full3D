#!/usr/bin/env python3
"""Tabula las lineas [PROBE-P] (fila de la ecuacion de presion de una celda,
por iteracion externa). El tiempo de cada paso sale del audit.csv junto al
run.log (columnas step,time; o --audit RUTA); sin audit se imprime nan.
Uso: probe_p.py run.log [--cada N] [--audit audit.csv]"""
import csv, os, re, sys
pat=re.compile(r'\[PROBE-P\] paso\s+(\d+).*act_l/g=\s*([TF])([TF]).*Su_liq=\s*(\S+)\s+Su_gas=\s*(\S+)\s+Su_comp=\s*(\S+).*aW=\s*(\S+)\s+aE=\s*(\S+)\s+aS=\s*(\S+)\s+aN=\s*(\S+)\s+aB=\s*(\S+)\s+aT=\s*(\S+)\s+aP=\s*(\S+).*p_in=\s*(\S+)\s+al=\s*(\S+)\s+ag=\s*(\S+).*aPuz=\s*(\S+)\s+aPuz_T=\s*(\S+)\s+aPur_W=\s*(\S+)\s+aPur=\s*(\S+)\s+aPuth=\s*(\S+)')
pp=re.compile(r'\[PROBE-P\] paso\s+(\d+)\s+pp=\s*(\S+)\s+pp_vec\(W,E,S,N,B,T\)=\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)')
rows={}; sol={}
for ln in open(sys.argv[1]):
    m=pat.search(ln)
    if m:
        st=int(m.group(1)); rows.setdefault(st,[]).append([m.group(2)+m.group(3)]+[float(x) for x in m.groups()[3:]])
        continue
    m=pp.search(ln)
    if m:
        st=int(m.group(1)); sol.setdefault(st,[]).append([float(x) for x in m.groups()[1:]])
ap=sys.argv[sys.argv.index('--audit')+1] if '--audit' in sys.argv else os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])),'audit.csv')
tmap={}
if os.path.exists(ap):
    for x in csv.DictReader(open(ap), skipinitialspace=True): tmap[int(x['step'])]=float(x['time'])
cada=int(sys.argv[sys.argv.index('--cada')+1]) if '--cada' in sys.argv else 1
print(' paso    t      | act | Su_liq    Su_gas    Su_comp  |  aW       aE       aS       aN       aB       aT    |   aP     | p_in     pp(ult) | al    ag    | aPuz     aPuz_T   aPur_W   aPur     aPuth')
for st in sorted(rows)[::cada]:
    r=rows[st][-1]; s=sol.get(st,[[float('nan')]*7])[-1]
    print('%6d %8.3f | %s  | %+8.2e %+8.2e %+8.2e | %7.1e %7.1e %7.1e %7.1e %7.1e %7.1e | %7.1e | %8.4g %+9.3g | %.3f %.3f | %7.1e %7.1e %7.1e %7.1e %7.1e'%(
        st,tmap.get(st,float('nan')),r[0],r[1],r[2],r[3],r[4],r[5],r[6],r[7],r[8],r[9],r[10],r[11],s[0],r[12],r[13],r[14],r[15],r[16],r[17],r[18]))
if sol:
    st=max(sol); s=sol[st][-1]
    print('ultimo paso %d: pp celda %+.3g; vecinas W %+.3g E %+.3g S %+.3g N %+.3g B %+.3g T %+.3g'%(st,*s))
