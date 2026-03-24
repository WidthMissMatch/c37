#!/usr/bin/tclsh
# ============================================================================
# 6-Channel PMU System - Vivado xsim Simulation Script
# ============================================================================
#
# This script compiles and simulates using Vivado's xsim simulator
#
# Usage:
#   vivado -mode batch -source sim_scripts/run_xsim_6ch.tcl
#   OR
#   xvhdl + xelab + xsim (see run_xsim_6ch.sh)
#
# Author: Arun's PMU Project
# Date: December 2024
# ============================================================================

puts "======================================"
puts "6-Channel PMU System - Vivado xsim"
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
    exit 1
}

puts "  medhavi.csv: OK"
puts ""

# ============================================================================
# Compilation
# ============================================================================

puts "Compiling VHDL source files with xvhdl..."
puts "--------------------------------------"

# Define compilation order
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

    # Compile with xvhdl (VHDL-93 standard, work library)
    if {[catch {exec xvhdl -work work $file} result]} {
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
# Elaboration
# ============================================================================

puts "Elaborating design..."

if {[catch {exec xelab -debug typical work.pmu_system_complete_256_tb -s pmu_tb_sim} result]} {
    puts "ERROR: Elaboration failed!"
    puts $result
    exit 1
}

puts "  Elaboration complete"
puts ""

# ============================================================================
# Simulation
# ============================================================================

puts "======================================"
puts "Starting simulation..."
puts "======================================"
puts ""
puts "Running 8-second simulation..."
puts "This will take 30-60 minutes..."
puts ""

# Create xsim TCL commands file
set sim_tcl [open "xsim_commands.tcl" w]
puts $sim_tcl "# xsim simulation commands"
puts $sim_tcl "log_wave -recursive *"
puts $sim_tcl "run 8 sec"
puts $sim_tcl "quit"
close $sim_tcl

# Run simulation
if {[catch {exec xsim pmu_tb_sim -tclbatch xsim_commands.tcl} result]} {
    puts "Simulation output:"
    puts $result
} else {
    puts $result
}

puts ""
puts "======================================"
puts "Simulation Complete"
puts "======================================"
puts ""

# Check outputs
if {[file exists "testbench_results_100k.csv"]} {
    puts "✓ testbench_results_100k.csv created"

    # Count lines
    set f [open "testbench_results_100k.csv" r]
    set line_count 0
    while {[gets $f line] >= 0} {
        incr line_count
    }
    close $f
    set data_lines [expr {$line_count - 1}]
    puts "  CSV contains $data_lines data rows"
} else {
    puts "✗ testbench_results_100k.csv NOT created"
}

puts ""
puts "Next steps:"
puts "  1. Review testbench_results_100k.csv"
puts "  2. Run validation: python3 validate_6ch_pmu.py --validate"
puts ""
