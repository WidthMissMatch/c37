#!/usr/bin/env python3
"""
PMU Harmonic Test Data Generator

Generates 3-phase V+I waveforms with configurable harmonics, packed as
128-bit AXI-Stream packets for the pmu_system_complete_256 testbench.

Outputs:
  1. test_data_harmonics_hex.txt   -- one 32-char hex string per line (3000 lines)
  2. test_data_harmonics_constants.vhd -- VHDL package with constant array

Usage:
  python3 generate_harmonic_test_data.py              # with harmonics
  python3 generate_harmonic_test_data.py --no-harmonics  # pure sine baseline
"""
import argparse
import math
import os
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SAMPLE_RATE      = 15000
GRID_FREQ        = 50.0
SAMPLES_PER_CYCLE = int(SAMPLE_RATE / GRID_FREQ)   # 300
NUM_CYCLES       = 10
TOTAL_SAMPLES    = SAMPLES_PER_CYCLE * NUM_CYCLES   # 3000

V_AMPLITUDE      = 10000
I_AMPLITUDE      = 5000

# 3-phase offsets (radians): A=0, B=-120deg, C=+120deg
PHASE_OFFSETS = [0.0, -2.0 * math.pi / 3.0, 2.0 * math.pi / 3.0]

# Harmonic definitions: (harmonic_order, relative_amplitude)
V_HARMONICS = [(3, 0.05), (5, 0.03), (7, 0.02)]
I_HARMONICS = [(3, 0.08), (5, 0.05), (7, 0.03)]

# Paths (relative to project root = parent of scripts/)
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
HEX_OUTPUT   = os.path.join(PROJECT_ROOT, "test_data_harmonics_hex.txt")
VHDL_OUTPUT  = os.path.join(PROJECT_ROOT, "test_data_harmonics_constants.vhd")


# ---------------------------------------------------------------------------
# Packet helpers (from generate_test_constants.py)
# ---------------------------------------------------------------------------
def signed16_to_unsigned_hex(value):
    """Convert signed 16-bit integer to unsigned hex (two's complement)"""
    if value < 0:
        unsigned = (1 << 16) + value
    else:
        unsigned = value
    return unsigned & 0xFFFF


def create_128bit_packet(ch0, ch1, ch2, ch3, ch4, ch5):
    """
    Pack 6 channels into 128-bit packet.
    [127:120] = 0xAA (SYNC)
    [119:104] = Ch0   [103:88] = Ch1   [87:72] = Ch2
    [71:56]   = Ch3   [55:40]  = Ch4   [39:24] = Ch5
    [23:16]   = 0x55 (CHECK)   [15:0] = 0x0000
    """
    packet = 0
    packet |= (0xAA << 120)
    packet |= (signed16_to_unsigned_hex(ch0) << 104)
    packet |= (signed16_to_unsigned_hex(ch1) << 88)
    packet |= (signed16_to_unsigned_hex(ch2) << 72)
    packet |= (signed16_to_unsigned_hex(ch3) << 56)
    packet |= (signed16_to_unsigned_hex(ch4) << 40)
    packet |= (signed16_to_unsigned_hex(ch5) << 24)
    packet |= (0x55 << 16)
    packet |= 0x0000
    return packet


def saturate16(val):
    """Saturate a float to signed 16-bit range and return int."""
    if val >= 32767.0:
        return 32767
    elif val <= -32768.0:
        return -32768
    else:
        return int(round(val))


# ---------------------------------------------------------------------------
# Waveform generation
# ---------------------------------------------------------------------------
def generate_samples(use_harmonics):
    """Generate 3000 six-channel samples (V_A, V_B, V_C, I_A, I_B, I_C)."""
    samples = []

    for n in range(TOTAL_SAMPLES):
        theta = 2.0 * math.pi * n / SAMPLES_PER_CYCLE   # base angle

        channels = []

        # --- Voltage channels (3-phase) ---
        for phi in PHASE_OFFSETS:
            v = V_AMPLITUDE * math.sin(theta + phi)
            if use_harmonics:
                for h, amp_frac in V_HARMONICS:
                    v += V_AMPLITUDE * amp_frac * math.sin(h * (theta + phi))
            channels.append(saturate16(v))

        # --- Current channels (3-phase) ---
        for phi in PHASE_OFFSETS:
            i = I_AMPLITUDE * math.sin(theta + phi)
            if use_harmonics:
                for h, amp_frac in I_HARMONICS:
                    i += I_AMPLITUDE * amp_frac * math.sin(h * (theta + phi))
            channels.append(saturate16(i))

        samples.append(channels)

    return samples


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------
def write_hex_file(samples, path):
    """Write one 32-char hex line per sample (128-bit packet)."""
    with open(path, 'w') as f:
        for ch0, ch1, ch2, ch3, ch4, ch5 in samples:
            pkt = create_128bit_packet(ch0, ch1, ch2, ch3, ch4, ch5)
            f.write(f"{pkt:032X}\n")
    print(f"  Wrote {len(samples)} lines to {path}")


