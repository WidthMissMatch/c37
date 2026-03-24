#!/usr/bin/env python3
"""
Analyze PMU output packets - extract and convert magnitude, phase, and frequency values
"""
import math

# Packet data extracted from simulation
packets = [
    {
        "packet": 1,
        "ch1_mag": "0011A454", "ch1_phase": "1971", "ch1_freq": "00000000",
        "ch2_mag": "0011A496", "ch2_phase": "D66F",
        "ch3_mag": "0011A5D0", "ch3_phase": "5C7B",
        "ch4_mag": "000E01E2", "ch4_phase": "0A03",
        "ch5_mag": "000E01A6", "ch5_phase": "591D",
        "ch6_mag": "000E01E9", "ch6_phase": "4D0B"
    },
    {
        "packet": 2,
        "ch1_mag": "0011A461", "ch1_phase": "1985", "ch1_freq": "00320000",
        "ch2_mag": "0011A498", "ch2_phase": "D681",
        "ch3_mag": "0011A5D8", "ch3_phase": "5C8D",
        "ch4_mag": "000E01FF", "ch4_phase": "0A15",
        "ch5_mag": "000E01AB", "ch5_phase": "5931",
        "ch6_mag": "000E01E3", "ch6_phase": "4D1F"
    },
    {
        "packet": 3,
        "ch1_mag": "0011A454", "ch1_phase": "1997", "ch1_freq": "003853BA",
        "ch2_mag": "0011A498", "ch2_phase": "D695",
        "ch3_mag": "0011A5D4", "ch3_phase": "5CA1",
        "ch4_mag": "000E01F2", "ch4_phase": "0A29",
        "ch5_mag": "000E019E", "ch5_phase": "5943",
        "ch6_mag": "000E01E3", "ch6_phase": "4D31"
    },
    {
        "packet": 4,
        "ch1_mag": "0011A459", "ch1_phase": "19AB", "ch1_freq": "003204F9",
        "ch2_mag": "0011A4A1", "ch2_phase": "D6A7",
        "ch3_mag": "0011A5D7", "ch3_phase": "5CB3",
        "ch4_mag": "000E01F1", "ch4_phase": "0A3D",
        "ch5_mag": "000E01A5", "ch5_phase": "5957",
        "ch6_mag": "000E01EE", "ch6_phase": "4D45"
    },
    {
        "packet": 5,
        "ch1_mag": "0011A451", "ch1_phase": "19BF", "ch1_freq": "0032047A",
        "ch2_mag": "0011A4A1", "ch2_phase": "D6BB",
        "ch3_mag": "0011A5D2", "ch3_phase": "5CC7",
        "ch4_mag": "000E01F7", "ch4_phase": "0A4F",
        "ch5_mag": "000E019F", "ch5_phase": "596B",
        "ch6_mag": "000E01F7", "ch6_phase": "4D57"
    }
]

def q16_15_to_float(hex_str):
    """Convert Q16.15 magnitude to float"""
    val = int(hex_str, 16)
    return val / (2**15)

def q2_13_to_radians(hex_str):
    """Convert Q2.13 phase to radians"""
    val = int(hex_str, 16)
    # Check if negative (bit 15 is sign bit for 16-bit value)
    if val & 0x8000:
        val = val - 0x10000
    return val / (2**13)

def radians_to_degrees(rad):
    """Convert radians to degrees"""
    return rad * 180.0 / math.pi

def q16_16_to_float(hex_str):
    """Convert Q16.16 frequency to Hz"""
    val = int(hex_str, 16)
    return val / (2**16)

print("=" * 100)
print("PMU OUTPUT ANALYSIS - All Packets")
print("=" * 100)
print()

# Summary statistics
all_mags = {f"CH{i}": [] for i in range(1, 7)}
all_phases = {f"CH{i}": [] for i in range(1, 7)}
all_freqs = []

for pkt in packets:
    print(f"{'='*100}")
    print(f"PACKET #{pkt['packet']}")
    print(f"{'='*100}")

    # CH1 Frequency (only in master channel)
    if pkt['ch1_freq']:
        freq_hz = q16_16_to_float(pkt['ch1_freq'])
        all_freqs.append(freq_hz)
        print(f"\nCH1 Frequency: 0x{pkt['ch1_freq']} = {freq_hz:.6f} Hz")

    print(f"\n{'Channel':<8} {'Magnitude (Hex)':<18} {'Magnitude':<15} {'Phase (Hex)':<15} {'Phase (rad)':<15} {'Phase (deg)':<15}")
    print(f"{'-'*100}")

    for ch in range(1, 7):
        mag_hex = pkt[f'ch{ch}_mag']
        phase_hex = pkt[f'ch{ch}_phase']

        mag = q16_15_to_float(mag_hex)
        phase_rad = q2_13_to_radians(phase_hex)
        phase_deg = radians_to_degrees(phase_rad)

        all_mags[f"CH{ch}"].append(mag)
        all_phases[f"CH{ch}"].append(phase_deg)

        print(f"CH{ch:<6} 0x{mag_hex:<16} {mag:<15.4f} 0x{phase_hex:<13} {phase_rad:<15.6f} {phase_deg:<15.2f}")

    print()

