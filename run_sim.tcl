# Run simulation with extended timeout
# This script runs the testbench for sufficient time to capture output

# Run for 150ms to capture first output (should appear around 40-60ms)
puts "Starting simulation run for 150ms..."
run 150ms

puts "========================================"
puts "Simulation completed at [current_time]"
puts "========================================"

# Exit
quit
