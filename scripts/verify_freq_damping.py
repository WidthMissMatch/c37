#!/usr/bin/env python3
"""
Frequency Damping Filter Verification & Analysis
=================================================

Reads VHDL simulation output files and performs:
1. Python IIR reference computation
2. VHDL vs Python comparison (fixed-point accuracy)
3. Key metrics: spike suppression, settling time, tracking error
4. Comparison plots across alpha values

Usage:
    cd "c37 compliance/sim_output"
    python3 ../scripts/verify_freq_damping.py

Input files (from GHDL simulation):
    freq_damp_alpha01.txt  (alpha = 0.1)
    freq_damp_alpha03.txt  (alpha = 0.3)
    freq_damp_alpha05.txt  (alpha = 0.5)
"""

import numpy as np
import os
import sys

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("[INFO] matplotlib not found - text-only analysis")

Q16_16 = 65536.0  # Q16.16 scale factor

SCENARIO_NAMES = {
    1: "Steady State (50 Hz)",
    2: "Single Spike (56.33 Hz)",
    3: "Frequency Ramp (50→51 Hz)",
    4: "Step Change (50→51 Hz)",
    5: "Real PMU Startup Pattern",
    6: "Oscillating (50 ±0.5 Hz)",
}

ALPHA_LABELS = {
    'alpha01': ('α=0.1', 0.1),
    'alpha03': ('α=0.3', 0.3),
    'alpha05': ('α=0.5', 0.5),
}


def load_data(filename):
    """Load scenario data: returns dict of {scenario_id: [(input_q16, output_q16), ...]}"""
    if not os.path.exists(filename):
        print(f"  [SKIP] {filename} not found")
        return None
    data = {}
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 3:
                scen = int(parts[0])
                inp = int(parts[1])
                out = int(parts[2])
                if scen not in data:
                    data[scen] = []
                data[scen].append((inp, out))
    return data


def python_iir_reference(inputs_q16, alpha, init_hz=50.0):
    """Compute Python IIR reference in Q16.16 domain (matching VHDL exactly)."""
    init_q16 = int(init_hz * Q16_16)
    alpha_q16 = int(alpha * Q16_16)

    outputs = []
    f_prev = inputs_q16[0]  # First sample initializes directly

    for i in range(1, len(inputs_q16)):
        diff = inputs_q16[i] - f_prev
        # Match VHDL: product = diff * alpha, shift right 16 with rounding
        product = diff * alpha_q16
        correction = (product + 32768) >> 16  # Round
        f_new = f_prev + correction
        # Saturation
        f_new = max(-2147483648, min(2147483647, f_new))
        outputs.append(f_new)
        f_prev = f_new

    return outputs


