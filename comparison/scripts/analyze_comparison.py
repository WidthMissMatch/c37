#!/usr/bin/env python3
"""
analyze_comparison.py
Read comparison CSVs from results/, compute metrics, print formatted table.

Metrics per dataset:
  - Magnitude mean (old/new), scaled: raw / 2^15
  - Magnitude ratio: new_mag / old_mag
  - Frequency mean error: |freq/2^16 - nominal_freq|
  - Frequency std dev: std(freq/2^16)
  - ROCOF std dev: std(rocof/2^16)
  - Phase std dev: std(phase/2^13)

Usage:
    cd "c37 compliance/comparison"
    python3 scripts/analyze_comparison.py [--plot]
"""

import os
import sys
import csv
import math
import argparse

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
BASE_DIR    = os.path.dirname(SCRIPT_DIR)
RESULT_DIR  = os.path.join(BASE_DIR, "results")

# Fixed-point scale factors
MAG_SCALE   = 2**15   # Q16.15 magnitude
FREQ_SCALE  = 2**16   # Q16.16 frequency (Hz)
ROCOF_SCALE = 2**16   # Q16.16 ROCOF (Hz/s)
PHASE_SCALE = 2**13   # Q2.13 phase (radians)

# Dataset info: (filename_prefix, nominal_freq, description)
DATASETS = [
    ("test_50hz_pure",       50.0,  "50 Hz pure sine"),
    ("test_49_5hz_offbin",   49.5,  "49.5 Hz off-bin"),
    ("test_50hz_harmonics",  50.0,  "50 Hz + harmonics"),
    ("test_freq_step",       50.5,  "50->51 Hz step"),  # average
    ("single_real",          50.0,  "Real ADC (single)"),
    ("medhavi_ch1_real",     50.0,  "Real grid (medhavi)"),
]


