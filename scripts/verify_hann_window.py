#!/usr/bin/env python3
"""
Hann Window Verification & Spectral Analysis
=============================================

Reads VHDL simulation output files and performs:
1. Hann coefficient verification (VHDL ROM vs Python reference)
2. FFT spectral comparison: Rectangular vs Hann windowed
3. Sidelobe suppression measurement
4. Generates comparison plots

Usage:
    cd "c37 compliance"
    python3 scripts/verify_hann_window.py

Input files (from GHDL simulation):
    hann_coefficients.txt    - VHDL ROM dump
    hann_test1_rect.txt      - Test 1 rectangular samples
    hann_test1_hann.txt      - Test 1 Hann-windowed samples
    hann_test2_rect.txt      - Test 2 rectangular samples
    hann_test2_hann.txt      - Test 2 Hann-windowed samples
    hann_test3_rect.txt      - Test 3 rectangular samples
    hann_test3_hann.txt      - Test 3 Hann-windowed samples
    hann_test4_rect.txt      - Test 4 rectangular samples
    hann_test4_hann.txt      - Test 4 Hann-windowed samples
"""

import numpy as np
import os
import sys

# Try to import matplotlib, fall back to text-only mode
try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("[INFO] matplotlib not found - text-only analysis mode")

N = 256  # Window size


def load_samples(filename):
    """Load integer samples from text file (one per line)."""
    if not os.path.exists(filename):
        print(f"  [SKIP] {filename} not found")
        return None
    with open(filename, 'r') as f:
        samples = [int(line.strip()) for line in f if line.strip()]
    return np.array(samples, dtype=np.float64)


