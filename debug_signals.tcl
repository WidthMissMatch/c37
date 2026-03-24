# Debug script to check if data is flowing through the pipeline
# Correct hierarchy: dut/pmu_processing_inst/ch1_master_inst/...

puts "========================================="
puts "PMU Pipeline Debug - Checking Internal Signals"
puts "========================================="

# Run for initial reset and sample injection (25ms)
run 25ms

puts "\n=== After 25ms (samples should be injected) ==="
puts "Sample injection:"
puts "  s_axis_tvalid  = [get_value /tb_pmu_simple_1cycle/s_axis_tvalid]"
puts "  s_axis_tready  = [get_value /tb_pmu_simple_1cycle/s_axis_tready]"
puts "  sample_count   = [get_value /tb_pmu_simple_1cycle/sample_count]"

# Check input interface (128-bit data splitting)
puts "\nInput Interface (128-bit to 6 channels):"
set inp_valid [get_value /tb_pmu_simple_1cycle/dut/input_interface_inst/input_valid]
set ch1_sample [get_value /tb_pmu_simple_1cycle/dut/input_interface_inst/ch1_sample]
puts "  input_valid    = $inp_valid"
puts "  ch1_sample     = $ch1_sample"

# Check circular buffer
puts "\nCircular Buffer (channel 1):"
set buf_count [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/circular_buffer_inst/sample_count]
set buf_wptr [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/circular_buffer_inst/write_ptr]
puts "  sample_count   = $buf_count"
puts "  write_ptr      = $buf_wptr"

# Check frequency feedback
puts "\nFrequency Feedback (init should be held high):"
set freq_valid [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/freq_feedback_valid]
set freq_count [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/freq_measurement_count]
set freq_value [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/freq_feedback]
puts "  freq_feedback_valid = $freq_valid"
puts "  freq_measurement_count = $freq_count"
puts "  freq_feedback (hex) = $freq_value"

# Check cycle tracker state
puts "\nCycle Tracker:"
set cycle_state [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/cycle_tracker_inst/current_state]
set cycle_complete [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/cycle_tracker_inst/cycle_complete]
puts "  current_state  = $cycle_state"
puts "  cycle_complete = $cycle_complete"

# Check DFT buffer
puts "\nDFT Buffer:"
set dft_buf_full [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/dft_buffer_inst/buffer_full]
puts "  buffer_full    = $dft_buf_full"

# Check output
puts "\nOutput Interface:"
set m_tvalid [get_value /tb_pmu_simple_1cycle/m_axis_tvalid]
set pkt_count [get_value /tb_pmu_simple_1cycle/packet_count]
puts "  m_axis_tvalid  = $m_tvalid"
puts "  packet_count   = $pkt_count"

puts "\n========================================="
puts "Running additional 75ms to check for output..."
puts "========================================="

# Run for another 75ms (total 100ms)
run 75ms

puts "\n=== After 100ms total ==="

# Re-check key signals
set buf_count [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/circular_buffer_inst/sample_count]
set freq_valid [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/freq_feedback_valid]
set cycle_state [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/resampler_inst/cycle_tracker_inst/current_state]
set dft_buf_full [get_value /tb_pmu_simple_1cycle/dut/pmu_processing_inst/ch1_master_inst/dft_buffer_inst/buffer_full]
set m_tvalid [get_value /tb_pmu_simple_1cycle/m_axis_tvalid]
set pkt_count [get_value /tb_pmu_simple_1cycle/packet_count]

puts "Pipeline Status:"
puts "  Buffer count: $buf_count (should be ~300+)"
puts "  Freq valid: $freq_valid (should be 1 during init)"
puts "  Cycle state: $cycle_state (should be TRACKING=1)"
puts "  DFT buffer full: $dft_buf_full (should be 1)"
puts "  m_axis_tvalid: $m_tvalid"
puts "  Packet count: $pkt_count"

if {$pkt_count > 0} {
    puts "\n*** SUCCESS: Packets generated! ***"
} else {
    puts "\n*** WARNING: No packets yet ***"
    puts "Problem in pipeline - check which stage is stuck"
}

puts "========================================="
quit
