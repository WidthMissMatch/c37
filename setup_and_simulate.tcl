#!/usr/bin/tclsh
puts "=============================================================================="
puts "  SETTING UP TESTBENCH FOR SIMULATION"
puts "=============================================================================="
puts ""

# Open project (we're now in the project directory)
set project_file "c37 compliance.xpr"
puts "Opening: $project_file"

if {[catch {open_project $project_file} err]} {
    puts "ERROR: $err"
    exit 1
}

puts "✓ Project opened"
puts ""

# Get simulation fileset
set sim_fileset [get_filesets sim_1]
puts "Simulation fileset: $sim_fileset"

# List current files
set files [get_files -of_objects [get_filesets sim_1]]
puts "Current files in sim_1 fileset:"
foreach f $files {
    puts "  - [file tail $f]"
}

puts ""
puts "Setting top module to: tb_packet_flow_validation"
catch {set_property top tb_packet_flow_validation [get_filesets sim_1]}

# Verify
set top_module [get_property top [get_filesets sim_1]]
puts "Simulation top module set to: $top_module"

puts ""
puts "Saving project..."
catch {save_project_as -force -overwrite "c37 compliance.xpr"}

puts ""
puts "=============================================================================="
puts "✓ SETUP COMPLETE"
puts "=============================================================================="
puts ""
puts "Next steps:"
puts "1. Open Vivado GUI:  vivado c37\ compliance.xpr &"
puts "2. Click: Simulation → Run Simulation"
puts "3. Or run: vivado -mode batch -source testbench_run.tcl"
puts ""

close_project
exit 0
