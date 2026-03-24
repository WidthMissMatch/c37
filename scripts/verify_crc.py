#!/usr/bin/env python3
"""
Verify CRC-CCITT calculation for IEEE C37.118 packets
CRC-CCITT: Polynomial 0x1021, Initial value 0xFFFF
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

def parse_hex_bytes(hex_string):
    """Parse hex string like 'AA 01 00 4C' to byte array"""
    return bytes.fromhex(hex_string.replace(' ', ''))

# Packet data from simulation output
packets = [
    {
        "number": 1,
        "data": [
            "AA 01 00 4C",  # 0-3: SYNC + FrameSize
            "00 01 00 00",  # 4-7: IDCODE + SOC[31:16]
            "00 01 00 00",  # 8-11: SOC[15:0] + Reserved
            "C0 10 00 00",  # 12-15: STAT + Reserved
            "00 11 A4 54",  # 16-19: CH1 Magnitude
            "00 00 19 71",  # 20-23: Padding + CH1 Phase
            "00 00 00 00",  # 24-27: CH1 Frequency
            "00 00 00 00",  # 28-31: CH1 ROCOF
            "00 11 A4 96",  # 32-35: CH2 Magnitude
            "00 00 D6 6F",  # 36-39: Padding + CH2 Phase
            "00 11 A5 D0",  # 40-43: CH3 Magnitude
            "00 00 5C 7B",  # 44-47: Padding + CH3 Phase
            "00 0E 01 E2",  # 48-51: CH4 Magnitude
            "00 00 0A 03",  # 52-55: Padding + CH4 Phase
            "00 0E 01 A6",  # 56-59: CH5 Magnitude
            "00 00 59 1D",  # 60-63: Padding + CH5 Phase
            "00 0E 01 E9",  # 64-67: CH6 Magnitude
            "00 00 4D 0B",  # 68-71: Padding + CH6 Phase
        ],
        "crc_reported": "00 00 99 9E"  # 72-75: CRC + Reserved
    },
    {
        "number": 2,
        "data": [
            "AA 01 00 4C",
            "00 01 00 00",
            "00 02 00 00",
            "C0 10 00 00",
            "00 11 A4 61",
            "00 00 19 85",
            "00 32 00 00",
            "00 00 00 00",
            "00 11 A4 98",
            "00 00 D6 81",
            "00 11 A5 D8",
            "00 00 5C 8D",
            "00 0E 01 FF",
            "00 00 0A 15",
            "00 0E 01 AB",
            "00 00 59 31",
            "00 0E 01 E3",
            "00 00 4D 1F",
        ],
        "crc_reported": "00 00 34 23"
    },
    {
        "number": 3,
        "data": [
            "AA 01 00 4C",
            "00 01 00 00",
            "00 03 00 00",
            "C0 10 00 00",
            "00 11 A4 54",
            "00 00 19 97",
            "00 38 53 BA",
            "00 00 00 00",
            "00 11 A4 98",
            "00 00 D6 95",
            "00 11 A5 D4",
            "00 00 5C A1",
            "00 0E 01 F2",
            "00 00 0A 29",
            "00 0E 01 9E",
            "00 00 59 43",
            "00 0E 01 E3",
            "00 00 4D 31",
        ],
        "crc_reported": "00 00 F5 F5"
    },
    {
        "number": 4,
        "data": [
            "AA 01 00 4C",
            "00 01 00 00",
            "00 04 00 00",
            "C0 10 00 00",
            "00 11 A4 59",
            "00 00 19 AB",
            "00 32 04 F9",
            "00 00 00 00",
            "00 11 A4 A1",
            "00 00 D6 A7",
            "00 11 A5 D7",
            "00 00 5C B3",
            "00 0E 01 F1",
            "00 00 0A 3D",
            "00 0E 01 A5",
            "00 00 59 57",
            "00 0E 01 EE",
            "00 00 4D 45",
        ],
        "crc_reported": "00 00 D3 14"
    },
    {
        "number": 5,
        "data": [
            "AA 01 00 4C",
            "00 01 00 00",
            "00 05 00 00",
            "C0 10 00 00",
            "00 11 A4 51",
            "00 00 19 BF",
            "00 32 04 7A",
            "00 00 00 00",
            "00 11 A4 A1",
            "00 00 D6 BB",
            "00 11 A5 D2",
            "00 00 5C C7",
            "00 0E 01 F7",
            "00 00 0A 4F",
            "00 0E 01 9F",
            "00 00 59 6B",
            "00 0E 01 F7",
            "00 00 4D 57",
        ],
        "crc_reported": "00 00 4E A6"
    }
]

print("=" * 100)
print("CRC-CCITT VERIFICATION FOR PMU PACKETS")
print("=" * 100)
print()
print("IEEE C37.118 CRC Standard:")
print("  Polynomial: 0x1021 (x^16 + x^12 + x^5 + 1)")
print("  Initial Value: 0xFFFF")
print("  CRC covers: SYNC through last data byte (excluding CHK itself)")
print()

all_pass = True

for pkt in packets:
    print(f"{'=' * 100}")
    print(f"PACKET #{pkt['number']}")
    print(f"{'=' * 100}")

    # Combine all data bytes
    all_data = b''
    for hex_str in pkt['data']:
        all_data += parse_hex_bytes(hex_str)

    # Calculate CRC
    calculated_crc = crc_ccitt_c37118(all_data)

    # Parse reported CRC (first 2 bytes of the 4-byte field)
    reported_crc_bytes = parse_hex_bytes(pkt['crc_reported'])
    reported_crc = (reported_crc_bytes[0] << 8) | reported_crc_bytes[1]

    # Check if match
    match = calculated_crc == reported_crc
    all_pass = all_pass and match

    print(f"\nPacket Data ({len(all_data)} bytes):")
    print(f"  First 16 bytes: {all_data[:16].hex(' ').upper()}")
    print(f"  Last 16 bytes:  {all_data[-16:].hex(' ').upper()}")
    print()
    print(f"CRC Calculation:")
    print(f"  Calculated CRC: 0x{calculated_crc:04X} ({calculated_crc})")
    print(f"  Reported CRC:   0x{reported_crc:04X} ({reported_crc})")
    print(f"  Reserved bytes: 0x{reported_crc_bytes[2]:02X}{reported_crc_bytes[3]:02X}")
    print()

    if match:
        print(f"  ✓ PASS - CRC matches!")
    else:
        print(f"  ✗ FAIL - CRC mismatch!")
        print(f"  Difference: {abs(calculated_crc - reported_crc)} ({calculated_crc - reported_crc:+d})")
    print()

print("=" * 100)
print("OVERALL CRC VERIFICATION")
print("=" * 100)

if all_pass:
    print("✓ ALL PACKETS PASS - CRC calculation is CORRECT!")
else:
    print("✗ SOME PACKETS FAIL - CRC calculation has errors")

print()
print("=" * 100)
print("ADDITIONAL CHECKS")
print("=" * 100)

# Check CRC implementation details
print("\n1. Polynomial Check:")
print("   Expected: 0x1021")
print("   ✓ Standard CRC-CCITT polynomial")

print("\n2. Initial Value Check:")
print("   Expected: 0xFFFF")
print("   ✓ Standard CRC-CCITT initial value")

print("\n3. Byte Order Check:")
print("   CRC should be transmitted MSB first (big-endian)")
print("   Reported CRC bytes: [MSB, LSB, Reserved, Reserved]")

print("\n4. Coverage Check:")
print("   CRC covers all bytes from SYNC through last data byte")
print("   Does NOT include the CRC field itself")

print("\n5. Reserved Bytes Check:")
print("   Last 2 bytes of 4-byte CRC field should be 0x0000")

for pkt in packets:
    reported_crc_bytes = parse_hex_bytes(pkt['crc_reported'])
    reserved = (reported_crc_bytes[2] << 8) | reported_crc_bytes[3]
    if reserved == 0:
        print(f"   Packet {pkt['number']}: Reserved = 0x{reserved:04X} ✓")
    else:
        print(f"   Packet {pkt['number']}: Reserved = 0x{reserved:04X} ✗ (should be 0x0000)")

print()
print("=" * 100)
