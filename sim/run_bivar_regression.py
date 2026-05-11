#!/usr/bin/env python3
"""
Kim et al. bivariate NTT regression harness.

Runs two tiers:
  1. Python model tier  : verifies the bivariate algebraic model against
                          direct negacyclic convolution (scripts/bivar_ntt_model.py).
  2. RTL simulation tier: compiles bivar_ntt_top and runs iverilog/vvp against
                          poly_mul_direct reference for each test vector.
"""

from __future__ import annotations

import argparse
import random
import re
import subprocess
import sys
from pathlib import Path

N = 256
Q = 65537
K = 16        # Fermat parameter: P = 2^K+1 = 65537
L = K // 2    # Row dimension (8-pt shift-only NTT)
M = N // L    # Column dimension (32-pt shift-only NTT)

OUTPUT_RE = re.compile(r"OUTPUT\[\s*(\d+)\]\s*=\s*([0-9a-fA-F]+)")
CYCLES_RE = re.compile(r"BIVAR_CYCLES=(\d+)")


def add_repo_imports(repo_root: Path) -> None:
    scripts_dir = repo_root / "scripts"
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))


def write_hex(path: Path, values: list[int]) -> None:
    with path.open("w", encoding="ascii") as f:
        for v in values:
            f.write(f"{v & 0x1FFFF:05x}\n")


def read_hex(path: Path) -> list[int]:
    return [int(x.strip(), 16) for x in path.read_text(encoding="ascii").splitlines()[:N]]


def run_cmd(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)


def generate_twiddles(sim_dir: Path) -> None:
    from bivar_ntt_model import get_psi
    psi = get_psi(N, Q)
    write_hex(sim_dir / "twiddle_factors.hex", [pow(psi, i, Q) for i in range(2 * N)])


def vector_case(name: str, rng: random.Random) -> tuple[list[int], list[int]]:
    if name == "random":
        return [rng.randrange(Q) for _ in range(N)], [rng.randrange(Q) for _ in range(N)]
    if name == "impulse":
        a = [0] * N; a[0] = 1
        b = [0] * N; b[0] = 1
        return a, b
    if name == "identity":
        a = [0] * N; a[0] = 1
        b = [rng.randrange(Q) for _ in range(N)]
        return a, b
    if name == "zero":
        return [0] * N, [rng.randrange(Q) for _ in range(N)]
    if name == "qminus1":
        return [Q - 1] * N, [Q - 1] * N
    if name == "alternating":
        a = [(1 if i % 2 == 0 else Q - 1) for i in range(N)]
        b = [rng.randrange(Q) for _ in range(N)]
        return a, b
    raise ValueError(f"unknown case {name}")


def poly_mul_direct(a: list[int], b: list[int]) -> list[int]:
    out = [0] * N
    for i, ai in enumerate(a):
        for j, bj in enumerate(b):
            prod = (ai * bj) % Q
            total = i + j
            idx = total % N
            out[idx] = (out[idx] - prod if total >= N else out[idx] + prod) % Q
    return out


def compile_rtl(repo_root: Path, sim_dir: Path) -> Path:
    rtl_files = sorted((repo_root / "rtl").glob("*.v"))
    out_bin = sim_dir / "bin" / "tb_bivar_ntt_capture"
    out_bin.parent.mkdir(exist_ok=True)
    cmd = [
        "iverilog",
        "-g2009",
        "-I../rtl",
        "-o", str(out_bin),
        "testbenches/tb_bivar_ntt_capture.v",
    ] + [str(p) for p in rtl_files]
    cp = run_cmd(cmd, sim_dir)
    if cp.returncode != 0:
        raise RuntimeError(f"RTL compile failed:\n{cp.stdout}\n{cp.stderr}")
    return out_bin


