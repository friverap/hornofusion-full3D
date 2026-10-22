import h5py, numpy as np, sys, glob
# uso: gmax_track.py dir [k j i] -> por snapshot: celda de |u_g| max (alpha_g >= 1e-2) y vecinos; con kji fija, su historia
d=sys.argv[1]; fix=tuple(map(int,sys.argv[2:5])) if len(sys.argv)>4 else None
D=((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)); L=['z+','z-','t+','t-','r+','r-']
for fn in sorted(glob.glob(d+'/eaf3d_*.h5')):
    f=h5py.File(fn,'r'); F=f['fields']; g=lambda n: F[n][()]
    p=g('pressure'); al,ag,a_s=g('alpha_liquid'),g('alpha_gas'),g('alpha_solid')
    cont=f['restart/liq_cont_prev'][()]>0.5
    ur,ut,uz=g('velocity_r_gas'),g('velocity_th_gas'),g('velocity_z_gas')
    U=np.sqrt(ur**2+ut**2+uz**2); Um=np.where(ag>=1e-2,U,0)
    k,j,i = fix if fix else np.unravel_index(np.argmax(Um),U.shape)
    nb=[]
    for (dk,dj,di),l in zip(D,L):
        kk,jj,ii=k+dk,(j+dj)%p.shape[1],i+di
        if 0<=kk<p.shape[0] and 0<=ii<p.shape[2]:
            nb.append(f"{l}:p{p[kk,jj,ii]/1e3:.1f}k as{a_s[kk,jj,ii]:.3f} al{al[kk,jj,ii]:.3f}{'C' if cont[kk,jj,ii] else 'd'} ag{ag[kk,jj,ii]:.3f}")
    print(f"{fn[-11:-3]} kji({k},{j},{i}) |ug|={U[k,j,i]:.0f} (r{ur[k,j,i]:.0f} t{ut[k,j,i]:.0f} z{uz[k,j,i]:.0f}) p={p[k,j,i]/1e3:.1f}k as={a_s[k,j,i]:.4f} al={al[k,j,i]:.4f}{'C' if cont[k,j,i] else 'd'} ag={ag[k,j,i]:.4f} | "+' '.join(nb))
