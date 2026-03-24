#!/bin/bash
################################################################################
# Complete automation script for PMU self-contained test
# Generates constants, compiles, elaborates, and simulates
################################################################################

set -e  # Exit on error

echo "========================================="
echo "PMU SELF-CONTAINED TEST - FULL RUN"
echo "========================================="
echo ""

cd "/home/arunupscee/Desktop/xtortion/c37 compliance"

# Step 1: Generate VHDL constants package
echo "[1/4] Generating VHDL constants from CSV..."
python3 generate_test_constants.py
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to generate constants"
    exit 1
fi
echo ""

# Step 2: Compile all VHDL files
echo "[2/4] Compiling VHDL files..."
bash compile_selfcontained_test_fixed.sh
if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed"
    exit 1
fi
echo ""

# Step 3: Elaborate design
echo "[3/4] Elaborating design..."
xelab -debug typical \
      -top tb_pmu_selfcontained_5cycles \
      -snapshot pmu_selfcontained_sim \
      xil_defaultlib.tb_pmu_selfcontained_5cycles
if [ $? -ne 0 ]; then
    echo "ERROR: Elaboration failed"
    exit 1
fi
echo ""
echo "Elaboration complete!"
echo ""

# Step 4: Run simulation
echo "[4/4] Running simulation..."
echo "This will take approximately 2-3 minutes..."
echo ""
xsim pmu_selfcontained_sim \
     -runall \
     -log simulation_hex_output.log

echo ""
echo "========================================="
echo "TEST COMPLETE!"
echo "========================================="
echo ""
echo "Results saved to: simulation_hex_output.log"
echo ""
echo "To view the hex dump:"
echo "  cat simulation_hex_output.log | grep -A 100 'HEX DUMP'"
echo ""
echo "Or view the entire log:"
echo "  less simulation_hex_output.log"
echo ""
echo "========================================="
