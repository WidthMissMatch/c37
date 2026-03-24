#!/bin/bash
# ============================================================================
# 5-Cycle System Test with Hann Window + Freq Damping Integration
# ============================================================================
#
# Compiles all VHDL modules (including hann_window and freq_damping_filter),
# elaborates tb_system_5cycle_hardcoded, and runs xsim simulation.
#
# Tests:
#   1. Full system end-to-end: 1500 packets -> 76-byte C37.118 output
#   2. Standalone hann_window: 256 sine samples, verify windowing
#   3. Standalone freq_damping_filter: step response 50->51->49 Hz
#
# Usage:
#   ./run_5cycle_test.sh
#
# Author: Arun's PMU Project
# Date: February 2026
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo ""
    echo "======================================"
    echo "$1"
    echo "======================================"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP $1]${NC} $2"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_banner "5-Cycle PMU Test (Hann + Freq Damping) - Vivado xsim"

# Change to project root (c37 compliance/)
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

echo "Project directory: $PROJECT_ROOT"
echo ""

# ----------------------------------------------------------------------------
# Pre-Flight Checks
# ----------------------------------------------------------------------------

print_step "0" "Pre-flight checks"

if ! command -v xvhdl &> /dev/null; then
    print_error "xvhdl not found! Please source Vivado settings:"
    echo "  source /path/to/Vivado/2025.1/settings64.sh"
    exit 1
fi
print_success "Vivado xsim tools found"

# Verify key files exist
MISSING=0
for f in \
    "vhdl_modules/hann_window.vhd" \
    "vhdl_modules/freq_damping_filter.vhd" \
    "vhdl_modules/pmu_processing_top.vhd" \
    "vhdl_modules/pmu_processing_top_no_freq.vhd" \
    "vhdl_modules/pmu_system_complete_256.vhd" \
    "testbenches/tb_system_5cycle_hardcoded.vhd"; do
    if [ ! -f "$f" ]; then
        print_error "Missing: $f"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -gt 0 ]; then
    print_error "$MISSING required file(s) missing!"
    exit 1
fi
print_success "All required files found"
echo ""

# ----------------------------------------------------------------------------
# Step 1: Compile VHDL with xvhdl
# ----------------------------------------------------------------------------

print_step "1" "Compiling VHDL files with xvhdl"
echo ""

mkdir -p xsim.dir
mkdir -p logs

# Compilation order: leaf modules first, then composites, then testbench
# New modules (hann_window, freq_damping_filter) inserted before their consumers
VHDL_FILES=(
    # ROMs
    "vhdl_modules/sine.vhd"
    "vhdl_modules/cos.vhd"
    # Resampler chain
    "vhdl_modules/circular_buffer.vhd"
    "vhdl_modules/sample_counter.vhd"
    "vhdl_modules/cycle_tracker.vhd"
    "vhdl_modules/position_calc.vhd"
    "vhdl_modules/Sample_fetcher.vhd"
    "vhdl_modules/interpolation_engine.vhd"
    "vhdl_modules/resampler_top.vhd"
    # DFT chain
    "vhdl_modules/dft_sample_buffer.vhd"
    "vhdl_modules/dft.vhd"
    # Post-DFT processing
    "vhdl_modules/cordic_calculator_256.vhd"
    "vhdl_modules/frequency_rocof_calculator_256.vhd"
    # NEW: Window and filter modules
    "vhdl_modules/hann_window.vhd"
    "vhdl_modules/freq_damping_filter.vhd"
    # Processing top modules (now depend on hann_window + freq_damping_filter)
    "vhdl_modules/pmu_processing_top.vhd"
    "vhdl_modules/pmu_processing_top_no_freq.vhd"
    # System integration
    "vhdl_modules/axi_packet_receiver_128bit.vhd"
    "vhdl_modules/input_interface_complete.vhd"
    "vhdl_modules/channel_extractor.vhd"
    "vhdl_modules/packet_validator.vhd"
    "vhdl_modules/crc_ccitt_c37118.vhd"
    "vhdl_modules/c37118_packet_formatter_6ch.vhd"
    "vhdl_modules/pmu_6ch_processing_256.vhd"
    "vhdl_modules/pmu_system_complete_256.vhd"
    # Testbench
    "testbenches/tb_system_5cycle_hardcoded.vhd"
)

COMPILE_ERRORS=0

: > logs/xvhdl_5cycle.log  # Clear log

for file in "${VHDL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        ((COMPILE_ERRORS++))
        continue
    fi

    echo -n "  Compiling $(basename "$file")... "

    if xvhdl --work work "$file" >> logs/xvhdl_5cycle.log 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        ((COMPILE_ERRORS++))
        echo "    See logs/xvhdl_5cycle.log for details"
    fi
done

echo ""

if [ $COMPILE_ERRORS -gt 0 ]; then
    print_error "Compilation failed with $COMPILE_ERRORS error(s)"
    echo "Check logs/xvhdl_5cycle.log for details"
    tail -n 30 logs/xvhdl_5cycle.log
    exit 1