def write_vhdl_package(samples, path, use_harmonics):
    """Write a VHDL-93 package with a constant array of 128-bit packets."""
    label = "harmonic" if use_harmonics else "pure-sine"
    with open(path, 'w') as f:
        f.write(f"-- Auto-generated VHDL Package ({label} test data)\n")
        f.write(f"-- {len(samples)} samples = {len(samples) // SAMPLES_PER_CYCLE} power cycles\n")
        f.write(f"-- Sample rate: {SAMPLE_RATE} Hz, Grid freq: {GRID_FREQ} Hz\n")
        if use_harmonics:
            f.write(f"-- Voltage harmonics: {V_HARMONICS}\n")
            f.write(f"-- Current harmonics: {I_HARMONICS}\n")
        else:
            f.write("-- Pure sine (no harmonics)\n")
        f.write("-- VHDL-93 Compatible\n\n")
        f.write("library IEEE;\n")
        f.write("use IEEE.STD_LOGIC_1164.ALL;\n\n")
        f.write("package test_data_harmonics_pkg is\n\n")
        f.write(f"    constant NUM_TEST_SAMPLES : integer := {len(samples)};\n\n")
        f.write("    type axi_packet_array is array (0 to NUM_TEST_SAMPLES-1) "
                "of std_logic_vector(127 downto 0);\n\n")
        f.write("    constant TEST_PACKETS : axi_packet_array := (\n")

        for idx, (ch0, ch1, ch2, ch3, ch4, ch5) in enumerate(samples):
            pkt = create_128bit_packet(ch0, ch1, ch2, ch3, ch4, ch5)
            hex_str = f"{pkt:032X}"

            if idx % SAMPLES_PER_CYCLE == 0:
                cycle_num = idx // SAMPLES_PER_CYCLE + 1
                f.write(f"        -- Cycle {cycle_num} starts (sample {idx})\n")

            comma = "," if idx < len(samples) - 1 else ""
            f.write(f'        x"{hex_str}"{comma}\n')

        f.write("    );\n\n")
        f.write("end package test_data_harmonics_pkg;\n")

    print(f"  Wrote VHDL package to {path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="PMU Harmonic Test Data Generator")
    parser.add_argument("--no-harmonics", action="store_true",
                        help="Generate pure sine waves (no harmonics) for baseline comparison")
    args = parser.parse_args()

    use_harmonics = not args.no_harmonics
    mode = "WITH harmonics" if use_harmonics else "PURE SINE (no harmonics)"

    print("=" * 70)
    print("PMU Harmonic Test Data Generator")
    print("=" * 70)
    print(f"  Mode:              {mode}")
    print(f"  Sample rate:       {SAMPLE_RATE} Hz")
    print(f"  Grid frequency:    {GRID_FREQ} Hz")
    print(f"  Samples/cycle:     {SAMPLES_PER_CYCLE}")
    print(f"  Num cycles:        {NUM_CYCLES}")
    print(f"  Total samples:     {TOTAL_SAMPLES}")
    print(f"  V amplitude:       {V_AMPLITUDE}")
    print(f"  I amplitude:       {I_AMPLITUDE}")
    if use_harmonics:
        print(f"  V harmonics:       3rd@5%, 5th@3%, 7th@2%")
        print(f"  I harmonics:       3rd@8%, 5th@5%, 7th@3%")
    print()

    # Generate samples
    print("Generating waveform samples...")
    samples = generate_samples(use_harmonics)

    # Quick sanity: print first sample
    s = samples[0]
    print(f"  Sample 0: V=({s[0]:+6d}, {s[1]:+6d}, {s[2]:+6d})  "
          f"I=({s[3]:+6d}, {s[4]:+6d}, {s[5]:+6d})")
    # Print a mid-cycle sample
    mid = SAMPLES_PER_CYCLE // 4
    s = samples[mid]
    print(f"  Sample {mid}: V=({s[0]:+6d}, {s[1]:+6d}, {s[2]:+6d})  "
          f"I=({s[3]:+6d}, {s[4]:+6d}, {s[5]:+6d})")
    print()

    # Write outputs
    print("Writing output files...")
    write_hex_file(samples, HEX_OUTPUT)
    write_vhdl_package(samples, VHDL_OUTPUT, use_harmonics)

    print()
    print("=" * 70)
    print("Generation complete!")
    print(f"  Hex file:  {HEX_OUTPUT}")
    print(f"  VHDL pkg:  {VHDL_OUTPUT}")
    print("=" * 70)


if __name__ == "__main__":
    main()
