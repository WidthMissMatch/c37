# Test full pipeline - run until first packet or timeout
puts "========================================="
puts "Full Pipeline Test - 305 Samples"
puts "========================================="

# Run for 40ms (enough for cycle + DFT + processing)
puts "Running simulation for 40ms..."
run 40ms

puts "\n========================================="
puts "Simulation reached 40ms"
puts "========================================="

quit
