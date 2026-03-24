#!/bin/bash
# PMU Testbench - Xilinx xsim Simulation Runner
# Uses Vivado xsim simulator

echo "========================================"
echo "PMU Processing Top - xsim Simulation"
echo "========================================"

# Navigate to parent directory
cd ..

# Check for single.txt
if [ ! -f "single.txt" ]; then
    echo "ERROR: single.txt not found!"
    echo "Please ensure single.txt is in the current directory"
    exit 1
fi

echo "✓ Found test data: single.txt"
echo ""

# Clean previous simulation
echo "Cleaning previous simulation..."
rm -rf xsim.dir .Xil *.pb *.wdb *.jou *.log 2>/dev/null

# Compile all VHDL files (VHDL-93 mode)
echo "========================================"
echo "Compiling VHDL files..."
echo "========================================"

echo "[1/15] circular_buffer.vhd"
xvhdl --2008 circular_buffer.vhd || exit 1

echo "[2/15] sample_counter.vhd"
xvhdl --2008 sample_counter.vhd || exit 1

echo "[3/15] cycle_tracker.vhd"
xvhdl --2008 cycle_tracker.vhd || exit 1

echo "[4/15] position_calc.vhd"
xvhdl --2008 position_calc.vhd || exit 1

echo "[5/15] Sample_fetcher.vhd"
xvhdl --2008 Sample_fetcher.vhd || exit 1

echo "[6/15] interpolation_engine.vhd"
xvhdl --2008 interpolation_engine.vhd || exit 1

echo "[7/15] cos.vhd"
xvhdl --2008 cos.vhd || exit 1

echo "[8/15] sine.vhd"
xvhdl --2008 sine.vhd || exit 1

echo "[9/15] dft_sample_buffer.vhd"
xvhdl --2008 dft_sample_buffer.vhd || exit 1

echo "[10/15] dft.vhd"
xvhdl --2008 dft.vhd || exit 1

echo "[11/15] cordic_calculator_256.vhd"
xvhdl --2008 cordic_calculator_256.vhd || exit 1

echo "[12/15] frequency_rocof_calculator_256.vhd"
xvhdl --2008 frequency_rocof_calculator_256.vhd || exit 1

echo "[13/15] resampler_top.vhd"
xvhdl --2008 resampler_top.vhd || exit 1

echo "[14/15] pmu_processing_top.vhd"
xvhdl --2008 pmu_processing_top.vhd || exit 1

echo "[15/15] pmu_processing_top_tb.vhd"
xvhdl --2008 pmu_processing_top_tb.vhd || exit 1

# Elaborate design
echo ""
echo "========================================"
echo "Elaborating design..."
echo "========================================"
xelab -debug all work.pmu_processing_top_tb -s pmu_sim || exit 1

# Run simulation
echo ""
echo "========================================"
echo "Running simulation (300ms)..."
echo "========================================"
echo "This may take several minutes..."
echo ""

xsim pmu_sim -runall

echo ""
echo "========================================"
echo "Simulation Complete!"
echo "========================================"
echo "Check the output above for:"
echo "  - Phasor outputs (14 expected)"
echo "  - Frequency outputs (13 expected)"
echo "  - ROCOF outputs (12 expected)"
echo "  - Phase rotation analysis (should be STABLE)"
echo "  - Pass/Fail status"
echo "========================================"
