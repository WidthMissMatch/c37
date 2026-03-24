# Folder Organization

This document describes the organized structure of the PMU C37.118 compliance project.

## Directory Structure

```
c37 compliance/
├── vhdl_modules/          # Core VHDL design files
├── testbenches/           # VHDL testbenches
├── data_files/            # CSV and test data
├── scripts/               # Python and shell scripts
├── reports_latest/        # Latest test reports and results
├── sim_scripts/           # Simulation helper scripts
├── xsim.dir/              # Vivado simulator build files
├── c37 compliance.cache/  # Vivado cache
├── c37 compliance.hw/     # Vivado hardware
├── c37 compliance.ip_user_files/  # Vivado IP files
├── c37 compliance.sim/    # Vivado simulation
├── c37 compliance.xpr     # Vivado project file
```

## vhdl_modules/ (25 files)

Core VHDL design modules for IEEE C37.118 PMU implementation:

**Top-Level:**
- `8.vhd` - Top-level system integration (pmu_system_complete_256)
- `ibrahim_lodhi.vhd` - 6-channel PMU processing wrapper
- `daulat_ibrahim.vhd` - Packet formatter (IEEE C37.118 compliance)

**Resampler Chain:**
- `resampler_top.vhd` - Resampler controller
- `circular_buffer.vhd` - 512-sample circular buffer
- `sample_counter.vhd` - Samples per cycle calculator (Q16.16)
- `cycle_tracker.vhd` - Cycle boundary detector
- `position_calc.vhd` - Interpolation position generator
- `Sample_fetcher.vhd` - Buffer access for interpolation
- `interpolation_engine.vhd` - Linear interpolation

**DFT Chain:**
- `dft_sample_buffer.vhd` - 256-sample buffer for DFT
- `dft.vhd` - 256-point DFT processor (k=1 bin)
- `sine.vhd` - Sine coefficient ROM (Q1.15)
- `cos.vhd` - Cosine coefficient ROM (Q1.15)

**Post-Processing:**
- `cordic_calculator_256.vhd` - Complex to polar conversion
- `frequency_rocof_calculator_256.vhd` - Frequency and ROCOF estimation
- `tve_calculator.vhd` - Total Vector Error calculator
- `crc_ccitt_c37118.vhd` - CRC-CCITT checksum (IEEE C37.118)

**Input Interface:**
- `input_interbace.vhd` - Input interface module
- `pyari.vhd` - AXI Stream input handler
- `hehehehehe.vhd` - Input support module
- `ain_e_akbiri.vhd` - Input processing module

**Processing Modules:**
- `pmu_processing_top.vhd` - Complete single-channel PMU pipeline
- `pmu_processing_top_no_freq.vhd` - PMU without frequency feedback

**Utilities:**
- `csv_reader_pkg.vhd` - CSV file reading package (for simulation)

## testbenches/ (4 files)

VHDL testbenches for verification:

- `tb_pmu_selfcontained_5cycles.vhd` - Main 5-cycle test (1500 samples)
- `test_data_constants_pkg.vhd` - Generated VHDL package with 1500 hardcoded test packets
- `crc_ccitt_c37118_tb.vhd` - CRC module testbench
- `tve_calculator_tb.vhd` - TVE calculator testbench

## data_files/ (5 files)

Test data and reference waveforms:

- `medhavi.csv` - Full 3-phase power system waveform (100K+ samples)
- `medhavi_small.csv` - Subset for quick testing
- `medhavi_1cycle.csv` - Single power cycle data
- `single.txt` - Single-column ADC samples
- `packets_complete.txt` - Expected packet hex dump

## scripts/ (7 files)

Python and shell scripts for automation:

**Python Scripts:**
- `generate_test_constants.py` - Generates VHDL test data constants from CSV
- `analyze_pmu_output.py` - Analyzes PMU output packets (magnitude, phase, frequency)
- `verify_crc_final.py` - CRC verification (74-byte coverage, correct)
- `verify_crc_correct.py` - Alternative CRC verification (72-byte coverage)
- `verify_crc.py` - Original CRC verification script

**Shell Scripts:**
- `compile_work_lib.sh` - Compiles all VHDL files in correct order (work library)
- `run_complete_test.sh` - Automated test workflow (generate → compile → simulate)

