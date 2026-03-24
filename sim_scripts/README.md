# 6-Channel PMU System Test Suite

This directory contains simulation and validation scripts for the complete 6-channel PMU system.

---

## Overview

The test suite validates the complete PMU system (`pmu_system_complete_256.vhd` in file `8.vhd`) which:
- Receives 128-bit AXI Stream input packets from PS containing 6 channels of ADC data
- Processes all 6 channels through adaptive resampling and 256-point DFT
- Outputs IEEE C37.118 compliant packets via 32-bit AXI Stream
- Implements master-slave architecture (Channel 1 calculates frequency, shared with Channels 2-6)

---

## Test Data

**Input:** `medhavi.csv` (must be in project root directory)
- 100,000 samples per channel (6 channels total)
- 16-bit signed ADC values
- ~6.7 seconds of data at 15 kHz sample rate
- Represents ~335 power cycles at 50 Hz

---

## Quick Start

### Automated Test (Recommended)

Run the complete test suite with one command:

```bash
cd sim_scripts
./run_6ch_testbench.sh
```

This will automatically:
1. Generate golden reference from medhavi.csv
2. Compile and simulate the VHDL testbench
3. Validate results against golden reference

### Manual Steps

If you prefer to run steps individually:

#### Step 1: Generate Golden Reference

```bash
cd ..  # Go to project root
python3 validate_6ch_pmu.py --generate-golden
```

This creates `golden_reference_6ch.csv` with expected phasor values for validation cycles (1, 50, 100, 200, 335).

#### Step 2: Run VHDL Simulation

```bash
vsim -c -do "sim_scripts/run_6ch_testbench.tcl; quit"
```

Or for GUI mode:
```bash
vsim -do sim_scripts/run_6ch_testbench.tcl
```

This compiles all VHDL files and runs an 8-second simulation, generating `testbench_results_100k.csv`.

#### Step 3: Validate Results

```bash
python3 validate_6ch_pmu.py --validate
```

This compares testbench results against the golden reference.

---

## Files in This Directory

### New 6-Channel Test Suite:
- **`run_6ch_testbench.sh`** - Master automation script (bash)
- **`run_6ch_testbench.tcl`** - ModelSim/Questa simulation script (TCL)

### Legacy Single-Channel Test:
- **`compile_all.tcl`** - Compiles VHDL for single-channel testbench
- **`run_sim.tcl`** - Single-channel simulation script
- **`run_xsim.sh`** - Xilinx xsim runner for single-channel test

### Documentation:
- **`README.md`** - This file

---

## Required Tools

- **ModelSim** or **Questa Sim** - For VHDL simulation
- **Python 3** - For golden reference generation and validation
- **Bash** - For automation script (Linux/macOS/WSL)

---

## Expected Outputs

### Console Output

During simulation, you'll see real-time validation messages:
- Pass/Fail checks for each cycle
- Magnitude and phase validation (6 channels per cycle)
- Frequency and ROCOF validation
- Phase stability checks

### Generated Files

After successful run:

1. **`golden_reference_6ch.csv`** - Expected phasor values for validation cycles
   - Columns: cycle, channel, mag_hex, mag_float, phase_hex, phase_rad
   - 5 cycles × 6 channels = 30 rows

2. **`testbench_results_100k.csv`** - Complete simulation results
   - ~335 rows (one per power cycle)
   - Columns per channel (× 6): magnitude (hex + float), phase (hex + rad)
   - Plus: frequency, ROCOF, timestamp

3. **`logs/simulation_run.log`** - Complete simulation transcript
4. **`logs/validation_report.log`** - Detailed validation comparison
5. **`simulation_transcript.log`** - ModelSim console output
6. **`work/`** - Compiled VHDL library

---

## Validation Criteria

### Pass/Fail Checks (Real-time)

For each output cycle:
- **Magnitude:** 31.8 - 38.9 range (all 6 channels)
- **Frequency:** 49.5 - 50.5 Hz
- **ROCOF:** ±1.0 Hz/s
- **Phase Stability:** < 0.5 rad jump between consecutive measurements

### Golden Reference Comparison

For validation cycles (1, 50, 100, 200, 335):
- **Magnitude Tolerance:** ±1% error
- **Phase Tolerance:** ±0.1 radian error

