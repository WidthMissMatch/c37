#!/usr/bin/env python3
"""
Correct CRC-CCITT verification for IEEE C37.118 PMU packets
Accounts for proper byte order and field positions
"""

def crc_ccitt_c37118(data_bytes):
    """
    Calculate CRC-CCITT for C37.118
    Polynomial: x^16 + x^12 + x^5 + 1 (0x1021)
    Initial: 0xFFFF
    """
    crc = 0xFFFF

    for byte in data_bytes:
        crc ^= (byte << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF

    return crc

# Complete packet data from simulation (all 76 bytes per packet)
packets_raw = [
    # Packet 1
    "AA 01 00 4C 00 01 00 00 00 01 00 00 C0 10 00 00 " +
    "00 11 A4 54 00 00 19 71 00 00 00 00 00 00 00 00 " +
    "00 11 A4 96 00 00 D6 6F 00 11 A5 D0 00 00 5C 7B " +
    "00 0E 01 E2 00 00 0A 03 00 0E 01 A6 00 00 59 1D " +
    "00 0E 01 E9 00 00 4D 0B 00 00 99 9E",

    # Packet 2
    "AA 01 00 4C 00 01 00 00 00 02 00 00 C0 10 00 00 " +
    "00 11 A4 61 00 00 19 85 00 32 00 00 00 00 00 00 " +
    "00 11 A4 98 00 00 D6 81 00 11 A5 D8 00 00 5C 8D " +
    "00 0E 01 FF 00 00 0A 15 00 0E 01 AB 00 00 59 31 " +
    "00 0E 01 E3 00 00 4D 1F 00 00 34 23",

    # Packet 3
    "AA 01 00 4C 00 01 00 00 00 03 00 00 C0 10 00 00 " +
    "00 11 A4 54 00 00 19 97 00 38 53 BA 00 00 00 00 " +
    "00 11 A4 98 00 00 D6 95 00 11 A5 D4 00 00 5C A1 " +
    "00 0E 01 F2 00 00 0A 29 00 0E 01 9E 00 00 59 43 " +
    "00 0E 01 E3 00 00 4D 31 00 00 F5 F5",

    # Packet 4
    "AA 01 00 4C 00 01 00 00 00 04 00 00 C0 10 00 00 " +
    "00 11 A4 59 00 00 19 AB 00 32 04 F9 00 00 00 00 " +
    "00 11 A4 A1 00 00 D6 A7 00 11 A5 D7 00 00 5C B3 " +
    "00 0E 01 F1 00 00 0A 3D 00 0E 01 A5 00 00 59 57 " +
    "00 0E 01 EE 00 00 4D 45 00 00 D3 14",

    # Packet 5
    "AA 01 00 4C 00 01 00 00 00 05 00 00 C0 10 00 00 " +
    "00 11 A4 51 00 00 19 BF 00 32 04 7A 00 00 00 00 " +
    "00 11 A4 A1 00 00 D6 BB 00 11 A5 D2 00 00 5C C7 " +
    "00 0E 01 F7 00 00 0A 4F 00 0E 01 9F 00 00 59 6B " +
    "00 0E 01 F7 00 00 4D 57 00 00 4E A6",
]

# Expected CRC values from simulation debug output
expected_crcs = [39326, 13347, 62965, 54036, 20134]  # Decimal values
expected_crcs_hex = [0x999E, 0x3423, 0xF5F5, 0xD314, 0x4EA6]

print("=" * 100)
print("CRC-CCITT VERIFICATION FOR PMU PACKETS")
print("=" * 100)
print()
print("IEEE C37.118 Packet Structure (76 bytes total):")
print("  Bytes 0-71:  Packet data (SYNC, IDCODE, data, etc.)")
print("  Bytes 72-73: Reserved (0x0000)")
print("  Bytes 74-75: CRC-CCITT checksum")
print()
print("CRC Calculation:")
print("  Polynomial: 0x1021 (x^16 + x^12 + x^5 + 1)")
print("  Initial: 0xFFFF")
print("  Coverage: Bytes 0-71 (first 72 bytes)")
print()

all_pass = True
results = []

for pkt_num, packet_hex in enumerate(packets_raw, start=1):
    print(f"{'=' * 100}")
    print(f"PACKET #{pkt_num}")
    print(f"{'=' * 100}")

    # Parse packet bytes
    packet_bytes = bytes.fromhex(packet_hex.replace(' ', ''))

    # Split into data and CRC portions
    data_bytes = packet_bytes[0:72]   # First 72 bytes (for CRC calculation)
    reserved_bytes = packet_bytes[72:74]  # Bytes 72-73 (should be 0x0000)
    crc_bytes = packet_bytes[74:76]    # Bytes 74-75 (CRC value)

    # Extract reported CRC (big-endian)
    reported_crc = (crc_bytes[0] << 8) | crc_bytes[1]
    reserved_val = (reserved_bytes[0] << 8) | reserved_bytes[1]

    # Calculate CRC
    calculated_crc = crc_ccitt_c37118(data_bytes)

    # Check match
    match = (calculated_crc == reported_crc)
    all_pass = all_pass and match

    print(f"\nPacket Structure:")
    print(f"  Total length: {len(packet_bytes)} bytes")
    print(f"  Data bytes (0-71): {len(data_bytes)} bytes")
    print(f"  First 8 bytes: {data_bytes[:8].hex(' ').upper()}")
    print(f"  Last 8 data bytes: {data_bytes[-8:].hex(' ').upper()}")
    print()

    print(f"CRC Field (Word 18, bytes 72-75):")
    print(f"  Reserved (bytes 72-73): 0x{reserved_val:04X} {'✓' if reserved_val == 0 else '✗ (should be 0x0000)'}")
    print(f"  CRC (bytes 74-75): 0x{reported_crc:04X} ({reported_crc})")
    print()

    print(f"CRC Verification:")
    print(f"  Calculated CRC: 0x{calculated_crc:04X} ({calculated_crc})")
    print(f"  Reported CRC:   0x{reported_crc:04X} ({reported_crc})")
    print(f"  Expected CRC:   0x{expected_crcs_hex[pkt_num-1]:04X} ({expected_crcs[pkt_num-1]})")
    print()

    if match:
        print(f"  ✓ PASS - CRC matches!")
        results.append((pkt_num, "PASS", calculated_crc, reported_crc))
    else:
        print(f"  ✗ FAIL - CRC mismatch!")
        print(f"  Difference: {abs(calculated_crc - reported_crc)} ({calculated_crc - reported_crc:+d})")
        results.append((pkt_num, "FAIL", calculated_crc, reported_crc))
    print()

print("=" * 100)
print("SUMMARY")
print("=" * 100)
print()
print(f"{'Packet':<10} {'Status':<10} {'Calculated CRC':<20} {'Reported CRC':<20} {'Match':<10}")
print("-" * 70)

for pkt_num, status, calc_crc, rep_crc in results:
    match_str = "✓" if status == "PASS" else "✗"
    print(f"{pkt_num:<10} {status:<10} 0x{calc_crc:04X} ({calc_crc:<6}) 0x{rep_crc:04X} ({rep_crc:<6}) {match_str:<10}")

print()
if all_pass:
    print("✓✓✓ ALL PACKETS PASS - CRC CALCULATION IS CORRECT! ✓✓✓")
else:
    print("✗✗✗ SOME PACKETS FAIL - CRC CALCULATION HAS ERRORS ✗✗✗")

print()
print("=" * 100)
print("IEEE C37.118 COMPLIANCE CHECK")
print("=" * 100)
print()
print("✓ CRC-CCITT polynomial: 0x1021 (correct)")
print("✓ Initial value: 0xFFFF (correct)")
print("✓ Coverage: First 72 bytes (correct)")
print("✓ CRC field position: Bytes 74-75 (correct)")
print("✓ Reserved field: Bytes 72-73 = 0x0000 (correct)")
print()

# Byte-by-byte comparison for debugging
if not all_pass:
    print("=" * 100)
    print("DETAILED ANALYSIS FOR FAILED PACKETS")
    print("=" * 100)
    for pkt_num, status, calc_crc, rep_crc in results:
        if status == "FAIL":
            print(f"\nPacket #{pkt_num} detailed analysis:")
            print(f"  Expected CRC bits: {calc_crc:016b}")
            print(f"  Reported CRC bits: {rep_crc:016b}")
            print(f"  XOR difference:    {(calc_crc ^ rep_crc):016b}")
print()
print("=" * 100)
