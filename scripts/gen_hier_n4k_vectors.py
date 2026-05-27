#!/usr/bin/env python3
"""
Generate (input_a_n4k.hex, input_b_n4k.hex, expected_hier_n4k.hex) for
N = 4096 negacyclic polynomial multiplication mod (X^N + 1), q = 65537.

This is the L=8, d=4 debug variant of Phase E.  N = 8^4 = 4096.

Uses fast_negacyclic_mul (O(N log N)) as the golden reference.
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trivar_ntt_model import fast_negacyclic_mul, Q

N_DEFAULT = 4096


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
    print(f"computing golden c = a*b mod (X^{args.n}+1) via fast_negacyclic_mul ...")
    c = fast_negacyclic_mul(a, b, args.n)

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)

    def dump(name, vec):
        path = os.path.join(out_dir, name)
        with open(path, "w") as f:
            for v in vec:
                f.write(f"{v & 0x1FFFF:05x}\n")
        print(f"wrote {path}  ({len(vec)} entries)")

    dump("input_a_n4k.hex", a)
    dump("input_b_n4k.hex", b)
    dump("expected_hier_n4k.hex", c)


if __name__ == "__main__":
    main()
