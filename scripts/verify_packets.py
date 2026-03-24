#!/usr/bin/env python3
"""
Verify CRC, frequency, and magnitude of output packets.
Reimplements the CRC-CCITT from crc_ccitt_c37118.vhd in Python.
"""
import sys
import os

def crc_ccitt_c37118(data_bytes):
    """
    CRC-CCITT as implemented in crc_ccitt_c37118.vhd:
      Polynomial: 0x1021
      Init: 0xFFFF
      No final XOR
      Bit-by-bit, MSB-first, byte-serial
    """
    crc = 0xFFFF
    for byte in data_bytes:
        crc ^= (byte << 8)  # XOR byte into upper 8 bits
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) & 0xFFFF) ^ 0x1021
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

def word_to_bytes(hex_str):
    """Convert 8-char hex word to 4 bytes (big-endian)."""
    val = int(hex_str, 16)
    return [
        (val >> 24) & 0xFF,
        (val >> 16) & 0xFF,
        (val >> 8) & 0xFF,
        val & 0xFF,
    ]

def q16_15(val):
    return val / 32768.0

def q16_16(val):
    return val / 65536.0

def q16_16_signed(val):
    if val & 0x80000000:
        val -= 0x100000000
    return val / 65536.0

def q2_13_signed(val16):
    if val16 & 0x8000:
        val16 -= 0x10000
    return val16 / 8192.0

