#!/bin/bash
# ============================================================================
# 6-Channel PMU System - Vivado xsim Test Suite
# ============================================================================
#
# This script uses Vivado's xsim for simulation
#
# Usage:
#   ./run_xsim_6ch.sh
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

print_banner "6-Channel PMU Test Suite (Vivado xsim)"

# Change to project root
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

echo "Project directory: $PROJECT_ROOT"
echo ""

# ----------------------------------------------------------------------------
# Pre-Flight Checks
# ----------------------------------------------------------------------------

print_step "0" "Pre-flight checks"

# Check Vivado tools
if ! command -v xvhdl &> /dev/null; then
    print_error "xvhdl not found! Please source Vivado settings:"
    echo "  source /path/to/Vivado/2025.1/settings64.sh"
    exit 1
fi
print_success "Vivado xsim tools found"

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
# Step 2: Compile VHDL with xvhdl
# ----------------------------------------------------------------------------

print_step "2" "Compiling VHDL files with xvhdl"
echo ""

# Create work library directory
mkdir -p xsim.dir
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
    "axi_packet_receiver_128bit.vhd"
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

    echo -n "  Compiling $file... "

    if xvhdl --work work "$file" >> logs/xvhdl_compile.log 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        ((COMPILE_ERRORS++))
        echo "    Check logs/xvhdl_compile.log for details"
    fi
done

echo ""

if [ $COMPILE_ERRORS -gt 0 ]; then
    print_error "Compilation failed with $COMPILE_ERRORS errors"
    echo "Check logs/xvhdl_compile.log for details"
    exit 1
fi

print_success "All files compiled successfully"
echo ""

# ----------------------------------------------------------------------------
# Step 3: Elaborate Design
# ----------------------------------------------------------------------------

print_step "3" "Elaborating design with xelab"
echo ""

xelab -debug typical work.pmu_system_complete_256_tb -s pmu_tb_sim >> logs/xelab.log 2>&1

if [ $? -ne 0 ]; then
    print_error "Elaboration failed!"
    echo "Check logs/xelab.log for details"
    tail -n 20 logs/xelab.log
    exit 1
fi

print_success "Elaboration complete"
echo ""

# ----------------------------------------------------------------------------
# Step 4: Run Simulation
# ----------------------------------------------------------------------------

print_step "4" "Running simulation with xsim"
echo ""
echo "Simulating 8 seconds of operation..."
echo "This will take 30-60 minutes on a typical workstation"
echo ""

# Create simulation commands
cat > xsim_run.tcl << 'EOF'
# xsim simulation script
puts "Starting 8-second simulation..."
puts "Processing 100,000 samples..."

# Run simulation
run 8 sec

puts ""
puts "Simulation complete!"

# Exit
quit
EOF

# Run simulation
xsim pmu_tb_sim -tclbatch xsim_run.tcl > logs/xsim_run.log 2>&1

SIM_EXIT_CODE=$?

if [ $SIM_EXIT_CODE -ne 0 ]; then
    print_error "Simulation failed!"
    echo "Check logs/xsim_run.log for details"
    tail -n 50 logs/xsim_run.log
    exit 1
fi

print_success "Simulation completed"

# Check output file
if [ ! -f "testbench_results_100k.csv" ]; then
    print_error "testbench_results_100k.csv was not created!"
    echo "Simulation may have failed during execution"
    echo "Check logs/xsim_run.log for details"
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
echo "  Step 2: VHDL compilation ... $([ $COMPILE_ERRORS -eq 0 ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 3: Elaboration ......... $([ -f xsim.dir/pmu_tb_sim/xsimk ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 4: Simulation .......... $([ -f testbench_results_100k.csv ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 5: Validation .......... $([ $VALIDATION_EXIT_CODE -eq 0 ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo ""

echo "Generated Files:"
echo "  - golden_reference_6ch.csv"
echo "  - testbench_results_100k.csv"
echo "  - logs/xvhdl_compile.log"
echo "  - logs/xelab.log"
echo "  - logs/xsim_run.log"
echo "  - logs/validation_report.log"
echo ""

if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}======================================"
    echo "✓ ALL TESTS PASSED"
    echo "======================================${NC}"
    echo ""
    echo "The 6-channel PMU system is working correctly!"
    exit 0
else
    echo -e "${RED}======================================"
    echo "✗ SOME TESTS FAILED"
    echo "======================================${NC}"
    echo ""
    echo "Review logs for details"
    exit 1
fi
