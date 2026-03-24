#!/usr/bin/env python3
"""
PMU Harmonic Test Output Analyzer

Reads hex output packets from sim_output/output_packets_hex.txt and
decodes C37.118 fields: magnitude, phase, frequency, ROCOF.

Usage:
  python3 analyze_harmonic_output.py [path_to_hex_file]
  python3 analyze_harmonic_output.py sim_output/output_packets_hex.txt
"""
import math
import sys
import os

# ---------------------------------------------------------------------------
# Default path
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_HEX_FILE = os.path.join(PROJECT_ROOT, "sim_output", "output_packets_hex.txt")

# ---------------------------------------------------------------------------
# Packet word layout (from c37118_packet_formatter_6ch.vhd lines 251-309)
# ---------------------------------------------------------------------------
# Word  0: SYNC(0xAA01) + FRAMESIZE(0x004C)
# Word  1: IDCODE(16b)  + TIMESTAMP_H(16b)
# Word  2: TIMESTAMP_L(16b) + Reserved(16b)
# Word  3: STAT(16b) + Reserved(16b)
# Word  4: Ch1 Magnitude (32-bit, Q16.15)
# Word  5: 0x0000 & Ch1 Phase (lower 16 bits, Q2.13 radians)
# Word  6: Ch1 Frequency (32-bit, Q16.16 Hz)
# Word  7: Ch1 ROCOF (32-bit, Q16.16 Hz/s)
# Word  8: Ch2 Magnitude      Word  9: 0x0000 & Ch2 Phase
# Word 10: Ch3 Magnitude      Word 11: 0x0000 & Ch3 Phase
# Word 12: Ch4 Magnitude      Word 13: 0x0000 & Ch4 Phase
# Word 14: Ch5 Magnitude      Word 15: 0x0000 & Ch5 Phase
# Word 16: Ch6 Magnitude      Word 17: 0x0000 & Ch6 Phase
# Word 18: 0x0000 & CRC (lower 16 bits)

IDX_CH1_MAG   = 4
IDX_CH1_PHASE = 5
IDX_CH1_FREQ  = 6
IDX_CH1_ROCOF = 7

# Ch2-6: magnitude at even indices 8,10,12,14,16; phase at odd 9,11,13,15,17
def ch_mag_idx(ch):
    """Return word index for channel magnitude (ch=1..6)."""
    if ch == 1:
        return 4
    return 6 + (ch - 1) * 2   # ch2->8, ch3->10, ch4->12, ch5->14, ch6->16

def ch_phase_idx(ch):
    """Return word index for channel phase (ch=1..6)."""
    if ch == 1:
        return 5
    return 7 + (ch - 1) * 2   # ch2->9, ch3->11, ch4->13, ch5->15, ch6->17


# ---------------------------------------------------------------------------
# Decoding functions (from analyze_pmu_output.py)
# ---------------------------------------------------------------------------
def q16_15_to_float(hex_val):
    """Convert 32-bit Q16.15 magnitude to float."""
    return hex_val / (2**15)


def q2_13_to_radians(hex_val_16bit):
    """Convert 16-bit Q2.13 phase to radians (signed)."""
    if hex_val_16bit & 0x8000:
        hex_val_16bit -= 0x10000
    return hex_val_16bit / (2**13)


def q16_16_to_float(hex_val):
    """Convert 32-bit Q16.16 to float (frequency in Hz, ROCOF in Hz/s)."""
    # Treat as unsigned for frequency (always positive for normal operation)
    return hex_val / (2**16)


def q16_16_signed(hex_val):
    """Convert 32-bit Q16.16 to signed float (for ROCOF which can be negative)."""
    if hex_val & 0x80000000:
        hex_val -= 0x100000000
    return hex_val / (2**16)


# ---------------------------------------------------------------------------
# File reader
# ---------------------------------------------------------------------------
def read_packets(filepath):
    """Read hex file: one line per packet, 19 space-separated 8-char hex words."""
    packets = []
    with open(filepath, 'r') as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            words_hex = line.split()
            if len(words_hex) < 19:
                print(f"WARNING: Line {line_no} has {len(words_hex)} words (expected 19), skipping")
                continue
            words = [int(w, 16) for w in words_hex[:19]]
            packets.append(words)
    return packets


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------
def decode_packet(words):
    """Decode a single packet into a dict of channel values."""
    result = {}

    # Header
    result['sync_framesize'] = words[0]
    result['valid'] = (words[0] == 0xAA01004C)

    # Ch1 with frequency and ROCOF
    result['ch1_mag'] = q16_15_to_float(words[IDX_CH1_MAG])
    result['ch1_phase_rad'] = q2_13_to_radians(words[IDX_CH1_PHASE] & 0xFFFF)
    result['ch1_phase_deg'] = result['ch1_phase_rad'] * 180.0 / math.pi
    result['ch1_freq'] = q16_16_to_float(words[IDX_CH1_FREQ])
    result['ch1_rocof'] = q16_16_signed(words[IDX_CH1_ROCOF])

    # Ch2-6
    for ch in range(2, 7):
        mi = ch_mag_idx(ch)
        pi = ch_phase_idx(ch)
        mag = q16_15_to_float(words[mi])
        phase_rad = q2_13_to_radians(words[pi] & 0xFFFF)
        phase_deg = phase_rad * 180.0 / math.pi
        result[f'ch{ch}_mag'] = mag
        result[f'ch{ch}_phase_rad'] = phase_rad
        result[f'ch{ch}_phase_deg'] = phase_deg

    # CRC
    result['crc'] = words[18] & 0xFFFF

    return result