## reports_latest/ (4 files)

Latest test reports and analysis results:

- `CRC_VERIFICATION_REPORT.md` - Complete CRC verification results (all 5 packets PASS)
- `SPECTRAL_LEAKAGE_ANALYSIS.md` - Analysis of spectral leakage handling
- `README_SELFCONTAINED_TEST.md` - Self-contained test implementation guide
- `simulation_hex_output.log` - Latest simulation hex dump (76 bytes × 5 packets)

## Key Files in Root

- `c37 compliance.xpr` - Vivado project file
- `FOLDER_ORGANIZATION.md` - This file

## Usage Guide

### Running the Self-Contained 5-Cycle Test

1. **Generate VHDL test constants:**
   ```bash
   cd "/home/arunupscee/Desktop/xtortion/c37 compliance"
   python3 scripts/generate_test_constants.py
   ```

2. **Compile VHDL files:**
   ```bash
   bash scripts/compile_work_lib.sh
   ```

3. **Elaborate design:**
   ```bash
   xelab -debug typical -top tb_pmu_selfcontained_5cycles -snapshot pmu_selfcontained_sim xil_defaultlib.tb_pmu_selfcontained_5cycles
   ```

4. **Run simulation:**
   ```bash
   xsim pmu_selfcontained_sim -runall -log simulation_hex_output.log
   ```

### Analyzing Results

**Verify CRC checksums:**
```bash
python3 scripts/verify_crc_final.py
```

**Analyze phasor measurements:**
```bash
python3 scripts/analyze_pmu_output.py
```

### Opening in Vivado

```bash
vivado "c37 compliance.xpr" &
```

## Test Results Summary

**Latest 5-Cycle Test (Jan 29, 2026):**
- ✅ All 1500 samples injected successfully
- ✅ 5 packets captured (76 bytes each)
- ✅ All CRC checksums verified correct
- ✅ Magnitude values stable (<0.0003 variation)
- ✅ Phase balance perfect (120° 3-phase separation)
- ✅ Frequency: 50.00-50.02 Hz (excellent)

**CRC Verification:**
- Packet 1: 0x999E ✓
- Packet 2: 0x3423 ✓
- Packet 3: 0xF5F5 ✓
- Packet 4: 0xD314 ✓
- Packet 5: 0x4EA6 ✓

All packets pass CRC-CCITT verification (polynomial 0x1021, initial 0xFFFF, covers 74 bytes including reserved field).

## Files Deleted During Cleanup

The following unnecessary files were removed:

**Old Testbenches:** test_*.vhd, pmu_*_tb.vhd (except current ones)
**Old Logs:** test_results.log (13MB), mini_test.log, final_test.log, *.wdb files (~2MB total)
**Backup Files:** *_backup.vhd, *.backup.log, *.backup.jou
**Old Scripts:** compile_6ch.sh, compile_all.sh, run_mini_test.sh, etc.
**Old Reports:** 5CYCLE_TEST_RESULTS.md, CRC_DIAGNOSTIC_REPORT.md, TEST_RUN_SUMMARY.md, etc.
**Temporary Files:** xelab.log, xvhdl.log, xsim.log, vivado.jou, work-obj93.cf

**Total Space Saved:** ~18 MB

## Notes

- All VHDL modules are VHDL-93 compatible (no VHDL-2008 features)
- Fixed-point formats: Q16.16 (frequency), Q16.15 (magnitude), Q2.13 (phase), Q1.15 (coefficients)
- Target device: Xilinx ZCU106 FPGA
- ADC sample rate: 15 kHz
- DFT size: 256 points
- Grid frequency: ~50 Hz (45-55 Hz tracking range)
- Packet format: IEEE C37.118-2011 compliant

## References

- IEEE Std C37.118-2011: IEEE Standard for Synchrophasor Measurements for Power Systems
- IEEE Std C37.118.2-2011: IEEE Standard for Synchrophasor Data Transfer for Power Systems
- CRC-CCITT: ITU-T Recommendation V.41

---

**Last Updated:** January 29, 2026
**Project Status:** Implementation Complete, All Tests Passing
