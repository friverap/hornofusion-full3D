# Phase 9 Validation - Summary

## Status: READY TO EXECUTE

All components for Phase 9 validation are prepared and ready. The full production simulation requires ~24-48 hours to complete.

## Completed Tasks

### ✅ 1. Production Configuration (`input/config_production.dat`)
- Mesh: 60 × 120 × 84 = 604,800 cells (matches paper)
- Physical time: 5040 seconds (full tap-to-tap melting)
- All parameters match Ugarte et al. (2024) specifications
- Adaptive time stepping enabled

### ✅ 2. Validation Script (`scripts/validate_phase9.py`)
Automated post-processing that:
- Parses monitor output for solid mass evolution
- Computes key validation metrics
- Compares against paper targets (Table 3)
- Generates comprehensive validation plots
- Reports pass/fail status for each metric

### ✅ 3. Launch Script (`run_production.sh`)
Automated workflow that:
- Compiles optimized version
- Prepares output directories
- Launches simulation in background
- Provides monitoring instructions

### ✅ 4. Documentation
- `PHASE9_VALIDATION.md`: Complete validation guide
- `README_VALIDATION.md`: This summary
- Clear instructions for execution and troubleshooting

## Quick Start

### Option A: Run Production Simulation (24-48 hours)

```bash
cd full3D
./run_production.sh
```

This will:
1. Compile optimized version
2. Launch 604,800-cell simulation
3. Run for ~5040 seconds physical time
4. Save results to `output_production/`

Monitor progress:
```bash
tail -f production_monitor.log
```

After completion:
```bash
python3 scripts/validate_phase9.py
```

### Option B: Quick Test First (5 minutes)

```bash
cd full3D
make clean && make debug
./bin/eaf3d input/config_small_test.dat
```

This verifies the solver is stable before committing to the long production run.

## Validation Metrics

The validation script will compare:

| Metric | Paper Target | Tolerance |
|--------|-------------|-----------|
| Solid mass @ t=2100s | 29.4 tons | ±10% |
| Solid mass @ t=5040s | 42.8 tons | ±10% |
| Solid/liquid ratio | 32.5% / 67.5% | ±10% |
| Avg melting rate | 18.3 kg/s | ±15% |

**Pass Criteria**: All metrics within tolerance

## Expected Output

### During Simulation
- Console monitor every 10 steps
- VTK files every 100 steps (~500 files)
- Total disk usage: ~50-100 GB
- Memory usage: ~10 GB RAM

### After Validation
- `validation_results.png`: 4-panel comparison plots
- `validation_metrics.txt`: Numerical results
- Console report with pass/fail for each metric

## Computational Requirements

### Minimum
- CPU: 4 cores (modern x86_64)
- RAM: 12 GB
- Disk: 150 GB free
- Time: 48 hours

### Recommended
- CPU: 8+ cores (with AVX2)
- RAM: 16 GB
- Disk: 250 GB SSD
- Time: 24 hours

## Troubleshooting

### Simulation crashes
1. Check `production_monitor.log` for error messages
2. Verify memory is sufficient (top/htop)
3. Try smaller mesh first (nr=40, ntheta=80, nz=60)

### Very large energy residuals
- Expected in first few timesteps (cold start)
- Should decrease exponentially
- If stuck at >1e20, check arc heat distribution

### Timestep collapses to minimum
- Normal if convergence is slow
- Simulation will still progress
- May indicate stiff physics (arc, melting)

### Validation fails
1. Check if simulation reached t=5040s
2. Verify solid mass trend is decreasing
3. Review parameter tuning section in `PHASE9_VALIDATION.md`

## Parameter Tuning

If metrics deviate >10% from targets, adjust in order:

1. **Arc heat distribution** (`mod_arc_cassie_mayr.f90`):
   - `frac_rad = 0.50` → adjust ±0.1
   - `frac_conv = 0.30` → adjust ±0.1
   - Gaussian width `sigma_r` → adjust ±20%

2. **Melting model** (`mod_constants.f90`):
   - `H_FUSION = 247000` J/kg → adjust ±10%
   - Check interphase heat transfer coefficients

3. **Material properties**:
   - Thermal conductivity `k_s`, `k_l`
   - Liquid viscosity `mu_l`

## Timeline

| Task | Duration | Status |
|------|----------|--------|
| Setup & configuration | 2 hours | ✅ DONE |
| Production run | 24-48 hours | ⏳ READY |
| Validation analysis | 30 minutes | ⏳ PENDING |
| Parameter tuning (if needed) | 1-2 days | ⏳ PENDING |
| Final documentation | 1 hour | ⏳ PENDING |

## Next Steps

1. **Immediate**: Run `./run_production.sh` to start validation
2. **After 24-48h**: Run `python3 scripts/validate_phase9.py`
3. **If PASS**: Document results, update plan, complete Phase 9
4. **If FAIL**: Analyze deviations, tune parameters, re-run

## Files Created

```
full3D/
├── input/
│   ├── config_production.dat      # Production config (604k cells)
│   ├── config_small_test.dat     # Quick test config (4k cells)
│   ├── electrode_profile.dat     # V/I time series (18 points)
│   └── charge_recipe.dat         # Scrap layering (27 layers)
├── scripts/
│   └── validate_phase9.py        # Validation post-processor
├── run_production.sh              # Launch script
├── PHASE9_VALIDATION.md          # Detailed guide
└── README_VALIDATION.md          # This file
```

## Contact / Notes

- Validation targets from: Ugarte et al. (2024) Materials 17(21), 5139
- Phases 1-8: Complete (all physics implemented, bugs fixed)
- Phase 9: Infrastructure ready, awaiting production run
- Estimated completion: 2-3 days (including re-runs if tuning needed)

---

**Ready to proceed with production validation run.**
