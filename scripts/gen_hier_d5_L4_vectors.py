#!/usr/bin/env python3
"""Generate test vectors for hier_d5_L4 (L=4, d=5, N=1024)."""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fivvar_ntt_model import fivvar_poly_mul
from bivar_ntt_model import Q

L, N = 4, 1024
random.seed(2026)
a = [random.randint(0, Q - 1) for _ in range(N)]
b = [random.randint(0, Q - 1) for _ in range(N)]
c = fivvar_poly_mul(a, b, N, L)

out_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "sim"))
for name, vec in [("input_a_hier_d5_L4.hex", a),
                  ("input_b_hier_d5_L4.hex", b),
                  ("expected_hier_d5_L4.hex", c)]:
    with open(os.path.join(out_dir, name), "w") as f:
        for v in vec:
            f.write(f"{v & 0x1FFFF:05x}\n")
    print(f"wrote {name}")
