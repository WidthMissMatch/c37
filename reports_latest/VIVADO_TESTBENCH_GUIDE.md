# Vivado PMU Testbench Guide

## Problem Summary

**Issue:** Waveform shows no output when simulating PMU testbenches in Vivado.

**Root Cause:** The PMU system requires **512+ input samples** before producing the first output packet because:
1. Circular buffer needs 512 samples to fill
2. Resampler needs time to lock to frequency
3. DFT requires 256 samples per cycle
4. Packet formatter waits for complete phasor data

**Your simulation with 300 samples:** Not enough! Zero packets output.
**Required:** Minimum 600 samples (2 cycles) for reliable first packet output.

---

## Available Testbenches

### 1. **tb_pmu_fast_hex.vhd** ⭐ **RECOMMENDED FOR VIVADO**

**Best for:** Vivado GUI simulation with waveform + console hex output

**Features:**
- Injects 600 samples (2 power cycles)
- Displays complete 76-byte packet in hex on TCL console
- Fast enough for Vivado GUI (~40ms simulation time)
- Clear observable signals for waveform

**How to use:**
```tcl
# In Vivado TCL console
set_property top tb_pmu_fast_hex [get_filesets sim_1]
launch_simulation

# Add key signals to waveform
add_wave {{/tb_pmu_fast_hex/sample_count}}
add_wave {{/tb_pmu_fast_hex/s_axis_tvalid}}
add_wave {{/tb_pmu_fast_hex/m_axis_tvalid}}
add_wave {{/tb_pmu_fast_hex/m_axis_tdata}}
add_wave {{/tb_pmu_fast_hex/m_axis_tlast}}
add_wave {{/tb_pmu_fast_hex/packet_captured}}

# Run simulation (45ms should be enough)
run 45ms

# Check TCL console for hex output
```

**Expected Output on TCL Console:**
```
========================================
OUTPUT PACKET (76 BYTES = 19 WORDS)
========================================
Byte  0- 3: AA 01 00 4C  (SYNC + FrameSize)
Byte  4- 7: 00 01 00 00  (IDCODE + SOC[31:16])
...
Byte 72-75: XX XX 00 00  (CRC + Reserved)
========================================
```

---

### 2. **tb_pmu_selfcontained_5cycles.vhd**

**Best for:** Command-line simulation, comprehensive testing

**Features:**
- Injects 1500 samples (5 power cycles)
- Captures and displays ALL 5 output packets
- Complete 76-byte hex dump for each packet
- Hardcoded test data (no CSV file needed)

**How to use:**
```bash
cd "/home/arunupscee/Desktop/xtortion/c37 compliance"

# Compile
bash scripts/compile_work_lib.sh

# Elaborate
xelab -debug typical -top tb_pmu_selfcontained_5cycles \
      -snapshot pmu_selfcontained_sim \
      work.tb_pmu_selfcontained_5cycles

# Run (takes ~2 minutes)
xsim pmu_selfcontained_sim -runall -log test_output.log

# View results
cat test_output.log | grep -A 100 "OUTPUT PACKET HEX DUMP"
```

**Note:** This takes 120ms simulation time (~2 min real-time). Not ideal for interactive Vivado GUI use.

---

### 3. **tb_pmu_simple_1cycle.vhd** ❌ **NOT RECOMMENDED**

**Issue:** Only injects 300 samples - **NOT ENOUGH** for packet output!

**Result:** `Total packets captured: 0`

**Do NOT use this testbench** - it was the cause of your "no output" problem.

---

## How to See Output in Vivado Waveform

The output is there, but you need to know **where and when** to look:

### Step 1: Add Critical Signals to Waveform

After launching simulation, add these signals:

