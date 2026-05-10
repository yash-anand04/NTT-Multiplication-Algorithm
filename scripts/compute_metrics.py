#!/usr/bin/env python3
from __future__ import annotations
"""
compute_metrics.py
==================
Extract Table IV metrics for the NTT RTL implementation.

Workflow:
  1. For each radix in {4, 8, 16}:
       a. Compile + simulate tb_measure_cycles.v -> get cycle counts
       b. (Optional) Read synth/r<N>/metrics_r<N>.txt  -> LUT/FF/DSP/BRAM/Fmax
  2. Compute derived metrics:
       - Time(us)  = COMPUTE_CYCLES / Fmax_MHz
       - ATP_X     = X_count x Time_us
  3. Print Table IV comparison rows vs paper reference values

Usage (from project root):
  python scripts/compute_metrics.py
  python scripts/compute_metrics.py --radices 4
  python scripts/compute_metrics.py --fmax 301 301 274   # override Fmax (no Vivado)
"""

import io
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

# Force UTF-8 output on Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

import argparse

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT  = SCRIPT_DIR.parent
SIM_DIR    = REPO_ROOT / "sim"
RTL_DIR    = REPO_ROOT / "rtl"
SYNTH_DIR  = REPO_ROOT / "synth"
TB_SRC     = SIM_DIR / "testbenches" / "tb_measure_cycles.v"
BIN_DIR    = SIM_DIR / "bin"

# Paper reference values from Table IV (Ours / Virtex-7 / N=256)
PAPER_REF = {
    4:  {"lut": 1690, "ff": 1289, "dsp": 4,  "bram": 0, "fmax": 301, "cycles": 876,  "time_us": 2.9},
    8:  {"lut": 3596, "ff": 2888, "dsp": 8,  "bram": 0, "fmax": 301, "cycles": 389,  "time_us": 1.3},
    16: {"lut": 8078, "ff": 6184, "dsp": 16, "bram": 0, "fmax": 274, "cycles": 197,  "time_us": 0.7},
}

# ---------------------------------------------------------------------------
# Step 1: Simulation - cycle counts
# ---------------------------------------------------------------------------

def get_rtl_files() -> list[str]:
    return sorted(str(p) for p in RTL_DIR.glob("*.v"))


def compile_tb(radix: int) -> Path:
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    out_bin = BIN_DIR / f"tb_measure_cycles_r{radix}"
    cmd = (
        ["iverilog", "-g2009", f"-DR_VAL={radix}", "-o", str(out_bin), str(TB_SRC)]
        + get_rtl_files()
    )
    r = subprocess.run(cmd, cwd=str(SIM_DIR), capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"iverilog failed R={radix}:\n{r.stdout}\n{r.stderr}")
    return out_bin


def simulate_cycles(radix: int) -> dict:
    out_bin = compile_tb(radix)
    r = subprocess.run(
        ["vvp", str(out_bin)],
        cwd=str(SIM_DIR), capture_output=True, text=True, timeout=300,
    )
    if r.returncode != 0:
        raise RuntimeError(f"vvp failed R={radix}:\n{r.stdout}\n{r.stderr}")

    metrics: dict = {}
    for line in (r.stdout + "\n" + r.stderr).splitlines():
        m = re.match(r"METRIC_(\w+)\s+(.+)", line.strip())
        if m:
            key = m.group(1).lower()
            try:
                metrics[key] = int(m.group(2).strip())
            except ValueError:
                metrics[key] = m.group(2).strip()

    if "compute_cycles" not in metrics:
        raise RuntimeError(
            f"No METRIC_COMPUTE_CYCLES in simulation output R={radix}.\n"
            f"{r.stdout}\n{r.stderr}"
        )
    return metrics

# ---------------------------------------------------------------------------
# Step 2: Vivado synthesis metrics (optional)
# ---------------------------------------------------------------------------

def read_synth_metrics(radix: int, synth_dir: Path) -> Optional[dict]:
    mfile = synth_dir / f"metrics_r{radix}.txt"
    if not mfile.exists():
        return None
    m: dict = {}
    for line in mfile.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            m[parts[0].lower()] = parts[1]

    def to_int(k):
        try:
            return int(m.get(k, ""))
        except (ValueError, TypeError):
            return None

    def to_float(k):
        try:
            return float(m.get(k, ""))
        except (ValueError, TypeError):
            return None

    return {
        "lut": to_int("lut"), "ff": to_int("ff"),
        "dsp": to_int("dsp"), "bram": to_int("bram"),
        "fmax_mhz": to_float("fmax_mhz"), "wns_ns": to_float("wns_ns"),
    }

