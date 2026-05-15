#!/usr/bin/env python3
"""
plot_scaling.py
===============
Generate publication-quality scaling plots comparing ntt_top (R=8) against
bivar_ntt_top (L=8) across N = 64, 128, 256.

Produces four figures saved to docs/figures/:
  1. cycles_vs_n.pdf      -- Total latency cycles vs N (both designs)
  2. dsp_atp_vs_n.pdf     -- DSP × cycles vs N
  3. lut_atp_vs_n.pdf     -- LUT × cycles vs N (requires synthesis data)
  4. dsp_count_vs_n.pdf   -- DSP count vs N (shows bivar reuse advantage)

Usage:
    python scripts/plot_scaling.py              # all plots
    python scripts/plot_scaling.py --no-synth   # skip LUT plot (no synthesis data)
"""

from __future__ import annotations

import argparse
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT  = SCRIPT_DIR.parent
SYNTH_DIR  = REPO_ROOT / "synth"
FIG_DIR    = REPO_ROOT / "docs" / "figures"

N_VALUES = [64, 128, 256]

# Simulation-derived total cycle counts
CYCLES_NTT8  = {64: 185, 128: 417, 256: 833}
CYCLES_BIVAR = {64: 208, 128: 392, 256: 760}

# Analytic DSP counts (used when synthesis data not available)
DSP_NTT8  = 32   # constant for all N (8 mod_mul, 4 DSPs each)
DSP_BIVAR = 8    # constant for all N (8 lanes, 1 mod_mul each)


