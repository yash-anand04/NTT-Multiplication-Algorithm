#!/usr/bin/env python3
"""
Generate (input_a_n32k.hex, input_b_n32k.hex, expected_hier_n32k.hex) for
N = 32768 negacyclic polynomial multiplication mod (X^N + 1), q = 65537.

Uses fast_negacyclic_mul from trivar_ntt_model as the golden reference
(O(N log N), seconds at N=32K).  trivar_poly_mul gives the same answer but
is O(N) sub-NTTs * L = ~32K subops which is slow in Python; we use the fast
golden for vector generation and the trivariate algo only for self-test.
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trivar_ntt_model import fast_negacyclic_mul, Q

N_DEFAULT = 32768


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

    dump("input_a_n32k.hex", a)
    dump("input_b_n32k.hex", b)
    dump("expected_hier_n32k.hex", c)


if __name__ == "__main__":
    main()
