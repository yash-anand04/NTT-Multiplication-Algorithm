#!/usr/bin/env python3
"""
fivvar_ntt_model.py
Five-variate (d=5) NTT-based negacyclic polynomial multiplication mod (X^N+1),
q = F_4 = 2^16 + 1 = 65537, with N = L^5.

Valid under F_4: only L in {4, 8} (else N > 32 768).
   L=4: N = 1 024
   L=8: N = 32 768

Cross-twiddle derivation (recursive Cooley-Tukey, axis order i4, i3, i2, i1, i0):
   Flat index: i = i0 + L*i1 + L^2*i2 + L^3*i3 + L^4*i4
   Output:     X[L^4*k0 + L^3*k1 + L^2*k2 + L*k3 + k4]

   XTW1 (after NTT_i4, before NTT_i3):
       psi^(2 * L^3 * i3 * k4)
   XTW2 (after NTT_i3, before NTT_i2):
       psi^(2 * L^2 * i2 * (L*k3 + k4))
   XTW3 (after NTT_i2, before NTT_i1):
       psi^(2 * L   * i1 * (L^2*k2 + L*k3 + k4))
   XTW4 (after NTT_i1, before NTT_i0):
       psi^(2 *       i0 * (L^3*k1 + L^2*k2 + L*k3 + k4))
"""
from __future__ import annotations

import random
import sys
import os
from typing import List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bivar_ntt_model import poly_mul_direct, Q, get_psi, modinv
from trivar_ntt_model import _ntt_L, fast_negacyclic_mul


