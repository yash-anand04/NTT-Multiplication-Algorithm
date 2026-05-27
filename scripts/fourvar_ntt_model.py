#!/usr/bin/env python3
"""
fourvar_ntt_model.py
Fourvariate (d=4) NTT-based negacyclic polynomial multiplication mod (X^N+1),
q = F_4 = 2^16 + 1 = 65537, with N = L^4 = 1,048,576 (L=32).

Cross-twiddle derivation (recursive Cooley-Tukey):
   Processing order: axis i3 first, then i2, then i1, then i0 (i0 is the
   innermost in the flat layout i = i0 + L*i1 + L*L*i2 + L*L*L*i3, hence
   processed last; output X[L^3*k0 + L^2*k1 + L*k2 + k3] has k0 in MSB.)

   omega_{L^2} = psi^(2 N / L^2) = psi^(2 L^2)     (for d=4)
   omega_{L^3} = psi^(2 N / L^3) = psi^(2 L)
   omega_{N}   = psi^2

   XTW1 (after NTT_i3, before NTT_i2):
       psi^(2 * L^2 * i2 * k3)
   XTW2 (after NTT_i2, before NTT_i1):
       psi^(2 * L * i1 * (L*k2 + k3))
   XTW3 (after NTT_i1, before NTT_i0):
       psi^(2 * i0 * (L^2*k1 + L*k2 + k3))

Inverse: reverse order with inverse twiddles, post-twist by psi^(-i),
scaling by 1/N is absorbed by the four inner INTTs (each divides by L,
total L^4 = N).
"""
from __future__ import annotations

import random
import sys
import os
from typing import List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bivar_ntt_model import poly_mul_direct, Q, get_psi, modinv
from trivar_ntt_model import _ntt_L, fast_negacyclic_mul


