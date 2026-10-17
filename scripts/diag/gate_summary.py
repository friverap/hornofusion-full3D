#!/usr/bin/env python3
"""gate_summary.py <rundir> - resumen de un gate de banco (Plan H, P4).

Maximos por segundo simulado de u_liq, vol_lim, u_gas y p (audit.csv), totales
de volfix y E_slag_tclip, y por snapshot: acero sobre la escoria, gas bajo la
escoria y rango de T_sl en celdas con escoria resuelta. Complementa a
check_audit.py / check_slag_bed.py (que son los gates formales).
"""
import csv, sys, glob
import h5py, numpy as np
d = sys.argv[1]
r=list(csv.DictReader(open(d+'/audit.csv')))
print('pasos',len(r))
def per_s(col,fmt,agg=max):
    out=[];T=float(r[-1]['time'])
    for s in range(int(np.ceil(T))):
        v=[float(x[col]) for x in r if s<float(x['time'])<=s+1]
        if v: out.append(fmt%agg(v))
    return out
print('u_liq/s',per_s('u_liq_max','%.3f'))
print('vol_lim/s',per_s('vol_lim','%.1e'))
print('u_gas/s',per_s('u_gas_max','%.0f'))
print('p_max kPa/s',[('%.0f'%(float(v)/1e3)) for v in per_s('p_max','%.6g')])
print('volfix tot %.2e kg'%sum(float(x['m_gas_volfix']) for x in r))
print('tclip tot %.2e J'%sum(float(x['E_slag_tclip']) for x in r))
for f in sorted(glob.glob(d+'/eaf3d_*.h5')):
    F=h5py.File(f,'r')['fields']; al=F['alpha_liquid'][:]; asl=F['alpha_slag'][:]; ag=F['alpha_gas'][:]; T=F['T_slag'][:]
    nz=al.shape[0]; above=0; gas_under=0
    for j in range(al.shape[1]):
        for i in range(al.shape[2]):
            ks=np.where(asl[:,j,i]>1e-3)[0]
            if len(ks)==0: continue
            above=max(above,al[ks.max()+1:,j,i].max() if ks.max()+1<nz else 0)
            gas_under=max(gas_under,ag[:ks.min(),j,i].max() if ks.min()>0 else 0)
    m=asl>1e-6
    print(f.split('_')[-1][:8],'acero sobre escoria %.2e gas bajo escoria %.2e Tsl[%.0f,%.0f]'%(above,gas_under,T[m].min() if m.any() else 0,T[m].max() if m.any() else 0))
