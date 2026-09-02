"""Utilidades compartidas de los tests de integración EAF3D.

Lectura de configs clave=valor (mismo dialecto que mod_config_3d.f90:
'#'/'!' comentarios, la última ocurrencia gana, claves desconocidas se
ignoran) y helpers de snapshots HDF5.

Convención de ejes h5py: los campos se escriben (nr,nth,nz) column-major
en Fortran, así que h5py los presenta como (nz, nth, nr) -> eje theta = 1.
"""
import glob
import os
import sys

import h5py
import numpy as np

# Valores por defecto de config_set_defaults (mod_config_3d.f90) que los
# checkers necesitan cuando el config del test no los redefine.
DEFAULTS = {
    "R_shell": 3.80, "H_total": 4.50, "H_bowl": 0.60, "R_bowl": 2.50,
    "R_pcd": 0.85, "R_elec": 0.30,
    "rho_steel": 7500.0, "T_initial": 300.0, "T_ambient": 300.0,
    "ntheta": 120, "nr": 60, "nz": 84,
}

N_ELECTRODES = 3


def read_config(path):
    cfg = dict(DEFAULTS)
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line[0] in "#!":
                continue
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key, val = key.strip(), val.strip()
            if not key:
                continue
            for cast in (int, float):
                try:
                    cfg[key] = cast(val)
                    break
                except ValueError:
                    continue
            else:
                if val in ("true", ".true."):
                    cfg[key] = True
                elif val in ("false", ".false."):
                    cfg[key] = False
                else:
                    cfg[key] = val
    return cfg


def snapshots(rundir):
    """Rutas de snapshots ordenadas por paso."""
    files = sorted(glob.glob(os.path.join(rundir, "eaf3d_*.h5")))
    if not files:
        sys.exit(f"ERROR: no hay snapshots eaf3d_*.h5 en {rundir}")
    return files


def load_snapshot(path):
    """Devuelve (fields: dict nombre->ndarray, mesh: dict, meta: dict).

    time/step/nprocs viven como ATRIBUTOS HDF5 del grupo /metadata
    (mod_output_hdf5.f90::write_metadata), no como datasets.
    """
    fields, mesh, meta = {}, {}, {}
    with h5py.File(path, "r") as f:
        for name, ds in f["fields"].items():
            fields[name] = ds[:]
        for name, ds in f["mesh"].items():
            mesh[name] = ds[:]
        g = f["metadata"]
        for name, ds in g.items():
            meta[name] = ds[()]
        for name, value in g.attrs.items():
            meta[name] = np.asarray(value).item()
    return fields, mesh, meta


def cell_volumes(mesh):
    """Volúmenes de celda (nz,nth,nr) desde coordenadas de centros.

    Exacto para stretch=1.0 (los configs de test lo fijan): con paso
    uniforme, vol = r_c*dr*dth*dz coincide con 0.5*(rf^2-rf-^2)*dth*dz.
    """
    r, th, z = mesh["r"], mesh["theta"], mesh["z"]
    for name, x in (("r", r), ("theta", th), ("z", z)):
        d = np.diff(x)
        if len(d) and not np.allclose(d, d[0], rtol=1e-9):
            sys.exit(f"ERROR: malla no uniforme en {name}; "
                     "cell_volumes exige stretch=1.0 en configs de test")
    dr = r[1] - r[0] if len(r) > 1 else r[0] * 2
    dth = th[1] - th[0] if len(th) > 1 else 2 * np.pi
    dz = z[1] - z[0] if len(z) > 1 else z[0] * 2
    vol_r = r * dr * dth * dz                    # (nr,)
    return np.broadcast_to(vol_r[None, None, :],
                           (len(z), len(th), len(r))).copy()


def arc_column_mask(mesh, cfg, radius_factor=2.0):
    """Máscara (nz,nth,nr) de la columna de arco: dist horizontal al eje de
    algún electrodo < radius_factor * sigma_r, con sigma_r = 1.5*R_elec
    (mismo criterio que distribute_arc_heat)."""
    r, th = mesh["r"], mesh["theta"]
    sigma_r = 1.5 * cfg["R_elec"]
    rr, tt = np.meshgrid(r, th, indexing="xy")   # (nth, nr)
    x, y = rr * np.cos(tt), rr * np.sin(tt)
    mask2d = np.zeros_like(x, dtype=bool)
    for e in range(N_ELECTRODES):
        the = 2 * np.pi * e / N_ELECTRODES
        xe, ye = cfg["R_pcd"] * np.cos(the), cfg["R_pcd"] * np.sin(the)
        mask2d |= np.hypot(x - xe, y - ye) < radius_factor * sigma_r
    nz = len(mesh["z"])
    return np.broadcast_to(mask2d[None, :, :], (nz,) + mask2d.shape).copy()


class Checker:
    """Acumula resultados PASS/FAIL/XFAIL/XPASS de sub-chequeos."""

    def __init__(self, xfail_ids):
        self.xfail = set(x for x in xfail_ids if x)
        self.hard_fail = False
        self.xpass = []

    def report(self, check_id, ok, detail=""):
        if ok and check_id in self.xfail:
            print(f"  XPASS {check_id}  {detail}  (si ya no falla en "
                  "NINGUNA corrida, quitar de tests/xfail.list)")
            self.xpass.append(check_id)
        elif ok:
            print(f"  PASS  {check_id}  {detail}")
        elif check_id in self.xfail:
            print(f"  XFAIL {check_id}  {detail}")
        else:
            print(f"  FAIL  {check_id}  {detail}")
            self.hard_fail = True

    def exit(self):
        sys.exit(1 if self.hard_fail else 0)


def parse_xfail_arg(argv_value):
    return [s.strip() for s in (argv_value or "").split(",") if s.strip()]
