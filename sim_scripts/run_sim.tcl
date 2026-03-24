# PMU Processing Top - Simulation Script
# ModelSim/QuestaSim Simulation Runner
#
# Usage: do run_sim.tcl

puts "========================================"
puts "PMU Processing Top - Simulation Setup"
puts "========================================"

# Create work library if it doesn't exist
if {![file exists work]} {
    puts "Creating work library..."
    vlib work
    vmap work work
}

# Compile all files
puts "\nCompiling design files..."
do compile_all.tcl

# Check for single.txt in parent directory
set parent_dir ".."
if {![file exists "$parent_dir/single.txt"]} {
    puts "ERROR: single.txt not found in parent directory!"
    puts "Please ensure single.txt is located at: $parent_dir/single.txt"
    return
} else {
    puts "\n✓ Found test data file: single.txt"
}

# Load testbench
puts "\nLoading testbench: pmu_processing_top_tb..."
vsim -t 1ns -voptargs=+acc work.pmu_processing_top_tb

# Configure waveform display
puts "\nConfiguring waveform display..."

# Add dividers and signals
add wave -divider "Clock and Reset"
add wave -noupdate /pmu_processing_top_tb/clk
add wave -noupdate /pmu_processing_top_tb/rst
add wave -noupdate /pmu_processing_top_tb/enable

add wave -divider "ADC Input"
add wave -noupdate -radix decimal /pmu_processing_top_tb/adc_sample
add wave -noupdate /pmu_processing_top_tb/adc_valid

add wave -divider "Phasor Outputs"
add wave -noupdate -radix hex /pmu_processing_top_tb/phasor_magnitude
add wave -noupdate -radix hex /pmu_processing_top_tb/phasor_phase
add wave -noupdate /pmu_processing_top_tb/phasor_valid

add wave -divider "Frequency Outputs"
add wave -noupdate -radix hex /pmu_processing_top_tb/frequency_out
add wave -noupdate /pmu_processing_top_tb/freq_valid
add wave -noupdate -radix hex /pmu_processing_top_tb/rocof_out
add wave -noupdate /pmu_processing_top_tb/rocof_valid

add wave -divider "Status Signals"
add wave -noupdate /pmu_processing_top_tb/cycle_complete
add wave -noupdate /pmu_processing_top_tb/dft_busy
add wave -noupdate /pmu_processing_top_tb/cordic_busy
add wave -noupdate /pmu_processing_top_tb/system_ready
add wave -noupdate -radix hex /pmu_processing_top_tb/samples_per_cycle
add wave -noupdate -radix unsigned /pmu_processing_top_tb/cycle_count_sig

# Internal DUT signals (optional - uncomment if needed for debugging)
# add wave -divider "DUT Internal"
# add wave -noupdate /pmu_processing_top_tb/DUT/*

puts "\n========================================"
puts "Starting Simulation"
puts "========================================"
puts "Running for 300 ms (includes ~280 ms for 4200 samples @ 15kHz)"
puts "Monitor console output for real-time verification..."
puts "========================================"

# Run simulation
run 300ms

puts "\n========================================"
puts "Simulation Complete!"
puts "========================================"
puts "Review the console output above for:"
puts "  - Sample loading confirmation"
puts "  - Phasor outputs (14 expected)"
puts "  - Frequency outputs (13 expected)"
puts "  - ROCOF outputs (12 expected)"
puts "  - Phase rotation analysis (should be STABLE)"
puts "  - Pass/Fail status for each output"
puts "========================================"
puts "\nWaveform viewer is ready. Use 'wave zoom full' to see all signals."
puts "========================================"

# Zoom waveform to show all activity
wave zoom full
