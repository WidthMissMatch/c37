# Vivado Interactive Testing Script
# Purpose: Run simulation and print hex output in Vivado TCL console

# Open the project
open_project "c37 compliance/c37 compliance.xpr"

# Set simulation top
set_property top tb_packet_flow_validation [get_filesets sim_1]

puts ""
puts "========================================================================"
puts "VIVADO INTERACTIVE TESTBENCH EXECUTION"
puts "========================================================================"
puts ""

# Try to launch simulation
if {[catch {launch_simulation -mode behavioral} sim_result]} {
    puts "Simulation launch result: $sim_result"
} else {
    puts "Simulation launched successfully"
}

# After simulation, you can examine signals in the waveform viewer
# and use TCL commands in the console to:
# 1. Read signal values
# 2. Convert to hex format  
# 3. Print formatted output

puts ""
puts "========================================================================"
puts "MANUAL TESTING INSTRUCTIONS"
puts "========================================================================"
puts ""
puts "1. In Vivado GUI, open Simulation window"
puts "2. Use TCL console to query signals:"
puts ""
puts "   # Example TCL commands:"
puts "   get_objects -filter {name =~ */clk}"
puts "   get_objects -filter {name =~ */s_axis_tdata}"
puts "   get_value /tb_packet_flow_validation/m_axis_tdata"
puts ""
puts "3. To print in hex format:"
puts "   format 0x%X [get_value /tb_packet_flow_validation/captured_packet(0)]"
puts ""
puts "4. To see all output words:"
puts "   for {set i 0} {$i < 19} {incr i} {"
puts "     puts [format \"Word %2d: 0x%08X\" $i [get_value /tb_packet_flow_validation/captured_packet($i)]]"
puts "   }"
puts ""