```tcl
# Input tracking
add_wave {{/tb_pmu_fast_hex/sample_count}}
add_wave {{/tb_pmu_fast_hex/s_axis_tvalid}}
add_wave {{/tb_pmu_fast_hex/s_axis_tdata}}

# Output tracking
add_wave {{/tb_pmu_fast_hex/m_axis_tvalid}}
add_wave {{/tb_pmu_fast_hex/m_axis_tdata}}
add_wave {{/tb_pmu_fast_hex/m_axis_tlast}}
add_wave {{/tb_pmu_fast_hex/word_idx}}

# Packet capture flag
add_wave {{/tb_pmu_fast_hex/packet_captured}}

# Status signals
add_wave {{/tb_pmu_fast_hex/sync_locked}}
add_wave {{/tb_pmu_fast_hex/system_ready}}
add_wave {{/tb_pmu_fast_hex/processing_active}}
```

### Step 2: Run Long Enough

```tcl
run 45ms
```

**Why so long?**
- 600 samples × 66.67 µs per sample = 40ms
- Plus 2-5ms for processing
- Total: ~45ms

### Step 3: Find the Output in Waveform

1. **Look at `sample_count`** - should reach 600
2. **Find when `m_axis_tvalid` goes high** - this is output activity
3. **Zoom in on `m_axis_tdata`** when `m_axis_tvalid=1` to see packet words
4. **Look for `m_axis_tlast` pulses** - marks end of 76-byte packet (19 words)
5. **Check `packet_captured`** - goes TRUE when packet is stored

**Timeline:**
- 0-100ns: Reset
- 100ns-40ms: Sample injection (`s_axis_tvalid` pulsing at 15 kHz)
- ~20-40ms: First packet output starts (`m_axis_tvalid` goes high)
- `m_axis_tdata` shows 19 consecutive words (76 bytes)
- `m_axis_tlast` pulses on word 19

---

## Vivado GUI Step-by-Step

### Method A: Using Existing Project

1. **Open project:**
   ```bash
   cd "/home/arunupscee/Desktop/xtortion/c37 compliance"
   vivado "c37 compliance.xpr" &
   ```

2. **Set testbench as top:**
   - Simulation Sources → Right-click `tb_pmu_fast_hex` → Set as Top
   - OR in TCL console:
     ```tcl
     set_property top tb_pmu_fast_hex [get_filesets sim_1]
     ```

3. **Launch simulation:**
   - Flow Navigator → Run Simulation → Run Behavioral Simulation
   - OR in TCL console:
     ```tcl
     launch_simulation
     ```

4. **Add signals** (see Step 1 above)

5. **Run:**
   ```tcl
   run 45ms
   ```

6. **View results:**
   - Check TCL console for hex dump
   - Zoom to fit waveform, look for `m_axis_tvalid` activity

### Method B: Fresh Simulation

1. **Compile testbench:**
   ```bash
   cd "/home/arunupscee/Desktop/xtortion/c37 compliance"
   xvhdl testbenches/tb_pmu_fast_hex.vhd
   ```

2. **Elaborate:**
   ```bash
   xelab -debug typical -top tb_pmu_fast_hex \
         -snapshot pmu_fast_hex_sim \
         work.tb_pmu_fast_hex
   ```

3. **Run in xsim:**
   ```bash
   xsim pmu_fast_hex_sim -gui
   ```

4. **In xsim GUI:**
   - Add signals (see list above)
   - Run 45ms
   - Check console for hex output

---

## Understanding the Packet Output

### IEEE C37.118 Packet Structure (76 bytes)

| Byte Range | Field | Description |
|------------|-------|-------------|
| 0-3 | SYNC + FrameSize | `AA 01 00 4C` |
| 4-7 | IDCODE + SOC[31:16] | PMU ID + timestamp |
| 8-11 | SOC[15:0] + Reserved | Timestamp lower + padding |
| 12-15 | STAT + Reserved | Status flags |
| 16-19 | CH1 Magnitude | Phasor magnitude (Q16.15) |
| 20-23 | Padding + CH1 Phase | Phase angle (Q2.13) |
| 24-27 | CH2 Magnitude | Channel 2 phasor |
| 28-31 | Padding + CH2 Phase | |
| 32-35 | CH3 Magnitude | Channel 3 phasor |
| 36-39 | Padding + CH3 Phase | |
| 40-43 | CH4 Magnitude | Channel 4 phasor |
| 44-47 | Padding + CH4 Phase | |
| 48-51 | CH5 Magnitude | Channel 5 phasor |
| 52-55 | Padding + CH5 Phase | |
| 56-59 | CH6 Magnitude | Channel 6 phasor |
| 60-63 | Padding + CH6 Phase | |
| 64-67 | Frequency | Grid frequency (Q16.16, Hz) |
| 68-71 | ROCOF | Rate of change of freq (Hz/s) |
| 72-75 | CRC + Reserved | CRC-CCITT checksum |

