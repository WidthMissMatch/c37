#!/bin/bash
#
# run_comparison_ghdl.sh
# Compile old/new pmu_processing_top into separate GHDL libraries,
# then run tb_pmu_comparison for all 6 test datasets.
#
# Usage:
#   cd "c37 compliance/comparison"
#   bash scripts/run_comparison_ghdl.sh
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
WORK_DIR="$COMP_DIR/ghdl_work"

# GHDL flags
GHDL_FLAGS="--std=08 -fsynopsys"

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
    taylor_window_rom.vhd
    taylor_dft_calculator.vhd
    taylor_frequency_estimator.vhd
    pmu_processing_top.vhd
)

# Test datasets (basename, no extension for display)
DATASETS=(
    test_50hz_pure
    test_49_5hz_offbin
    test_50hz_harmonics
    test_freq_step
    single_real
    medhavi_ch1_real
)

echo "============================================================"
echo "  PMU Comparison: GHDL Flow"
echo "============================================================"
echo "  Source (old): $SRC_OLD"
echo "  Source (new): $SRC_NEW"
echo "  Datasets:    $DATASET_DIR"
echo "  Results:     $RESULT_DIR"
echo ""

# ---------------------------------------------------------------
# Step 1: Clean and create work directories
# ---------------------------------------------------------------
echo "[1/4] Creating work directories..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/old_lib" "$WORK_DIR/new_lib" "$WORK_DIR/work"
mkdir -p "$RESULT_DIR"

# ---------------------------------------------------------------
# Step 2: Compile source files into old_lib and new_lib
# ---------------------------------------------------------------
echo "[2/4] Compiling old sources into old_lib..."
for f in "${COMPILE_FILES[@]}"; do
    if [ -f "$SRC_OLD/$f" ]; then
        echo "  Compiling: $f"
        ghdl -a $GHDL_FLAGS --work=old_lib --workdir="$WORK_DIR/old_lib" "$SRC_OLD/$f"
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
        ghdl -a $GHDL_FLAGS --work=new_lib --workdir="$WORK_DIR/new_lib" "$SRC_NEW/$f"
    else
        echo "  WARNING: $SRC_NEW/$f not found, skipping"
    fi
done
echo "  new_lib compilation complete."
echo ""

# ---------------------------------------------------------------
# Step 3: Compile testbench into work library
# ---------------------------------------------------------------
echo "[3/4] Compiling testbench..."
ghdl -a $GHDL_FLAGS --work=work --workdir="$WORK_DIR/work" \
    -P"$WORK_DIR/old_lib" -P"$WORK_DIR/new_lib" \
    "$TB_DIR/tb_pmu_comparison.vhd"

echo "  Elaborating testbench..."
ghdl -e $GHDL_FLAGS --work=work --workdir="$WORK_DIR/work" \
    -P"$WORK_DIR/old_lib" -P"$WORK_DIR/new_lib" \
    tb_pmu_comparison
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
    OUTPUT_FILE="$RESULT_DIR/${ds}_comparison.csv"

    if [ ! -f "$INPUT_FILE" ]; then
        echo "  SKIP: $INPUT_FILE not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    echo "  ---- Dataset: ${ds} ----"
    echo "    Input:  $INPUT_FILE"
    echo "    Output: $OUTPUT_FILE"

    # Create symlinks for the testbench generics default paths
    ln -sf "$INPUT_FILE" "$COMP_DIR/input_samples.txt"

    # Run simulation from the comparison directory
    cd "$COMP_DIR"
    if ghdl -r $GHDL_FLAGS --work=work --workdir="$WORK_DIR/work" \
        -P"$WORK_DIR/old_lib" -P"$WORK_DIR/new_lib" \
        tb_pmu_comparison \
        -gINPUT_FILE="input_samples.txt" \
        -gOUTPUT_FILE="comparison_output.csv" \
        --stop-time=500ms 2>&1 | tee "$RESULT_DIR/${ds}_ghdl.log"; then

        # Move output CSV
        if [ -f "$COMP_DIR/comparison_output.csv" ]; then
            mv "$COMP_DIR/comparison_output.csv" "$OUTPUT_FILE"
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
    rm -f "$COMP_DIR/input_samples.txt"
    echo ""
done

echo "============================================================"
echo "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "  Output directory: $RESULT_DIR"
echo "============================================================"
