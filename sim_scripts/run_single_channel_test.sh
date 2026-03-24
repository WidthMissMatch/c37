#!/bin/bash
# ============================================================================
# Single-Channel pmu_processing_top Test
# ============================================================================
#
# Compiles only the modules needed for pmu_processing_top (no AXI, no packet
# formatter, no system top), elaborates tb_pmu_processing_top_single, and
# runs xsim simulation.
#
# Tests:
#   A. Pipeline activity (system_ready, cycle_complete, dft, phasor, freq)
#   B. Phasor output verification (magnitude range)
#   C. Frequency output verification (within ±2 Hz of 50 Hz)
#   D. Hann window confirmation (magnitude consistency)
#   E. Freq damping confirmation (smooth convergence)
#
# Usage:
#   ./run_single_channel_test.sh
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

print_banner "Single-Channel PMU Processing Top Test - Vivado xsim"

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
    "vhdl_modules/sine.vhd" \
    "vhdl_modules/cos.vhd" \
    "vhdl_modules/circular_buffer.vhd" \
    "vhdl_modules/sample_counter.vhd" \
    "vhdl_modules/cycle_tracker.vhd" \
    "vhdl_modules/position_calc.vhd" \
    "vhdl_modules/Sample_fetcher.vhd" \
    "vhdl_modules/interpolation_engine.vhd" \
    "vhdl_modules/resampler_top.vhd" \
    "vhdl_modules/dft_sample_buffer.vhd" \
    "vhdl_modules/dft.vhd" \
    "vhdl_modules/cordic_calculator_256.vhd" \
    "vhdl_modules/frequency_rocof_calculator_256.vhd" \
    "vhdl_modules/hann_window.vhd" \
    "vhdl_modules/freq_damping_filter.vhd" \
    "vhdl_modules/pmu_processing_top.vhd" \
    "testbenches/tb_pmu_processing_top_single.vhd"; do
    if [ ! -f "$f" ]; then
        print_error "Missing: $f"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -gt 0 ]; then
    print_error "$MISSING required file(s) missing!"
    exit 1
fi
print_success "All required files found (17 VHDL sources + 1 testbench)"
echo ""

# ----------------------------------------------------------------------------
# Step 1: Compile VHDL with xvhdl
# ----------------------------------------------------------------------------

print_step "1" "Compiling VHDL files with xvhdl"
echo ""

mkdir -p xsim.dir
mkdir -p logs

# Compilation order: leaf modules first, then composites, then testbench
# Only modules needed for pmu_processing_top — no AXI, no system top
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
    # Window and filter modules
    "vhdl_modules/hann_window.vhd"
    "vhdl_modules/freq_damping_filter.vhd"
    # Processing top (depends on all above)
    "vhdl_modules/pmu_processing_top.vhd"
    # Testbench
    "testbenches/tb_pmu_processing_top_single.vhd"
)

COMPILE_ERRORS=0

: > logs/xvhdl_single_ch.log  # Clear log

for file in "${VHDL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        ((COMPILE_ERRORS++))
        continue
    fi

    echo -n "  Compiling $(basename "$file")... "

    if xvhdl --work work "$file" >> logs/xvhdl_single_ch.log 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        ((COMPILE_ERRORS++))
        echo "    See logs/xvhdl_single_ch.log for details"
    fi
done

echo ""

if [ $COMPILE_ERRORS -gt 0 ]; then
    print_error "Compilation failed with $COMPILE_ERRORS error(s)"
    echo "Check logs/xvhdl_single_ch.log for details"
    tail -n 30 logs/xvhdl_single_ch.log
    exit 1
fi

print_success "All ${#VHDL_FILES[@]} files compiled successfully (0 errors)"
echo ""

# ----------------------------------------------------------------------------
# Step 2: Elaborate Design
# ----------------------------------------------------------------------------

print_step "2" "Elaborating design with xelab"
echo ""

xelab -debug typical work.tb_pmu_processing_top_single \
    -s single_ch_sim >> logs/xelab_single_ch.log 2>&1

if [ $? -ne 0 ]; then
    print_error "Elaboration failed!"
    echo "Check logs/xelab_single_ch.log for details"
    tail -n 30 logs/xelab_single_ch.log
    exit 1
fi

print_success "Elaboration complete (0 errors)"
echo ""

# ----------------------------------------------------------------------------
# Step 3: Run Simulation
# ----------------------------------------------------------------------------

print_step "3" "Running simulation with xsim"
echo ""
echo "Running single-channel test: 1500 samples (5 cycles @ 50 Hz, 15 kHz)"
echo "Timeout: 150 ms simulation time"
echo ""