# Summary Statistics
print(f"\n{'='*100}")
print("SUMMARY STATISTICS")
print(f"{'='*100}")

print("\n--- FREQUENCY TRACKING (CH1 only) ---")
print(f"{'Packet':<10} {'Frequency (Hz)':<20} {'Error from 50 Hz':<20}")
print("-" * 50)
for i, freq in enumerate(all_freqs, start=1):
    error = freq - 50.0
    print(f"Packet {i:<3} {freq:<20.6f} {error:+.6f} Hz")

if len(all_freqs) > 1:
    avg_freq = sum(all_freqs) / len(all_freqs)
    print(f"\nAverage Frequency (Packets 2-5): {avg_freq:.6f} Hz")
    print(f"Deviation from 50 Hz: {avg_freq - 50.0:+.6f} Hz")

print("\n--- MAGNITUDE STATISTICS ---")
print(f"{'Channel':<10} {'Min':<12} {'Max':<12} {'Average':<12} {'Std Dev':<12}")
print("-" * 60)
for ch, values in all_mags.items():
    min_val = min(values)
    max_val = max(values)
    avg_val = sum(values) / len(values)
    std_dev = math.sqrt(sum((x - avg_val)**2 for x in values) / len(values))
    print(f"{ch:<10} {min_val:<12.4f} {max_val:<12.4f} {avg_val:<12.4f} {std_dev:<12.6f}")

print("\n--- PHASE STATISTICS (degrees) ---")
print(f"{'Channel':<10} {'Min':<12} {'Max':<12} {'Average':<12} {'Range':<12}")
print("-" * 60)
for ch, values in all_phases.items():
    min_val = min(values)
    max_val = max(values)
    avg_val = sum(values) / len(values)
    range_val = max_val - min_val
    print(f"{ch:<10} {min_val:<12.2f} {max_val:<12.2f} {avg_val:<12.2f} {range_val:<12.2f}")

print("\n--- PHASE DIFFERENCES (120° for balanced 3-phase) ---")
print("Expected: CH1-CH2 ≈ -120°, CH2-CH3 ≈ -120°, CH1-CH3 ≈ +120°")
print(f"{'Packet':<10} {'CH1-CH2':<15} {'CH2-CH3':<15} {'CH1-CH3':<15}")
print("-" * 55)
for i in range(len(packets)):
    ch1_phase = all_phases["CH1"][i]
    ch2_phase = all_phases["CH2"][i]
    ch3_phase = all_phases["CH3"][i]

    diff_12 = ch1_phase - ch2_phase
    diff_23 = ch2_phase - ch3_phase
    diff_13 = ch1_phase - ch3_phase

    print(f"Packet {i+1:<3} {diff_12:<15.2f} {diff_23:<15.2f} {diff_13:<15.2f}")

print("\n--- CHANNEL GROUPING ---")
print("Voltage Channels (CH1-3): Higher magnitude expected")
print(f"  Average: {sum(sum(all_mags[f'CH{i}']) for i in range(1,4)) / 15:.4f}")
print("Current Channels (CH4-6): Lower magnitude expected")
print(f"  Average: {sum(sum(all_mags[f'CH{i}']) for i in range(4,7)) / 15:.4f}")

print("\n" + "="*100)
print("VERIFICATION CHECKLIST")
print("="*100)

# Verification checks
checks = []

# Check 1: Frequency convergence
if len(all_freqs) >= 2:
    freq_converged = all(abs(f - 50.0) < 1.0 for f in all_freqs[1:])
    checks.append(("Frequency converges to ~50 Hz", freq_converged))

# Check 2: Magnitude stability
mag_stable = all(
    max(values) - min(values) < 0.05  # Less than 5% variation
    for values in all_mags.values()
)
checks.append(("Magnitude values stable", mag_stable))

# Check 3: Voltage vs Current magnitude ratio
avg_voltage = sum(sum(all_mags[f'CH{i}']) for i in range(1,4)) / 15
avg_current = sum(sum(all_mags[f'CH{i}']) for i in range(4,7)) / 15
ratio_correct = 1.2 < (avg_voltage / avg_current) < 1.4
checks.append(("Voltage/Current magnitude ratio reasonable", ratio_correct))

# Check 4: All values non-zero
all_nonzero = all(
    all(v > 0.01 for v in values)
    for values in all_mags.values()
)
checks.append(("All magnitudes non-zero", all_nonzero))

for check, result in checks:
    status = "✓ PASS" if result else "✗ FAIL"
    print(f"{status:<10} {check}")

all_pass = all(result for _, result in checks)
print("\n" + "="*100)
if all_pass:
    print("OVERALL RESULT: ✓ ALL CHECKS PASSED")
else:
    print("OVERALL RESULT: ✗ SOME CHECKS FAILED")
print("="*100)