def read_csv(filepath):
    """Read comparison CSV, return list of dicts with integer values."""
    rows = []
    with open(filepath, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            parsed = {}
            for key, val in row.items():
                key = key.strip()
                try:
                    parsed[key] = int(val.strip())
                except (ValueError, AttributeError):
                    parsed[key] = 0
            rows.append(parsed)
    return rows


def compute_stats(values):
    """Compute mean and std dev of a list of floats."""
    if not values:
        return 0.0, 0.0
    n = len(values)
    mean = sum(values) / n
    if n < 2:
        return mean, 0.0
    variance = sum((v - mean) ** 2 for v in values) / (n - 1)
    return mean, math.sqrt(variance)


def analyze_dataset(rows, nominal_freq):
    """Compute all metrics for one dataset."""
    if not rows:
        return None

    # Use all rows for magnitude/phase (valid from cycle 1)
    all_data = rows

    # For frequency/ROCOF, filter out startup transient (freq=0 means
    # frequency_rocof_calculator hasn't seen enough phase measurements yet)
    freq_data = [r for r in rows if r.get("old_freq", 0) != 0 or r.get("new_freq", 0) != 0]

    # Extract scaled values - magnitude uses all data
    old_mags   = [r.get("old_mag", 0) / MAG_SCALE for r in all_data]
    new_mags   = [r.get("new_mag", 0) / MAG_SCALE for r in all_data]
    old_phases = [r.get("old_phase", 0) / PHASE_SCALE for r in all_data]
    new_phases = [r.get("new_phase", 0) / PHASE_SCALE for r in all_data]

    # Frequency/ROCOF uses only rows with valid freq output
    old_freqs  = [r.get("old_freq", 0) / FREQ_SCALE for r in freq_data]
    new_freqs  = [r.get("new_freq", 0) / FREQ_SCALE for r in freq_data]
    old_rocofs = [r.get("old_rocof", 0) / ROCOF_SCALE for r in freq_data]
    new_rocofs = [r.get("new_rocof", 0) / ROCOF_SCALE for r in freq_data]

    # Magnitude stats
    old_mag_mean, _ = compute_stats(old_mags)
    new_mag_mean, _ = compute_stats(new_mags)
    mag_ratio = new_mag_mean / old_mag_mean if old_mag_mean != 0 else 0.0

    # Frequency stats (only valid measurements)
    old_freq_mean, old_freq_std = compute_stats(old_freqs)
    new_freq_mean, new_freq_std = compute_stats(new_freqs)
    old_freq_err = abs(old_freq_mean - nominal_freq) if old_freqs else float('nan')
    new_freq_err = abs(new_freq_mean - nominal_freq) if new_freqs else float('nan')

    # ROCOF stats (only valid measurements)
    _, old_rocof_std = compute_stats(old_rocofs)
    _, new_rocof_std = compute_stats(new_rocofs)

    # Phase stats
    _, old_phase_std = compute_stats(old_phases)
    _, new_phase_std = compute_stats(new_phases)

    return {
        "n_cycles":      len(all_data),
        "n_freq_valid":  len(freq_data),
        "old_mag_mean":  old_mag_mean,
        "new_mag_mean":  new_mag_mean,
        "mag_ratio":     mag_ratio,
        "old_freq_mean": old_freq_mean,
        "new_freq_mean": new_freq_mean,
        "old_freq_err":  old_freq_err,
        "new_freq_err":  new_freq_err,
        "old_freq_std":  old_freq_std,
        "new_freq_std":  new_freq_std,
        "old_rocof_std": old_rocof_std,
        "new_rocof_std": new_rocof_std,
        "old_phase_std": old_phase_std,
        "new_phase_std": new_phase_std,
    }


def print_comparison_table(results):
    """Print formatted comparison table."""
    # Header
    print()
    print("=" * 110)
    print("  PMU Old vs New Comparison Results")
    print("=" * 110)
    print()

    # Table 1: Magnitude
    print("--- Magnitude (Q16.15 / 2^15) ---")
    print(f"{'Dataset':<25} {'Old Mean':>10} {'New Mean':>10} {'Ratio':>8} {'Cycles':>8} {'Freq OK':>8}")
    print("-" * 75)
    for name, nom, desc in DATASETS:
        r = results.get(name)
        if r is None:
            print(f"{desc:<25} {'N/A':>10} {'N/A':>10} {'N/A':>8} {'N/A':>8} {'N/A':>8}")
        else:
            print(f"{desc:<25} {r['old_mag_mean']:10.2f} {r['new_mag_mean']:10.2f} "
                  f"{r['mag_ratio']:8.4f} {r['n_cycles']:8d} {r['n_freq_valid']:8d}")
    print()

    # Table 2: Frequency
    print("--- Frequency Tracking (Q16.16 Hz) ---")
    print(f"{'Dataset':<25} {'Old Mean':>10} {'New Mean':>10} "
          f"{'Old Err':>10} {'New Err':>10} {'Old Std':>10} {'New Std':>10}")
    print("-" * 95)
    for name, nom, desc in DATASETS:
        r = results.get(name)
        if r is None:
            print(f"{desc:<25} {'N/A':>10}" * 6)
        else:
            print(f"{desc:<25} {r['old_freq_mean']:10.4f} {r['new_freq_mean']:10.4f} "
                  f"{r['old_freq_err']:10.6f} {r['new_freq_err']:10.6f} "
                  f"{r['old_freq_std']:10.6f} {r['new_freq_std']:10.6f}")
    print()

    # Table 3: ROCOF & Phase
    print("--- ROCOF Std Dev (Hz/s) & Phase Std Dev (rad) ---")
    print(f"{'Dataset':<25} {'Old ROCOF':>12} {'New ROCOF':>12} "
          f"{'Old Phase':>12} {'New Phase':>12}")
    print("-" * 80)
    for name, nom, desc in DATASETS:
        r = results.get(name)
        if r is None:
            print(f"{desc:<25} {'N/A':>12}" * 4)
        else:
            print(f"{desc:<25} {r['old_rocof_std']:12.6f} {r['new_rocof_std']:12.6f} "
                  f"{r['old_phase_std']:12.6f} {r['new_phase_std']:12.6f}")
    print()

    # Summary: improvement indicators
    print("--- Improvement Summary ---")
    print(f"{'Dataset':<25} {'Freq Err':>12} {'Freq Std':>12} {'ROCOF Std':>12} {'Phase Std':>12}")
    print("-" * 80)
    for name, nom, desc in DATASETS:
        r = results.get(name)
        if r is None:
            continue
        def indicator(old_val, new_val):
            if old_val == 0 and new_val == 0:
                return "  SAME"
            if old_val == 0:
                return "  WORSE"
            ratio = new_val / old_val
            if ratio < 0.9:
                return f"  +{(1-ratio)*100:.0f}% BETTER"
            elif ratio > 1.1:
                return f"  -{(ratio-1)*100:.0f}% WORSE"
            else:
                return f"  ~SAME ({ratio:.2f}x)"

        freq_err_ind  = indicator(r['old_freq_err'], r['new_freq_err'])
        freq_std_ind  = indicator(r['old_freq_std'], r['new_freq_std'])
        rocof_std_ind = indicator(r['old_rocof_std'], r['new_rocof_std'])
        phase_std_ind = indicator(r['old_phase_std'], r['new_phase_std'])
        print(f"{desc:<25} {freq_err_ind:>12} {freq_std_ind:>12} {rocof_std_ind:>12} {phase_std_ind:>12}")
    print()


def try_plot(results):
    """Generate bar charts if matplotlib is available."""
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib not available, skipping plots")
        return

    labels = []
    old_freq_errs = []
    new_freq_errs = []
    old_freq_stds = []
    new_freq_stds = []
    old_rocof_stds = []
    new_rocof_stds = []

    for name, nom, desc in DATASETS:
        r = results.get(name)
        if r is None:
            continue
        labels.append(desc.replace(" ", "\n"))
        old_freq_errs.append(r["old_freq_err"])
        new_freq_errs.append(r["new_freq_err"])
        old_freq_stds.append(r["old_freq_std"])
        new_freq_stds.append(r["new_freq_std"])
        old_rocof_stds.append(r["old_rocof_std"])
        new_rocof_stds.append(r["new_rocof_std"])

    if not labels:
        print("No data to plot")
        return

    import numpy as np
    x = np.arange(len(labels))
    width = 0.35

    fig, axes = plt.subplots(1, 3, figsize=(18, 6))

    # Frequency Error
    axes[0].bar(x - width/2, old_freq_errs, width, label='Old', color='salmon')
    axes[0].bar(x + width/2, new_freq_errs, width, label='New', color='steelblue')
    axes[0].set_ylabel('Frequency Error (Hz)')
    axes[0].set_title('Frequency Mean Error')
    axes[0].set_xticks(x)
    axes[0].set_xticklabels(labels, fontsize=8)
    axes[0].legend()

    # Frequency Std Dev
    axes[1].bar(x - width/2, old_freq_stds, width, label='Old', color='salmon')
    axes[1].bar(x + width/2, new_freq_stds, width, label='New', color='steelblue')
    axes[1].set_ylabel('Frequency Std Dev (Hz)')
    axes[1].set_title('Frequency Stability')
    axes[1].set_xticks(x)
    axes[1].set_xticklabels(labels, fontsize=8)
    axes[1].legend()

    # ROCOF Std Dev
    axes[2].bar(x - width/2, old_rocof_stds, width, label='Old', color='salmon')
    axes[2].bar(x + width/2, new_rocof_stds, width, label='New', color='steelblue')
    axes[2].set_ylabel('ROCOF Std Dev (Hz/s)')
    axes[2].set_title('ROCOF Noise')
    axes[2].set_xticks(x)
    axes[2].set_xticklabels(labels, fontsize=8)
    axes[2].legend()

    plt.tight_layout()
    plot_path = os.path.join(RESULT_DIR, "comparison_charts.png")
    plt.savefig(plot_path, dpi=150)
    print(f"Charts saved to: {plot_path}")


def main():
    parser = argparse.ArgumentParser(description="Analyze PMU comparison results")
    parser.add_argument("--plot", action="store_true", help="Generate bar charts")
    parser.add_argument("--suffix", default="_comparison.csv",
                        help="CSV filename suffix (default: _comparison.csv)")
    args = parser.parse_args()

    if not os.path.exists(RESULT_DIR):
        print(f"ERROR: Results directory not found: {RESULT_DIR}")
        print("Run the simulation scripts first.")
        sys.exit(1)

    results = {}
    found_any = False

    for name, nominal, desc in DATASETS:
        filepath = os.path.join(RESULT_DIR, f"{name}{args.suffix}")
        if not os.path.exists(filepath):
            print(f"  WARNING: {filepath} not found")
            continue

        rows = read_csv(filepath)
        if not rows:
            print(f"  WARNING: {filepath} is empty")
            continue

        stats = analyze_dataset(rows, nominal)
        if stats:
            results[name] = stats
            found_any = True
            print(f"  Loaded {name}: {stats['n_cycles']} cycles")

    if not found_any:
        print("\nNo result files found. Run simulations first.")
        sys.exit(1)

    print_comparison_table(results)

    if args.plot:
        try_plot(results)


if __name__ == "__main__":
    main()
