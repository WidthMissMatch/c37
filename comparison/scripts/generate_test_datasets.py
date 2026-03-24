#!/usr/bin/env python3
"""
Generate 6 test datasets for PMU old-vs-new comparison.

Each dataset: 4500 samples (15 power cycles @ 300 samples/cycle at 15 kHz),
one 16-bit signed integer per line, no header.

Datasets:
  1. test_50hz_pure.txt       - Clean 50 Hz sine, +/-16000
  2. test_49_5hz_offbin.txt   - 49.5 Hz sine (worst-case spectral leakage)
  3. test_50hz_harmonics.txt  - 50 Hz + 10% 3rd + 5% 5th harmonic
  4. test_freq_step.txt       - 50->51 Hz step at sample 2250 (phase-continuous)
  5. single_real.txt          - First 4500 from data_files/single.txt
  6. medhavi_ch1_real.txt     - All available from data_files/medhavi_small.csv col1

Usage:
    cd "c37 compliance/comparison"
    python3 scripts/generate_test_datasets.py
"""

import math
import os
import sys
import csv

SAMPLE_RATE = 15000  # Hz
NUM_SAMPLES = 4500   # 15 power cycles at 50 Hz
AMPLITUDE   = 16000  # peak amplitude (fits in 16-bit signed)

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
BASE_DIR    = os.path.dirname(SCRIPT_DIR)  # comparison/
DATASET_DIR = os.path.join(BASE_DIR, "datasets")
DATA_FILES  = os.path.join(os.path.dirname(BASE_DIR), "data_files")


def write_samples(filename, samples):
    """Write integer samples to file, one per line."""
    path = os.path.join(DATASET_DIR, filename)
    with open(path, "w") as f:
        for s in samples:
            f.write(f"{int(round(s))}\n")
    print(f"  Created {filename}: {len(samples)} samples")


def gen_pure_50hz():
    """Dataset 1: Clean 50 Hz sine."""
    samples = []
    for i in range(NUM_SAMPLES):
        theta = 2.0 * math.pi * 50.0 * i / SAMPLE_RATE
        samples.append(AMPLITUDE * math.sin(theta))
    write_samples("test_50hz_pure.txt", samples)


def gen_offbin_49_5hz():
    """Dataset 2: 49.5 Hz sine (off-bin, worst-case leakage)."""
    samples = []
    for i in range(NUM_SAMPLES):
        theta = 2.0 * math.pi * 49.5 * i / SAMPLE_RATE
        samples.append(AMPLITUDE * math.sin(theta))
    write_samples("test_49_5hz_offbin.txt", samples)


def gen_harmonics():
    """Dataset 3: 50 Hz fundamental + 10% 3rd harmonic + 5% 5th harmonic."""
    samples = []
    for i in range(NUM_SAMPLES):
        t = float(i) / SAMPLE_RATE
        fundamental = math.sin(2.0 * math.pi * 50.0 * t)
        third       = 0.10 * math.sin(2.0 * math.pi * 150.0 * t)
        fifth       = 0.05 * math.sin(2.0 * math.pi * 250.0 * t)
        samples.append(AMPLITUDE * (fundamental + third + fifth))
    write_samples("test_50hz_harmonics.txt", samples)


def gen_freq_step():
    """Dataset 4: 50->51 Hz step at midpoint, phase-continuous transition."""
    samples = []
    phase = 0.0
    midpoint = NUM_SAMPLES // 2
    for i in range(NUM_SAMPLES):
        if i < midpoint:
            freq = 50.0
        else:
            freq = 51.0
        samples.append(AMPLITUDE * math.sin(phase))
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
    write_samples("test_freq_step.txt", samples)


def gen_single_real():
    """Dataset 5: First NUM_SAMPLES samples from data_files/single.txt."""
    src = os.path.join(DATA_FILES, "single.txt")
    if not os.path.exists(src):
        print(f"  WARNING: {src} not found, skipping single_real.txt")
        return
    samples = []
    with open(src, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("Column"):
                continue
            try:
                samples.append(int(line))
            except ValueError:
                continue
            if len(samples) >= NUM_SAMPLES:
                break
    if len(samples) < NUM_SAMPLES:
        print(f"  WARNING: single.txt only has {len(samples)} data lines, "
              f"padding with zeros to {NUM_SAMPLES}")
        samples.extend([0] * (NUM_SAMPLES - len(samples)))
    write_samples("single_real.txt", samples)


def gen_medhavi_ch1_real():
    """Dataset 6: All available samples from medhavi_small.csv column 1."""
    src = os.path.join(DATA_FILES, "medhavi_small.csv")
    if not os.path.exists(src):
        print(f"  WARNING: {src} not found, skipping medhavi_ch1_real.txt")
        return
    samples = []
    with open(src, "r", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)  # skip header
        for row in reader:
            if len(row) < 1:
                continue
            try:
                samples.append(int(row[0]))
            except ValueError:
                continue
            if len(samples) >= NUM_SAMPLES:
                break
    if len(samples) < NUM_SAMPLES:
        print(f"  NOTE: medhavi_small.csv has {len(samples)} rows (< {NUM_SAMPLES}), "
              f"using all available")
    write_samples("medhavi_ch1_real.txt", samples)


def main():
    os.makedirs(DATASET_DIR, exist_ok=True)
    print("Generating 6 test datasets for PMU comparison...")
    print(f"  Output directory: {DATASET_DIR}")
    print(f"  Samples per dataset: {NUM_SAMPLES}")
    print()

    gen_pure_50hz()
    gen_offbin_49_5hz()
    gen_harmonics()
    gen_freq_step()
    gen_single_real()
    gen_medhavi_ch1_real()

    print()
    print("All datasets generated successfully.")


if __name__ == "__main__":
    main()
