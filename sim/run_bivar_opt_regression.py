#!/usr/bin/env python3
"""
bivar_opt regression: RTL tier only.  Compares bivar_opt_top against
poly_mul_direct golden reference for a handful of test vectors.
"""
from __future__ import annotations

import argparse
import random
import re
import subprocess
import sys
from pathlib import Path

Q = 65537
OUTPUT_RE = re.compile(r"OUTPUT\[\s*(\d+)\]\s*=\s*([0-9a-fA-F]+)")
CYCLES_RE = re.compile(r"BIVAR_OPT_CYCLES=(\d+)")


def write_hex(path, values):
    with open(path, "w", encoding="ascii") as f:
        for v in values:
            f.write(f"{v & 0x1FFFF:05x}\n")


def poly_mul_direct(a, b, n):
    out = [0] * n
    for i, ai in enumerate(a):
        for j, bj in enumerate(b):
            prod = (ai * bj) % Q
            total = i + j
            idx = total % n
            out[idx] = (out[idx] - prod if total >= n else out[idx] + prod) % Q
    return out


def vector(case, n, rng):
    if case == "random":
        return [rng.randrange(Q) for _ in range(n)], [rng.randrange(Q) for _ in range(n)]
    if case == "impulse":
        a = [0] * n; a[0] = 1
        b = [rng.randrange(Q) for _ in range(n)]
        return a, b
    if case == "identity":
        a = [0] * n; a[0] = 1
        b = [0] * n; b[0] = 1
        return a, b
    raise ValueError(case)


def parse_outputs(raw, n):
    out = [0] * n
    seen = 0
    for line in raw.splitlines():
        m = OUTPUT_RE.search(line)
        if not m:
            continue
        idx = int(m.group(1))
        val = int(m.group(2), 16)
        if 0 <= idx < n:
            out[idx] = val
            seen += 1
    if seen != n:
        raise RuntimeError(f"captured {seen}/{n} output coefficients")
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--n-values", nargs="+", type=int, default=[64, 128, 256])
    p.add_argument("--cases", nargs="+", default=["random", "impulse", "identity"])
    args = p.parse_args()

    sim_dir = Path(__file__).resolve().parent
    repo_root = sim_dir.parent
    rtl_dir = repo_root / "rtl"
    opt_dir = repo_root / "rtl_bivar_opt"

    sys.path.insert(0, str(repo_root / "scripts"))
    from bivar_ntt_model import get_psi

    rng = random.Random(7)
    L = 8

    any_fail = False
    for n in args.n_values:
        m = n // L
        # Twiddles must be the 2n-th roots of unity for this specific n.
        psi = get_psi(n, Q)
        write_hex(sim_dir / "twiddle_factors.hex",
                  [pow(psi, i, Q) for i in range(2 * n)])
        # Compile.
        rtl_files = sorted(rtl_dir.glob("*.v")) + [opt_dir / "bivar_opt_mem.v", opt_dir / "bivar_opt_top.v"]
        out_bin = sim_dir / "bin" / f"tb_bivar_opt_n{n}"
        out_bin.parent.mkdir(exist_ok=True)
        cmd = [
            "iverilog", "-g2009",
            f"-DBIVAR_L={L}", f"-DBIVAR_M={m}",
            "-o", str(out_bin),
            "testbenches/tb_bivar_opt_capture.v",
        ] + [str(p) for p in rtl_files]
        cp = subprocess.run(cmd, cwd=str(sim_dir), capture_output=True, text=True)
        if cp.returncode != 0:
            print(f"COMPILE FAIL N={n}:\n{cp.stderr}")
            any_fail = True
            continue

        for case in args.cases:
            a, b = vector(case, n, rng)
            expected = poly_mul_direct(a, b, n)
            write_hex(sim_dir / "input_a.hex", a)
            write_hex(sim_dir / "input_b.hex", b)

            rp = subprocess.run(["vvp", str(out_bin)], cwd=str(sim_dir), capture_output=True, text=True)
            if rp.returncode != 0:
                print(f"SIM FAIL N={n} case={case}:\n{rp.stderr[:300]}")
                any_fail = True
                continue

            combined = rp.stdout + "\n" + rp.stderr
            got = parse_outputs(combined, n)
            matches = sum(1 for i in range(n) if got[i] == expected[i])
            cm = CYCLES_RE.search(combined)
            cycles = int(cm.group(1)) if cm else -1
            ok = matches == n
            print(f"N={n:4d} case={case:10s} matches={matches}/{n} cycles={cycles} {'OK' if ok else 'FAIL'}")
            if not ok:
                first = next(i for i in range(n) if got[i] != expected[i])
                print(f"  first_mismatch idx={first} got={got[first]:05x} exp={expected[first]:05x}")
                any_fail = True
    return 1 if any_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