fi

print_success "All ${#VHDL_FILES[@]} files compiled successfully (0 errors)"
echo ""

# ----------------------------------------------------------------------------
# Step 2: Elaborate Design
# ----------------------------------------------------------------------------

print_step "2" "Elaborating design with xelab"
echo ""

xelab -debug typical work.tb_system_5cycle_hardcoded \
    -s tb_5cycle_sim >> logs/xelab_5cycle.log 2>&1

if [ $? -ne 0 ]; then
    print_error "Elaboration failed!"
    echo "Check logs/xelab_5cycle.log for details"
    tail -n 30 logs/xelab_5cycle.log
    exit 1
fi

print_success "Elaboration complete (0 errors)"
echo ""

# ----------------------------------------------------------------------------
# Step 3: Run Simulation
# ----------------------------------------------------------------------------

print_step "3" "Running simulation with xsim"
echo ""
echo "Running 5-cycle system test + standalone Hann/FreqDamp tests..."
echo "Timeout set to 200 ms simulation time"
echo ""

# Create simulation TCL script
cat > xsim_5cycle_run.tcl << 'EOF'
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
EOF

xsim tb_5cycle_sim -tclbatch xsim_5cycle_run.tcl > logs/xsim_5cycle.log 2>&1

SIM_EXIT_CODE=$?

# xsim returns non-zero on assert failure (which is how the testbench ends)
# So check the log for results instead of exit code

print_success "Simulation finished"
echo ""

# ----------------------------------------------------------------------------
# Step 4: Analyze Results
# ----------------------------------------------------------------------------

print_step "4" "Analyzing test results"
echo ""

LOG_FILE="logs/xsim_5cycle.log"

# Extract test results from simulation log
TEST1_RESULT="UNKNOWN"
TEST2_RESULT="UNKNOWN"
TEST3_RESULT="UNKNOWN"

if grep -q "\[TEST 1\] PASSED" "$LOG_FILE"; then
    TEST1_RESULT="PASSED"
elif grep -q "\[TEST 1\] FAILED" "$LOG_FILE"; then
    TEST1_RESULT="FAILED"
elif grep -q "\[TEST 1\]" "$LOG_FILE"; then
    TEST1_RESULT="PARTIAL"
fi

if grep -q "\[TEST 2\] PASSED" "$LOG_FILE"; then
    TEST2_RESULT="PASSED"
elif grep -q "\[TEST 2\] FAILED" "$LOG_FILE"; then
    TEST2_RESULT="FAILED"
fi

if grep -q "\[TEST 3\] PASSED" "$LOG_FILE"; then
    TEST3_RESULT="PASSED"
elif grep -q "\[TEST 3\] FAILED" "$LOG_FILE"; then
    TEST3_RESULT="FAILED"
fi

# Check for ALL TESTS PASSED
ALL_PASSED=false
if grep -q "ALL TESTS PASSED" "$LOG_FILE"; then
    ALL_PASSED=true
fi

# Print key log lines
echo "Key simulation output:"
echo "------------------------------"
grep -E "\[TEST [123]\]|\[OUTPUT\]|ALL TESTS|SOME TESTS|FINAL TEST" "$LOG_FILE" | head -30
echo "------------------------------"
echo ""

# ----------------------------------------------------------------------------
# Final Summary
# ----------------------------------------------------------------------------

print_banner "Test Results Summary"

echo "  TEST 1 - System End-to-End (5 cycles -> C37.118 packets):"
if [ "$TEST1_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
elif [ "$TEST1_RESULT" = "PARTIAL" ]; then
    echo -e "    Result: ${YELLOW}PARTIAL${NC}"
else
    echo -e "    Result: ${RED}$TEST1_RESULT${NC}"
fi

echo ""
echo "  TEST 2 - Hann Window Standalone:"
if [ "$TEST2_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
else
    echo -e "    Result: ${RED}$TEST2_RESULT${NC}"
fi

echo ""
echo "  TEST 3 - Frequency Damping Filter Standalone:"
if [ "$TEST3_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
else
    echo -e "    Result: ${RED}$TEST3_RESULT${NC}"
fi

echo ""
echo "Generated Files:"
echo "  - logs/xvhdl_5cycle.log   (compilation)"
echo "  - logs/xelab_5cycle.log   (elaboration)"
echo "  - logs/xsim_5cycle.log    (simulation)"
echo ""

if [ "$ALL_PASSED" = true ]; then
    echo -e "${GREEN}======================================"
    echo "✓ ALL 3 TESTS PASSED"
    echo "======================================${NC}"
    exit 0
else
    echo -e "${YELLOW}======================================"
    echo "Some tests may need review"
    echo "======================================${NC}"
    echo "Check logs/xsim_5cycle.log for details"
    exit 1
fi