**Output Format:** 32-bit words via AXI Stream
- 76 bytes ÷ 4 bytes/word = **19 words per packet**
- Last word has `m_axis_tlast = '1'`

---

## Troubleshooting

### "No output in waveform"

**Check:**
1. Did simulation run long enough? (need 45ms minimum)
2. Is `sample_count` reaching 600? (if not, input injection stalled)
3. Is `m_axis_tvalid` going high at any point? (if no, system not producing output)
4. Did you add `m_axis_tdata` and `m_axis_tvalid` to waveform?
5. Are you zoomed out too far? (zoom in around 20-40ms timeframe)

### "Packets captured: 0"

**Cause:** Not enough input samples!

**Fix:** Use `tb_pmu_fast_hex.vhd` (600 samples) or `tb_pmu_selfcontained_5cycles.vhd` (1500 samples).

### "Simulation takes forever"

**Expected:**
- 300 samples = 20ms sim = 30-60 sec real-time
- 600 samples = 40ms sim = 60-120 sec real-time
- 1500 samples = 100ms sim = 2-3 min real-time

**Solution:** Be patient OR reduce sample count (but keep ≥600 for output)

### "Hex output not showing in TCL console"

**Check:**
1. Did simulation complete? (look for "TEST COMPLETE" message)
2. Scroll up in TCL console - hex dump appears after sample injection
3. Try `run all` instead of `run 45ms` to ensure display process runs

---

## Simulation Performance Tips

### Faster Simulations

1. **Use smaller sample counts:**
   - Minimum 600 for first packet
   - Use 900 for 3 packets
   - Only use 1500 (5 cycles) when necessary

2. **Disable waveform recording:**
   ```tcl
   close_wave_config
   run 45ms
   # Much faster without waveform updates
   ```

3. **Use command-line xsim:**
   ```bash
   xsim pmu_fast_hex_sim -runall -log output.log
   # No GUI overhead
   ```

### View Waveform After Completion

```tcl
# Run without waveform first
run 45ms

# Then add signals and restart
restart
add_wave {{/tb_pmu_fast_hex/m_axis_tdata}}
add_wave {{/tb_pmu_fast_hex/m_axis_tvalid}}
add_wave {{/tb_pmu_fast_hex/m_axis_tlast}}
run 45ms
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Open Vivado | `vivado "c37 compliance.xpr" &` |
| Set testbench | `set_property top tb_pmu_fast_hex [get_filesets sim_1]` |
| Launch sim | `launch_simulation` |
| Run simulation | `run 45ms` |
| Restart | `restart` |
| Close sim | `close_sim` |
| Zoom to fit | `WaveformWindow → View → Zoom Fit` |

---

## Summary

✅ **Use `tb_pmu_fast_hex.vhd` in Vivado GUI** - best balance of speed and output

✅ **Run for 45ms minimum** - packet output happens around 20-40ms

✅ **Check TCL console for hex dump** - don't just look at waveform

✅ **Add key signals to waveform** - `m_axis_tdata`, `m_axis_tvalid`, `m_axis_tlast`

❌ **Don't use tb_pmu_simple_1cycle.vhd** - 300 samples not enough for output

✅ **For full testing, use command-line** - `tb_pmu_selfcontained_5cycles.vhd` with xsim

---

**Last Updated:** January 29, 2026
**Tested with:** Vivado 2025.1, ZCU106 target