def analyze_scenario(scen_id, scen_name, all_data):
    """Analyze one scenario across all alpha values."""
    print(f"\n{'='*65}")
    print(f" SCENARIO {scen_id}: {scen_name}")
    print(f"{'='*65}")

    results = {}

    for alpha_key in ['alpha01', 'alpha03', 'alpha05']:
        label, alpha_val = ALPHA_LABELS[alpha_key]
        data = all_data.get(alpha_key)
        if data is None or scen_id not in data:
            continue

        pairs = data[scen_id]
        inputs_q16 = [p[0] for p in pairs]
        outputs_q16 = [p[1] for p in pairs]

        # Need one more input for reference (first sample is init)
        # Reconstruct full input sequence: first sample = init, then inputs_q16
        full_inputs = [int(50.0 * Q16_16)] + inputs_q16  # prepend init
        py_ref = python_iir_reference(full_inputs, alpha_val)

        # Convert to Hz for display
        inputs_hz = np.array(inputs_q16) / Q16_16
        outputs_hz = np.array(outputs_q16) / Q16_16
        py_ref_hz = np.array(py_ref) / Q16_16

        # Compute errors
        n = min(len(outputs_q16), len(py_ref))
        vhdl_arr = np.array(outputs_q16[:n])
        py_arr = np.array(py_ref[:n])
        errors_q16 = np.abs(vhdl_arr - py_arr)
        errors_hz = errors_q16 / Q16_16

        max_err_hz = np.max(errors_hz) if len(errors_hz) > 0 else 0
        rms_err_hz = np.sqrt(np.mean(errors_hz**2)) if len(errors_hz) > 0 else 0

        # Scenario-specific metrics
        metrics = {}

        if scen_id == 1:
            # Steady state: final value should be 50.0 Hz
            final_hz = outputs_hz[-1] if len(outputs_hz) > 0 else 0
            metrics['final_value'] = final_hz
            metrics['final_error'] = abs(final_hz - 50.0)

        elif scen_id == 2:
            # Spike: measure peak output and suppression ratio
            spike_input = 56.33
            peak_output = np.max(outputs_hz)
            suppression = spike_input - 50.0 - (peak_output - 50.0)
            suppression_pct = (1.0 - (peak_output - 50.0) / (spike_input - 50.0)) * 100
            # Recovery: how many samples to get within 0.01 Hz of 50.0
            recovery = -1
            for i in range(len(outputs_hz)):
                if outputs_hz[i] > 50.0 + 0.01 and i > 3:
                    continue
                elif i > 3 and abs(outputs_hz[i] - 50.0) < 0.01:
                    recovery = i
                    break
            metrics['peak_output'] = peak_output
            metrics['suppression_pct'] = suppression_pct
            metrics['recovery_samples'] = recovery

        elif scen_id == 4:
            # Step: measure settling time (within 1% of 51.0)
            target = 51.0
            settled = -1
            for i in range(len(outputs_hz)):
                if abs(outputs_hz[i] - target) < 0.01:
                    settled = i
                    break
            metrics['settling_samples'] = settled
            metrics['final_value'] = outputs_hz[-1] if len(outputs_hz) > 0 else 0

        elif scen_id == 6:
            # Oscillation: measure amplitude attenuation
            if len(outputs_hz) > 10:
                in_amp = (np.max(inputs_hz[5:]) - np.min(inputs_hz[5:])) / 2
                out_amp = (np.max(outputs_hz[5:]) - np.min(outputs_hz[5:])) / 2
                metrics['input_amplitude'] = in_amp
                metrics['output_amplitude'] = out_amp
                metrics['attenuation_pct'] = (1.0 - out_amp / in_amp) * 100 if in_amp > 0 else 0

        results[alpha_key] = {
            'label': label,
            'alpha': alpha_val,
            'inputs_hz': inputs_hz,
            'outputs_hz': outputs_hz,
            'py_ref_hz': py_ref_hz,
            'max_err_hz': max_err_hz,
            'rms_err_hz': rms_err_hz,
            'metrics': metrics,
        }

    # Print comparison table
    print(f"\n  {'Metric':<30s}", end='')
    for ak in ['alpha01', 'alpha03', 'alpha05']:
        if ak in results:
            print(f" {results[ak]['label']:>14s}", end='')
    print()
    print(f"  {'-'*30}", end='')
    for ak in ['alpha01', 'alpha03', 'alpha05']:
        if ak in results:
            print(f" {'-'*14}", end='')
    print()

    # VHDL vs Python accuracy
    print(f"  {'Max error (Hz) VHDL vs Py':<30s}", end='')
    for ak in ['alpha01', 'alpha03', 'alpha05']:
        if ak in results:
            print(f" {results[ak]['max_err_hz']:>14.6f}", end='')
    print()

    print(f"  {'RMS error (Hz) VHDL vs Py':<30s}", end='')
    for ak in ['alpha01', 'alpha03', 'alpha05']:
        if ak in results:
            print(f" {results[ak]['rms_err_hz']:>14.6f}", end='')
    print()

    # Scenario-specific metrics
    if scen_id == 1:
        print(f"  {'Final value (Hz)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('final_value', 0)
                print(f" {v:>14.6f}", end='')
        print()

    elif scen_id == 2:
        print(f"  {'Peak output (Hz)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('peak_output', 0)
                print(f" {v:>14.4f}", end='')
        print()

        print(f"  {'Spike suppression (%)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('suppression_pct', 0)
                print(f" {v:>13.1f}%", end='')
        print()

        print(f"  {'Recovery (samples to ±0.01)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('recovery_samples', -1)
                s = str(v) if v >= 0 else ">N"
                print(f" {s:>14s}", end='')
        print()

    elif scen_id == 4:
        print(f"  {'Settling time (samples)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('settling_samples', -1)
                s = str(v) if v >= 0 else ">N"
                print(f" {s:>14s}", end='')
        print()

        print(f"  {'Final value (Hz)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('final_value', 0)
                print(f" {v:>14.6f}", end='')
        print()

    elif scen_id == 6:
        print(f"  {'Output amplitude (Hz)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('output_amplitude', 0)
                print(f" {v:>14.4f}", end='')
        print()

        print(f"  {'Attenuation (%)':<30s}", end='')
        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in results:
                v = results[ak]['metrics'].get('attenuation_pct', 0)
                print(f" {v:>13.1f}%", end='')
        print()

    return results


def plot_all(all_results):
    """Generate comparison plots for all scenarios."""
    if not HAS_MATPLOTLIB:
        print("\n[INFO] Skipping plots (no matplotlib)")
        return

    scenarios = sorted(all_results.keys())
    n_scen = len(scenarios)
    fig, axes = plt.subplots(n_scen, 1, figsize=(14, 4 * n_scen), sharex=False)
    if n_scen == 1:
        axes = [axes]

    colors = {'alpha01': 'green', 'alpha03': 'blue', 'alpha05': 'orange'}

    for idx, scen_id in enumerate(scenarios):
        ax = axes[idx]
        scen_results = all_results[scen_id]

        # Plot input (same for all alphas)
        first_key = list(scen_results.keys())[0]
        inputs = scen_results[first_key]['inputs_hz']
        n_pts = len(inputs)
        x = np.arange(n_pts)

        ax.plot(x, inputs, 'k--', linewidth=1.5, alpha=0.6, label='Input (raw)')

        for ak in ['alpha01', 'alpha03', 'alpha05']:
            if ak in scen_results:
                r = scen_results[ak]
                out = r['outputs_hz']
                ax.plot(x[:len(out)], out, color=colors[ak], linewidth=1.5,
                        label=f"Filtered {r['label']}")

        ax.set_title(f"Scenario {scen_id}: {SCENARIO_NAMES.get(scen_id, '?')}", fontsize=12, fontweight='bold')
        ax.set_xlabel('Sample')
        ax.set_ylabel('Frequency (Hz)')
        ax.legend(fontsize=9, loc='best')
        ax.grid(True, alpha=0.3)

        # Add reference line at 50 Hz
        ax.axhline(y=50.0, color='gray', linestyle=':', alpha=0.4)

    plt.tight_layout()
    plot_file = 'freq_damping_analysis.png'
    plt.savefig(plot_file, dpi=150)
    print(f"\n  Plot saved: {plot_file}")
    plt.close()


def main():
    print("=" * 65)
    print(" FREQUENCY DAMPING FILTER VERIFICATION")
    print("=" * 65)

    # Load all data files
    all_data = {}
    for alpha_key in ['alpha01', 'alpha03', 'alpha05']:
        fname = f"freq_damp_{alpha_key}.txt"
        data = load_data(fname)
        if data is not None:
            all_data[alpha_key] = data
            n_scenarios = len(data)
            n_samples = sum(len(v) for v in data.values())
            print(f"  Loaded {fname}: {n_scenarios} scenarios, {n_samples} samples")
        else:
            print(f"  MISSING: {fname}")

    if not all_data:
        print("\n[ERROR] No data files found. Run GHDL simulation first.")
        return

    # Analyze each scenario
    all_results = {}
    for scen_id in sorted(SCENARIO_NAMES.keys()):
        results = analyze_scenario(scen_id, SCENARIO_NAMES[scen_id], all_data)
        if results:
            all_results[scen_id] = results

    # Summary table
    print(f"\n{'='*65}")
    print(f" SUMMARY: ALPHA SELECTION GUIDE")
    print(f"{'='*65}")
    print(f"""
  Alpha=0.1 (slow):  Best spike suppression, slowest tracking
                     Use when: stability > speed (steady-state PMU)

  Alpha=0.3 (default): Good balance of suppression and tracking
                     Use when: general purpose (recommended for your PMU)

  Alpha=0.5 (fast):  Fastest tracking, moderate suppression
                     Use when: frequency changes rapidly (transient events)

  Key trade-off: Lower alpha = better spike rejection but slower step response
                 Higher alpha = faster tracking but less noise suppression
    """)

    # Plots
    plot_all(all_results)

    print("=" * 65)
    print(" ANALYSIS COMPLETE")
    print("=" * 65)


if __name__ == '__main__':
    main()