def fivvar_poly_mul(a: List[int], b: List[int],
                    n: int, L: int) -> List[int]:
    if n != L**5:
        raise ValueError(f"fivvar requires N = {L**5} for L={L}, got {n}")
    if n > 32768:
        raise ValueError(f"N={n} exceeds F_4 limit (32768)")

    psi = get_psi(n, Q)
    inv_psi = modinv(psi, Q)
    L2, L3, L4 = L*L, L*L*L, L*L*L*L

    def to_tensor(flat):
        t = [[[[[0]*L for _ in range(L)] for _ in range(L)]
              for _ in range(L)] for _ in range(L)]
        for idx, v in enumerate(flat):
            i0 = idx % L
            i1 = (idx // L) % L
            i2 = (idx // L2) % L
            i3 = (idx // L3) % L
            i4 = idx // L4
            t[i0][i1][i2][i3][i4] = v % Q
        return t

    def from_tensor(t):
        flat = [0]*n
        for i4 in range(L):
            for i3 in range(L):
                for i2 in range(L):
                    for i1 in range(L):
                        for i0 in range(L):
                            flat[i0 + L*i1 + L2*i2 + L3*i3 + L4*i4] = (
                                t[i0][i1][i2][i3][i4])
        return flat

    # ---- Forward NTT ---------------------------------------------------------
    def fwd(flat):
        # Pre-twist (negacyclic -> cyclic)
        twisted = [(flat[i] * pow(psi, i, Q)) % Q for i in range(n)]
        t = to_tensor(twisted)

        # Stage 0: NTT along i4
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for i3 in range(L):
                        col = [t[i0][i1][i2][i3][i4] for i4 in range(L)]
                        col = _ntt_L(col, inverse=False)
                        for k4 in range(L):
                            t[i0][i1][i2][i3][k4] = col[k4]
        # XTW1
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for i3 in range(L):
                        for k4 in range(L):
                            t[i0][i1][i2][i3][k4] = (
                                t[i0][i1][i2][i3][k4] * pow(psi, 2*L3*i3*k4, Q)
                            ) % Q
        # Stage 1: NTT along i3
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for k4 in range(L):
                        col = [t[i0][i1][i2][i3][k4] for i3 in range(L)]
                        col = _ntt_L(col, inverse=False)
                        for k3 in range(L):
                            t[i0][i1][i2][k3][k4] = col[k3]
        # XTW2
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for k3 in range(L):
                        for k4 in range(L):
                            t[i0][i1][i2][k3][k4] = (
                                t[i0][i1][i2][k3][k4]
                                * pow(psi, 2*L2*i2*(L*k3+k4), Q)
                            ) % Q
        # Stage 2: NTT along i2
        for i0 in range(L):
            for i1 in range(L):
                for k3 in range(L):
                    for k4 in range(L):
                        col = [t[i0][i1][i2][k3][k4] for i2 in range(L)]
                        col = _ntt_L(col, inverse=False)
                        for k2 in range(L):
                            t[i0][i1][k2][k3][k4] = col[k2]
        # XTW3
        for i0 in range(L):
            for i1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        for k4 in range(L):
                            t[i0][i1][k2][k3][k4] = (
                                t[i0][i1][k2][k3][k4]
                                * pow(psi, 2*L*i1*(L2*k2+L*k3+k4), Q)
                            ) % Q
        # Stage 3: NTT along i1
        for i0 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    for k4 in range(L):
                        col = [t[i0][i1][k2][k3][k4] for i1 in range(L)]
                        col = _ntt_L(col, inverse=False)
                        for k1 in range(L):
                            t[i0][k1][k2][k3][k4] = col[k1]
        # XTW4
        for i0 in range(L):
            for k1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        for k4 in range(L):
                            t[i0][k1][k2][k3][k4] = (
                                t[i0][k1][k2][k3][k4]
                                * pow(psi, 2*i0*(L3*k1+L2*k2+L*k3+k4), Q)
                            ) % Q
        # Stage 4: NTT along i0
        for k1 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    for k4 in range(L):
                        col = [t[i0][k1][k2][k3][k4] for i0 in range(L)]
                        col = _ntt_L(col, inverse=False)
                        for k0 in range(L):
                            t[k0][k1][k2][k3][k4] = col[k0]
        return from_tensor(t)

    # ---- Inverse NTT ---------------------------------------------------------
    def inv(flat):
        t = to_tensor(flat)
        # Stage 4 inv
        for k1 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    for k4 in range(L):
                        col = [t[k0][k1][k2][k3][k4] for k0 in range(L)]
                        col = _ntt_L(col, inverse=True)
                        for i0 in range(L):
                            t[i0][k1][k2][k3][k4] = col[i0]
        # XTW4 inv
        for i0 in range(L):
            for k1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        for k4 in range(L):
                            t[i0][k1][k2][k3][k4] = (
                                t[i0][k1][k2][k3][k4]
                                * pow(inv_psi, 2*i0*(L3*k1+L2*k2+L*k3+k4), Q)
                            ) % Q
        # Stage 3 inv
        for i0 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    for k4 in range(L):
                        col = [t[i0][k1][k2][k3][k4] for k1 in range(L)]
                        col = _ntt_L(col, inverse=True)
                        for i1 in range(L):
                            t[i0][i1][k2][k3][k4] = col[i1]
        # XTW3 inv
        for i0 in range(L):
            for i1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        for k4 in range(L):
                            t[i0][i1][k2][k3][k4] = (
                                t[i0][i1][k2][k3][k4]
                                * pow(inv_psi, 2*L*i1*(L2*k2+L*k3+k4), Q)
                            ) % Q
        # Stage 2 inv
        for i0 in range(L):
            for i1 in range(L):
                for k3 in range(L):
                    for k4 in range(L):
                        col = [t[i0][i1][k2][k3][k4] for k2 in range(L)]
                        col = _ntt_L(col, inverse=True)
                        for i2 in range(L):
                            t[i0][i1][i2][k3][k4] = col[i2]
        # XTW2 inv
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for k3 in range(L):
                        for k4 in range(L):
                            t[i0][i1][i2][k3][k4] = (
                                t[i0][i1][i2][k3][k4]
                                * pow(inv_psi, 2*L2*i2*(L*k3+k4), Q)
                            ) % Q
        # Stage 1 inv
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for k4 in range(L):
                        col = [t[i0][i1][i2][k3][k4] for k3 in range(L)]
                        col = _ntt_L(col, inverse=True)
                        for i3 in range(L):
                            t[i0][i1][i2][i3][k4] = col[i3]
        # XTW1 inv
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for i3 in range(L):
                        for k4 in range(L):
                            t[i0][i1][i2][i3][k4] = (
                                t[i0][i1][i2][i3][k4]
                                * pow(inv_psi, 2*L3*i3*k4, Q)
                            ) % Q
        # Stage 0 inv
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for i3 in range(L):
                        col = [t[i0][i1][i2][i3][k4] for k4 in range(L)]
                        col = _ntt_L(col, inverse=True)
                        for i4 in range(L):
                            t[i0][i1][i2][i3][i4] = col[i4]
        flat_out = from_tensor(t)
        # Post-twist
        return [(flat_out[i] * pow(inv_psi, i, Q)) % Q for i in range(n)]

    a_hat = fwd(a)
    b_hat = fwd(b)
    c_hat = [(x*y) % Q for x, y in zip(a_hat, b_hat)]
    return inv(c_hat)


def _self_test(L: int, trials: int = 2):
    n = L**5
    if n > 32768:
        print(f"SKIP L={L}: N={n} > 32768 (invalid under F_4)")
        return True
    print(f"--- Fivvar self-test at L={L}, N={n} ---")
    rng = random.Random(2026 + L)
    use_direct = (n <= 1024)
    for trial in range(trials):
        a = [rng.randrange(Q) for _ in range(n)]
        b = [rng.randrange(Q) for _ in range(n)]
        got = fivvar_poly_mul(a, b, n=n, L=L)
        if use_direct:
            exp = poly_mul_direct(a, b, Q, n)
            ref = "poly_mul_direct"
        else:
            exp = fast_negacyclic_mul(a, b, n)
            ref = "fast_negacyclic_mul"
        if got != exp:
            mismatches = [(i, got[i], exp[i])
                          for i in range(n) if got[i] != exp[i]]
            print(f"FAIL trial {trial}: {len(mismatches)} mismatches, "
                  f"first 5: {mismatches[:5]}")
            return False
        print(f"trial {trial}: PASS (vs {ref})")
    # Edge cases at small L
    if L == 4:
        a = [0]*n; a[0] = 1
        b = [rng.randrange(Q) for _ in range(n)]
        got = fivvar_poly_mul(a, b, n=n, L=L)
        if got != b:
            print("FAIL identity case"); return False
        print("identity case: PASS")
        a = [0]*n; a[1] = 1
        b = [0]*n; b[0] = 1
        expected = [0]*n; expected[1] = 1
        got = fivvar_poly_mul(a, b, n=n, L=L)
        if got != expected:
            print(f"FAIL X*1 case, got[1]={got[1]}"); return False
        print("X*1 case: PASS")
    return True


def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--L8", action="store_true",
                   help="also run L=8 N=32768 (slow, ~minutes)")
    args = p.parse_args()
    if not _self_test(4):
        sys.exit(1)
    if args.L8:
        if not _self_test(8, trials=1):
            sys.exit(1)


if __name__ == "__main__":
    main()
