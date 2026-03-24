# PMU Processing Top - Compilation Script
# Compiles all VHDL files in correct dependency order
# Compatible with ModelSim/QuestaSim and Vivado Simulator
#
# Usage (ModelSim):  do compile_all.tcl
# Usage (Vivado):    source compile_all.tcl

puts "========================================"
puts "Compiling PMU Processing Top Design"
puts "========================================"

# Set parent directory (one level up from sim_scripts)
set parent_dir ".."

# VHDL-93 compilation flag
set vhdl_std "-93"

puts "\n[1/15] Compiling circular_buffer.vhd..."
vcom $vhdl_std -work work $parent_dir/circular_buffer.vhd

puts "\n[2/15] Compiling sample_counter.vhd..."
vcom $vhdl_std -work work $parent_dir/sample_counter.vhd

puts "\n[3/15] Compiling cycle_tracker.vhd..."
vcom $vhdl_std -work work $parent_dir/cycle_tracker.vhd

puts "\n[4/15] Compiling position_calc.vhd..."
vcom $vhdl_std -work work $parent_dir/position_calc.vhd

puts "\n[5/15] Compiling Sample_fetcher.vhd..."
vcom $vhdl_std -work work $parent_dir/Sample_fetcher.vhd

puts "\n[6/15] Compiling interpolation_engine.vhd..."
vcom $vhdl_std -work work $parent_dir/interpolation_engine.vhd

puts "\n[7/15] Compiling cos.vhd..."
vcom $vhdl_std -work work $parent_dir/cos.vhd

puts "\n[8/15] Compiling sine.vhd..."
vcom $vhdl_std -work work $parent_dir/sine.vhd

puts "\n[9/15] Compiling dft_sample_buffer.vhd..."
vcom $vhdl_std -work work $parent_dir/dft_sample_buffer.vhd

puts "\n[10/15] Compiling dft.vhd..."
vcom $vhdl_std -work work $parent_dir/dft.vhd

puts "\n[11/15] Compiling cordic_calculator_256.vhd..."
vcom $vhdl_std -work work $parent_dir/cordic_calculator_256.vhd

puts "\n[12/15] Compiling frequency_rocof_calculator_256.vhd..."
vcom $vhdl_std -work work $parent_dir/frequency_rocof_calculator_256.vhd

puts "\n[13/15] Compiling resampler_top.vhd..."
vcom $vhdl_std -work work $parent_dir/resampler_top.vhd

puts "\n[14/15] Compiling pmu_processing_top.vhd..."
vcom $vhdl_std -work work $parent_dir/pmu_processing_top.vhd

puts "\n[15/15] Compiling pmu_processing_top_tb.vhd..."
vcom $vhdl_std -work work $parent_dir/pmu_processing_top_tb.vhd

puts "\n========================================"
puts "Compilation Complete!"
puts "========================================"
puts "Ready to simulate: vsim work.pmu_processing_top_tb"
puts "========================================"
