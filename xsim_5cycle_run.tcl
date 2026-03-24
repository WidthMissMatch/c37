puts "Starting 5-cycle PMU simulation..."
puts "  - TEST 1: Full system (1500 input packets -> C37.118 output)"
puts "  - TEST 2: Hann window standalone (256 samples)"
puts "  - TEST 3: Freq damping filter standalone (step response)"
puts ""

# Run simulation (testbench self-terminates via assert failure at 200 ms)
run 250 ms

puts ""
puts "Simulation complete!"
quit
