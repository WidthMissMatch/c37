#!/bin/bash
#
# run_comparison_xsim.sh
# Compile old/new pmu_processing_top into separate Vivado xsim libraries,
# then run tb_pmu_comparison for all 6 test datasets.
#
# Prerequisites:
#   - Vivado must be on PATH (source /tools/Xilinx/Vivado/*/settings64.sh)
#
# Usage:
#   cd "c37 compliance/comparison"
#   bash scripts/run_comparison_xsim.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMP_DIR="$(dirname "$SCRIPT_DIR")"        # comparison/
C37_DIR="$(dirname "$COMP_DIR")"           # c37 compliance/

SRC_OLD="$C37_DIR/src/old"
SRC_NEW="$C37_DIR/src/new"
TB_DIR="$COMP_DIR/testbenches"
DATASET_DIR="$COMP_DIR/datasets"
RESULT_DIR="$COMP_DIR/results"
WORK_DIR="$COMP_DIR/xsim_work"

# Compile order: dependencies first, then top-level last
COMPILE_FILES=(
    sine.vhd
    cos.vhd
    circular_buffer.vhd
    sample_counter.vhd
    cycle_tracker.vhd
    position_calc.vhd
    Sample_fetcher.vhd
    interpolation_engine.vhd
    resampler_top.vhd
    dft_sample_buffer.vhd
    dft.vhd
    cordic_calculator_256.vhd
    frequency_rocof_calculator_256.vhd
    hann_window.vhd
    freq_damping_filter.vhd
    pmu_processing_top.vhd
)

# Test datasets
DATASETS=(
    test_50hz_pure
    test_49_5hz_offbin
    test_50hz_harmonics
    test_freq_step
    single_real
    medhavi_ch1_real
)

echo "============================================================"
echo "  PMU Comparison: Vivado xsim Flow"
echo "============================================================"
echo "  Source (old): $SRC_OLD"
echo "  Source (new): $SRC_NEW"
echo "  Datasets:    $DATASET_DIR"
echo "  Results:     $RESULT_DIR"
echo ""

# Check Vivado tools
if ! command -v xvhdl &> /dev/null; then
    echo "ERROR: xvhdl not found. Source Vivado settings first:"
    echo "  source /tools/Xilinx/Vivado/<version>/settings64.sh"
    exit 1
fi

# ---------------------------------------------------------------
# Step 1: Clean and create work directories
# ---------------------------------------------------------------
echo "[1/4] Creating work directories..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$RESULT_DIR"
cd "$WORK_DIR"

# Create TCL batch script for simulation
cat > run_sim.tcl << 'EOF'
run 500 ms
quit
EOF

# ---------------------------------------------------------------
# Step 2: Compile source files into old_lib and new_lib
# ---------------------------------------------------------------
echo "[2/4] Compiling old sources into old_lib..."
for f in "${COMPILE_FILES[@]}"; do
    if [ -f "$SRC_OLD/$f" ]; then
        echo "  Compiling: $f"
        xvhdl --2008 -work old_lib "$SRC_OLD/$f" 2>&1 | grep -i "error" || true
    else
        echo "  WARNING: $SRC_OLD/$f not found, skipping"
    fi
done
echo "  old_lib compilation complete."
echo ""

echo "  Compiling new sources into new_lib..."
for f in "${COMPILE_FILES[@]}"; do
    if [ -f "$SRC_NEW/$f" ]; then
        echo "  Compiling: $f"
        xvhdl --2008 -work new_lib "$SRC_NEW/$f" 2>&1 | grep -i "error" || true
    else
        echo "  WARNING: $SRC_NEW/$f not found, skipping"
    fi
done
echo "  new_lib compilation complete."
echo ""

# ---------------------------------------------------------------
# Step 3: Compile testbench and elaborate
# ---------------------------------------------------------------
echo "[3/4] Compiling and elaborating testbench..."
xvhdl --2008 "$TB_DIR/tb_pmu_comparison.vhd"

echo "  Elaborating..."
xelab -debug off work.tb_pmu_comparison -s pmu_comparison_sim \
    -L old_lib -L new_lib 2>&1 | tail -5
echo "  Testbench ready."
echo ""

# ---------------------------------------------------------------
# Step 4: Run simulation for each dataset
# ---------------------------------------------------------------
echo "[4/4] Running simulations..."
echo ""

PASS_COUNT=0
FAIL_COUNT=0

for ds in "${DATASETS[@]}"; do
    INPUT_FILE="$DATASET_DIR/${ds}.txt"
    OUTPUT_FILE="$RESULT_DIR/${ds}_comparison_xsim.csv"

    if [ ! -f "$INPUT_FILE" ]; then
        echo "  SKIP: $INPUT_FILE not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo "  ---- Dataset: ${ds} ----"
    echo "    Input:  $INPUT_FILE"
    echo "    Output: $OUTPUT_FILE"

    # Create symlinks for testbench default generic paths
    ln -sf "$INPUT_FILE" "$WORK_DIR/input_samples.txt"

    # Run simulation
    if xsim pmu_comparison_sim -tclbatch run_sim.tcl \
        2>&1 | tee "$RESULT_DIR/${ds}_xsim.log" | tail -20; then

        # Move output CSV
        if [ -f "$WORK_DIR/comparison_output.csv" ]; then
            mv "$WORK_DIR/comparison_output.csv" "$OUTPUT_FILE"
            ROWS=$(wc -l < "$OUTPUT_FILE")
            echo "    PASS: $ROWS lines written"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "    FAIL: No output CSV generated"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo "    FAIL: Simulation error (see log)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Clean up symlink
    rm -f "$WORK_DIR/input_samples.txt"
    echo ""
done

echo "============================================================"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "  Output directory: $RESULT_DIR"
echo "============================================================"
