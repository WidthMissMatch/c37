#!/usr/bin/tclsh
# ============================================================================
# 6-Channel PMU System Complete Testbench - TCL Simulation Script
# ============================================================================
#
# This script compiles and simulates the complete 6-channel PMU system
# with testbench that reads 100,000 samples from medhavi.csv
#
# Usage (ModelSim/Questa):
#   vsim -c -do "run_6ch_testbench.tcl; quit"
#   OR
#   vsim -do run_6ch_testbench.tcl
#
# Author: Arun's PMU Project
# Date: December 2024
# ============================================================================

puts "======================================"
puts "6-Channel PMU System Testbench"
puts "Complete System Integration Test"
puts "======================================"
puts ""

# Change to project directory
cd ..

# ============================================================================
# Pre-Flight Checks
# ============================================================================

puts "Checking prerequisites..."

if {![file exists "medhavi.csv"]} {
    puts "ERROR: medhavi.csv not found!"
    puts "Please ensure medhavi.csv is in the project root directory."
    exit 1
}

if {![file exists "pmu_system_complete_256_tb.vhd"]} {
    puts "ERROR: pmu_system_complete_256_tb.vhd not found!"
    exit 1
}

puts "  medhavi.csv: OK"
puts "  Testbench file: OK"
puts ""

# ============================================================================
# Library Setup
# ============================================================================

puts "Setting up work library..."

# Delete old work library if it exists
if {[file exists "work"]} {
    vdel -all
}

# Create fresh work library
vlib work
vmap work work

puts "  Work library created"
puts ""

# ============================================================================
# VHDL Compilation
# ============================================================================

puts "Compiling VHDL source files..."
puts "--------------------------------------"

# Define compilation order (respecting dependencies)
set vhdl_files [list \
    "sine.vhd" \
    "cos.vhd" \
    "circular_buffer.vhd" \
    "sample_counter.vhd" \
    "cycle_tracker.vhd" \
    "position_calc.vhd" \
    "Sample_fetcher.vhd" \
    "interpolation_engine.vhd" \
    "resampler_top.vhd" \
    "dft_sample_buffer.vhd" \
    "dft.vhd" \
    "cordic_calculator_256.vhd" \
    "frequency_rocof_calculator_256.vhd" \
    "pmu_processing_top.vhd" \
    "axi_packet_receiver_128bit.vhd" \
    "input_interface_complete.vhd" \
    "pmu_6ch_processing_256.vhd" \
    "pmu_system_complete_256.vhd" \
    "pmu_system_complete_256_tb.vhd" \
]

set compile_errors 0

foreach file $vhdl_files {
    if {![file exists $file]} {
        puts "  ERROR: File not found: $file"
        incr compile_errors
        continue
    }

    puts -nonewline "  Compiling $file... "
    flush stdout

    # Compile with VHDL-93 standard
    if {[catch {vcom -93 -work work $file} result]} {
        puts "FAILED"
        puts "    Error: $result"
        incr compile_errors
    } else {
        puts "OK"
    }
}

puts "--------------------------------------"

if {$compile_errors > 0} {
    puts "ERROR: Compilation failed with $compile_errors errors"
    exit 1
}

puts "All files compiled successfully!"
puts ""

# ============================================================================
# Simulation Setup
# ============================================================================

puts "Loading simulation..."

# Load testbench
vsim -t 1ps -voptargs="+acc" work.pmu_system_complete_256_tb

puts "  Testbench loaded"
puts ""

# ============================================================================
# Waveform Configuration
# ============================================================================

puts "Configuring waveforms..."

# Clock and Reset
add wave -divider "Clock and Reset"
add wave -label "clk" /pmu_system_complete_256_tb/clk
add wave -label "rst" /pmu_system_complete_256_tb/rst
add wave -label "enable" /pmu_system_complete_256_tb/enable

# Control Flags
add wave -divider "Control Flags"
add wave -label "csv_loaded" /pmu_system_complete_256_tb/csv_loaded
add wave -label "stimulus_complete" /pmu_system_complete_256_tb/stimulus_complete

# AXI-Stream Input Interface
add wave -divider "AXI-Stream Input (128-bit)"
add wave -label "s_axis_tdata" -radix hex /pmu_system_complete_256_tb/s_axis_tdata
add wave -label "s_axis_tvalid" /pmu_system_complete_256_tb/s_axis_tvalid
add wave -label "s_axis_tready" /pmu_system_complete_256_tb/s_axis_tready
add wave -label "s_axis_tlast" /pmu_system_complete_256_tb/s_axis_tlast

