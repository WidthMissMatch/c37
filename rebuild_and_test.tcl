# Clean rebuild and test script for Vivado
# Run this from Vivado TCL console

puts "========================================="
puts "Clean Rebuild and Test"
puts "========================================="

# Recompile all modified source files
puts "\nRecompiling modified VHDL files..."
xvhdl vhdl_modules/pmu_processing_top.vhd
xvhdl vhdl_modules/circular_buffer.vhd
xvhdl vhdl_modules/dft_sample_buffer.vhd
xvhdl vhdl_modules/resampler_top.vhd
xvhdl vhdl_modules/cycle_tracker.vhd
xvhdl vhdl_modules/channel_extractor.vhd
xvhdl testbenches/tb_pmu_simple_1cycle.vhd

puts "\nRe-elaborating design..."
xelab -debug typical -top tb_pmu_simple_1cycle -snapshot tb_pmu_simple_1cycle_behav work.tb_pmu_simple_1cycle

puts "\nLaunching simulation..."
xsim tb_pmu_simple_1cycle_behav -gui

puts "\n========================================="
puts "Simulation loaded in GUI"
puts "Click 'Run All' or 'Run for 100ms'"
puts "========================================="
