import h5py, numpy as np, sys, glob
# uso: pmax_track.py dir [k j i]  -> por snapshot: celda de |p| max y estado; con kji fija, su historia
d=sys.argv[1]; fix=tuple(map(int,sys.argv[2:5])) if len(sys.argv)>4 else None
fs=sorted(glob.glob(d+'/eaf3d_*.h5'))
for fn in fs:
    f=h5py.File(fn,'r'); F=f['fields']; g=lambda n: F[n][()]
    p=g('pressure'); al,ag,a_s=g('alpha_liquid'),g('alpha_gas'),g('alpha_solid')
    cont=f['restart/liq_cont_prev'][()]>0.5
    ugz=g('velocity_z_gas'); ulz=g('velocity_z_liquid')
    Ug=np.sqrt(g('velocity_r_gas')**2+g('velocity_th_gas')**2+ugz**2)
    k,j,i = fix if fix else np.unravel_index(np.argmax(np.abs(p)),p.shape)
    st=int(fn[-11:-3])
    nb=[]
    for dk,dj,di in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
        kk,jj,ii=k+dk,(j+dj)%p.shape[1],i+di
        if 0<=kk<p.shape[0] and 0<=ii<p.shape[2]:
            nb.append(f"{'zzttrr'[[(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)].index((dk,dj,di))]}{'+-+-+-'[[(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)].index((dk,dj,di))]}:p{p[kk,jj,ii]/1e3:.0f}k as{a_s[kk,jj,ii]:.3f} al{al[kk,jj,ii]:.3f}{'C' if cont[kk,jj,ii] else 'd'}")
    print(f"{st} kji({k},{j},{i}) p={p[k,j,i]/1e3:.1f}k as={a_s[k,j,i]:.4f} al={al[k,j,i]:.4f}{'C' if cont[k,j,i] else 'd'} ag={ag[k,j,i]:.4f} |ug|={Ug[k,j,i]:.0f} ugz={ugz[k,j,i]:.1f} ulz={ulz[k,j,i]:.2f} | "+' '.join(nb))
