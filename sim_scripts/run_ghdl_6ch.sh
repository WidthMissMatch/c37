#!/bin/bash
# ============================================================================
# 6-Channel PMU System - GHDL Test Suite
# ============================================================================
#
# This script uses GHDL (open-source VHDL simulator)
# GHDL is much faster than commercial simulators
#
# Usage:
#   ./run_ghdl_6ch.sh
#
# Author: Arun's PMU Project
# Date: December 2024
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

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_banner "6-Channel PMU Test Suite (GHDL)"

# Change to project root
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

echo "Project directory: $PROJECT_ROOT"
echo ""

# ----------------------------------------------------------------------------
# Pre-Flight Checks
# ----------------------------------------------------------------------------

print_step "0" "Pre-flight checks"

# Check GHDL
if ! command -v ghdl &> /dev/null; then
    print_error "GHDL not found! Please install GHDL:"
    echo "  sudo apt install ghdl  # Ubuntu/Debian"
    echo "  sudo dnf install ghdl  # Fedora"
    exit 1
fi

GHDL_VERSION=$(ghdl --version | head -n 1)
print_success "GHDL found: $GHDL_VERSION"

# Check files
if [ ! -f "medhavi.csv" ]; then
    print_error "medhavi.csv not found!"
    exit 1
fi
print_success "medhavi.csv found"

if [ ! -f "validate_6ch_pmu.py" ]; then
    print_error "validate_6ch_pmu.py not found!"
    exit 1
fi
print_success "validate_6ch_pmu.py found"

if [ ! -f "pmu_system_complete_256_tb.vhd" ]; then
    print_error "pmu_system_complete_256_tb.vhd not found!"
    exit 1
fi
print_success "pmu_system_complete_256_tb.vhd found"

echo ""

# ----------------------------------------------------------------------------
# Step 1: Generate Golden Reference
# ----------------------------------------------------------------------------

print_step "1" "Generating golden reference"
echo ""

python3 validate_6ch_pmu.py --generate-golden

if [ $? -ne 0 ]; then
    print_error "Golden reference generation failed!"
    exit 1
fi

if [ ! -f "golden_reference_6ch.csv" ]; then
    print_error "golden_reference_6ch.csv was not created!"
    exit 1
fi

print_success "Golden reference generated"
echo ""

# ----------------------------------------------------------------------------
# Step 2: Analyze (Compile) VHDL with GHDL
# ----------------------------------------------------------------------------

print_step "2" "Analyzing VHDL files with GHDL"
echo ""

# Create logs directory
mkdir -p logs

# Compilation order
VHDL_FILES=(
    "sine.vhd"
    "cos.vhd"
    "circular_buffer.vhd"
    "sample_counter.vhd"
    "cycle_tracker.vhd"
    "position_calc.vhd"
    "Sample_fetcher.vhd"
    "interpolation_engine.vhd"
    "resampler_top.vhd"
    "dft_sample_buffer.vhd"
    "dft.vhd"
    "cordic_calculator_256.vhd"
    "frequency_rocof_calculator_256.vhd"
    "pmu_processing_top.vhd"
    "packet_validator.vhd"
    "c37118_packet_formatter_6ch.vhd"
    "axi_packet_receiver_128bit.vhd"
    "channel_extractor.vhd"
    "input_interface_complete.vhd"
    "pmu_6ch_processing_256.vhd"
    "pmu_system_complete_256.vhd"
    "pmu_system_complete_256_tb.vhd"
)

COMPILE_ERRORS=0

for file in "${VHDL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        ((COMPILE_ERRORS++))
        continue
    fi

    echo -n "  Analyzing $file... "

    # GHDL analyze with VHDL-93 standard
    # -C: allow any character in comments (for π symbol)
    if ghdl -a --std=93 -C --work=work "$file" 2>> logs/ghdl_analyze.log; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        ((COMPILE_ERRORS++))
        echo "    Check logs/ghdl_analyze.log for details"
    fi
done

echo ""

if [ $COMPILE_ERRORS -gt 0 ]; then
    print_error "Analysis failed with $COMPILE_ERRORS errors"
    echo ""
    echo "Last 30 lines of error log:"
    tail -n 30 logs/ghdl_analyze.log
    exit 1
fi

print_success "All files analyzed successfully"
echo ""

