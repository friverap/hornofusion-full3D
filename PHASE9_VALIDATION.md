# Phase 9 - Validation

## Overview

This phase validates the 3D EAF CFD solver against the results from Ugarte et al. (2024) "CFD Modeling of HBI/scrap Melting in Industrial EAF and the Impact of Charge Layering on Melting Performance" (Materials 17(21), 5139).

## Validation Targets (from Paper Table 3)

1. **Solid mass at end of Bucket 1** (t = 2100s): 29.4 tons (from initial 65.7 tons)
2. **Solid mass at refining start** (t = 5040s): 42.8 tons (32.5% of 131.9 tons total)
3. **Average melting rate**: 18.3 kg/s (within 8.3% of plant data: 19.9 kg/s)
4. **Solid/liquid ratio at refining start**: 32.5% / 67.5%

## Configuration

### Production Configuration
File: `input/config_production.dat`

- Mesh: 60 × 120 × 84 = 604,800 cells (matching paper)
- Physical time: 5040 seconds (full tap-to-tap melting stage)
- Time step: adaptive (0.001 to 1.0 s)
- All physics modules enabled

### Computational Requirements

**Estimated runtime:** 
- With current implementation: **24-48 hours** on a modern workstation
- Cell count: 604,800 cells
- Time steps: ~50,000 steps (assuming average dt ≈ 0.1s)
- Memory: ~8-12 GB RAM

## Running the Validation

### Step 1: Compile Production Version

```bash
cd full3D
make clean
make opt  # Use optimized build for production run
```

### Step 2: Run Production Simulation

```bash
# Create output directory
mkdir -p output_production

# Run simulation (this will take a long time!)
nohup ./bin/eaf3d input/config_production.dat > monitor.log 2>&1 &

# Monitor progress
tail -f monitor.log
```

**Note:** The simulation will output:
- Console monitoring every 10 steps
- VTK files every 100 steps (~500 files total)
- Total output size: ~50-100 GB

### Step 3: Post-Process Results

Once the simulation completes:

```bash
cd scripts
python3 validate_phase9.py
```

This will:
1. Parse `monitor.log` for solid mass evolution
2. Compute validation metrics
3. Compare with paper targets
4. Generate validation plots (`validation_results.png`)
5. Save metrics to `validation_metrics.txt`

## Validation Criteria

✓ **PASS**: All metrics within ±10% of paper targets
✗ **FAIL**: Any metric exceeds ±10% deviation

If validation fails, parameter tuning may be required (see below).

## Quick Test (Reduced Scale)

For a quick sanity check before the full run:

```bash
# Run small test (5 seconds, 4608 cells)
./bin/eaf3d input/config_small_test.dat > test_monitor.log 2>&1

# Check that:
# 1. Simulation runs without crashes
# 2. Solid mass decreases over time
# 3. Energy residual converges
```

## Parameter Tuning (if needed)

If validation metrics deviate >10%, consider adjusting:

### Arc Model Parameters
- `frac_rad`, `frac_conv`, `frac_elec`: Heat distribution shares
- Arc constants: `tau`, `w`, `sigma` in `mod_constants.f90`

### Melting Model
- `h_fusion`: Latent heat (currently 247 kJ/kg)
- Solid-liquid heat transfer coefficients in `mod_interphase_ht.f90`

### Material Properties
- `k_s`, `k_l`: Thermal conductivities
- `mu_l`: Liquid viscosity
- `cp_s`, `cp_l`: Specific heats

### Numerical Parameters
- Under-relaxation factors: `alpha_u`, `alpha_T`
- Convergence tolerances: `tol_energy`
- Time step bounds: `dt_min`, `dt_max`

## Current Status

- ✅ Phase 1-8: Complete (all physics modules implemented)
- ✅ Production config: Created
- ✅ Validation script: Ready
- ⏳ Production run: **Not yet executed** (requires 24-48 hours)
- ⏳ Validation: Pending production run completion

## Expected Results

Based on the physics implementation:

### Likely Outcomes
1. **Solid mass evolution**: Should follow general trend (decreasing from 132t to ~43t)
2. **Melting rate**: Should be in ballpark of 15-25 kg/s
3. **Solid/liquid ratio**: Should reach ~30-40% solid at end

### Potential Issues
1. **Faster melting**: If heat transfer coefficients too high → reduce `h_vgs`
2. **Slower melting**: If arc heat distribution too diffuse → adjust Gaussian width
3. **Mass conservation**: Should be exact (<0.1% error) - any deviation indicates bug

## Next Steps

### For Immediate Testing
Run the small test to verify stability:
```bash
./bin/eaf3d input/config_small_test.dat
```

### For Full Validation
1. Start production run (ideally overnight/weekend)
2. Monitor progress periodically
3. After completion, run validation script
4. Document results
5. Tune parameters if needed and re-run

## Files

- `input/config_production.dat`: Production configuration
- `input/config_small_test.dat`: Quick test configuration
- `scripts/validate_phase9.py`: Validation post-processor
- `monitor.log`: Runtime output (created during simulation)
- `validation_results.png`: Validation plots (created by script)
- `validation_metrics.txt`: Numerical comparison (created by script)

## Notes

- The paper used ANSYS Fluent which is highly optimized. Our Fortran implementation may be slower but should produce comparable results.
- First run will be slower due to OS caching. Subsequent runs faster.
- Consider using optimized BLAS/LAPACK for linear solvers if available.
- For very long runs, enable checkpointing to restart if interrupted.