# Create simulation TCL script
cat > xsim_single_ch_run.tcl << 'EOF'
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
EOF

xsim single_ch_sim -tclbatch xsim_single_ch_run.tcl > logs/xsim_single_ch.log 2>&1

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

LOG_FILE="logs/xsim_single_ch.log"

# Extract test results from simulation log
TESTA_RESULT="UNKNOWN"
TESTB_RESULT="UNKNOWN"
TESTC_RESULT="UNKNOWN"
TESTD_RESULT="UNKNOWN"
TESTE_RESULT="UNKNOWN"

if grep -q "\[TEST A\] PASSED" "$LOG_FILE"; then
    TESTA_RESULT="PASSED"
elif grep -q "\[TEST A\] FAILED" "$LOG_FILE"; then
    TESTA_RESULT="FAILED"
fi

if grep -q "\[TEST B\] PASSED" "$LOG_FILE"; then
    TESTB_RESULT="PASSED"
elif grep -q "\[TEST B\] FAILED" "$LOG_FILE"; then
    TESTB_RESULT="FAILED"
fi

if grep -q "\[TEST C\] PASSED" "$LOG_FILE"; then
    TESTC_RESULT="PASSED"
elif grep -q "\[TEST C\] FAILED" "$LOG_FILE"; then
    TESTC_RESULT="FAILED"
fi

if grep -q "\[TEST D\] PASSED" "$LOG_FILE"; then
    TESTD_RESULT="PASSED"
elif grep -q "\[TEST D\] FAILED" "$LOG_FILE"; then
    TESTD_RESULT="FAILED"
fi

if grep -q "\[TEST E\] PASSED" "$LOG_FILE"; then
    TESTE_RESULT="PASSED"
elif grep -q "\[TEST E\] FAILED" "$LOG_FILE"; then
    TESTE_RESULT="FAILED"
fi

# Check for ALL TESTS PASSED
ALL_PASSED=false
if grep -q "ALL TESTS PASSED" "$LOG_FILE"; then
    ALL_PASSED=true
fi

# Print key log lines
echo "Key simulation output:"
echo "------------------------------"
grep -E "\[TEST [A-E]\]|\[STIM\]|\[STATUS\]|ALL TESTS|SOME TESTS|FINAL TEST|cycle_complete|dft_valid|phasor_valid|freq_valid|Phasor #|Frequency #|Mag\[|Freq\[" "$LOG_FILE" | head -60
echo "------------------------------"
echo ""

# ----------------------------------------------------------------------------
# Final Summary
# ----------------------------------------------------------------------------

print_banner "Test Results Summary"

echo "  TEST A - Pipeline Activity (system_ready, cycle_complete, dft, phasor, freq):"
if [ "$TESTA_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
else
    echo -e "    Result: ${RED}$TESTA_RESULT${NC}"
fi

echo ""
echo "  TEST B - Phasor Output (magnitude range, non-zero):"
if [ "$TESTB_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
else
    echo -e "    Result: ${RED}$TESTB_RESULT${NC}"
fi

echo ""
echo "  TEST C - Frequency Output (within ±2 Hz of 50 Hz after settling):"
if [ "$TESTC_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
else
    echo -e "    Result: ${RED}$TESTC_RESULT${NC}"
fi

echo ""
echo "  TEST D - Hann Window Confirmation (magnitude consistency):"
if [ "$TESTD_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
else
    echo -e "    Result: ${RED}$TESTD_RESULT${NC}"
fi

echo ""
echo "  TEST E - Freq Damping Confirmation (smooth convergence):"
if [ "$TESTE_RESULT" = "PASSED" ]; then
    echo -e "    Result: ${GREEN}PASSED${NC}"
else
    echo -e "    Result: ${RED}$TESTE_RESULT${NC}"
fi

echo ""
echo "Generated Files:"
echo "  - logs/xvhdl_single_ch.log   (compilation)"
echo "  - logs/xelab_single_ch.log   (elaboration)"
echo "  - logs/xsim_single_ch.log    (simulation)"
echo ""

if [ "$ALL_PASSED" = true ]; then
    echo -e "${GREEN}======================================"
    echo "✓ ALL 5 TESTS PASSED (A-E)"
    echo "======================================${NC}"
    echo ""
    echo "Next step: Run full system test:"
    echo "  ./run_5cycle_test.sh"
    exit 0
else
    echo -e "${YELLOW}======================================"
    echo "Some tests may need review"
    echo "======================================${NC}"
    echo "Check logs/xsim_single_ch.log for details"
    exit 1
fi
