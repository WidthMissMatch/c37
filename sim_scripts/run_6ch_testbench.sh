#!/bin/bash
# ============================================================================
# 6-Channel PMU Complete Test Suite - Automation Script
# ============================================================================
#
# This script automates the complete testing workflow:
#   1. Generate golden reference from medhavi.csv
#   2. Run VHDL simulation with 100K samples
#   3. Validate testbench results against golden reference
#
# Usage:
#   ./run_6ch_testbench.sh
#   OR
#   bash run_6ch_testbench.sh
#
# Author: Arun's PMU Project
# Date: December 2024
# ============================================================================

set -e  # Exit on error

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

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

# ============================================================================
# Main Test Flow
# ============================================================================

print_banner "6-Channel PMU Complete Test Suite"

# Change to project root directory
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

echo "Project directory: $PROJECT_ROOT"
echo ""

# ----------------------------------------------------------------------------
# Pre-Flight Checks
# ----------------------------------------------------------------------------

print_step "0" "Pre-flight checks"

# Check for required files
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

if [ ! -f "sim_scripts/run_6ch_testbench.tcl" ]; then
    print_error "sim_scripts/run_6ch_testbench.tcl not found!"
    exit 1
fi
print_success "sim_scripts/run_6ch_testbench.tcl found"

if [ ! -f "pmu_system_complete_256_tb.vhd" ]; then
    print_error "pmu_system_complete_256_tb.vhd not found!"
    exit 1
fi
print_success "pmu_system_complete_256_tb.vhd found"

# Check for Python 3
if ! command -v python3 &> /dev/null; then
    print_error "python3 not found! Please install Python 3."
    exit 1
fi
print_success "Python 3 found: $(python3 --version)"

# Check for vsim (ModelSim/Questa)
if ! command -v vsim &> /dev/null; then
    print_warning "vsim (ModelSim/Questa) not found in PATH"
    print_warning "Please ensure ModelSim or Questa is installed and in your PATH"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# ----------------------------------------------------------------------------
# Step 1: Generate Golden Reference
# ----------------------------------------------------------------------------

print_step "1" "Generating golden reference from medhavi.csv"
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

print_success "Golden reference generated successfully"
echo ""

# ----------------------------------------------------------------------------
# Step 2: Run VHDL Simulation
# ----------------------------------------------------------------------------

print_step "2" "Running VHDL testbench simulation"
echo ""
echo "This will take several minutes (simulating 8 seconds of real-time)..."
echo "Compiling VHDL files and running simulation..."
echo ""

# Create log directory
mkdir -p logs

# Run simulation in batch mode
vsim -c -do "sim_scripts/run_6ch_testbench.tcl; quit" > logs/simulation_run.log 2>&1

SIM_EXIT_CODE=$?

if [ $SIM_EXIT_CODE -ne 0 ]; then
    print_error "Simulation failed! Check logs/simulation_run.log for details"

    # Show last 50 lines of log
    echo ""
    echo "Last 50 lines of simulation log:"
    echo "--------------------------------------"
    tail -n 50 logs/simulation_run.log
    echo "--------------------------------------"

    exit 1
fi

print_success "Simulation completed"

# Check if testbench CSV was created
if [ ! -f "testbench_results_100k.csv" ]; then
    print_error "testbench_results_100k.csv was not created!"
    print_error "Simulation may have failed during execution"
    echo ""
    echo "Check logs/simulation_run.log for details"
    exit 1
fi

# Count result lines
RESULT_LINES=$(wc -l < testbench_results_100k.csv)
DATA_LINES=$((RESULT_LINES - 1))  # Subtract header

print_success "testbench_results_100k.csv created with $DATA_LINES data rows"

echo ""

# ----------------------------------------------------------------------------
# Step 3: Validate Results
# ----------------------------------------------------------------------------

print_step "3" "Validating testbench results against golden reference"
echo ""

python3 validate_6ch_pmu.py --validate > logs/validation_report.log 2>&1

VALIDATION_EXIT_CODE=$?

# Show validation output
cat logs/validation_report.log

if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
    print_success "Validation PASSED"
else
    print_error "Validation FAILED"
    echo ""
    echo "Check logs/validation_report.log for details"
fi

echo ""

# ----------------------------------------------------------------------------
# Final Summary
# ----------------------------------------------------------------------------

print_banner "Test Suite Complete"

echo "Summary:"
echo "--------"
echo "  Step 1: Golden reference generation ... $([ -f golden_reference_6ch.csv ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 2: VHDL simulation ............... $([ -f testbench_results_100k.csv ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo "  Step 3: Result validation ............. $([ $VALIDATION_EXIT_CODE -eq 0 ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}")"
echo ""

echo "Generated Files:"
echo "  - golden_reference_6ch.csv"
echo "  - testbench_results_100k.csv"
echo "  - logs/simulation_run.log"
echo "  - logs/validation_report.log"
echo "  - simulation_transcript.log"
echo "  - work/ (compiled VHDL library)"
echo ""

if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}======================================"
    echo -e "✓ ALL TESTS PASSED"
    echo -e "======================================${NC}"
    echo ""
    echo "The 6-channel PMU system is functioning correctly!"
    exit 0
else
    echo -e "${RED}======================================"
    echo -e "✗ SOME TESTS FAILED"
    echo -e "======================================${NC}"
    echo ""
    echo "Review the logs for details:"
    echo "  - logs/simulation_run.log"
    echo "  - logs/validation_report.log"
    echo ""
    echo "Common issues:"
    echo "  - Check that medhavi.csv has correct format"
    echo "  - Verify all VHDL files compiled without errors"
    echo "  - Ensure system had enough time to process all inputs"
    exit 1
fi
