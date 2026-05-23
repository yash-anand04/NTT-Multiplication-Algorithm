#!/usr/bin/env python3
"""
trivar_ntt_model.py
Trivariate (d=3) NTT-based negacyclic polynomial multiplication mod (X^N + 1),
q = F_4 = 2^16 + 1 = 65537, with N = L1 * L2 * L3 and L1 = L2 = L3 = 32.

Algebraic embedding:
    X1 := X
    X2 := X1^L1
    X3 := X2^L2
    X3^L3 = -1                       (negacyclic boundary)

A coefficient is f[i1][i2][i3] for X1^i1 * X2^i2 * X3^i3 with i_k in [0, 32).
Univariate index:  i = i1 + L1 * i2 + L1 * L2 * i3.

Forward NTT (per polynomial):
    Step 1 (level 0, "inner" axis i1):
        for each (i2, i3): pre-twist by psi^( i1 * 1 ) ... apply 32-point NTT
            along i1.
    Step 2 (cross-twiddle 0->1):
        multiply by psi^(2 * f1 * i2 * L1) where f1 is the NTT-domain index
        of the i1 axis.  This realigns coefficients so the i2 axis can be
        NTT'd with omega = psi^2.
    Step 3 (level 1, axis i2): 32-point NTT along i2.
    Step 4 (cross-twiddle 1->2): multiply by psi^(2 * f2 * i3 * L1 * L2).
    Step 5 (level 2, axis i3): 32-point NTT along i3.

After this, every (f1, f2, f3) lives in the "fully transformed" domain.

PWM:  c_hat[f1][f2][f3] = a_hat * b_hat   (pointwise, mod q).

Inverse NTT: reverse the steps with inverse twiddles and divide by N at the
end (we fold the 1/N into the very last twiddle multiplication for cycle
parity with the RTL).

This module's job is to:
    (a) define the algorithm so it can be ported to RTL exactly,
    (b) prove (via random testing against poly_mul_direct) that it gives the
        correct ring product,
    (c) provide a fast `trivar_poly_mul` that we can use to generate test
        vectors for the N=32K testbench.
"""
from __future__ import annotations

import random
import sys
import os
from typing import List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bivar_ntt_model import poly_mul_direct, Q, get_psi, modinv

# ---- 32-point shift-only NTT primitive (data layer) -------------------------
# In F_4 = 2^16+1, ord(2) = 32, so omega = 2 makes a 32-point NTT trivially
# shift-only.  We use this for the inner 32-point NTTs.