def read_metric(synth_dir: Path, design: str, n: int, key: str) -> float | None:
    if design == "ntt8":
        path = synth_dir / f"results_r8_n{n}" / "metrics_raw.txt"
    else:
        path = synth_dir / f"results_bivar_n{n}" / "metrics_raw.txt"
    if not path.exists():
        return None
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            if k.strip() == key:
                try:
                    return float(v.strip())
                except ValueError:
                    return None
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-synth", action="store_true",
                        help="Skip plots that require synthesis data")
    parser.add_argument("--show", action="store_true",
                        help="Show plots interactively instead of saving")
    args = parser.parse_args()

    try:
        import matplotlib
        if not args.show:
            matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import matplotlib.ticker as ticker
    except ImportError:
        print("ERROR: matplotlib not installed. Run: pip install matplotlib")
        return 1

    FIG_DIR.mkdir(parents=True, exist_ok=True)

    plt.rcParams.update({
        "font.family": "serif",
        "font.size": 11,
        "axes.labelsize": 12,
        "axes.titlesize": 13,
        "legend.fontsize": 10,
        "xtick.labelsize": 10,
        "ytick.labelsize": 10,
        "figure.dpi": 150,
    })

    ns = N_VALUES
    cyc_ntt  = [CYCLES_NTT8[n]  for n in ns]
    cyc_biv  = [CYCLES_BIVAR[n] for n in ns]

    # ---- 1. Cycles vs N ----
    fig, ax = plt.subplots(figsize=(5.5, 4))
    ax.plot(ns, cyc_ntt,  "o-", label=f"ntt_top R=8  ({DSP_NTT8} DSPs)", color="steelblue")
    ax.plot(ns, cyc_biv,  "s--", label=f"bivar L=8  ({DSP_BIVAR} DSPs)", color="tomato")
    ax.set_xlabel("Polynomial degree N")
    ax.set_ylabel("Total latency (cycles)")
    ax.set_title("Latency Scaling: ntt_top vs bivar_ntt_top")
    ax.set_xticks(ns)
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    out = FIG_DIR / "cycles_vs_n.pdf"
    fig.savefig(out)
    print(f"Saved: {out}")
    if args.show:
        plt.show()
    plt.close()

    # ---- 2. DSP-ATP vs N ----
    dsp_atp_ntt = [DSP_NTT8  * CYCLES_NTT8[n]  for n in ns]
    dsp_atp_biv = [DSP_BIVAR * CYCLES_BIVAR[n] for n in ns]
    ratio       = [n / b for n, b in zip(dsp_atp_ntt, dsp_atp_biv)]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))

    ax1.plot(ns, dsp_atp_ntt, "o-", label=f"ntt_top R=8", color="steelblue")
    ax1.plot(ns, dsp_atp_biv, "s--", label=f"bivar L=8",  color="tomato")
    ax1.set_xlabel("N")
    ax1.set_ylabel("DSP × Cycles")
    ax1.set_title("DSP-ATP")
    ax1.set_xticks(ns)
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    ax2.bar([str(n) for n in ns], ratio, color="mediumseagreen")
    ax2.axhline(1.0, color="grey", linestyle="--", linewidth=0.8)
    ax2.set_xlabel("N")
    ax2.set_ylabel("ntt_top / bivar  (> 1 = bivar better)")
    ax2.set_title("DSP-ATP Ratio")
    ax2.grid(True, alpha=0.3, axis="y")

    fig.suptitle("DSP Area-Time Product: ntt_top (R=8) vs bivar_ntt_top (L=8)")
    fig.tight_layout()
    out = FIG_DIR / "dsp_atp_vs_n.pdf"
    fig.savefig(out)
    print(f"Saved: {out}")
    if args.show:
        plt.show()
    plt.close()

    # ---- 3. LUT-ATP vs N (synthesis data required) ----
    lut_ntt  = [read_metric(SYNTH_DIR, "ntt8",  n, "LUT") for n in ns]
    lut_biv  = [read_metric(SYNTH_DIR, "bivar", n, "LUT") for n in ns]

    if args.no_synth or all(v is None for v in lut_ntt + lut_biv):
        print("Skipping LUT-ATP plot (no synthesis data; run vivado_run_all_metrics.ps1)")
    else:
        lut_atp_ntt = [l * CYCLES_NTT8[n]  if l else None for l, n in zip(lut_ntt,  ns)]
        lut_atp_biv = [l * CYCLES_BIVAR[n] if l else None for l, n in zip(lut_biv, ns)]

        fig, ax = plt.subplots(figsize=(5.5, 4))
        ns_ntt_valid = [n for n, v in zip(ns, lut_atp_ntt) if v is not None]
        ns_biv_valid = [n for n, v in zip(ns, lut_atp_biv) if v is not None]
        ax.plot(ns_ntt_valid, [v for v in lut_atp_ntt if v], "o-",
                label="ntt_top R=8", color="steelblue")
        ax.plot(ns_biv_valid, [v for v in lut_atp_biv if v], "s--",
                label="bivar L=8", color="tomato")
        ax.set_xlabel("N")
        ax.set_ylabel("LUT × Cycles")
        ax.set_title("LUT-ATP Scaling")
        ax.set_xticks(ns)
        ax.legend()
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        out = FIG_DIR / "lut_atp_vs_n.pdf"
        fig.savefig(out)
        print(f"Saved: {out}")
        if args.show:
            plt.show()
        plt.close()

    # ---- 4. DSP count vs N (shows resource reuse) ----
    fig, ax = plt.subplots(figsize=(5, 3.5))
    dsp_ntt_vals  = [read_metric(SYNTH_DIR, "ntt8",  n, "DSP") or DSP_NTT8  for n in ns]
    dsp_biv_vals  = [read_metric(SYNTH_DIR, "bivar", n, "DSP") or DSP_BIVAR for n in ns]
    bar_w = 18
    x = [n for n in ns]
    ax.bar([xi - bar_w/2 for xi in x], dsp_ntt_vals, width=bar_w,
           label=f"ntt_top R=8", color="steelblue", alpha=0.8)
    ax.bar([xi + bar_w/2 for xi in x], dsp_biv_vals, width=bar_w,
           label=f"bivar L=8",   color="tomato",    alpha=0.8)
    ax.set_xlabel("N")
    ax.set_ylabel("DSP count")
    ax.set_title("DSP Utilization vs N")
    ax.set_xticks(ns)
    ax.legend()
    ax.grid(True, alpha=0.3, axis="y")
    fig.tight_layout()
    out = FIG_DIR / "dsp_count_vs_n.pdf"
    fig.savefig(out)
    print(f"Saved: {out}")
    if args.show:
        plt.show()
    plt.close()

    print(f"\nAll figures saved to {FIG_DIR}")
    print("Run Vivado synthesis to fill in LUT/Fmax data for the remaining plots.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