### Statistical Analysis

Computed automatically by testbench:
- Mean, standard deviation, min, max (per channel)
- Frequency statistics
- ROCOF statistics
- Phase drift analysis (linear regression)
- Convergence time

---

## Simulation Timeline

```
Time Range          | Activity
--------------------|------------------------------------------
0 - 200 ns          | Reset assertion
200 - 300 ns        | Reset release, settling
300 - 400 ns        | Enable assertion
400 ns - 6.67 s     | Input stimulus (100K packets @ 15 kHz)
20 ms - 6.69 s      | Output packets (~335 cycles @ 50 Hz)
6.69 - 7.0 s        | Final processing
7.0 - 8.0 s         | Statistics calculation, CSV writing
```

**Total simulation time:** ~8 seconds

**Note:** First 2 frequency outputs use hardcoded 50 Hz (as per frequency feedback modification in `pmu_processing_top.vhd`). Measured frequency is used from cycle 3 onwards.

---

## Troubleshooting

### Simulation won't start

**Problem:** `vsim: command not found`

**Solution:** Add ModelSim/Questa to your PATH:
```bash
export PATH=/path/to/modelsim/bin:$PATH
```

Or use full path to vsim in the scripts.

### Python script fails

**Problem:** `ModuleNotFoundError` or similar

**Solution:** The scripts use only Python standard library. Ensure you're using Python 3.6 or later:
```bash
python3 --version
```

### CSV not found

**Problem:** `ERROR: medhavi.csv not found!`

**Solution:** Ensure `medhavi.csv` is in the project root directory (one level up from `sim_scripts/`).

### Simulation takes too long

**Problem:** Simulation running for hours

**Solution:** This is normal for large simulations. 100K samples with full PMU processing can take:
- **ModelSim:** 30-60 minutes
- **Questa (optimized):** 15-30 minutes

Consider reducing `SAMPLE_COUNT` in the testbench for quicker tests.

### Validation fails

**Problem:** Results don't match golden reference

**Possible causes:**
1. Check that `medhavi.csv` has correct format (6 columns, 100K+ rows)
2. Verify all VHDL files compiled without warnings
3. Ensure simulation ran for full 8 seconds
4. Check `cordic_calculator_256.vhd` has `RMS_SCALE = 18432` (not 256)

---

## Advanced Usage

### View Waveforms

To keep the GUI open after simulation:

```bash
vsim -do sim_scripts/run_6ch_testbench.tcl
# Don't include "quit" command
```

Waveforms are pre-configured for:
- Clock, reset, enable
- AXI Stream input/output interfaces
- System status signals
- Result counters
- Frequency/ROCOF outputs

### Run Subset of Tests

Modify `SAMPLE_COUNT` in `pmu_system_complete_256_tb.vhd`:
```vhdl
constant SAMPLE_COUNT : integer := 10000;  -- Test with 10K samples instead
```

Adjust simulation time in TCL script accordingly:
```tcl
run 1 sec  # Instead of 8 sec
```

### Generate Additional Golden Cycles

Modify `VALIDATION_CYCLES` in `validate_6ch_pmu.py`:
```python
VALIDATION_CYCLES = [1, 10, 20, 30, 40, 50, 100, 200, 335]
```

---

## Performance Notes

**Simulation Speed:**
- 100K samples = 6.67 seconds simulated time
- Actual wall-clock time: 15-60 minutes (depending on CPU)
- Majority of time spent in DFT and CORDIC calculations

**Memory Usage:**
- Testbench stores all 100K samples in memory
- Results array for 335 cycles (relatively small)
- ModelSim work library: ~50-100 MB

---

## Expected Results

For valid medhavi.csv data with nominal 50 Hz waveforms:

**All Channels:**
- Magnitude: ~35 (range 31.8-38.9)
- Phase: Stable, smooth progression
- Frequency: 50.00 ± 0.05 Hz (after cycle 2)
- ROCOF: Near 0 Hz/s for steady-state

**Pass Rate:** 100% for all validation checks

---

**Author:** Arun's PMU Project
**Date:** December 2024
**Version:** 2.0 (6-Channel Complete System)
