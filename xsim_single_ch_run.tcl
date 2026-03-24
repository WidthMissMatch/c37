puts "Starting single-channel PMU processing top simulation..."
puts "  - TEST A: Pipeline activity checks"
puts "  - TEST B: Phasor output verification"
puts "  - TEST C: Frequency output verification"
puts "  - TEST D: Hann window confirmation"
puts "  - TEST E: Freq damping confirmation"
puts ""

# Run simulation (testbench self-terminates via assert failure at 150 ms)
run 200 ms

puts ""
puts "Simulation complete!"
quit
