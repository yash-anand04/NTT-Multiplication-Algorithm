#!/usr/bin/env python3
"""
Run end-to-end regression vectors across multiple radix configurations.

Default matrix:
- Radix:    4, 8, 16
- Vectors:  random, impulse, identity
"""

from __future__ import annotations

import argparse
import random
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable

N = 256
Q = 65537
OUTPUT_RE = re.compile(r"OUTPUT\[\s*(\d+)\]\s*=\s*([0-9a-fA-F]+)")


def write_hex(path: Path, values: Iterable[int]) -> None:
    with path.open("w", encoding="ascii") as f:
        for v in values:
            f.write(f"{v & 0x1FFFF:05x}\n")


def read_hex(path: Path, n: int = N) -> list[int]:
    lines = path.read_text(encoding="ascii").splitlines()[:n]
    return [int(x.strip(), 16) for x in lines]


def poly_mul_direct(a: list[int], b: list[int], q: int = Q, n: int = N) -> list[int]:
    c = [0] * n
    for i in range(n):
        ai = a[i]
        for j in range(n):
            prod = (ai * b[j]) % q
            s = i + j
            k = s % n
            if s >= n:
                c[k] = (c[k] - prod) % q
            else:
                c[k] = (c[k] + prod) % q
    return c


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)


def prepare_vectors(case_name: str, repo_root: Path, sim_dir: Path) -> Path:
    py = sys.executable

    if case_name == "random":
        proc = run_cmd([py, str(repo_root / "scripts" / "golden_model.py")], cwd=sim_dir)
        if proc.returncode != 0:
            raise RuntimeError(f"golden_model failed:\n{proc.stdout}\n{proc.stderr}")
        return sim_dir / "expected_out.hex"

    if case_name == "impulse":
        a = [0] * N
        b = [0] * N
        a[0] = 1
        b[0] = 1
        expected = [0] * N
        expected[0] = 1
    elif case_name == "identity":
        rng = random.Random(7)
        a = [rng.randrange(Q) for _ in range(N)]
        b = [0] * N
        b[0] = 1
        expected = a[:]
    else:
        raise ValueError(f"Unsupported case: {case_name}")

    write_hex(sim_dir / "input_a.hex", a)
    write_hex(sim_dir / "input_b.hex", b)
    write_hex(sim_dir / "expected_direct.hex", expected)
    return sim_dir / "expected_direct.hex"


def parse_rtl_output(raw_text: str) -> list[int]:
    outputs = [0] * N
    seen = 0
    for line in raw_text.splitlines():
        m = OUTPUT_RE.search(line)
        if not m:
            continue
        idx = int(m.group(1))
        val = int(m.group(2), 16)
        if 0 <= idx < N:
            outputs[idx] = val
            seen += 1
    if seen < N:
        raise RuntimeError(f"Captured only {seen}/{N} OUTPUT lines")
    return outputs


def run_one(radix: int, case_name: str, expected_path: Path, repo_root: Path, sim_dir: Path) -> tuple[int, int]:
    rtl_files = sorted((repo_root / "rtl").glob("*.v"))
    if not rtl_files:
        raise RuntimeError("No RTL files found under rtl/")

    out_bin = sim_dir / "bin" / f"tb_ntt_capture_r{radix}_{case_name}"
    cmd_compile = [
        "iverilog",
        "-g2009",
        "-I../rtl",
        f"-DR_VAL={radix}",
        "-o",
        str(out_bin),
        "testbenches/tb_ntt_capture.v",
    ] + [str(p) for p in rtl_files]

    cp = run_cmd(cmd_compile, cwd=sim_dir)
    if cp.returncode != 0:
        raise RuntimeError(f"Compile failed for R={radix}, case={case_name}:\n{cp.stdout}\n{cp.stderr}")

    rp = run_cmd(["vvp", str(out_bin)], cwd=sim_dir)
    if rp.returncode != 0:
        raise RuntimeError(f"Simulation failed for R={radix}, case={case_name}:\n{rp.stdout}\n{rp.stderr}")

    rtl = parse_rtl_output(rp.stdout + "\n" + rp.stderr)
    expected = read_hex(expected_path)
    matches = sum(1 for i in range(N) if rtl[i] == expected[i])

    out_txt = sim_dir / f"outputs_{case_name}_r{radix}.txt"
    with out_txt.open("w", encoding="ascii") as f:
        for i, val in enumerate(rtl):
            f.write(f"{i}: {val:05x}\n")

    return matches, N


def main() -> int:
    parser = argparse.ArgumentParser(description="Run radix regression matrix for ntt_top")
    parser.add_argument("--radices", nargs="+", type=int, default=[4, 8, 16], help="Radix values to test")
    parser.add_argument(
        "--cases",
        nargs="+",
        default=["random", "impulse", "identity"],
        choices=["random", "impulse", "identity"],
        help="Vector cases to test",
    )
    args = parser.parse_args()

    sim_dir = Path(__file__).resolve().parent
    repo_root = sim_dir.parent

    # Ensure twiddle factors exist before non-random cases.
    prep = run_cmd([sys.executable, str(repo_root / "scripts" / "golden_model.py")], cwd=sim_dir)
    if prep.returncode != 0:
        print(prep.stdout)
        print(prep.stderr)
        print("Failed to initialize vectors/twiddles.")
        return 2

    failed = False
    for case_name in args.cases:
        expected_path = prepare_vectors(case_name, repo_root, sim_dir)
        for radix in args.radices:
            try:
                matches, total = run_one(radix, case_name, expected_path, repo_root, sim_dir)
                print(f"case={case_name:8s} R={radix:2d} matches={matches}/{total}")
                if matches != total:
                    failed = True
            except Exception as exc:
                print(f"case={case_name:8s} R={radix:2d} ERROR: {exc}")
                failed = True

    # Restore default deterministic random vectors for normal workflow.
    run_cmd([sys.executable, str(repo_root / "scripts" / "golden_model.py")], cwd=sim_dir)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