def parse_outputs(raw: str) -> list[int]:
    out = [0] * N
    seen = 0
    for line in raw.splitlines():
        m = OUTPUT_RE.search(line)
        if not m:
            continue
        idx = int(m.group(1))
        val = int(m.group(2), 16)
        if 0 <= idx < N:
            out[idx] = val
            seen += 1
    if seen != N:
        raise RuntimeError(f"captured {seen}/{N} output coefficients")
    return out


def run_rtl_case(
    out_bin: Path,
    case_label: str,
    a: list[int],
    b: list[int],
    expected: list[int],
    sim_dir: Path,
) -> tuple[bool, int]:
    write_hex(sim_dir / "input_a.hex", a)
    write_hex(sim_dir / "input_b.hex", b)
    write_hex(sim_dir / "expected_direct.hex", expected)

    rp = run_cmd(["vvp", str(out_bin)], sim_dir)
    if rp.returncode != 0:
        raise RuntimeError(f"simulation failed for {case_label}:\n{rp.stdout}\n{rp.stderr}")

    combined = rp.stdout + "\n" + rp.stderr
    got = parse_outputs(combined)
    matches = sum(1 for i in range(N) if got[i] == expected[i])

    cm = CYCLES_RE.search(combined)
    cycles = int(cm.group(1)) if cm else -1

    ok = matches == N
    print(f"rtl case={case_label:16s} matches={matches}/{N} cycles={cycles}")
    if not ok:
        first = next(i for i in range(N) if got[i] != expected[i])
        print(f"  first_mismatch idx={first} got={got[first]:05x} exp={expected[first]:05x}")
    return ok, cycles


def run_model_tier(pairs: list[tuple[int, int]], random_count: int, q: int) -> bool:
    from bivar_ntt_model import estimate_bivar_cost, run_bivar_checks
    failed = False
    for n, k in pairs:
        try:
            run_bivar_checks(n=n, k=k, q=q, random_count=random_count, exhaustive_limit=8)
            est = estimate_bivar_cost(n, k)
            print(
                f"model pair={n}:{k} PASS  L={est.l_dim} M={est.m_dim} "
                f"active={est.active_coeffs}"
            )
        except Exception as exc:
            print(f"model pair={n}:{k} FAIL: {exc}")
            failed = True
    return not failed


def main() -> int:
    parser = argparse.ArgumentParser(description="Bivariate NTT Kim et al. regression")
    parser.add_argument(
        "--cases",
        nargs="+",
        default=["random", "impulse", "identity", "zero", "qminus1", "alternating"],
        choices=["random", "impulse", "identity", "zero", "qminus1", "alternating"],
    )
    parser.add_argument("--random-count", type=int, default=50)
    parser.add_argument("--skip-model-tier", action="store_true")
    parser.add_argument("--skip-rtl-tier", action="store_true")
    args = parser.parse_args()

    sim_dir = Path(__file__).resolve().parent
    repo_root = sim_dir.parent
    add_repo_imports(repo_root)

    generate_twiddles(sim_dir)

    failed = False

    if not args.skip_model_tier:
        model_pairs = [(16, 8), (32, 8), (N, K)]
        if not run_model_tier(model_pairs, random_count=200, q=Q):
            failed = True

    if not args.skip_rtl_tier:
        out_bin = compile_rtl(repo_root, sim_dir)
        rng = random.Random(42)
        cycles_list: list[int] = []

        for case_name in args.cases:
            repeat = args.random_count if case_name == "random" else 1
            for idx in range(repeat):
                a, b = vector_case(case_name, rng)
                label = f"{case_name}_{idx}" if repeat > 1 else case_name
                exp = poly_mul_direct(a, b)
                ok, cyc = run_rtl_case(out_bin, label, a, b, exp, sim_dir)
                if not ok:
                    failed = True
                if cyc >= 0:
                    cycles_list.append(cyc)

        if cycles_list:
            avg = sum(cycles_list) / len(cycles_list)
            print(f"\nRTL cycle summary: min={min(cycles_list)} "
                  f"max={max(cycles_list)} avg={avg:.1f} over {len(cycles_list)} cases")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
