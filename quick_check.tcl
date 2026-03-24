# Quick diagnostic - check first 30ms only
puts "========================================="
puts "Quick Pipeline Check"
puts "========================================="

# Run just 30ms (enough to inject samples + a bit more)
run 30ms

puts "\n=== Checking Key Signals at 30ms ==="

# Sample injection
set sample_count [get_value /tb_pmu_simple_1cycle/sample_count]
puts "\n1. Sample Injection:"
puts "   sample_count = $sample_count (should be 300)"

# Check if freq_feedback_valid is HIGH during init
set freq_valid [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/freq_feedback_valid]
set freq_count [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/freq_measurement_count]
puts "\n2. Frequency Feedback (THE FIX):"
puts "   freq_feedback_valid = $freq_valid (should be 1 if fix works)"
puts "   freq_measurement_count = $freq_count (should be 0 or 1)"

# Check circular buffer
set buf_count [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/circular_buffer_inst/sample_count]
puts "\n3. Circular Buffer:"
puts "   sample_count = $buf_count (should be ~300+)"

# Check cycle tracker state
set cycle_state [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/cycle_tracker_inst/current_state]
puts "\n4. Cycle Tracker:"
puts "   current_state = $cycle_state"
puts "   (0=IDLE, 1=WAIT_SPC, 2=TRACKING)"

if {$freq_valid == 1} {
    puts "\n*** FIX VERIFICATION: freq_feedback_valid is HIGH - FIX IS WORKING! ***"
} else {
    puts "\n*** WARNING: freq_feedback_valid is LOW - fix may not be working ***"
}

if {$cycle_state == 2} {
    puts "\n*** PIPELINE STATUS: Cycle tracker in TRACKING state - PIPELINE IS RUNNING! ***"
} elseif {$cycle_state == 1} {
    puts "\n*** PIPELINE STATUS: Cycle tracker stuck in WAIT_SPC - DEADLOCK STILL EXISTS ***"
} else {
    puts "\n*** PIPELINE STATUS: Cycle tracker in IDLE - WAITING TO START ***"
}

puts "\n========================================="
puts "Diagnostic complete - this is enough to verify the fix"
puts "Full packet output would take 60-80ms but deadlock check only needs 30ms"
puts "========================================="

quit