def fourvar_poly_mul(a: List[int], b: List[int],
                     n: int = 32**4, L: int = 32) -> List[int]:
    """
    c = a * b mod (X^n + 1) via fourvariate (d=4) decomposition.
    Returns a flat list of n coefficients.
    """
    if n != L**4:
        raise ValueError(f"fourvar requires N = {L**4} for L={L}, got {n}")

    psi = get_psi(n, Q)
    inv_psi = modinv(psi, Q)

    # ---- Tensor <-> flat conversions ----------------------------------------
    # layout: i = i0 + L*i1 + L^2*i2 + L^3*i3, t[i0][i1][i2][i3]
    def to_tensor(flat):
        t = [[[[0]*L for _ in range(L)] for _ in range(L)] for _ in range(L)]
        for idx, v in enumerate(flat):
            i0 = idx % L
            i1 = (idx // L) % L
            i2 = (idx // (L*L)) % L
            i3 = idx // (L*L*L)
            t[i0][i1][i2][i3] = v % Q
        return t

    def from_tensor(t):
        flat = [0] * n
        for i3 in range(L):
            for i2 in range(L):
                for i1 in range(L):
                    for i0 in range(L):
                        flat[i0 + L*i1 + L*L*i2 + L*L*L*i3] = t[i0][i1][i2][i3]
        return flat

    # ---- Forward NTT --------------------------------------------------------
    def fwd(flat):
        # Pre-twist by psi^i (negacyclic -> cyclic)
        twisted = [(flat[i] * pow(psi, i, Q)) % Q for i in range(n)]
        t = to_tensor(twisted)
        # Stage 0: NTT along i3 axis
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    col = [t[i0][i1][i2][i3] for i3 in range(L)]
                    col = _ntt_L(col, inverse=False)
                    for k3 in range(L):
                        t[i0][i1][i2][k3] = col[k3]
        # XTW1: psi^(2 * L^2 * i2 * k3)
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for k3 in range(L):
                        t[i0][i1][i2][k3] = (
                            t[i0][i1][i2][k3] * pow(psi, 2*L*L*i2*k3, Q)
                        ) % Q
        # Stage 1: NTT along i2 axis
        for i0 in range(L):
            for i1 in range(L):
                for k3 in range(L):
                    col = [t[i0][i1][i2][k3] for i2 in range(L)]
                    col = _ntt_L(col, inverse=False)
                    for k2 in range(L):
                        t[i0][i1][k2][k3] = col[k2]
        # XTW2: psi^(2 * L * i1 * (L*k2 + k3))
        for i0 in range(L):
            for i1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        t[i0][i1][k2][k3] = (
                            t[i0][i1][k2][k3] * pow(psi, 2*L*i1*(L*k2+k3), Q)
                        ) % Q
        # Stage 2: NTT along i1 axis
        for i0 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    col = [t[i0][i1][k2][k3] for i1 in range(L)]
                    col = _ntt_L(col, inverse=False)
                    for k1 in range(L):
                        t[i0][k1][k2][k3] = col[k1]
        # XTW3: psi^(2 * i0 * (L^2*k1 + L*k2 + k3))
        for i0 in range(L):
            for k1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        t[i0][k1][k2][k3] = (
                            t[i0][k1][k2][k3] *
                            pow(psi, 2*i0*(L*L*k1 + L*k2 + k3), Q)
                        ) % Q
        # Stage 3: NTT along i0 axis
        for k1 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    col = [t[i0][k1][k2][k3] for i0 in range(L)]
                    col = _ntt_L(col, inverse=False)
                    for k0 in range(L):
                        t[k0][k1][k2][k3] = col[k0]
        return from_tensor(t)

    # ---- Inverse NTT --------------------------------------------------------
    def inv(flat):
        t = to_tensor(flat)
        # Stage 3 inv: INTT along k0 (-> i0)
        for k1 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    col = [t[k0][k1][k2][k3] for k0 in range(L)]
                    col = _ntt_L(col, inverse=True)
                    for i0 in range(L):
                        t[i0][k1][k2][k3] = col[i0]
        # XTW3 inv
        for i0 in range(L):
            for k1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        t[i0][k1][k2][k3] = (
                            t[i0][k1][k2][k3] *
                            pow(inv_psi, 2*i0*(L*L*k1 + L*k2 + k3), Q)
                        ) % Q
        # Stage 2 inv: INTT along k1 (-> i1)
        for i0 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    col = [t[i0][k1][k2][k3] for k1 in range(L)]
                    col = _ntt_L(col, inverse=True)
                    for i1 in range(L):
                        t[i0][i1][k2][k3] = col[i1]
        # XTW2 inv
        for i0 in range(L):
            for i1 in range(L):
                for k2 in range(L):
                    for k3 in range(L):
                        t[i0][i1][k2][k3] = (
                            t[i0][i1][k2][k3] *
                            pow(inv_psi, 2*L*i1*(L*k2+k3), Q)
                        ) % Q
        # Stage 1 inv: INTT along k2 (-> i2)
        for i0 in range(L):
            for i1 in range(L):
                for k3 in range(L):
                    col = [t[i0][i1][k2][k3] for k2 in range(L)]
                    col = _ntt_L(col, inverse=True)
                    for i2 in range(L):
                        t[i0][i1][i2][k3] = col[i2]
        # XTW1 inv
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    for k3 in range(L):
                        t[i0][i1][i2][k3] = (
                            t[i0][i1][i2][k3] *
                            pow(inv_psi, 2*L*L*i2*k3, Q)
                        ) % Q
        # Stage 0 inv: INTT along k3 (-> i3)
        for i0 in range(L):
            for i1 in range(L):
                for i2 in range(L):
                    col = [t[i0][i1][i2][k3] for k3 in range(L)]
                    col = _ntt_L(col, inverse=True)
                    for i3 in range(L):
                        t[i0][i1][i2][i3] = col[i3]
        flat_out = from_tensor(t)
        # Post-twist by psi^(-i)
        return [(flat_out[i] * pow(inv_psi, i, Q)) % Q for i in range(n)]

    a_hat = fwd(a)
    b_hat = fwd(b)
    c_hat = [(x*y) % Q for x, y in zip(a_hat, b_hat)]
    return inv(c_hat)


def _self_test_small_L():
    """Verify the fourvar algorithm at L=4 (N=256) where direct check is cheap."""
    rng = random.Random(2026)
    L = 4
    n = L**4   # 256
    print(f"--- Fourvar self-test at L={L}, N={n} ---")
    for trial in range(3):
        a = [rng.randrange(Q) for _ in range(n)]
        b = [rng.randrange(Q) for _ in range(n)]
        got = fourvar_poly_mul(a, b, n=n, L=L)
        exp = poly_mul_direct(a, b, Q, n)
        if got != exp:
            mismatches = [(i, got[i], exp[i])
                          for i in range(n) if got[i] != exp[i]]
            print(f"FAIL trial {trial}: {len(mismatches)} mismatches, "
                  f"first 5: {mismatches[:5]}")
            return False
        print(f"trial {trial}: PASS")

    # Edge cases
    a = [0]*n; a[0] = 1
    b = [rng.randrange(Q) for _ in range(n)]
    got = fourvar_poly_mul(a, b, n=n, L=L)
    if got != b:
        print(f"FAIL identity case")
        return False
    print("identity case: PASS")

    a = [0]*n; a[1] = 1
    b = [0]*n; b[0] = 1
    expected = [0]*n; expected[1] = 1
    got = fourvar_poly_mul(a, b, n=n, L=L)
    if got != expected:
        print(f"FAIL X*1 case, got[1]={got[1]}")
        return False
    print("X*1 case: PASS")

    return True


def _self_test_L8():
    """Verify at L=8 (N=4096) via fast_negacyclic_mul (avoid O(N^2) direct)."""
    rng = random.Random(7)
    L = 8
    n = L**4   # 4096
    print(f"--- Fourvar self-test at L={L}, N={n} ---")
    for trial in range(2):
        a = [rng.randrange(Q) for _ in range(n)]
        b = [rng.randrange(Q) for _ in range(n)]
        got = fourvar_poly_mul(a, b, n=n, L=L)
        exp = fast_negacyclic_mul(a, b, n)
        if got != exp:
            mismatches = [(i, got[i], exp[i])
                          for i in range(n) if got[i] != exp[i]]
            print(f"FAIL trial {trial}: {len(mismatches)} mismatches, "
                  f"first 5: {mismatches[:5]}")
            return False
        print(f"trial {trial}: PASS (vs fast_negacyclic_mul)")
    return True


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--small", action="store_true",
                        help="Only L=4 N=256 direct-mul check (fastest)")
    parser.add_argument("--full", action="store_true",
                        help="Also include L=32 N=10^6 (very slow)")
    args = parser.parse_args()
    if not _self_test_small_L():
        sys.exit(1)
    if args.small:
        return
    if not _self_test_L8():
        sys.exit(1)
    if args.full:
        # Single random case at L=32, N=10^6 vs fast_negacyclic_mul
        print("--- Fourvar self-test at L=32, N=10^6 (slow, ~minutes) ---")
        rng = random.Random(42)
        n = 32**4
        a = [rng.randrange(Q) for _ in range(n)]
        b = [rng.randrange(Q) for _ in range(n)]
        got = fourvar_poly_mul(a, b, n=n, L=32)
        exp = fast_negacyclic_mul(a, b, n)
        if got != exp:
            print("FAIL at L=32 N=10^6")
            sys.exit(1)
        print("PASS at L=32 N=10^6")


if __name__ == "__main__":
    main()
