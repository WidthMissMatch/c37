#!/usr/bin/env python3
"""
PMU Test Data Generator
Reads medhavi.csv and generates VHDL package with 1500 hardcoded 128-bit packets
"""
import csv
import sys

# Configuration
CSV_PATH = "/home/arunupscee/Desktop/xtortion/c37 compliance/medhavi.csv"
OUTPUT_PATH = "/home/arunupscee/Desktop/xtortion/c37 compliance/test_data_constants_pkg.vhd"
TOTAL_SAMPLES = 1500

def signed16_to_unsigned_hex(value):
    """Convert signed 16-bit integer to unsigned hex (two's complement)"""
    if value < 0:
        unsigned = (1 << 16) + value
    else:
        unsigned = value
    return unsigned & 0xFFFF

def create_128bit_packet(ch0, ch1, ch2, ch3, ch4, ch5):
    """
    Pack 6 channels into 128-bit packet
    Packet Format:
    [127:120] = 0xAA (SYNC)
    [119:104] = Ch0 (16-bit, signed → unsigned hex)
    [103:88]  = Ch1
    [87:72]   = Ch2
    [71:56]   = Ch3
    [55:40]   = Ch4
    [39:24]   = Ch5
    [23:16]   = 0x55 (CHECKSUM)
    [15:0]    = 0x0000 (Reserved)
    """
    packet = 0
    packet |= (0xAA << 120)  # SYNC
    packet |= (signed16_to_unsigned_hex(ch0) << 104)
    packet |= (signed16_to_unsigned_hex(ch1) << 88)
    packet |= (signed16_to_unsigned_hex(ch2) << 72)
    packet |= (signed16_to_unsigned_hex(ch3) << 56)
    packet |= (signed16_to_unsigned_hex(ch4) << 40)
    packet |= (signed16_to_unsigned_hex(ch5) << 24)
    packet |= (0x55 << 16)  # CHECKSUM
    packet |= 0x0000        # Reserved
    return packet

def read_csv_samples(csv_path, num_samples):
    """Read samples from CSV with error checking"""
    samples = []

    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            next(reader)  # Skip header

            for i, row in enumerate(reader):
                if i >= num_samples:
                    break

                if len(row) != 6:
                    raise ValueError(f"Row {i+2} has {len(row)} columns, expected 6")

                try:
                    ch_values = [int(val) for val in row]
                except ValueError as e:
                    raise ValueError(f"Row {i+2} has invalid integer value: {e}")

                samples.append(ch_values)

                if (i + 1) % 300 == 0:
                    print(f"Read {i+1}/{num_samples} samples...")

        if len(samples) < num_samples:
            raise ValueError(f"CSV only has {len(samples)} rows, expected {num_samples}")

    except FileNotFoundError:
        print(f"ERROR: CSV file not found: {csv_path}")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR reading CSV: {e}")
        sys.exit(1)

    return samples

def generate_vhdl_package(samples, output_path):
    """Generate VHDL package with constant array"""
    try:
        with open(output_path, 'w') as f:
            # Write header
            f.write("-- Auto-generated VHDL Package\n")
            f.write("-- PMU Test Data Constants (1500 samples = 5 power cycles)\n")
            f.write("-- Generated from medhavi.csv\n")
            f.write("-- VHDL-93 Compatible\n")
            f.write("--\n")
            f.write("-- Packet Format (128 bits):\n")
            f.write("--   [127:120] = 0xAA (SYNC)\n")
            f.write("--   [119:104] = Ch0 (16-bit unsigned hex)\n")
            f.write("--   [103:88]  = Ch1\n")
            f.write("--   [87:72]   = Ch2\n")
            f.write("--   [71:56]   = Ch3\n")
            f.write("--   [55:40]   = Ch4\n")
            f.write("--   [39:24]   = Ch5\n")
            f.write("--   [23:16]   = 0x55 (CHECKSUM)\n")
            f.write("--   [15:0]    = 0x0000 (Reserved)\n\n")

            f.write("library IEEE;\n")
            f.write("use IEEE.STD_LOGIC_1164.ALL;\n")
            f.write("use IEEE.NUMERIC_STD.ALL;\n\n")

            f.write("package test_data_constants_pkg is\n\n")
            f.write(f"    constant NUM_TEST_SAMPLES : integer := {len(samples)};\n\n")
            f.write("    type axi_packet_array is array (0 to NUM_TEST_SAMPLES-1) of std_logic_vector(127 downto 0);\n\n")
            f.write("    constant TEST_PACKETS : axi_packet_array := (\n")

            # Generate packets
            for idx, (ch0, ch1, ch2, ch3, ch4, ch5) in enumerate(samples):
                packet_value = create_128bit_packet(ch0, ch1, ch2, ch3, ch4, ch5)
                hex_str = f"{packet_value:032X}"

                # Add cycle markers
                if idx % 300 == 0:
                    cycle_num = idx // 300 + 1
                    f.write(f"        -- Cycle {cycle_num} starts (sample {idx})\n")

                if idx < len(samples) - 1:
                    f.write(f'        x"{hex_str}",\n')
                else:
                    f.write(f'        x"{hex_str}"\n')

            f.write("    );\n\n")
            f.write("end package test_data_constants_pkg;\n")

    except Exception as e:
        print(f"ERROR writing VHDL file: {e}")
        sys.exit(1)

def main():
    print("=" * 70)
    print("PMU Test Data Generator")
    print("=" * 70)
    print(f"Reading {TOTAL_SAMPLES} samples from CSV...")
    print(f"Source: {CSV_PATH}")
    print()

    samples = read_csv_samples(CSV_PATH, TOTAL_SAMPLES)
    print(f"\nSuccessfully read {len(samples)} samples")
    print()

    print("Generating VHDL package...")
    generate_vhdl_package(samples, OUTPUT_PATH)
    print(f"\nSuccessfully generated: {OUTPUT_PATH}")

    # Print statistics
    print()
    print("=" * 70)
    print("Generation Statistics:")
    print(f"  Total samples: {len(samples)}")
    print(f"  Power cycles: {len(samples) // 300}")
    print(f"  Samples per cycle: 300")
    print(f"  Packet size: 128 bits (16 bytes)")
    print(f"  Total data size: {len(samples) * 16} bytes")
    print("=" * 70)

if __name__ == "__main__":
    main()
