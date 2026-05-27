#!/usr/bin/env python3
"""
Generate (input_a_n{N}.hex, input_b_n{N}.hex, expected_hier_n{N}.hex)
for hier_d3 L-variant tests.  N = L^3.  Uses fast_negacyclic_mul as golden.
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trivar_ntt_model import fast_negacyclic_mul, Q


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--L", type=int, required=True, help="lane width (sub-NTT size)")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out-dir",
        default=os.path.join(os.path.dirname(__file__), "..", "sim"))
    args = parser.parse_args()

    N = args.L ** 3
    random.seed(args.seed)
    a = [random.randint(0, Q - 1) for _ in range(N)]
    b = [random.randint(0, Q - 1) for _ in range(N)]
    print(f"computing golden c = a*b mod (X^{N}+1) ...")
    c = fast_negacyclic_mul(a, b, N)

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)

    def dump(name, vec):
        path = os.path.join(out_dir, name)
        with open(path, "w") as f:
            for v in vec:
                f.write(f"{v & 0x1FFFF:05x}\n")
        print(f"wrote {path}  ({len(vec)} entries)")

    dump(f"input_a_n{N}.hex", a)
    dump(f"input_b_n{N}.hex", b)
    dump(f"expected_hier_n{N}.hex", c)


if __name__ == "__main__":
    main()
