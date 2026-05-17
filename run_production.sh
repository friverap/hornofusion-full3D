#!/bin/bash
#===============================================================================
# run_production.sh - Launch production validation run
#
# This script:
# 1. Compiles optimized version
# 2. Prepares output directory
# 3. Launches production simulation in background
# 4. Sets up monitoring
#===============================================================================

set -e  # Exit on error

echo "========================================================================"
echo "PHASE 9 VALIDATION - PRODUCTION RUN"
echo "Ugarte et al. (2024) - Full tap-to-tap melting simulation"
echo "========================================================================"
echo ""

# Configuration
CONFIG_FILE="input/config_production.dat"
OUTPUT_DIR="output_production"
LOG_FILE="production_monitor.log"
PID_FILE="production.pid"

# Check if already running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Error: Production run already in progress (PID: $PID)"
        echo "Kill it first with: kill $PID"
        exit 1
    else
        rm "$PID_FILE"
    fi
fi

# Step 1: Compile optimized version
echo "[1/5] Compiling optimized version..."
make clean > /dev/null 2>&1
make opt
if [ $? -ne 0 ]; then
    echo "Error: Compilation failed"
    exit 1
fi
echo "✓ Compilation successful"
echo ""

# Step 2: Prepare output directory
echo "[2/5] Preparing output directory..."
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.vtk  # Clean previous output
echo "✓ Output directory ready: $OUTPUT_DIR"
echo ""

# Step 3: Check configuration
echo "[3/5] Checking configuration..."
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Extract key parameters
NR=$(grep "^nr" "$CONFIG_FILE" | awk -F= '{print $2}' | tr -d ' ')
NTH=$(grep "^ntheta" "$CONFIG_FILE" | awk -F= '{print $2}' | tr -d ' ')
NZ=$(grep "^nz" "$CONFIG_FILE" | awk -F= '{print $2}' | tr -d ' ')
TFINAL=$(grep "^t_final" "$CONFIG_FILE" | awk -F= '{print $2}' | tr -d ' ')

NCELLS=$((NR * NTH * NZ))

echo "Configuration:"
echo "  Mesh: $NR × $NTH × $NZ = $NCELLS cells"
echo "  Physical time: $TFINAL seconds"
echo "  Config file: $CONFIG_FILE"
echo "✓ Configuration valid"
echo ""

# Step 4: Estimate runtime
echo "[4/5] Runtime estimation..."
NSTEPS=$(echo "$TFINAL / 0.1" | bc)  # Assuming avg dt ~ 0.1s
echo "  Estimated time steps: ~$NSTEPS"
echo "  Estimated runtime: 24-48 hours"
echo "  Memory usage: ~10 GB RAM"
echo "  Disk usage: ~50-100 GB (VTK files)"
echo ""

# Ask for confirmation
read -p "Ready to launch production run? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled by user"
    exit 0
fi

# Step 5: Launch simulation
echo "[5/5] Launching simulation..."
echo ""
echo "Starting at: $(date)"
echo "Log file: $LOG_FILE"
echo "PID will be saved to: $PID_FILE"
echo ""

# Launch in background
nohup ./bin/eaf3d "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
SIM_PID=$!

# Save PID
echo "$SIM_PID" > "$PID_FILE"

echo "✓ Simulation launched successfully!"
echo ""
echo "========================================================================"
echo "SIMULATION RUNNING"
echo "========================================================================"
echo "PID: $SIM_PID"
echo ""
echo "Monitor progress with:"
echo "  tail -f $LOG_FILE"
echo ""
echo "Check status with:"
echo "  ps -p $SIM_PID"
echo ""
echo "Stop simulation with:"
echo "  kill $SIM_PID"
echo ""
echo "When complete, run validation:"
echo "  python3 scripts/validate_phase9.py"
echo "========================================================================"