# ---------------------------------------------------------------------------
# Step 3: Build row dict
# ---------------------------------------------------------------------------

def format_row(radix: int, sim: dict, synth: Optional[dict],
               fmax_override: Optional[float]) -> dict:
    compute_cycles = sim.get("compute_cycles", 0)

    fmax = None
    if synth and synth.get("fmax_mhz") is not None:
        fmax = synth["fmax_mhz"]
    elif fmax_override is not None:
        fmax = fmax_override
    else:
        fmax = PAPER_REF.get(radix, {}).get("fmax")  # fall back to paper value

    time_us = (compute_cycles / fmax) if (fmax and compute_cycles) else None

    lut  = synth["lut"]  if synth else None
    ff   = synth["ff"]   if synth else None
    dsp  = synth["dsp"]  if synth else None
    bram = synth["bram"] if synth else None

    def fmt_atp(val):
        if val is None or time_us is None:
            return "N/A"
        return f"{val}/{val * time_us:.1f}"

    return {
        "radix":          radix,
        "lut":            lut, "ff": ff, "dsp": dsp, "bram": bram,
        "fmax_mhz":       fmax,
        "load_cycles":    sim.get("load_cycles", 0),
        "ntt1_cycles":    sim.get("ntt1_cycles", 0),
        "ntt2_cycles":    sim.get("ntt2_cycles", 0),
        "pwm_cycles":     sim.get("pwm_cycles",  0),
        "intt_cycles":    sim.get("intt_cycles",  0),
        "output_cycles":  sim.get("output_cycles", 0),
        "compute_cycles": compute_cycles,
        "total_cycles":   sim.get("total_cycles", 0),
        "time_us":        time_us,
        "atp_lut":  fmt_atp(lut), "atp_ff":   fmt_atp(ff),
        "atp_dsp":  fmt_atp(dsp), "atp_bram": fmt_atp(bram),
    }

# ---------------------------------------------------------------------------
# Step 4: Print
# ---------------------------------------------------------------------------

def print_cycle_breakdown(rows: list[dict]) -> None:
    SEP = "=" * 75
    print()
    print(SEP)
    print("  CYCLE BREAKDOWN  (from simulation)")
    print(SEP)
    print(f"{'':6}  {'LOAD':>6}  {'NTT1':>6}  {'NTT2':>6}  {'PWM':>5}  "
          f"{'INTT':>6}  {'OUT':>6}  {'COMPUTE':>9}  {'TOTAL':>8}")
    print("-" * 75)
    for r in rows:
        rad = r["radix"]
        ref_cyc = PAPER_REF.get(rad, {}).get("cycles", "---")
        print(f"R={rad:<4d}  {r['load_cycles']:>6}  {r['ntt1_cycles']:>6}  "
              f"{r['ntt2_cycles']:>6}  {r['pwm_cycles']:>5}  "
              f"{r['intt_cycles']:>6}  {r['output_cycles']:>6}  "
              f"{r['compute_cycles']:>9}  {r['total_cycles']:>8}")
        print(f"       paper ref compute = {ref_cyc}  (Table IV)")
    print()