# ----------------------------------------------------------------------------
# Step 3: Elaborate Design
# ----------------------------------------------------------------------------

print_step "3" "Elaborating design with GHDL"
echo ""

ghdl -e --std=93 -C --work=work pmu_system_complete_256_tb >> logs/ghdl_elaborate.log 2>&1

if [ $? -ne 0 ]; then
    print_error "Elaboration failed!"
    echo "Check logs/ghdl_elaborate.log for details"
    cat logs/ghdl_elaborate.log
    exit 1
fi

print_success "Elaboration complete"
echo ""

# ----------------------------------------------------------------------------
# Step 4: Run Simulation
# ----------------------------------------------------------------------------

print_step "4" "Running simulation with GHDL"
echo ""
echo "Simulating 8 seconds of operation..."
echo "GHDL is much faster than commercial simulators (5-15 minutes typical)"
echo ""

# Run simulation
# --stop-time=8sec : run for 8 simulated seconds
# --wave=waveform.ghw : save waveforms (optional)
# --assert-level=warning : show warnings and errors

START_TIME=$(date +%s)

ghdl -r --std=93 -C --work=work pmu_system_complete_256_tb --stop-time=8sec \
    --assert-level=warning > logs/ghdl_run.log 2>&1

SIM_EXIT_CODE=$?
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

if [ $SIM_EXIT_CODE -ne 0 ]; then
    print_error "Simulation failed!"
    echo "Check logs/ghdl_run.log for details"
    echo ""
    echo "Last 50 lines of log:"
    tail -n 50 logs/ghdl_run.log
    exit 1
fi

print_success "Simulation completed in ${MINUTES}m ${SECONDS}s"

# Check output file
if [ ! -f "testbench_results_100k.csv" ]; then
    print_error "testbench_results_100k.csv was not created!"
    echo "Simulation may have completed but CSV writer failed"
    echo ""
    echo "Last 100 lines of simulation log:"
    tail -n 100 logs/ghdl_run.log
    exit 1
fi

RESULT_LINES=$(wc -l < testbench_results_100k.csv)
DATA_LINES=$((RESULT_LINES - 1))

print_success "testbench_results_100k.csv created with $DATA_LINES data rows"
echo ""

# ----------------------------------------------------------------------------
# Step 5: Validate Results
# ----------------------------------------------------------------------------

print_step "5" "Validating results"
echo ""

python3 validate_6ch_pmu.py --validate > logs/validation_report.log 2>&1

VALIDATION_EXIT_CODE=$?

# Show validation output
cat logs/validation_report.log

echo ""

if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
    print_success "Validation PASSED"
else
    print_error "Validation FAILED"
fi

echo ""

# ----------------------------------------------------------------------------
# Final Summary
# ----------------------------------------------------------------------------

print_banner "Test Suite Complete"

echo "Summary:"
echo "--------"
echo "  Step 1: Golden reference ... $([ -f golden_reference_6ch.csv ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 2: VHDL analysis ....... $([ $COMPILE_ERRORS -eq 0 ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 3: Elaboration ......... $([ -f pmu_system_complete_256_tb ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 4: Simulation .......... $([ -f testbench_results_100k.csv ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 5: Validation .......... $([ $VALIDATION_EXIT_CODE -eq 0 ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo ""

echo "Performance:"
echo "  Simulation time: ${MINUTES}m ${SECONDS}s"
echo ""

echo "Generated Files:"
echo "  - golden_reference_6ch.csv"
echo "  - testbench_results_100k.csv"
echo "  - logs/ghdl_analyze.log"
echo "  - logs/ghdl_elaborate.log"
echo "  - logs/ghdl_run.log"
echo "  - logs/validation_report.log"
echo ""

if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}======================================"
    echo "✓ ALL TESTS PASSED"
    echo "======================================${NC}"
    echo ""
    echo "The 6-channel PMU system is working correctly!"
    echo ""
    echo "Note: To view waveforms, add --wave=waveform.ghw to ghdl -r command"
    echo "      and use gtkwave to view: gtkwave waveform.ghw"
    exit 0
else
    echo -e "${RED}======================================"
    echo "✗ SOME TESTS FAILED"
    echo "======================================${NC}"
    echo ""
    echo "Review logs for details"
    exit 1
fi