def main():
    hex_file = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "sim_output", "output_packets_hex.txt")
    if len(sys.argv) > 1:
        hex_file = sys.argv[1]

    with open(hex_file) as f:
        lines = [l.strip() for l in f if l.strip()]

    print("=" * 110)
    print("PACKET VERIFICATION: CRC + Frequency + Magnitude")
    print("=" * 110)
    print(f"Packets: {len(lines)}")
    print()

    all_crc_ok = True
    all_freq_ok = True

    for pkt_num, line in enumerate(lines, 1):
        words_hex = line.split()
        words_int = [int(w, 16) for w in words_hex]

        # ----- CRC verification -----
        # CRC covers words 0-17 (72 bytes) + 2 reserved bytes (upper 16 of word 18)
        data_bytes = []
        for w in range(18):
            data_bytes.extend(word_to_bytes(words_hex[w]))
        # Add 2 reserved bytes (upper 16 bits of word 18 = 0x0000)
        data_bytes.append(0x00)
        data_bytes.append(0x00)
        # Total: 74 bytes

        computed_crc = crc_ccitt_c37118(data_bytes)
        packet_crc = words_int[18] & 0xFFFF
        crc_ok = (computed_crc == packet_crc)
        if not crc_ok:
            all_crc_ok = False

        # ----- Frequency -----
        freq_raw = words_int[6]
        freq_hz = q16_16(freq_raw)

        # After settling (pkt >= 4), expect 50.0 Hz
        freq_ok = True
        if pkt_num >= 4:
            if abs(freq_hz - 50.0) > 0.01:
                freq_ok = False
                all_freq_ok = False

        # ----- ROCOF -----
        rocof_raw = words_int[7]
        rocof_val = q16_16_signed(rocof_raw)

        # ----- Magnitudes (all 6 channels) -----
        ch_mags = []
        ch_phases_deg = []
        # Ch1: word 4 = mag, word 5 = phase
        ch_mags.append(q16_15(words_int[4]))
        ch_phases_deg.append(q2_13_signed(words_int[5] & 0xFFFF) * 180.0 / 3.141592653589793)
        # Ch2-6: mag at even words 8,10,12,14,16; phase at odd 9,11,13,15,17
        for ch in range(2, 7):
            mi = 6 + (ch - 1) * 2
            pi = 7 + (ch - 1) * 2
            ch_mags.append(q16_15(words_int[mi]))
            ch_phases_deg.append(q2_13_signed(words_int[pi] & 0xFFFF) * 180.0 / 3.141592653589793)

        # V/I ratio (Ch1/Ch4)
        vi_ratio = ch_mags[0] / ch_mags[3] if ch_mags[3] > 0 else 0

        # ----- Print -----
        crc_str = "OK" if crc_ok else f"MISMATCH (got 0x{packet_crc:04X}, expected 0x{computed_crc:04X})"
        freq_str = f"{freq_hz:.4f} Hz"
        if pkt_num < 4:
            freq_str += " (settling)"

        print(f"--- Packet #{pkt_num} ---")
        print(f"  SYNC+FRAME: 0x{words_int[0]:08X}  {'OK' if words_int[0] == 0xAA01004C else 'BAD'}")
        print(f"  CRC:        0x{packet_crc:04X}  computed=0x{computed_crc:04X}  {crc_str}")
        print(f"  Frequency:  {freq_str}")
        print(f"  ROCOF:      {rocof_val:+.4f} Hz/s")
        print(f"  Magnitudes: V1={ch_mags[0]:.4f}  V2={ch_mags[1]:.4f}  V3={ch_mags[2]:.4f}"
              f"  I1={ch_mags[3]:.4f}  I2={ch_mags[4]:.4f}  I3={ch_mags[5]:.4f}")
        print(f"  Phases(deg): V1={ch_phases_deg[0]:+.2f}  V2={ch_phases_deg[1]:+.2f}  V3={ch_phases_deg[2]:+.2f}"
              f"  I1={ch_phases_deg[3]:+.2f}  I2={ch_phases_deg[4]:+.2f}  I3={ch_phases_deg[5]:+.2f}")
        print(f"  V/I ratio:  {vi_ratio:.6f}")
        print()

    # ----- Summary -----
    print("=" * 110)
    print("SUMMARY")
    print("=" * 110)

    # CRC
    if all_crc_ok:
        print("[PASS] CRC: All 10 packets have correct CRC-CCITT")
    else:
        print("[FAIL] CRC: Some packets have CRC mismatch")

    # Frequency (packets 4-10 should be exactly 50 Hz)
    settled_freqs = []
    for i, line in enumerate(lines):
        words = [int(w, 16) for w in line.split()]
        f = q16_16(words[6])
        if i >= 3:  # packets 4-10 (0-indexed i>=3)
            settled_freqs.append(f)

    if settled_freqs:
        avg_f = sum(settled_freqs) / len(settled_freqs)
        max_err = max(abs(f - 50.0) for f in settled_freqs)
        print(f"[{'PASS' if max_err < 0.01 else 'FAIL'}] Frequency: "
              f"settled avg={avg_f:.6f} Hz, max error={max_err:.6f} Hz")

    # Magnitude consistency
    mags_ch1 = []
    mags_ch4 = []
    for line in lines:
        words = [int(w, 16) for w in line.split()]
        mags_ch1.append(q16_15(words[4]))
        mags_ch4.append(q16_15(words[12]))

    ch1_std = (sum((m - sum(mags_ch1)/len(mags_ch1))**2 for m in mags_ch1) / len(mags_ch1)) ** 0.5
    ch4_std = (sum((m - sum(mags_ch4)/len(mags_ch4))**2 for m in mags_ch4) / len(mags_ch4)) ** 0.5
    vi_ratio_avg = sum(m1/m4 for m1, m4 in zip(mags_ch1, mags_ch4)) / len(mags_ch1)

    print(f"[{'PASS' if ch1_std < 0.01 else 'FAIL'}] Magnitude stability: "
          f"Ch1 mean={sum(mags_ch1)/len(mags_ch1):.4f}, std={ch1_std:.6f}")
    print(f"[{'PASS' if abs(vi_ratio_avg - 2.0) < 0.01 else 'FAIL'}] V/I ratio: "
          f"{vi_ratio_avg:.6f} (expected 2.0)")

    print("=" * 110)


if __name__ == "__main__":
    main()
