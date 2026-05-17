#!/usr/bin/env python3
"""
hdf5_to_vtk.py - Convert HDF5 parallel output to VTK for visualization

Usage:
    python hdf5_to_vtk.py input.h5 [output.vts]
    python hdf5_to_vtk.py output/*.h5  # Batch convert all
"""

import h5py
import numpy as np
import sys
import os
from pathlib import Path

try:
    import pyvista as pv
    HAS_PYVISTA = True
except ImportError:
    HAS_PYVISTA = False
    print("Warning: pyvista not installed. Install with: pip install pyvista")

def read_hdf5(filename):
    """Read EAF HDF5 file and return dictionary of data"""
    data = {}
    
    with h5py.File(filename, 'r') as f:
        # Read mesh
        data['r'] = f['/mesh/r'][:]
        data['theta'] = f['/mesh/theta'][:]
        data['z'] = f['/mesh/z'][:]
        
        # Read metadata
        data['time'] = f['/metadata'].attrs['time']
        data['step'] = f['/metadata'].attrs['step']
        data['nprocs'] = f['/metadata'].attrs['nprocs']
        
        # Read all fields
        for key in f['/fields'].keys():
            data[key] = f[f'/fields/{key}'][:]
    
    return data

def cylindrical_to_cartesian_grid(r, theta, z):
    """Convert cylindrical mesh to Cartesian coordinates for VTK"""
    nr, nth, nz = len(r), len(theta), len(z)
    
    # Create structured grid points in Cartesian
    X = np.zeros((nr, nth, nz))
    Y = np.zeros((nr, nth, nz))
    Z = np.zeros((nr, nth, nz))
    
    for i, ri in enumerate(r):
        for j, thj in enumerate(theta):
            X[i,j,:] = ri * np.cos(thj)
            Y[i,j,:] = ri * np.sin(thj)
            Z[i,j,:] = z
    
    return X, Y, Z

def convert_to_vtk(hdf5_file, vtk_file=None):
    """Convert HDF5 to VTK structured grid"""
    if not HAS_PYVISTA:
        print(f"ERROR: pyvista required for VTK conversion")
        return False
    
    if vtk_file is None:
        vtk_file = hdf5_file.replace('.h5', '.vts')
    
    print(f"Converting: {hdf5_file} -> {vtk_file}")
    
    # Read HDF5
    data = read_hdf5(hdf5_file)
    
    # Convert to Cartesian grid
    X, Y, Z = cylindrical_to_cartesian_grid(data['r'], data['theta'], data['z'])
    
    # Create structured grid
    grid = pv.StructuredGrid(X, Y, Z)
    
    # Add all field data (flatten to 1D for pyvista)
    nr, nth, nz = len(data['r']), len(data['theta']), len(data['z'])
    
    for key in data.keys():
        if key in ['r', 'theta', 'z', 'time', 'step', 'nprocs']:
            continue
        
        field = data[key]
        if field.shape == (nr, nth, nz):
            # Flatten in Fortran order (i changes fastest)
            grid[key] = field.flatten(order='F')
    
    # Add metadata as field data
    grid.field_data['time'] = np.array([data['time']])
    grid.field_data['step'] = np.array([data['step']])
    grid.field_data['nprocs'] = np.array([data['nprocs']])
    
    # Save
    grid.save(vtk_file)
    print(f"  ✓ Written: {vtk_file}")
    print(f"    Time: {data['time']:.2f} s, Step: {data['step']}, Procs: {data['nprocs']}")
    
    return True

def print_hdf5_info(filename):
    """Print summary of HDF5 file contents"""
    data = read_hdf5(filename)
    
    print(f"\n{'='*60}")
    print(f"HDF5 File: {filename}")
    print(f"{'='*60}")
    print(f"Metadata:")
    print(f"  Time:      {data['time']:.4f} s")
    print(f"  Step:      {data['step']}")
    print(f"  Processes: {data['nprocs']}")
    print(f"\nMesh:")
    print(f"  r:     {len(data['r'])} points ({data['r'][0]:.4f} to {data['r'][-1]:.4f} m)")
    print(f"  theta: {len(data['theta'])} points (0 to {data['theta'][-1]:.4f} rad)")
    print(f"  z:     {len(data['z'])} points ({data['z'][0]:.4f} to {data['z'][-1]:.4f} m)")
    print(f"  Total cells: {len(data['r']) * len(data['theta']) * len(data['z'])}")
    
    print(f"\nFields:")
    nr, nth, nz = len(data['r']), len(data['theta']), len(data['z'])
    for key in sorted(data.keys()):
        if key in ['r', 'theta', 'z', 'time', 'step', 'nprocs']:
            continue
        field = data[key]
        print(f"  {key:25s}: shape {field.shape}, " +
              f"range [{field.min():.3e}, {field.max():.3e}]")
    
    print(f"{'='*60}\n")

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    files = sys.argv[1:]
    
    # Check if user wants info only
    if '--info' in files:
        files = [f for f in files if f != '--info']
        for f in files:
            print_hdf5_info(f)
        return
    
    # Convert to VTK
    if not HAS_PYVISTA:
        print("ERROR: pyvista not available. Use --info to just print file contents.")
        sys.exit(1)
    
    success_count = 0
    for hdf5_file in files:
        if not os.path.exists(hdf5_file):
            print(f"ERROR: File not found: {hdf5_file}")
            continue
        
        if convert_to_vtk(hdf5_file):
            success_count += 1
    
    print(f"\n✓ Converted {success_count}/{len(files)} files")

if __name__ == '__main__':
    main()
