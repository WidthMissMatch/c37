#!/bin/bash
# Quick Vivado xsim test - 8 cycles (2400 samples)

set -e

echo "=========================================="
echo "Vivado xsim Quick Test (8 cycles)"
echo "=========================================="
echo ""

PROJECT_DIR="/home/arunupscee/Desktop/xtortion/c37 compliance"
cd "$PROJECT_DIR"

# Clean
rm -rf xsim.dir .Xil *.jou *.log *.pb webtalk* xvhdl.log xelab.log xsim*.log 2>/dev/null

# Create quick test constants
cat > test_constants.txt << EOF
SAMPLE_COUNT=2400
CSV_FILE=medhavi_small.csv
STOP_TIME=200ms
EOF

echo "Step 1: Compiling VHDL files with xvhdl..."

xvhdl --work work sine.vhd
xvhdl --work work cos.vhd
xvhdl --work work circular_buffer.vhd
xvhdl --work work sample_counter.vhd
xvhdl --work work cycle_tracker.vhd
xvhdl --work work position_calc.vhd
xvhdl --work work Sample_fetcher.vhd
xvhdl --work work interpolation_engine.vhd
xvhdl --work work resampler_top.vhd
xvhdl --work work dft_sample_buffer.vhd
xvhdl --work work dft.vhd
xvhdl --work work cordic_calculator_256.vhd
xvhdl --work work frequency_rocof_calculator_256.vhd
xvhdl --work work pmu_processing_top.vhd
xvhdl --work work packet_validator.vhd
xvhdl --work work c37118_packet_formatter_6ch.vhd
xvhdl --work work axi_packet_receiver_128bit.vhd
xvhdl --work work channel_extractor.vhd
xvhdl --work work input_interface_complete.vhd
xvhdl --work work pmu_6ch_processing_256.vhd
xvhdl --work work pmu_system_complete_256.vhd
xvhdl --work work pmu_system_complete_256_tb.vhd

echo "✓ Compilation complete"
echo ""

echo "Step 2: Elaborating with xelab..."
xelab -debug typical work.pmu_system_complete_256_tb -s pmu_tb_sim

echo "✓ Elaboration complete"
echo ""

echo "Step 3: Running simulation..."
echo "This will take 1-2 minutes..."
echo ""

START_TIME=$(date +%s)

xsim pmu_tb_sim -runall -onfinish quit 2>&1 | tee xsim_quick.log

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "QUICK TEST COMPLETE"
echo "=========================================="
echo "Simulation time: ${ELAPSED}s"
echo ""

# Check for output
if grep -q "CSV WRITING COMPLETE" xsim_quick.log; then
    echo "✓✓✓ SUCCESS - CSV file generated!"

    if [ -f "testbench_results_100k.csv" ]; then
        LINES=$(wc -l < testbench_results_100k.csv)
        echo "CSV has $LINES lines"

        if [ $LINES -gt 5 ]; then
            echo ""
            echo "First 5 data rows:"
            head -6 testbench_results_100k.csv | tail -5
            echo "..."
            echo ""
            echo "✓ System is working correctly!"
            exit 0
        fi
    fi
else
    echo "✗ No CSV output detected"
    echo ""
    echo "Last 30 lines of log:"
    tail -30 xsim_quick.log
    exit 1
fi
