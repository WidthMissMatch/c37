#!/bin/bash
################################################################################
# Compile script for self-contained PMU 5-cycle test (Fixed for xil_defaultlib)
################################################################################

set -e  # Exit on error

echo "========================================"
echo "Compiling PMU Self-Contained Test"
echo "========================================"

cd "/home/arunupscee/Desktop/xtortion/c37 compliance"

# Compile all core PMU modules (in dependency order) into xil_defaultlib
echo "[1/26] Compiling circular_buffer.vhd..."
xvhdl vhdl_modules/circular_buffer.vhd

echo "[2/26] Compiling sample_counter.vhd..."
xvhdl vhdl_modules/sample_counter.vhd

echo "[3/26] Compiling cycle_tracker.vhd..."
xvhdl vhdl_modules/cycle_tracker.vhd

echo "[4/26] Compiling position_calc.vhd..."
xvhdl vhdl_modules/position_calc.vhd

echo "[5/26] Compiling Sample_fetcher.vhd..."
xvhdl vhdl_modules/Sample_fetcher.vhd

echo "[6/26] Compiling interpolation_engine.vhd..."
xvhdl vhdl_modules/interpolation_engine.vhd

echo "[7/26] Compiling resampler_top.vhd..."
xvhdl vhdl_modules/resampler_top.vhd

echo "[8/26] Compiling dft_sample_buffer.vhd..."
xvhdl vhdl_modules/dft_sample_buffer.vhd

echo "[9/26] Compiling sine.vhd..."
xvhdl vhdl_modules/sine.vhd

echo "[10/26] Compiling cos.vhd..."
xvhdl vhdl_modules/cos.vhd

echo "[11/26] Compiling dft.vhd..."
xvhdl vhdl_modules/dft.vhd

echo "[12/26] Compiling cordic_calculator_256.vhd..."
xvhdl vhdl_modules/cordic_calculator_256.vhd

echo "[13/26] Compiling frequency_rocof_calculator_256.vhd..."
xvhdl vhdl_modules/frequency_rocof_calculator_256.vhd

echo "[14/26] Compiling pmu_processing_top.vhd..."
xvhdl vhdl_modules/pmu_processing_top.vhd

echo "[15/26] Compiling pmu_processing_top_no_freq.vhd..."
xvhdl vhdl_modules/pmu_processing_top_no_freq.vhd

echo "[16/26] Compiling tve_calculator.vhd..."
xvhdl vhdl_modules/tve_calculator.vhd

echo "[17/26] Compiling crc_ccitt_c37118.vhd..."
xvhdl vhdl_modules/crc_ccitt_c37118.vhd

echo "[18/26] Compiling pmu_6ch_processing_256.vhd..."
xvhdl vhdl_modules/pmu_6ch_processing_256.vhd

echo "[19/26] Compiling c37118_packet_formatter_6ch.vhd..."
xvhdl vhdl_modules/c37118_packet_formatter_6ch.vhd

echo "[20/26] Compiling axi_packet_receiver_128bit.vhd..."
xvhdl vhdl_modules/axi_packet_receiver_128bit.vhd

echo "[21/26] Compiling channel_extractor.vhd..."
xvhdl vhdl_modules/channel_extractor.vhd

echo "[22/26] Compiling input_interface_complete.vhd..."
xvhdl vhdl_modules/input_interface_complete.vhd

echo "[23/26] Compiling pmu_system_complete_256.vhd (top-level)..."
xvhdl vhdl_modules/pmu_system_complete_256.vhd

echo ""
echo "Compiling NEW test files..."
echo "[24/25] Compiling test_data_constants_pkg.vhd..."
xvhdl testbenches/test_data_constants_pkg.vhd

echo "[25/25] Compiling tb_pmu_selfcontained_5cycles.vhd..."
xvhdl testbenches/tb_pmu_selfcontained_5cycles.vhd

echo ""
echo "========================================"
echo "Compilation Complete!"
echo "========================================"
