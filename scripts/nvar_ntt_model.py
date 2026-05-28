#!/usr/bin/env python3
"""
nvar_ntt_model.py
General d-variate NTT-based negacyclic polynomial multiplication mod (X^N+1),
q = F_4 = 2^16 + 1 = 65537, with N = L^d.  Valid under F_4: N <= 32768.

Generalises trivar/fourvar/fivvar to arbitrary d.  Axis processing order is
i_{d-1} first, then i_{d-2}, ..., i0 last (i0 is the bank-only axis in RTL).

Flat index: i = sum_{j=0}^{d-1} i_j * L^j
Output:     X[sum_j k_j * L^{d-1-j}]  (k0 in MSB)

Cross-twiddle XTW_m (m = 1..d-1), applied after NTT on axis i_{d-m},
before NTT on axis i_{d-1-m}:
    psi^( 2 * L^{d-1-m} * i_{d-1-m} * SUM )
  where SUM = sum_{j=1}^{m} k_{d-j} * L^{m-j}
       = k_{d-1}*L^{m-1} + k_{d-2}*L^{m-2} + ... + k_{d-m}*L^0
"""
from __future__ import annotations
import random, sys, os
from typing import List
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bivar_ntt_model import poly_mul_direct, Q, get_psi, modinv
from trivar_ntt_model import _ntt_L, fast_negacyclic_mul


def nvar_poly_mul(a: List[int], b: List[int], d: int, L: int) -> List[int]:
    n = L**d
    if n > 32768:
        raise ValueError(f"N={n} exceeds F_4 limit (32768)")
    psi = get_psi(n, Q)
    inv_psi = modinv(psi, Q)

    def idx_to_tuple(idx):
        t = []
        for j in range(d):
            t.append(idx % L)
            idx //= L
        return tuple(t)  # (i0, i1, ..., i_{d-1})

    def tuple_to_idx(t):
        return sum(t[j] * (L**j) for j in range(d))

    # tensor as flat dict keyed by tuple, but use list for speed
    def fwd(flat):
        # pre-twist
        cur = [(flat[i] * pow(psi, i, Q)) % Q for i in range(n)]
        # process axes from i_{d-1} down to i0
        # After transforming axis i_ax, that coordinate becomes k_ax.
        for stage in range(d):
            ax = d - 1 - stage          # axis being transformed this stage
            # NTT along axis `ax`
            new = [0]*n
            stride = L**ax
            block = stride * L
            for base in range(0, n, block):
                for off in range(stride):
                    col = [cur[base + off + s*stride] for s in range(L)]
                    col = _ntt_L(col, inverse=False)
                    for s in range(L):
                        new[base + off + s*stride] = col[s]
            cur = new
            # cross-twiddle after this NTT (except after the last axis i0)
            if stage < d - 1:
                m = stage + 1            # XTW_m
                ax_mul = d - 1 - m       # i_{d-1-m}, the multiplier axis
                Lpow_lead = L**(d-1-m)
                for i in range(n):
                    t = idx_to_tuple(i)
                    # multiplier index value
                    imul = t[ax_mul]
                    if imul == 0:
                        continue
                    # SUM over already-transformed higher axes k_{d-1..d-m}
                    # those are coordinates t[ax+1 .. d-1] (ax = d-1-m here),
                    # i.e. axes d-m, d-m+1, ..., d-1 are transformed (k's).
                    s = 0
                    for jj in range(1, m+1):
                        kax = d - jj          # axis index of k_{d-jj}
                        s += t[kax] * (L**(jj-1))
                    e = (2 * Lpow_lead * imul * s) % (2*n)
                    if e:
                        cur[i] = (cur[i] * pow(psi, e, Q)) % Q
        return cur

    def inv(flat):
        cur = list(flat)
        # reverse of fwd: INTT_i0, XTW_{d-1}^-1, INTT_i1, XTW_{d-2}^-1, ...,
        # INTT_i_{d-1}.  Each INTT_ax is immediately followed by the inverse of
        # the forward XTW whose multiplier axis was `ax` (i.e. m = d-1-ax).
        for stage in range(d):
            ax = stage               # axis being inverse-transformed
            # inverse NTT along axis `ax`
            new = [0]*n
            stride = L**ax
            block = stride * L
            for base in range(0, n, block):
                for off in range(stride):
                    col = [cur[base + off + s*stride] for s in range(L)]
                    col = _ntt_L(col, inverse=True)
                    for s in range(L):
                        new[base + off + s*stride] = col[s]
            cur = new
            # inverse cross-twiddle AFTER the inverse NTT (undoes XTW_{d-1-ax})
            if ax < d - 1:
                m = d - 1 - ax
                Lpow_lead = L**(ax)      # = L^{d-1-m}
                for i in range(n):
                    t = idx_to_tuple(i)
                    imul = t[ax]
                    if imul == 0:
                        continue
                    s = 0
                    for jj in range(1, m+1):
                        kax = d - jj
                        s += t[kax] * (L**(jj-1))
                    e = (2 * Lpow_lead * imul * s) % (2*n)
                    if e:
                        cur[i] = (cur[i] * pow(inv_psi, e, Q)) % Q
        # post-twist
        return [(cur[i] * pow(inv_psi, i, Q)) % Q for i in range(n)]

    a_hat = fwd(a); b_hat = fwd(b)
    c_hat = [(x*y) % Q for x, y in zip(a_hat, b_hat)]
    return inv(c_hat)


def _self_test(d, L, trials=2):
    n = L**d
    if n > 32768:
        print(f"SKIP d={d} L={L}: N={n}>32768"); return True
    print(f"--- nvar self-test d={d} L={L} N={n} ---")
    rng = random.Random(1234 + d*10 + L)
    use_direct = (n <= 1024)
    for tr in range(trials):
        a = [rng.randrange(Q) for _ in range(n)]
        b = [rng.randrange(Q) for _ in range(n)]
        got = nvar_poly_mul(a, b, d, L)
        exp = poly_mul_direct(a, b, Q, n) if use_direct else fast_negacyclic_mul(a, b, n)
        if got != exp:
            mm = [(i, got[i], exp[i]) for i in range(n) if got[i] != exp[i]]
            print(f"  FAIL trial {tr}: {len(mm)} mismatches, first 5: {mm[:5]}")
            return False
        print(f"  trial {tr}: PASS")
    return True


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--d", type=int, default=6)
    p.add_argument("--L", type=int, default=4)
    args = p.parse_args()
    ok = _self_test(args.d, args.L)
    sys.exit(0 if ok else 1)