def print_table_iv(rows: list[dict]) -> None:
    SEP = "=" * 92
    print(SEP)
    print("  TABLE IV -- Implementation Metrics  (N=256, q=65537, Virtex-7 xc7vx485t)")
    print(SEP)
    print(f"{'':5}  {'LUT/ATP':>12}  {'FF/ATP':>12}  {'DSP/ATP':>10}  "
          f"{'BRAM/ATP':>10}  {'Fmax(MHz)':>9}  {'Compute':>8}  {'Time(us)':>8}")
    print("-" * 92)

    for r in rows:
        rad = r["radix"]
        fmax_s = f"{r['fmax_mhz']:.0f}" if r["fmax_mhz"] else "N/A"
        time_s = f"{r['time_us']:.2f}"   if r["time_us"]  else "N/A"
        print(f"R={rad:<3d}  "
              f"{r['atp_lut']:>12}  {r['atp_ff']:>12}  {r['atp_dsp']:>10}  "
              f"{r['atp_bram']:>10}  {fmax_s:>9}  "
              f"{r['compute_cycles']:>8}  {time_s:>8}")

        ref = PAPER_REF.get(rad, {})
        if ref:
            rt = ref["time_us"]
            rl, rf, rd, rb = ref["lut"], ref["ff"], ref["dsp"], ref["bram"]
            print(f"  paper  "
                  f"{rl}/{rl*rt:.1f}  {rf}/{rf*rt:.1f}  "
                  f"{rd}/{rd*rt:.1f}  {rb}/{rb*rt:.1f}  "
                  f"{ref['fmax']}MHz  {ref['cycles']}cyc  {rt}us")
        print()

    print(SEP)
    print("  ATP = resource_count x Time(us)")
    print("  Compute = NTT1+NTT2+PWM+INTT  (excludes LOAD and OUTPUT phases)")

    if not any(r["lut"] for r in rows):
        print()
        print("  [!] LUT/FF/DSP/BRAM show N/A -- Vivado synthesis not yet run.")
        print("  Run Vivado (batch) once per radix to fill in resource columns:")
        for r in rows:
            rad = r["radix"]
            print(f"      vivado -mode batch -source synth/synth_ntt.tcl "
                  f"-tclargs {rad} synth/r{rad}")
        print()
        print("  If you have Fmax from timing reports, pass it directly:")
        fmax_vals = " ".join(
            str(int(r["fmax_mhz"])) if r["fmax_mhz"] else "301"
            for r in rows
        )
        radix_vals = " ".join(str(r["radix"]) for r in rows)
        print(f"      python scripts/compute_metrics.py "
              f"--radices {radix_vals} --fmax {fmax_vals}")
    print(SEP)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Extract Table IV metrics from RTL")
    parser.add_argument("--radices", nargs="+", type=int, default=[4, 8, 16])
    parser.add_argument("--fmax", nargs="+", type=float, default=None,
                        help="Override Fmax (MHz) per radix, same order as --radices")
    parser.add_argument("--synth-dir", type=Path, default=SYNTH_DIR,
                        help="Directory containing metrics_rN.txt from Vivado")
    parser.add_argument("--no-sim", action="store_true",
                        help="Skip simulation (use zero cycle counts)")
    args = parser.parse_args()

    fmax_map: dict[int, Optional[float]] = {}
    if args.fmax:
        for i, rad in enumerate(args.radices):
            fmax_map[rad] = args.fmax[i] if i < len(args.fmax) else None

    rows = []
    for radix in args.radices:
        print(f"\n--- R={radix} " + "-" * 42)

        if not args.no_sim:
            print(f"  [1/2] Simulating cycle counts ...")
            try:
                sim = simulate_cycles(radix)
                print(f"        LOAD={sim.get('load_cycles',0)}  "
                      f"NTT1={sim.get('ntt1_cycles',0)}  "
                      f"NTT2={sim.get('ntt2_cycles',0)}  "
                      f"PWM={sim.get('pwm_cycles',0)}  "
                      f"INTT={sim.get('intt_cycles',0)}")
                print(f"        compute_cycles={sim['compute_cycles']}  "
                      f"total_cycles={sim['total_cycles']}")
            except Exception as exc:
                print(f"  ERROR: {exc}")
                sim = {k: 0 for k in ["compute_cycles","total_cycles","load_cycles",
                                       "ntt1_cycles","ntt2_cycles","pwm_cycles",
                                       "intt_cycles","output_cycles"]}
        else:
            sim = {k: 0 for k in ["compute_cycles","total_cycles","load_cycles",
                                   "ntt1_cycles","ntt2_cycles","pwm_cycles",
                                   "intt_cycles","output_cycles"]}

        print(f"  [2/2] Reading Vivado synthesis results ...")
        synth = read_synth_metrics(radix, args.synth_dir)
        if synth:
            print(f"        LUT={synth['lut']}  FF={synth['ff']}  "
                  f"DSP={synth['dsp']}  BRAM={synth['bram']}  "
                  f"Fmax={synth['fmax_mhz']} MHz")
        else:
            print(f"        (synth/r{radix}/metrics_r{radix}.txt not found)")

        rows.append(format_row(radix, sim, synth, fmax_map.get(radix)))

    print_cycle_breakdown(rows)
    print_table_iv(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
