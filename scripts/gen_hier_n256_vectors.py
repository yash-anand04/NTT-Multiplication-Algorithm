#!/usr/bin/env python3
"""Generate vectors for N=256 polyMul."""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trivar_ntt_model import fast_negacyclic_mul, Q

N = 256
random.seed(42)
a = [random.randint(0, Q - 1) for _ in range(N)]
b = [random.randint(0, Q - 1) for _ in range(N)]
c = fast_negacyclic_mul(a, b, N)

out_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sim"))
for name, vec in [("input_a_n256.hex", a), ("input_b_n256.hex", b), ("expected_hier_n256.hex", c)]:
    with open(os.path.join(out_dir, name), "w") as f:
        for v in vec: f.write(f"{v & 0x1FFFF:05x}\n")
    print(f"wrote {name}")
