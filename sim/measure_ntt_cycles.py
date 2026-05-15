#!/usr/bin/env python3
"""
Measure ntt_top cycle counts for multiple (R, N) pairs via simulation.

Generates a twiddle file for each N, compiles tb_measure_cycles with
the corresponding R_VAL and N_VAL defines, runs vvp, and parses
METRIC_TOTAL_CYCLES from the output.

Usage:
    python sim/measure_ntt_cycles.py
    python sim/measure_ntt_cycles.py --radices 8 --n-values 64 128 256
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

Q = 65537

TOTAL_RE   = re.compile(r"METRIC_TOTAL_CYCLES\s+(\d+)")
COMPUTE_RE = re.compile(r"METRIC_COMPUTE_CYCLES\s+(\d+)")


def write_twiddles(work_dir: Path, n: int) -> None:
    """Write twiddle_factors.hex for a given N into work_dir."""
    # psi = primitive 2N-th root of unity = 3^(65536/(2N)) mod 65537
    psi = pow(3, 65536 // (2 * n), Q)
    with (work_dir / "twiddle_factors.hex").open("w", encoding="ascii") as f:
        for i in range(2 * n):
            f.write(f"{pow(psi, i, Q):05x}\n")


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)


def measure_one(repo_root: Path, work_dir: Path, radix: int, n: int) -> int:
    work_dir.mkdir(parents=True, exist_ok=True)
    write_twiddles(work_dir, n)

    rtl_files = sorted((repo_root / "rtl").glob("*.v"))
    tb_path = repo_root / "sim" / "testbenches" / "tb_measure_cycles.v"
    out_bin = work_dir / f"tb_cycles_r{radix}_n{n}"

    cmd_compile = [
        "iverilog",
        "-g2009",
        f"-DR_VAL={radix}",
        f"-DN_VAL={n}",
        f"-I{repo_root / 'rtl'}",
        "-o", str(out_bin),
        str(tb_path),
    ] + [str(p) for p in rtl_files]

    cp = run_cmd(cmd_compile, work_dir)
    if cp.returncode != 0:
        raise RuntimeError(f"Compile R={radix} N={n}:\n{cp.stdout}\n{cp.stderr}")

    rp = run_cmd(["vvp", str(out_bin)], work_dir)
    if rp.returncode != 0:
        raise RuntimeError(f"Sim R={radix} N={n}:\n{rp.stdout}\n{rp.stderr}")

    combined = rp.stdout + "\n" + rp.stderr
    mc = COMPUTE_RE.search(combined)
    mt = TOTAL_RE.search(combined)
    if not mc:
        raise RuntimeError(f"No METRIC_COMPUTE_CYCLES for R={radix} N={n}:\n{combined}")
    return int(mc.group(1)), int(mt.group(1)) if mt else -1


def main() -> int:
    parser = argparse.ArgumentParser(description="Measure ntt_top cycle counts")
    parser.add_argument("--radices", nargs="+", type=int, default=[4, 8, 16])
    parser.add_argument("--n-values", nargs="+", type=int, default=[64, 128, 256, 512])
    args = parser.parse_args()

    sim_dir = Path(__file__).resolve().parent
    repo_root = sim_dir.parent
    work_dir = sim_dir / "work" / "cycles"

    print(f"{'R':>4}  {'N':>6}  {'Compute':>9}  {'Total':>8}  (Compute = NTT1+NTT2+PWM+INTT, used for ATP)")
    print("-" * 44)

    results: dict[tuple[int, int], int] = {}
    failed = False

    for radix in args.radices:
        for n in args.n_values:
            try:
                compute, total = measure_one(repo_root, work_dir, radix, n)
                results[(radix, n)] = compute
                print(f"{radix:>4}  {n:>6}  {compute:>9}  {total:>8}")
            except Exception as exc:
                print(f"{radix:>4}  {n:>6}  ERROR: {exc}")
                failed = True

    # Print as TCL dict for easy copy-paste into vivado_synth_metrics.tcl
    print("\n# TCL cycles_map entries (compute cycles, for ATP calculation):")
    for (r, n), c in sorted(results.items()):
        print(f'    "{r}:{n}"   {c} \\')

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