def _ntt32(vec: List[int], inverse: bool = False, root: int = None) -> List[int]:
    """32-pt NTT with canonical primitive 32nd root  omega_32 = 3^((q-1)/32) mod q.

    The canonical root makes cross-twiddle exponents like psi^(2*k1*i2) align
    algebraically (since psi = 3^((q-1)/(2N)) and the rest of Cooley-Tukey is
    derived from a single generator g=3).
    """
    n = len(vec)
    if n != 32:
        raise ValueError("ntt32 expects length 32")
    if root is None:
        root = pow(3, (Q - 1) // n, Q)        # primitive 32nd root from generator 3
    omega = root if not inverse else modinv(root, Q)
    out = [0] * n
    for j in range(n):
        acc = 0
        wj = pow(omega, j, Q)
        wjk = 1
        for k in range(n):
            acc = (acc + vec[k] * wjk) % Q
            wjk = (wjk * wj) % Q
        out[j] = acc
    if inverse:
        inv_n = modinv(n, Q)
        out = [(v * inv_n) % Q for v in out]
    return out


def _bivar_phaseC_algorithm(a: List[int], b: List[int]) -> List[int]:
    """
    Direct transcription of the Phase C RTL d=2 algorithm.  N = L*M = 32*32.
    Layout: flat index i = op_count + L*tg, i.e., op_count is the "row" axis
    (inner) and tg is the "col" axis (outer).

    Steps for each polynomial:
      1. ROW (input -> work): per (op_count, tg), multiply by psi^(tg*M + op_count)
         then 32-pt NTT along tg axis (sub_ntt32 with omega=2).
      2. XTW (work -> trans): multiply by psi^(2 * op_count * tg).
      3. COL (trans -> spec): 32-pt NTT along op_count axis.
    PWM: spec_a * spec_b -> prod.
    Inverse: COL-INTT -> XTW^-1 -> ROW-INTT (with post-divide and inv pre-twist).
    """
    L = 32
    M = 32
    N = L * M
    psi = get_psi(N, Q)
    inv_psi = modinv(psi, Q)

    def to_t(flat):
        # t[op_count][tg] -- i.e., t[inner][outer]
        t = [[0]*L for _ in range(M)]
        for i in range(N):
            op = i % M
            tg = i // M
            t[op][tg] = flat[i]
        return t

    def from_t(t):
        flat = [0]*N
        for op in range(M):
            for tg in range(L):
                flat[op + M*tg] = t[op][tg]
        return flat

    def fwd(flat):
        t = to_t(flat)
        # ROW: per (op, tg), multiply by psi^(tg*M + op), then NTT along tg axis.
        for op in range(M):
            row = [(t[op][tg] * pow(psi, tg*M + op, Q)) % Q for tg in range(L)]
            row = _ntt32(row, inverse=False)
            for tg in range(L):
                t[op][tg] = row[tg]
        # XTW: multiply by psi^(2 * op * tg).  Note: tg here is now k1 (NTT'd).
        for op in range(M):
            for tg in range(L):
                t[op][tg] = (t[op][tg] * pow(psi, 2*op*tg, Q)) % Q
        # COL: 32-pt NTT along op axis.  For each tg, transform the M-length col.
        for tg in range(L):
            col = [t[op][tg] for op in range(M)]
            col = _ntt32(col, inverse=False)
            for op in range(M):
                t[op][tg] = col[op]
        return t

    def inv(t):
        # Inverse COL
        for tg in range(L):
            col = [t[op][tg] for op in range(M)]
            col = _ntt32(col, inverse=True)
            for op in range(M):
                t[op][tg] = col[op]
        # Inverse XTW: psi^(-2 * op * tg)
        for op in range(M):
            for tg in range(L):
                t[op][tg] = (t[op][tg] * pow(inv_psi, 2*op*tg, Q)) % Q
        # Inverse ROW: INTT along tg, then multiply by psi^(-(tg*M + op))
        for op in range(M):
            row = [t[op][tg] for tg in range(L)]
            row = _ntt32(row, inverse=True)
            for tg in range(L):
                t[op][tg] = (row[tg] * pow(inv_psi, tg*M + op, Q)) % Q
        return from_t(t)

    a_hat = fwd(a)
    b_hat = fwd(b)
    # PWM
    c_hat = [[(a_hat[op][tg] * b_hat[op][tg]) % Q for tg in range(L)] for op in range(M)]
    return inv(c_hat)


def _phaseC_fwd(flat: List[int], n_inner: int = 1024) -> List[List[int]]:
    """Phase-C-style forward transform for a length-1024 vector.
    Returns the tensor t[op][tg] (32x32) in the post-fwd domain.
    Pulled out of _bivar_phaseC_algorithm so it can be reused.
    """
    L = M = 32
    N = L * M
    if n_inner != N:
        raise ValueError("inner phase-C transform only at N=1024")
    psi = get_psi(N, Q)
    # tensor build
    t = [[0]*L for _ in range(M)]
    for i in range(N):
        op = i % M
        tg = i // M
        t[op][tg] = flat[i]
    # ROW
    for op in range(M):
        row = [(t[op][tg] * pow(psi, tg*M + op, Q)) % Q for tg in range(L)]
        row = _ntt32(row, inverse=False)
        for tg in range(L):
            t[op][tg] = row[tg]
    # XTW
    for op in range(M):
        for tg in range(L):
            t[op][tg] = (t[op][tg] * pow(psi, 2*op*tg, Q)) % Q
    # COL
    for tg in range(L):
        col = [t[op][tg] for op in range(M)]
        col = _ntt32(col, inverse=False)
        for op in range(M):
            t[op][tg] = col[op]
    return t


def _phaseC_inv(t: List[List[int]], n_inner: int = 1024) -> List[int]:
    """Inverse of _phaseC_fwd: tensor t[op][tg] -> flat list of 1024 ints."""
    L = M = 32
    N = L * M
    psi = get_psi(N, Q)
    inv_psi = modinv(psi, Q)
    # inv COL
    for tg in range(L):
        col = [t[op][tg] for op in range(M)]
        col = _ntt32(col, inverse=True)
        for op in range(M):
            t[op][tg] = col[op]
    # inv XTW
    for op in range(M):
        for tg in range(L):
            t[op][tg] = (t[op][tg] * pow(inv_psi, 2*op*tg, Q)) % Q
    # inv ROW
    for op in range(M):
        row = [t[op][tg] for tg in range(L)]
        row = _ntt32(row, inverse=True)
        for tg in range(L):
            t[op][tg] = (row[tg] * pow(inv_psi, tg*M + op, Q)) % Q
    flat = [0]*N
    for op in range(M):
        for tg in range(L):
            flat[op + M*tg] = t[op][tg]
    return flat


def trivar_poly_mul_composed(a: List[int], b: List[int], n: int = 32768) -> List[int]:
    """
    Trivariate via composition: outer K-NTT over inner (L*M = 1024) Phase C blocks.

    Layout: flat index i = i_inner + 1024 * k, where k in [0,32) is the outer
    axis and i_inner in [0,1024) is the inner Phase-C index.

    Forward:
      1. Pre-twist by psi_N^i.
      2. For each outer slot k: apply Phase-C forward (without its own pre-twist).
         Wait -- Phase C's forward DOES include its own pre-twist by psi_1024^i.
         That's incompatible with our outer-level pre-twist by psi_N^i. So we
         can't naively reuse _phaseC_fwd; we need a "raw" inner cyclic NTT.

    Conclusion: composition is non-trivial because Phase C's pre/post twists
    are baked in.  Stub for now.
    """
    raise NotImplementedError("Composed trivariate needs a separate inner-cyclic NTT primitive")


def trivar_poly_mul(a: List[int], b: List[int], n: int = 32768) -> List[int]:
    """
    Compute c = a * b mod (X^n + 1) using the trivariate NTT decomposition.

    Returns the negacyclic product as a flat list of n coefficients.
    """
    L = 32
    if n != L * L * L:
        raise ValueError(f"trivar_poly_mul requires N = {L*L*L} (L=32^3)")

    psi = get_psi(n, Q)            # primitive 2N-th root
    inv_psi = modinv(psi, Q)

    def to_tensor(flat: List[int]):
        t = [[[0] * L for _ in range(L)] for _ in range(L)]
        for idx, v in enumerate(flat):
            i1 = idx % L
            i2 = (idx // L) % L
            i3 = idx // (L * L)
            t[i1][i2][i3] = v % Q
        return t

    def from_tensor(t) -> List[int]:
        flat = [0] * n
        for i3 in range(L):
            for i2 in range(L):
                for i1 in range(L):
                    idx = i1 + L * i2 + L * L * i3
                    flat[idx] = t[i1][i2][i3]
        return flat

    # Algorithm derived as nested bivariate Cooley-Tukey:
    #   N = L * (M*K)  with inner (M*K) further split as M*K.
    # Forward: NTT_axis3 -> XTW1 -> NTT_axis2 -> XTW2 -> NTT_axis1.
    def fwd(flat: List[int]) -> List[int]:
        # Pre-twist all coefficients by psi^i (negacyclic -> cyclic).
        twisted = [(flat[i] * pow(psi, i, Q)) % Q for i in range(n)]
        t = to_tensor(twisted)
        # Step 1: NTT along i3 axis (innermost of the (M*K) sub-NTT).
        for i1 in range(L):
            for i2 in range(L):
                col = [t[i1][i2][i3] for i3 in range(L)]
                col = _ntt32(col, inverse=False)
                for k3 in range(L):
                    t[i1][i2][k3] = col[k3]
        # Cross 1: omega_(L^2)^(i2 * k3) = psi^(2*L*i2*k3)
        for i1 in range(L):
            for i2 in range(L):
                for k3 in range(L):
                    t[i1][i2][k3] = (t[i1][i2][k3] * pow(psi, 2 * L * i2 * k3, Q)) % Q
        # Step 2: NTT along i2 axis (completes the inner (M*K)-NTT).
        for i1 in range(L):
            for k3 in range(L):
                col = [t[i1][i2][k3] for i2 in range(L)]
                col = _ntt32(col, inverse=False)
                for k2 in range(L):
                    t[i1][k2][k3] = col[k2]
        # Cross 2: outer omega_N^(i1 * K) where K = L*k2 + k3 is the inner
        # frequency.  Expanded: psi^(2L*i1*k2) * psi^(2*i1*k3) = psi^(2*i1*(L*k2+k3))
        for i1 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    t[i1][k2][k3] = (
                        t[i1][k2][k3] * pow(psi, 2 * i1 * (L * k2 + k3), Q)
                    ) % Q
        # Step 3: NTT along i1 (outer L-NTT).
        for k2 in range(L):
            for k3 in range(L):
                col = [t[i1][k2][k3] for i1 in range(L)]
                col = _ntt32(col, inverse=False)
                for k1 in range(L):
                    t[k1][k2][k3] = col[k1]
        return from_tensor(t)

    def inv(flat: List[int]) -> List[int]:
        t = to_tensor(flat)
        # Step 3-inv: INTT along k1.
        for k2 in range(L):
            for k3 in range(L):
                col = [t[k1][k2][k3] for k1 in range(L)]
                col = _ntt32(col, inverse=True)
                for i1 in range(L):
                    t[i1][k2][k3] = col[i1]
        # Cross 2-inv
        for i1 in range(L):
            for k2 in range(L):
                for k3 in range(L):
                    t[i1][k2][k3] = (
                        t[i1][k2][k3] * pow(inv_psi, 2 * i1 * (L * k2 + k3), Q)
                    ) % Q
        # Step 2-inv: INTT along k2.
        for i1 in range(L):
            for k3 in range(L):
                col = [t[i1][k2][k3] for k2 in range(L)]
                col = _ntt32(col, inverse=True)
                for i2 in range(L):
                    t[i1][i2][k3] = col[i2]
        # Cross 1-inv
        for i1 in range(L):
            for i2 in range(L):
                for k3 in range(L):
                    t[i1][i2][k3] = (
                        t[i1][i2][k3] * pow(inv_psi, 2 * L * i2 * k3, Q)
                    ) % Q
        # Step 1-inv: INTT along k3.
        for i1 in range(L):
            for i2 in range(L):
                col = [t[i1][i2][k3] for k3 in range(L)]
                col = _ntt32(col, inverse=True)
                for i3 in range(L):
                    t[i1][i2][i3] = col[i3]
        flat_out = from_tensor(t)
        # Post-twist: psi^(-i)
        return [(flat_out[i] * pow(inv_psi, i, Q)) % Q for i in range(n)]

    a_hat = fwd(a)
    b_hat = fwd(b)
    c_hat = [(x * y) % Q for x, y in zip(a_hat, b_hat)]
    return inv(c_hat)


# ---- Fast O(N log N) negacyclic NTT-based golden ----------------------------
# Used to validate trivar_poly_mul without paying the O(N^2) cost of
# poly_mul_direct at N=32768.

def _fast_ntt_iter(vec: List[int], root: int) -> List[int]:
    """Iterative Cooley-Tukey radix-2 NTT.  Power-of-two length required."""
    n = len(vec)
    a = list(vec)
    # Bit-reverse permutation
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    # Butterflies
    length = 2
    while length <= n:
        half = length // 2
        w_step = pow(root, n // length, Q)
        for start in range(0, n, length):
            w = 1
            for k in range(half):
                u = a[start + k]
                t = (a[start + k + half] * w) % Q
                a[start + k] = (u + t) % Q
                a[start + k + half] = (u - t) % Q
                w = (w * w_step) % Q
        length <<= 1
    return a


def fast_negacyclic_mul(a: List[int], b: List[int], n: int) -> List[int]:
    """c = a * b mod (X^n + 1), via NTT with pre/post twist by psi^i."""
    psi = get_psi(n, Q)
    psi_inv = modinv(psi, Q)
    omega = pow(psi, 2, Q)        # primitive N-th root
    omega_inv = modinv(omega, Q)
    inv_n = modinv(n, Q)

    a_twist = [(a[i] * pow(psi, i, Q)) % Q for i in range(n)]
    b_twist = [(b[i] * pow(psi, i, Q)) % Q for i in range(n)]
    a_hat = _fast_ntt_iter(a_twist, omega)
    b_hat = _fast_ntt_iter(b_twist, omega)
    c_hat = [(x * y) % Q for x, y in zip(a_hat, b_hat)]
    c_twist = _fast_ntt_iter(c_hat, omega_inv)
    c = [(c_twist[i] * inv_n) % Q * pow(psi_inv, i, Q) % Q for i in range(n)]
    return c


def _self_test_small():
    """Verify the ntt32 primitive and the fast golden against poly_mul_direct
    at a small N where the direct check is cheap."""
    rng = random.Random(2026)
    # ntt32 must invert itself
    v = [rng.randrange(Q) for _ in range(32)]
    f = _ntt32(v)
    inv = _ntt32(f, inverse=True)
    assert inv == v, "ntt32 forward/inverse mismatch"
    print("ntt32 self-test passed")
    # fast_negacyclic_mul matches poly_mul_direct at small N
    for n_small in (16, 64, 256):
        a = [rng.randrange(Q) for _ in range(n_small)]
        b = [rng.randrange(Q) for _ in range(n_small)]
        fast = fast_negacyclic_mul(a, b, n_small)
        direct = poly_mul_direct(a, b, Q, n_small)
        assert fast == direct, f"fast_negacyclic_mul mismatch at N={n_small}"
    print("fast_negacyclic_mul self-test passed at N=16,64,256")
    # Phase C algorithm transcription must match poly_mul_direct at N=1024
    a = [rng.randrange(Q) for _ in range(1024)]
    b = [rng.randrange(Q) for _ in range(1024)]
    got = _bivar_phaseC_algorithm(a, b)
    exp = fast_negacyclic_mul(a, b, 1024)
    if got != exp:
        bad = [(i, got[i], exp[i]) for i in range(1024) if got[i] != exp[i]]
        print(f"bivar Phase C algo FAIL: {len(bad)} mismatches, first 5: {bad[:5]}")
    else:
        print("bivar Phase C algo transcription matches golden at N=1024")


def _self_test_full(seed: int = 11, count: int = 1) -> None:
    """Compare trivar_poly_mul against fast_negacyclic_mul at N=32K."""
    rng = random.Random(seed)
    N = 32768
    for c in range(count):
        a = [rng.randrange(Q) for _ in range(N)]
        b = [rng.randrange(Q) for _ in range(N)]
        got = trivar_poly_mul(a, b, N)
        exp = fast_negacyclic_mul(a, b, N)
        if got != exp:
            mismatches = [(i, got[i], exp[i]) for i in range(N) if got[i] != exp[i]]
            print(f"FAIL case {c}: {len(mismatches)} mismatched coeffs, "
                  f"first 5: {mismatches[:5]}")
            return
        print(f"trivar_poly_mul case {c}: PASS (N={N})")


def _self_test_full(seed: int = 11, count: int = 1) -> None:
    """Compare trivariate algorithm against poly_mul_direct at N=32K.

    poly_mul_direct is O(N^2) so this is slow (~10 minutes at N=32K) — keep
    `count` very small.  For routine development use a smaller N variant.
    """
    rng = random.Random(seed)
    N = 32768
    for c in range(count):
        a = [rng.randrange(Q) for _ in range(N)]
        b = [rng.randrange(Q) for _ in range(N)]
        got = trivar_poly_mul(a, b, N)
        exp = poly_mul_direct(a, b, Q, N)
        if got != exp:
            mismatches = [(i, got[i], exp[i]) for i in range(N) if got[i] != exp[i]]
            print(f"FAIL case {c}: {len(mismatches)} mismatched coeffs, first 5: {mismatches[:5]}")
            return
        print(f"trivar_poly_mul case {c}: PASS (N={N})")


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--small", action="store_true", help="Run only the ntt32 self-test")
    parser.add_argument("--full", action="store_true",
                        help="Compare trivar_poly_mul vs poly_mul_direct at N=32K (slow)")
    parser.add_argument("--count", type=int, default=1)
    args = parser.parse_args()
    _self_test_small()
    if args.full:
        _self_test_full(count=args.count)
    elif not args.small:
        _self_test_small()


if __name__ == "__main__":
    main()
