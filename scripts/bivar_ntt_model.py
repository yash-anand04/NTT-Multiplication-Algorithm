#!/usr/bin/env python3
"""
Kim et al. (2024) Bivariate NTT software proof model.
  Algebraic embedding: X2 = X1^(L) where L = K/2.

Provides the minimal software proof for the bivariate mapping:
  1) Active-basis mapper (M x L, L = K/2, M = N/L)
  2) Explicit fold rule: X1^L -> X2
  3) Explicit negacyclic wrap: X2^M -> -1
  4) Inverse remap to univariate coefficient order
  5) Equivalence checks against direct negacyclic convolution
  6) Basic cost estimator for bivariate NTT overhead

Natural polynomial index convention: i = i1 + L*i2
  (i1 in [0,L), i2 in [0,M); consecutive in memory per i2-group)
"""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass

Q = 65537
GENERATOR = 3


def modinv(a: int, q: int) -> int:
    return pow(a, q - 2, q)


def get_psi(n: int, q: int = Q) -> int:
    if (q - 1) % (2 * n) != 0:
        raise ValueError(f"2N does not divide q-1 for N={n}, q={q}")
    return pow(GENERATOR, (q - 1) // (2 * n), q)


def ntt(vec: list[int], root: int, q: int) -> list[int]:
    length = len(vec)
    return [sum(vec[i] * pow(root, i * j, q) for i in range(length)) % q for j in range(length)]


def intt(vec: list[int], root: int, q: int) -> list[int]:
    length = len(vec)
    inv_root = modinv(root, q)
    inv_length = modinv(length, q)
    return [
        (sum(vec[j] * pow(inv_root, i * j, q) for j in range(length)) * inv_length) % q
        for i in range(length)
    ]


def poly_mul_direct(a: list[int], b: list[int], q: int, n: int) -> list[int]:
    out = [0] * n
    for i, ai in enumerate(a):
        for j, bj in enumerate(b):
            prod = (ai * bj) % q
            total = i + j
            idx = total % n
            if total >= n:
                out[idx] = (out[idx] - prod) % q
            else:
                out[idx] = (out[idx] + prod) % q
    return out


def map_to_bivar_tensor(coeffs: list[int], n: int, k: int) -> list[list[int]]:
    """
    Map univariate polynomial into the bivariate active basis.

    L = K/2, M = N/L.  Index: i = i1 + L*i2  (consecutive per i2-group).
    tensor[i2][i1] = coeffs[i2*L + i1].
    """
    if n % (k // 2) != 0:
        raise ValueError("N must be divisible by L=K/2")
    l_dim = k // 2
    m_dim = n // l_dim
    tensor = [[0 for _ in range(l_dim)] for _ in range(m_dim)]
    for idx, value in enumerate(coeffs):
        i2, i1 = divmod(idx, l_dim)
        tensor[i2][i1] = value % Q
    return tensor


def map_from_bivar_tensor(tensor: list[list[int]], n: int, k: int) -> list[int]:
    l_dim = k // 2
    m_dim = n // l_dim
    out = [0] * n
    for i2 in range(m_dim):
        for i1 in range(l_dim):
            out[i2 * l_dim + i1] = tensor[i2][i1] % Q
    return out


def fold_exponent(e1: int, e2: int, l_dim: int, m_dim: int) -> tuple[int, int, int]:
    """
    Reduce X1^e1 * X2^e2 to canonical basis using:
      X1^L = X2   and   X2^M = -1.

    Returns (reduced_e1, reduced_e2, sign) where sign is +1 or -1.
    """
    carried = e1 // l_dim
    reduced_e1 = e1 % l_dim
    e2_total = e2 + carried
    wraps = e2_total // m_dim
    reduced_e2 = e2_total % m_dim
    sign = -1 if (wraps % 2 == 1) else 1
    return reduced_e1, reduced_e2, sign


def bivar_multiply_via_fold(a: list[int], b: list[int], q: int, n: int, k: int) -> list[int]:
    """
    Multiply polynomials using explicit bivariate fold/carry.

    Basis: sum_{i2,i1} t[i2][i1] * X1^i1 * X2^i2  with X1^L=X2, X2^M=-1.
    """
    l_dim = k // 2
    m_dim = n // l_dim
    a_t = map_to_bivar_tensor(a, n, k)
    b_t = map_to_bivar_tensor(b, n, k)
    out_t = [[0 for _ in range(l_dim)] for _ in range(m_dim)]

    for a2 in range(m_dim):
        for a1 in range(l_dim):
            av = a_t[a2][a1]
            if av == 0:
                continue
            for b2 in range(m_dim):
                for b1 in range(l_dim):
                    bv = b_t[b2][b1]
                    if bv == 0:
                        continue
                    raw_e1 = a1 + b1
                    raw_e2 = a2 + b2
                    red_e1, red_e2, sign = fold_exponent(raw_e1, raw_e2, l_dim, m_dim)
                    term = (av * bv) % q
                    if sign < 0:
                        out_t[red_e2][red_e1] = (out_t[red_e2][red_e1] - term) % q
                    else:
                        out_t[red_e2][red_e1] = (out_t[red_e2][red_e1] + term) % q

    return map_from_bivar_tensor(out_t, n, k)


def linear_conv_via_k_ntt(u: list[int], v: list[int], n: int, k: int, q: int) -> list[int]:
    """
    Demonstrate zero-padded K-point X1 convolution (row-direction check).
    """
    l_dim = k // 2
    if len(u) != l_dim or len(v) != l_dim:
        raise ValueError("u and v must have length L=K/2")

    psi = get_psi(n, q)
    omega = pow(psi, 2, q)
    root_k = pow(omega, n // k, q)

    up = u + [0] * (k - l_dim)
    vp = v + [0] * (k - l_dim)
    uf = ntt(up, root_k, q)
    vf = ntt(vp, root_k, q)
    wf = [(x * y) % q for x, y in zip(uf, vf)]
    wp = intt(wf, root_k, q)
    return wp


def linear_conv_direct(u: list[int], v: list[int], q: int) -> list[int]:
    out = [0] * (len(u) + len(v) - 1)
    for i, ui in enumerate(u):
        for j, vj in enumerate(v):
            out[i + j] = (out[i + j] + ui * vj) % q
    return out


@dataclass
class BivarCostEstimate:
    n: int
    k: int
    l_dim: int
    m_dim: int
    active_coeffs: int
    dense_slots: int
    slot_overhead: int
    fold_candidates_per_poly_mul: int
    max_x2_wraps_per_term: int
    mapper_reads: int
    mapper_writes: int


def estimate_bivar_cost(n: int, k: int) -> BivarCostEstimate:
    l_dim = k // 2
    m_dim = (2 * n) // k
    active_coeffs = l_dim * m_dim
    dense_slots = m_dim * k
    slot_overhead = dense_slots - active_coeffs
    fold_candidates = m_dim * m_dim * l_dim * l_dim
    max_wraps = ((m_dim - 1) + 1) // m_dim

    return BivarCostEstimate(
        n=n, k=k, l_dim=l_dim, m_dim=m_dim,
        active_coeffs=active_coeffs, dense_slots=dense_slots,
        slot_overhead=slot_overhead,
        fold_candidates_per_poly_mul=fold_candidates,
        max_x2_wraps_per_term=max_wraps,
        mapper_reads=n, mapper_writes=n,
    )


def run_bivar_checks(n: int, k: int, q: int, random_count: int, exhaustive_limit: int) -> None:
    if k % 2 != 0:
        raise ValueError("K must be even for bivariate NTT")
    if (2 * n) % k != 0:
        raise ValueError("K must divide 2N for bivariate NTT")
    l_dim = k // 2
    m_dim = (2 * n) // k
    if l_dim * m_dim != n:
        raise ValueError("Bivariate active basis must satisfy L*M=N")

    rng = random.Random(7)

    mapper_probe = [rng.randrange(q) for _ in range(n)]
    mapped = map_to_bivar_tensor(mapper_probe, n, k)
    remapped = map_from_bivar_tensor(mapped, n, k)
    if remapped != [x % q for x in mapper_probe]:
        raise AssertionError("Bivariate mapper inverse failed")

    for _ in range(8):
        u = [rng.randrange(q) for _ in range(l_dim)]
        v = [rng.randrange(q) for _ in range(l_dim)]
        via_k = linear_conv_via_k_ntt(u, v, n, k, q)
        direct = linear_conv_direct(u, v, q)
        if via_k[: len(direct)] != direct:
            raise AssertionError("K-point padded X1 convolution check failed")
        if any(via_k[idx] % q != 0 for idx in range(len(direct), k)):
            raise AssertionError("Expected zero tail in padded X1 convolution")

    exhaustive_values = min(q, exhaustive_limit)
    if n <= 16:
        space = list(range(exhaustive_values))
        for a0 in space:
            for a1 in space:
                a = [0] * n
                b = [0] * n
                a[0], a[1] = a0, a1
                b[0], b[1] = (a1 + 1) % q, (a0 + 2) % q
                exp = poly_mul_direct(a, b, q, n)
                got = bivar_multiply_via_fold(a, b, q, n, k)
                if got != exp:
                    raise AssertionError("Bivariate exhaustive check failed")

    for _ in range(random_count):
        a = [rng.randrange(q) for _ in range(n)]
        b = [rng.randrange(q) for _ in range(n)]
        exp = poly_mul_direct(a, b, q, n)
        got = bivar_multiply_via_fold(a, b, q, n, k)
        if got != exp:
            raise AssertionError("Bivariate random campaign failed")


def main() -> int:
    parser = argparse.ArgumentParser(description="Kim et al. bivariate NTT software proof model")
    parser.add_argument("--n", type=int, default=256, help="Polynomial length N")
    parser.add_argument("--k", type=int, default=16, help="Fermat parameter K (even, P=2^K+1 prime)")
    parser.add_argument("--q", type=int, default=Q, help="Prime modulus q")
    parser.add_argument("--random-count", type=int, default=200, help="Random test vectors")
    parser.add_argument("--exhaustive-limit", type=int, default=8,
                        help="Value range [0,limit) for small-N exhaustive checks")
    parser.add_argument("--self-test", action="store_true", help="Run bivariate NTT checks")
    parser.add_argument("--print-cost", action="store_true", help="Print cost estimate")
    args = parser.parse_args()

    if args.print_cost:
        est = estimate_bivar_cost(args.n, args.k)
        print("bivar_ntt_cost_estimate")
        print(f"  N={est.n} K={est.k} L={est.l_dim} M={est.m_dim}")
        print(f"  active_coeffs={est.active_coeffs}")
        print(f"  dense_slots={est.dense_slots} slot_overhead={est.slot_overhead}")
        print(f"  fold_candidates_per_poly_mul={est.fold_candidates_per_poly_mul}")
        print(f"  max_x2_wraps_per_term={est.max_x2_wraps_per_term}")
        print(f"  mapper_reads={est.mapper_reads} mapper_writes={est.mapper_writes}")

    if args.self_test:
        run_bivar_checks(args.n, args.k, args.q, args.random_count, args.exhaustive_limit)
        print(
            "bivar_ntt_self_test_passed "
            f"(N={args.n}, K={args.k}, random_count={args.random_count})"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
