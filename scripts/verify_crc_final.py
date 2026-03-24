#!/usr/bin/env python3
"""
Final CRC verification - accounting for reserved field inclusion
The CRC covers bytes 0-73 (74 bytes total, INCLUDING the reserved field)
"""

def crc_ccitt_c37118(data_bytes):
    """Calculate CRC-CCITT for C37.118"""
    crc = 0xFFFF

    for byte in data_bytes:
        crc ^= (byte << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF

    return crc

# Complete packet data (76 bytes per packet)
packets_raw = [
    "AA 01 00 4C 00 01 00 00 00 01 00 00 C0 10 00 00 " +
    "00 11 A4 54 00 00 19 71 00 00 00 00 00 00 00 00 " +
    "00 11 A4 96 00 00 D6 6F 00 11 A5 D0 00 00 5C 7B " +
    "00 0E 01 E2 00 00 0A 03 00 0E 01 A6 00 00 59 1D " +
    "00 0E 01 E9 00 00 4D 0B 00 00 99 9E",

    "AA 01 00 4C 00 01 00 00 00 02 00 00 C0 10 00 00 " +
    "00 11 A4 61 00 00 19 85 00 32 00 00 00 00 00 00 " +
    "00 11 A4 98 00 00 D6 81 00 11 A5 D8 00 00 5C 8D " +
    "00 0E 01 FF 00 00 0A 15 00 0E 01 AB 00 00 59 31 " +
    "00 0E 01 E3 00 00 4D 1F 00 00 34 23",

    "AA 01 00 4C 00 01 00 00 00 03 00 00 C0 10 00 00 " +
    "00 11 A4 54 00 00 19 97 00 38 53 BA 00 00 00 00 " +
    "00 11 A4 98 00 00 D6 95 00 11 A5 D4 00 00 5C A1 " +
    "00 0E 01 F2 00 00 0A 29 00 0E 01 9E 00 00 59 43 " +
    "00 0E 01 E3 00 00 4D 31 00 00 F5 F5",

    "AA 01 00 4C 00 01 00 00 00 04 00 00 C0 10 00 00 " +
    "00 11 A4 59 00 00 19 AB 00 32 04 F9 00 00 00 00 " +
    "00 11 A4 A1 00 00 D6 A7 00 11 A5 D7 00 00 5C B3 " +
    "00 0E 01 F1 00 00 0A 3D 00 0E 01 A5 00 00 59 57 " +
    "00 0E 01 EE 00 00 4D 45 00 00 D3 14",

    "AA 01 00 4C 00 01 00 00 00 05 00 00 C0 10 00 00 " +
    "00 11 A4 51 00 00 19 BF 00 32 04 7A 00 00 00 00 " +
    "00 11 A4 A1 00 00 D6 BB 00 11 A5 D2 00 00 5C C7 " +
    "00 0E 01 F7 00 00 0A 4F 00 0E 01 9F 00 00 59 6B " +
    "00 0E 01 F7 00 00 4D 57 00 00 4E A6",
]

print("=" * 100)
print("CRC-CCITT VERIFICATION - FINAL (Correct byte coverage)")
print("=" * 100)
print()
print("CRITICAL FINDING:")
print("  CRC covers bytes 0-73 (74 bytes), INCLUDING reserved field!")
print()
print("IEEE C37.118 Packet Structure (76 bytes total):")
print("  Bytes 0-71:  Packet data")
print("  Bytes 72-73: Reserved field (INCLUDED in CRC calculation)")
print("  Bytes 74-75: CRC-CCITT checksum")
print()

all_pass = True

for pkt_num, packet_hex in enumerate(packets_raw, start=1):
    print(f"{'=' * 100}")
    print(f"PACKET #{pkt_num}")
    print(f"{'=' * 100}")

    # Parse bytes
    packet_bytes = bytes.fromhex(packet_hex.replace(' ', ''))

    # CRC covers bytes 0-73 (74 bytes total)
    crc_input_bytes = packet_bytes[0:74]
    crc_bytes = packet_bytes[74:76]

    # Extract CRC
    reported_crc = (crc_bytes[0] << 8) | crc_bytes[1]

    # Calculate CRC over 74 bytes (including reserved)
    calculated_crc = crc_ccitt_c37118(crc_input_bytes)

    # Check
    match = (calculated_crc == reported_crc)
    all_pass = all_pass and match

    print(f"\nCRC Coverage:")
    print(f"  Bytes 0-71 (data):     {crc_input_bytes[0:72].hex(' ').upper()[:60]}...")
    print(f"  Bytes 72-73 (reserved): {crc_input_bytes[72:74].hex(' ').upper()} (INCLUDED in CRC)")
    print(f"  Bytes 74-75 (CRC):      {crc_bytes.hex(' ').upper()}")
    print()

    print(f"CRC Calculation (over 74 bytes):")
    print(f"  Calculated: 0x{calculated_crc:04X} ({calculated_crc})")
    print(f"  Reported:   0x{reported_crc:04X} ({reported_crc})")
    print()

    if match:
        print(f"  ✓✓✓ PASS - CRC CORRECT!")
    else:
        print(f"  ✗✗✗ FAIL - CRC mismatch by {abs(calculated_crc - reported_crc)}")
    print()

print("=" * 100)
print("FINAL VERDICT")
print("=" * 100)
print()

if all_pass:
    print("✓✓✓ ALL 5 PACKETS PASS ✓✓✓")
    print()
    print("CRC CALCULATION IS CORRECT!")
    print()
    print("Key Findings:")
    print("  ✓ CRC-CCITT polynomial 0x1021 implemented correctly")
    print("  ✓ Initial value 0xFFFF used correctly")
    print("  ✓ CRC covers 74 bytes (bytes 0-73, including reserved field)")
    print("  ✓ CRC stored in bytes 74-75 (big-endian)")
    print("  ✓ All 5 test packets have valid CRC checksums")
else:
    print("✗✗✗ CRC VERIFICATION FAILED ✗✗✗")

print()
print("=" * 100)