# AXI-Stream Output Interface
add wave -divider "AXI-Stream Output (32-bit)"
add wave -label "m_axis_tdata" -radix hex /pmu_system_complete_256_tb/m_axis_tdata
add wave -label "m_axis_tvalid" /pmu_system_complete_256_tb/m_axis_tvalid
add wave -label "m_axis_tready" /pmu_system_complete_256_tb/m_axis_tready
add wave -label "m_axis_tlast" /pmu_system_complete_256_tb/m_axis_tlast

# System Status
add wave -divider "System Status"
add wave -label "sync_locked" /pmu_system_complete_256_tb/sync_locked
add wave -label "system_ready" /pmu_system_complete_256_tb/system_ready
add wave -label "processing_active" /pmu_system_complete_256_tb/processing_active

# Result Counters
add wave -divider "Result Counters"
add wave -label "result_count" -radix unsigned /pmu_system_complete_256_tb/result_count
add wave -label "input_packets_good" -radix unsigned /pmu_system_complete_256_tb/input_packets_good
add wave -label "input_packets_bad" -radix unsigned /pmu_system_complete_256_tb/input_packets_bad
add wave -label "output_packets" -radix unsigned /pmu_system_complete_256_tb/output_packets

# Frequency and ROCOF Outputs
add wave -divider "Frequency/ROCOF"
add wave -label "frequency_out" -radix hex /pmu_system_complete_256_tb/frequency_out
add wave -label "freq_valid" /pmu_system_complete_256_tb/freq_valid
add wave -label "rocof_out" -radix hex /pmu_system_complete_256_tb/rocof_out
add wave -label "rocof_valid" /pmu_system_complete_256_tb/rocof_valid

# Debug Signals
add wave -divider "Debug"
add wave -label "channels_extracted" -radix unsigned /pmu_system_complete_256_tb/channels_extracted
add wave -label "dft_busy" /pmu_system_complete_256_tb/dft_busy
add wave -label "cordic_busy" /pmu_system_complete_256_tb/cordic_busy

puts "  Waveforms configured"
puts ""

# ============================================================================
# Simulation Execution
# ============================================================================

puts "======================================"
puts "Starting simulation..."
puts "======================================"
puts ""
puts "Timeline:"
puts "  0-200 ns: System reset"
puts "  200-300 ns: Reset release"
puts "  300 ns: Enable assertion"
puts "  400 ns - 6.67 s: Input stimulus (100K packets @ 15 kHz)"
puts "  20 ms - 6.69 s: Output packets (~335 cycles @ 50 Hz)"
puts "  6.69-8.0 s: Final processing and statistics"
puts ""
puts "Expected outputs:"
puts "  - 335 IEEE C37.118 packets (one per power cycle)"
puts "  - Each packet: 6 phasors + frequency + ROCOF"
puts "  - Console: Real-time validation reports"
puts "  - CSV: testbench_results_100k.csv"
puts ""
puts "This will take several minutes..."
puts "--------------------------------------"

# Configure transcript output
transcript file simulation_transcript.log

# Run simulation for 8 seconds
run 8 sec

puts ""
puts "--------------------------------------"
puts "Simulation completed!"
puts ""

# ============================================================================
# Post-Simulation Summary
# ============================================================================

puts "======================================"
puts "Simulation Summary"
puts "======================================"

# Check if CSV file was created
if {[file exists "testbench_results_100k.csv"]} {
    puts "  ✓ testbench_results_100k.csv created"

    # Count lines in CSV
    set f [open "testbench_results_100k.csv" r]
    set line_count 0
    while {[gets $f line] >= 0} {
        incr line_count
    }
    close $f
    set data_lines [expr {$line_count - 1}]
    puts "    CSV contains $data_lines data rows"
} else {
    puts "  ✗ testbench_results_100k.csv NOT created"
}

# Extract final statistics from simulation signals
puts ""
puts "Signal Values at End:"
puts "  result_count: [examine -radix unsigned /pmu_system_complete_256_tb/result_count]"
puts "  input_packets_good: [examine -radix unsigned /pmu_system_complete_256_tb/input_packets_good]"
puts "  input_packets_bad: [examine -radix unsigned /pmu_system_complete_256_tb/input_packets_bad]"
puts "  output_packets: [examine -radix unsigned /pmu_system_complete_256_tb/output_packets]"

puts ""
puts "======================================"
puts "Next Steps:"
puts "======================================"
puts "1. Review console output for validation results"
puts "2. Check testbench_results_100k.csv"
puts "3. Run validation:"
puts "   python3 validate_6ch_pmu.py --validate"
puts "4. Analyze waveforms in GUI if needed"
puts ""
puts "To view waveforms:"
puts "  - Waveforms have been added automatically"
puts "  - Use zoom/cursor controls to inspect signals"
puts "  - Check AXI handshaking and packet integrity"
puts ""
puts "======================================"

# Save waveform configuration
do wave.do

puts ""
puts "Simulation script complete!"
puts ""