def main():
    # Determine input file
    if len(sys.argv) > 1:
        hex_file = sys.argv[1]
    else:
        hex_file = DEFAULT_HEX_FILE

    if not os.path.exists(hex_file):
        print(f"ERROR: File not found: {hex_file}")
        print(f"Usage: python3 {sys.argv[0]} [path_to_hex_file]")
        sys.exit(1)

    print("=" * 100)
    print("PMU HARMONIC TEST OUTPUT ANALYSIS")
    print("=" * 100)
    print(f"Input file: {hex_file}")
    print()

    packets_raw = read_packets(hex_file)
    print(f"Total packets read: {len(packets_raw)}")
    if len(packets_raw) == 0:
        print("ERROR: No valid packets found!")
        sys.exit(1)

    # Decode all packets
    decoded = [decode_packet(w) for w in packets_raw]

    # Check all packets start with correct SYNC+FRAMESIZE
    valid_count = sum(1 for d in decoded if d['valid'])
    print(f"Valid packets (SYNC=AA01004C): {valid_count}/{len(decoded)}")
    print()

    # -----------------------------------------------------------------------
    # Per-packet table
    # -----------------------------------------------------------------------
    print("-" * 100)
    print(f"{'Pkt':>4}  {'Ch1 Mag':>10}  {'Ch1 Phase':>10}  {'Ch1 Freq':>10}  "
          f"{'Ch1 ROCOF':>10}  {'Ch4 Mag':>10}  {'V/I Ratio':>10}")
    print("-" * 100)

    for i, d in enumerate(decoded):
        v_mag = d['ch1_mag']
        i_mag = d['ch4_mag']
        ratio = v_mag / i_mag if i_mag > 0.001 else float('inf')
        print(f"{i+1:4d}  {v_mag:10.4f}  {d['ch1_phase_deg']:+10.2f}  "
              f"{d['ch1_freq']:10.4f}  {d['ch1_rocof']:+10.4f}  "
              f"{i_mag:10.4f}  {ratio:10.4f}")
    print()

    # -----------------------------------------------------------------------
    # V/I magnitude ratio
    # -----------------------------------------------------------------------
    print("=" * 100)
    print("V/I MAGNITUDE RATIO (expected ~2.0 = 10000/5000)")
    print("=" * 100)
    ratios = []
    for d in decoded:
        for vch, ich in [(1, 4), (2, 5), (3, 6)]:
            v = d[f'ch{vch}_mag']
            i_val = d[f'ch{ich}_mag']
            if i_val > 0.001:
                ratios.append(v / i_val)
    if ratios:
        avg_ratio = sum(ratios) / len(ratios)
        print(f"  Average V/I ratio: {avg_ratio:.4f}")
        print(f"  Min: {min(ratios):.4f}  Max: {max(ratios):.4f}")
    print()

    # -----------------------------------------------------------------------
    # 3-phase balance (phase separation)
    # -----------------------------------------------------------------------
    print("=" * 100)
    print("3-PHASE BALANCE (expected ~120 deg separation)")
    print("=" * 100)
    print(f"{'Pkt':>4}  {'Ch1-Ch2 (deg)':>14}  {'Ch2-Ch3 (deg)':>14}  {'Ch1-Ch3 (deg)':>14}")
    print("-" * 60)

    phase_diffs_12 = []
    phase_diffs_23 = []
    for i, d in enumerate(decoded):
        p1 = d['ch1_phase_deg']
        p2 = d['ch2_phase_deg']
        p3 = d['ch3_phase_deg']
        diff12 = p1 - p2
        diff23 = p2 - p3
        diff13 = p1 - p3
        # Normalize to [-180, 180]
        while diff12 > 180: diff12 -= 360
        while diff12 < -180: diff12 += 360
        while diff23 > 180: diff23 -= 360
        while diff23 < -180: diff23 += 360
        while diff13 > 180: diff13 -= 360
        while diff13 < -180: diff13 += 360
        phase_diffs_12.append(abs(diff12))
        phase_diffs_23.append(abs(diff23))
        print(f"{i+1:4d}  {diff12:+14.2f}  {diff23:+14.2f}  {diff13:+14.2f}")
    print()

    # -----------------------------------------------------------------------
    # Frequency accuracy
    # -----------------------------------------------------------------------
    print("=" * 100)
    print("FREQUENCY ACCURACY (expected 50.0 Hz)")
    print("=" * 100)
    freqs = [d['ch1_freq'] for d in decoded]
    # Skip first packet (may not have settled)
    settled_freqs = freqs[1:] if len(freqs) > 1 else freqs

    if settled_freqs:
        avg_freq = sum(settled_freqs) / len(settled_freqs)
        freq_std = math.sqrt(sum((f - avg_freq)**2 for f in settled_freqs) / len(settled_freqs))
        print(f"  Packets analyzed: {len(settled_freqs)} (skipped first)")
        print(f"  Mean frequency:   {avg_freq:.6f} Hz")
        print(f"  Std deviation:    {freq_std:.6f} Hz")
        print(f"  Error from 50 Hz: {avg_freq - 50.0:+.6f} Hz")
        print(f"  Min: {min(settled_freqs):.6f}  Max: {max(settled_freqs):.6f}")
    print()

    # -----------------------------------------------------------------------
    # ROCOF
    # -----------------------------------------------------------------------
    print("=" * 100)
    print("ROCOF (expected ~0 for constant frequency input)")
    print("=" * 100)
    rocofs = [d['ch1_rocof'] for d in decoded]
    settled_rocofs = rocofs[1:] if len(rocofs) > 1 else rocofs
    if settled_rocofs:
        avg_rocof = sum(settled_rocofs) / len(settled_rocofs)
        print(f"  Mean ROCOF:  {avg_rocof:+.6f} Hz/s")
        print(f"  Min: {min(settled_rocofs):+.6f}  Max: {max(settled_rocofs):+.6f}")
    print()

    # -----------------------------------------------------------------------
    # Magnitude stability
    # -----------------------------------------------------------------------
    print("=" * 100)
    print("MAGNITUDE STABILITY")
    print("=" * 100)
    print(f"{'Channel':>8}  {'Mean':>12}  {'Std Dev':>12}  {'Min':>12}  {'Max':>12}")
    print("-" * 65)
    for ch in range(1, 7):
        mags = [d[f'ch{ch}_mag'] for d in decoded]
        avg_m = sum(mags) / len(mags)
        std_m = math.sqrt(sum((m - avg_m)**2 for m in mags) / len(mags))
        print(f"{'CH' + str(ch):>8}  {avg_m:12.4f}  {std_m:12.6f}  "
              f"{min(mags):12.4f}  {max(mags):12.4f}")
    print()

    # -----------------------------------------------------------------------
    # Verification checklist
    # -----------------------------------------------------------------------
    print("=" * 100)
    print("VERIFICATION CHECKLIST")
    print("=" * 100)

    checks = []

    # 1. File has 8+ packets
    checks.append(("8+ output packets", len(decoded) >= 8))

    # 2. All packets start with AA01004C
    checks.append(("All packets SYNC=AA01004C", valid_count == len(decoded)))

    # 3. Frequency ~50 Hz (within +/-0.5 Hz after settling)
    if settled_freqs:
        freq_ok = all(abs(f - 50.0) < 0.5 for f in settled_freqs)
        checks.append(("Frequency within +/-0.5 Hz of 50 Hz", freq_ok))

    # 4. V/I ratio ~2.0
    if ratios:
        ratio_ok = 1.5 < avg_ratio < 2.5
        checks.append(("V/I magnitude ratio ~2.0", ratio_ok))

    # 5. 3-phase separation ~120 deg
    if phase_diffs_12:
        settled_diffs = phase_diffs_12[1:]  # skip first
        if settled_diffs:
            phase_ok = all(abs(d - 120.0) < 15.0 for d in settled_diffs)
            checks.append(("3-phase separation ~120 deg", phase_ok))

    # 6. ROCOF near zero
    if settled_rocofs:
        rocof_ok = all(abs(r) < 5.0 for r in settled_rocofs)
        checks.append(("ROCOF near zero", rocof_ok))

    for desc, passed in checks:
        status = "PASS" if passed else "FAIL"
        marker = "+" if passed else "!"
        print(f"  [{marker}] {status:4s}  {desc}")

    all_pass = all(p for _, p in checks)
    print()
    print("=" * 100)
    if all_pass:
        print("OVERALL: ALL CHECKS PASSED")
    else:
        print("OVERALL: SOME CHECKS FAILED")
    print("=" * 100)

    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