def compute_spectrum_db(samples, n_fft=None):
    """Compute magnitude spectrum in dB."""
    if n_fft is None:
        n_fft = len(samples)
    spectrum = np.fft.fft(samples, n_fft)
    magnitude = np.abs(spectrum[:n_fft//2])
    # Avoid log(0)
    magnitude[magnitude < 1e-10] = 1e-10
    mag_db = 20 * np.log10(magnitude / np.max(magnitude))
    return mag_db


def measure_sidelobes(mag_db, main_bin=1, exclude_range=2):
    """Measure peak sidelobe level relative to main lobe."""
    mask = np.ones(len(mag_db), dtype=bool)
    low = max(0, main_bin - exclude_range)
    high = min(len(mag_db), main_bin + exclude_range + 1)
    mask[low:high] = False
    # Also exclude DC
    mask[0] = False
    if np.any(mask):
        peak_sidelobe = np.max(mag_db[mask])
    else:
        peak_sidelobe = -100.0
    return peak_sidelobe


def verify_coefficients(vhdl_coeffs):
    """Compare VHDL ROM coefficients against Python reference."""
    print("\n" + "="*60)
    print(" COEFFICIENT VERIFICATION")
    print("="*60)

    # Generate Python reference Hann coefficients in Q0.15
    n = np.arange(N)
    w = 0.5 * (1 - np.cos(2*np.pi*n/N))
    w_fixed = np.round(w * 32768).astype(int)
    w_fixed = np.clip(w_fixed, 0, 32767)

    if len(vhdl_coeffs) != N:
        print(f"  [WARN] Expected {N} coefficients, got {len(vhdl_coeffs)}")
        vhdl_coeffs = vhdl_coeffs[:N]

    # Compare
    errors = vhdl_coeffs - w_fixed
    max_err = np.max(np.abs(errors))
    rms_err = np.sqrt(np.mean(errors**2))

    print(f"  Coefficients compared: {N}")
    print(f"  Max absolute error:    {max_err}")
    print(f"  RMS error:             {rms_err:.4f}")

    # Check key values
    checks = [
        (0,   0,     "w[0]   = 0.0"),
        (64,  16384, "w[64]  = 0.5"),
        (128, 32767, "w[128] = 1.0 (capped)"),
        (192, 16384, "w[192] = 0.5"),
    ]
    all_pass = True
    for idx, expected, desc in checks:
        actual = int(vhdl_coeffs[idx])
        status = "PASS" if actual == expected else "FAIL"
        if status == "FAIL":
            all_pass = False
        print(f"  {desc}: VHDL={actual}, expected={expected} [{status}]")

    # Symmetry check: Periodic Hann has w[i] == w[N-i] for i=1..N-1
    # (NOT w[N-1-i] which is a different relationship)
    sym_errors = 0
    for i in range(1, N//2 + 1):
        j = N - i  # mirror index
        if j < N:
            if abs(int(vhdl_coeffs[i]) - int(vhdl_coeffs[j])) > 1:
                sym_errors += 1

    print(f"  Symmetry check (w[i]==w[N-i]): {sym_errors} violations (>1 LSB)")

    overall = "PASS" if (max_err <= 1 and all_pass and sym_errors == 0) else "FAIL"
    print(f"\n  COEFFICIENT VERIFICATION: [{overall}]")
    return overall == "PASS"


def analyze_test(test_num, test_name, freq_hz, rect_file, hann_file):
    """Analyze one test case: compare rectangular vs Hann spectra."""
    print(f"\n{'='*60}")
    print(f" TEST {test_num}: {test_name}")
    print(f" Signal: {freq_hz}")
    print(f"{'='*60}")

    rect = load_samples(rect_file)
    hann = load_samples(hann_file)

    if rect is None or hann is None:
        print("  [SKIP] Missing data files")
        return None

    print(f"  Rectangular samples: {len(rect)}")
    print(f"  Hann samples:        {len(hann)}")

    # Also compute Python Hann reference for comparison
    n = np.arange(N)
    w = 0.5 * (1 - np.cos(2*np.pi*n/N))
    if len(rect) == N:
        python_hann = rect * w
    else:
        python_hann = None

    # Compute spectra
    rect_db = compute_spectrum_db(rect[:N])
    hann_db = compute_spectrum_db(hann[:min(len(hann), N)])

    if python_hann is not None:
        python_hann_db = compute_spectrum_db(python_hann)
    else:
        python_hann_db = None

    # Find main bin (highest magnitude)
    rect_spectrum = np.abs(np.fft.fft(rect[:N])[:N//2])
    main_bin = np.argmax(rect_spectrum[1:]) + 1  # Exclude DC

    print(f"\n  Main DFT bin: k={main_bin} (freq = {main_bin * 50.0/1.0:.1f} Hz equivalent)")

    # Measure sidelobes
    rect_sidelobe = measure_sidelobes(rect_db, main_bin)
    hann_sidelobe = measure_sidelobes(hann_db, main_bin)

    print(f"\n  {'Metric':<35s} {'Rectangular':>12s} {'Hann (VHDL)':>12s} {'Improvement':>12s}")
    print(f"  {'-'*35} {'-'*12} {'-'*12} {'-'*12}")
    print(f"  {'Peak sidelobe level (dB)':<35s} {rect_sidelobe:>12.1f} {hann_sidelobe:>12.1f} {rect_sidelobe - hann_sidelobe:>12.1f}")

    # Main lobe magnitude
    rect_main = rect_db[main_bin]
    hann_main = hann_db[main_bin]
    print(f"  {'Main lobe level (dB)':<35s} {rect_main:>12.1f} {hann_main:>12.1f} {'N/A':>12s}")

    # If Python Hann available, compare VHDL vs Python
    if python_hann_db is not None:
        py_sidelobe = measure_sidelobes(python_hann_db, main_bin)
        print(f"  {'Peak sidelobe (Python ref)':<35s} {'':>12s} {py_sidelobe:>12.1f} {'':>12s}")

        # Compare VHDL Hann vs Python Hann
        if len(hann) >= N:
            vhdl_vs_py_err = np.max(np.abs(hann[:N] - python_hann))
            vhdl_vs_py_rms = np.sqrt(np.mean((hann[:N] - python_hann)**2))
            print(f"\n  VHDL vs Python Hann comparison:")
            print(f"    Max sample error: {vhdl_vs_py_err:.1f}")
            print(f"    RMS sample error: {vhdl_vs_py_rms:.2f}")

    # Leakage energy metric: sum of sidelobe power / total power
    rect_spec_mag = np.abs(np.fft.fft(rect[:N])[:N//2])
    hann_spec_mag = np.abs(np.fft.fft(hann[:min(len(hann), N)])[:N//2])

    total_rect = np.sum(rect_spec_mag**2)
    total_hann = np.sum(hann_spec_mag**2)

    mask = np.ones(N//2, dtype=bool)
    low = max(0, main_bin - 2)
    high = min(N//2, main_bin + 3)
    mask[low:high] = False
    mask[0] = False

    leak_rect = np.sum(rect_spec_mag[mask]**2) / total_rect * 100 if total_rect > 0 else 0
    leak_hann = np.sum(hann_spec_mag[mask]**2) / total_hann * 100 if total_hann > 0 else 0

    print(f"\n  {'Leakage energy (% of total)':<35s} {leak_rect:>11.2f}% {leak_hann:>11.2f}%")

    return {
        'test_num': test_num,
        'test_name': test_name,
        'rect_db': rect_db,
        'hann_db': hann_db,
        'python_hann_db': python_hann_db,
        'main_bin': main_bin,
        'rect_sidelobe': rect_sidelobe,
        'hann_sidelobe': hann_sidelobe,
        'rect_leak': leak_rect,
        'hann_leak': leak_hann,
        'rect': rect,
        'hann': hann,
    }


def plot_results(results):
    """Generate comparison plots."""
    if not HAS_MATPLOTLIB:
        print("\n[INFO] Skipping plots (matplotlib not available)")
        return

    valid_results = [r for r in results if r is not None]
    if not valid_results:
        print("\n[INFO] No valid results to plot")
        return

    n_tests = len(valid_results)
    fig, axes = plt.subplots(n_tests, 2, figsize=(16, 4*n_tests))
    if n_tests == 1:
        axes = axes.reshape(1, -1)

    for i, r in enumerate(valid_results):
        # Left: Time domain
        ax = axes[i, 0]
        n_pts = min(len(r['rect']), N)
        x = np.arange(n_pts)
        ax.plot(x, r['rect'][:n_pts], 'b-', alpha=0.7, label='Rectangular')
        ax.plot(x, r['hann'][:min(len(r['hann']), n_pts)], 'r-', alpha=0.7, label='Hann')
        ax.set_title(f"Test {r['test_num']}: {r['test_name']} - Time Domain")
        ax.set_xlabel('Sample Index')
        ax.set_ylabel('Amplitude')
        ax.legend()
        ax.grid(True, alpha=0.3)

        # Right: Frequency domain
        ax = axes[i, 1]
        bins = np.arange(len(r['rect_db']))
        ax.plot(bins, r['rect_db'], 'b-', alpha=0.7, linewidth=1.5, label=f"Rectangular (sidelobe: {r['rect_sidelobe']:.1f} dB)")
        ax.plot(bins[:len(r['hann_db'])], r['hann_db'], 'r-', alpha=0.7, linewidth=1.5, label=f"Hann VHDL (sidelobe: {r['hann_sidelobe']:.1f} dB)")
        if r['python_hann_db'] is not None:
            ax.plot(bins[:len(r['python_hann_db'])], r['python_hann_db'], 'g--', alpha=0.5, linewidth=1, label='Hann Python ref')
        ax.set_title(f"Test {r['test_num']}: {r['test_name']} - Spectrum (dB)")
        ax.set_xlabel('DFT Bin')
        ax.set_ylabel('Magnitude (dB)')
        ax.set_ylim([-80, 5])
        ax.legend(fontsize=8)
        ax.grid(True, alpha=0.3)
        ax.axhline(y=-13, color='b', linestyle=':', alpha=0.3, label='Rect theoretical: -13 dB')
        ax.axhline(y=-31, color='r', linestyle=':', alpha=0.3, label='Hann theoretical: -31 dB')

    plt.tight_layout()
    plot_file = 'hann_window_analysis.png'
    plt.savefig(plot_file, dpi=150)
    print(f"\n  Plot saved: {plot_file}")
    plt.close()


def main():
    print("="*60)
    print(" HANN WINDOW VERIFICATION & SPECTRAL ANALYSIS")
    print("="*60)

    # Step 1: Verify coefficients
    coeffs = load_samples('hann_coefficients.txt')
    if coeffs is not None:
        coeff_pass = verify_coefficients(coeffs)
    else:
        coeff_pass = False
        print("\n[WARN] hann_coefficients.txt not found - skipping coefficient check")

    # Step 2: Analyze each test case
    tests = [
        (1, "On-bin (50.0 Hz)",               "50.0 Hz pure sine",
         "hann_test1_rect.txt", "hann_test1_hann.txt"),
        (2, "Off-bin (50.5 Hz)",              "50.5 Hz pure sine (between bins)",
         "hann_test2_rect.txt", "hann_test2_hann.txt"),
        (3, "Harmonic (50+150 Hz)",           "50 Hz + 10% 3rd harmonic @ 150 Hz",
         "hann_test3_rect.txt", "hann_test3_hann.txt"),
        (4, "Far off-bin (52.0 Hz)",          "52.0 Hz pure sine",
         "hann_test4_rect.txt", "hann_test4_hann.txt"),
    ]

    results = []
    for test_num, test_name, freq_desc, rect_file, hann_file in tests:
        r = analyze_test(test_num, test_name, freq_desc, rect_file, hann_file)
        results.append(r)

    # Step 3: Summary table
    print("\n" + "="*60)
    print(" SUMMARY")
    print("="*60)
    print(f"\n  {'Test':<30s} {'Rect SL (dB)':>13s} {'Hann SL (dB)':>13s} {'Improvement':>12s} {'Leak Rect%':>10s} {'Leak Hann%':>10s}")
    print(f"  {'-'*30} {'-'*13} {'-'*13} {'-'*12} {'-'*10} {'-'*10}")

    for r in results:
        if r is not None:
            improvement = r['rect_sidelobe'] - r['hann_sidelobe']
            print(f"  {r['test_name']:<30s} {r['rect_sidelobe']:>13.1f} {r['hann_sidelobe']:>13.1f} {improvement:>12.1f} {r['rect_leak']:>9.2f}% {r['hann_leak']:>9.2f}%")

    print(f"\n  Coefficient verification: {'PASS' if coeff_pass else 'FAIL/SKIP'}")
    print(f"\n  Theoretical sidelobe levels:")
    print(f"    Rectangular: -13 dB")
    print(f"    Hann:        -31 dB (18 dB improvement)")

    # Step 4: Plots
    plot_results(results)

    print("\n" + "="*60)
    print(" ANALYSIS COMPLETE")
    print("="*60)


if __name__ == '__main__':
    main()
