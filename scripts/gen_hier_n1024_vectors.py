#!/usr/bin/env python3
"""
Generate (input_a.hex, input_b.hex, expected_hier_n1024.hex) for N=1024
negacyclic polynomial multiplication mod (X^N + 1), q = 65537.

Uses scripts.bivar_ntt_model.poly_mul_direct as the golden reference.
Hex files are 17-bit values, one per line, suitable for $readmemh.
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bivar_ntt_model import poly_mul_direct, Q

N_DEFAULT = 1024


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=N_DEFAULT)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--out-dir",
        default=os.path.join(os.path.dirname(__file__), "..", "sim"),
    )
    args = parser.parse_args()

    random.seed(args.seed)
    a = [random.randint(0, Q - 1) for _ in range(args.n)]
    b = [random.randint(0, Q - 1) for _ in range(args.n)]
    c = poly_mul_direct(a, b, Q, args.n)

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)

    def dump(name, vec):
        path = os.path.join(out_dir, name)
        with open(path, "w") as f:
            for v in vec:
                f.write(f"{v & 0x1FFFF:05x}\n")
        print(f"wrote {path}  ({len(vec)} entries)")

    dump("input_a_hier.hex", a)
    dump("input_b_hier.hex", b)
    dump("expected_hier_n1024.hex", c)


if __name__ == "__main__":
    main()
