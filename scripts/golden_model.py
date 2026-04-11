#!/usr/bin/env python3
"""
golden_model.py
Golden reference model for High-Radix NTT Polynomial Multiplication
over Fermat modulus q = F4 = 65537, N = 256, R = 4.

Generates:
  - input_a.hex      : N coefficients of poly a (hex)
  - input_b.hex      : N coefficients of poly b (hex)
  - expected_out.hex : N coefficients of product c = a*b mod (x^N+1) mod q
  - twiddle_factors.hex : twiddle factor ROM for NTT stages
"""

import random
import sys
import os

# ---- Parameters -------------------------------------------------------
q = 65537        # F4 = 2^16 + 1
N = 256          # Polynomial degree
B = 16           # bit width (q = 2^B + 1)
R = 4            # Radix

# ---- Fermat modular arithmetic ----------------------------------------

def mod_q(x):
    """Reduce x modulo q = 2^B + 1"""
    low  = x & ((1 << B) - 1)   # x mod 2^B
    high = x >> B                # x // 2^B
    r = low - high
    if r < 0:
        r += q
    if r >= q:
        r -= q
    return r

def mod_pow(base, exp, mod):
    return pow(base, exp, mod)

def modinv(a, m):
    g, x, _ = extended_gcd(a, m)
    if g != 1:
        raise ValueError(f"Inverse does not exist: gcd({a},{m})={g}")
    return x % m

def extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    g, x, y = extended_gcd(b % a, a)
    return g, y - (b // a) * x, x

# ---- Find primitive 2N-th root of unity ω_{2N} mod q -----------------

def find_primitive_root_of_unity(n, q):
    """Find a primitive n-th root of unity mod q."""
    # Since q is prime, q-1 must be divisible by n
    assert (q - 1) % n == 0, f"n={n} does not divide q-1={q-1}"
    while True:
        g = random.randint(2, q - 1)
        # g^{(q-1)/n} must be a primitive n-th root
        omega = pow(g, (q - 1) // n, q)
        if omega != 1 and pow(omega, n // 2, q) != 1:
            return omega

# For q = 65537, primitive TOTIENT = 65536 = 2^16
# 2N = 512, so we need ω_{512}: a 512th primitive root of unity
# q-1 = 65536 = 2^16, 512 = 2^9, so 512 | 65536 ✓
# ω_{512} = g^{65536/512} = g^{128} for a generator g
# 3 is a primitive root mod 65537

def get_omega_2N(q, N):
    """Get primitive 2N-th root of unity mod q via primitive root 3."""
    g = 3  # primitive root mod 65537
    order = q - 1  # = 65536
    tw_2N = 2 * N
    assert order % tw_2N == 0
    omega = pow(g, order // tw_2N, q)
    # Verify order
    assert pow(omega, tw_2N, q) == 1
    assert pow(omega, tw_2N // 2, q) != 1
    return omega

# ---- D1 arithmetic (reference) ----------------------------------------

def norm_to_d1(x, B=16):
    q = (1 << B) + 1
    x = x % q
    return (1 << B) if x == 0 else x - 1

def d1_to_norm(x, B=16):
    return 0 if x == (1 << B) else x + 1

def d1_mul_2k(k, x, B=16):
    """Multiply D1 value x by 2^k mod F_B in D1."""
    if x == (1 << B):
        return x  # D1 zero stays zero
    k = k % B
    bits = x & ((1 << B) - 1)
    # invert circular left shift by k on B bits
    shifted = ((bits << k) | (bits >> (B - k))) & ((1 << B) - 1)
    # D1 correction: D1(a*2^k) = shifted(D1(a)) + (2^k - 1)
    adjusted = (shifted + ((1 << k) - 1)) & ((1 << (B+1)) - 1)
    return adjusted

def d1_add(a, b, B=16):
    if a == (1 << B):
        return b
    if b == (1 << B):
        return a
    s = a + b
    return (s & ((1 << B) - 1)) + (1 - ((s >> B) & 1))

def d1_neg(a, B=16):
    if a == (1 << B):
        return a
    return (~a) & ((1 << B) - 1)

def d1_sub(a, b, B=16):
    return d1_add(a, d1_neg(b, B), B)

# ---- Reference R2 NTT (Algorithm 1) -----------------------------------

def bit_reverse(n, bits):
    result = 0
    for _ in range(bits):
        result = (result << 1) | (n & 1)
        n >>= 1
    return result

def ntt_reference(a, omega_2N, n=None):
    """Reference NTT using Algorithm 1 (R2 DIT) with pre-processing merged."""
    if n is None:
        n = len(a)
    a = list(a)
    # Pre-processing: multiply a[i] by omega_2N^i
    for i in range(n):
        a[i] = (a[i] * pow(omega_2N, i, q)) % q

    # Radix-2 DIT NTT
    j_step = n
    stage = 0
    while j_step > 1:
        j_step //= 2
        omega_M = pow(omega_2N, n // (j_step * 2), q)
        for k in range(0, n, j_step * 2):
            omega_pow = 1
            for j in range(j_step):
                t = (omega_pow * a[k + j + j_step]) % q
                a[k + j + j_step] = (a[k + j] - t) % q
                a[k + j]          = (a[k + j] + t) % q
                omega_pow = (omega_pow * omega_M) % q
        stage += 1
    return a

def intt_reference(A, omega_2N_inv, n=None):
    """Reference INTT using Algorithm 2 (R2 DIF) with post-processing merged."""
    if n is None:
        n = len(A)
    A = list(A)
    n_inv = modinv(n, q)

    # Radix-2 DIF INTT
    j_step = 1
    while j_step < n:
        omega_M_inv = pow(omega_2N_inv, n // (j_step * 2), q)
        for k in range(0, n, j_step * 2):
            omega_pow = 1
            for j in range(j_step):
                t = a_sum = (A[k + j] + A[k + j + j_step]) % q
                d_diff = (A[k + j] - A[k + j + j_step]) % q
                A[k + j]          = modinv(2, q) * t % q
                A[k + j + j_step] = modinv(2, q) * (omega_pow * d_diff % q) % q
                omega_pow = (omega_pow * omega_M_inv) % q
        j_step *= 2

    # Post-processing: multiply a[i] by omega_2N_inv^i * N^{-1}
    for i in range(n):
        A[i] = (A[i] * pow(omega_2N_inv, i, q) * n_inv) % q
    return A

# ---- Main polynomial multiplication ------------------------------------

def poly_mul_ntt(a_coeffs, b_coeffs, q=65537, N=256):
    """Multiply two polynomials mod x^N+1, mod q using NTT."""
    omega_2N     = get_omega_2N(q, N)
    omega_2N_inv = modinv(omega_2N, q)

    A = ntt_reference(a_coeffs, omega_2N, N)
    B = ntt_reference(b_coeffs, omega_2N, N)
    # Point-wise multiplication
    C = [(A[i] * B[i]) % q for i in range(N)]
    # INTT
    c = intt_reference(C, omega_2N_inv, N)
    return [x % q for x in c]

# ---- Generate twiddle factor ROM --------------------------------------

def generate_twiddle_rom(q=65537, N=256):
    """Generate ω_{2N}^k mod q for k=0..2N-1 (all entries)."""
    omega_2N = get_omega_2N(q, N)
    return [pow(omega_2N, k, q) for k in range(2 * N)]

# ---- Main -------------------------------------------------------------

if __name__ == "__main__":
    random.seed(42)

    # Get the directory where golden_model.py is located
    base_dir = os.path.dirname(os.path.abspath(__file__))
    # Target directory is one level up and then into 'sim'
    sim_dir = os.path.join(base_dir, "..", "sim")

    # Ensure the sim directory exists
    if not os.path.exists(sim_dir):
        os.makedirs(sim_dir)

    # Generate random polynomials with coefficients in [0, q-1]
    a_coeffs = [random.randint(0, q - 1) for _ in range(N)]
    b_coeffs = [random.randint(0, q - 1) for _ in range(N)]

    print(f"q = {q}, N = {N}, R = {R}")
    print(f"omega_2N = {get_omega_2N(q, N)}")

    # Compute expected output
    c_coeffs = poly_mul_ntt(a_coeffs, b_coeffs)

    # Write stimulus and expected output
    with open(os.path.join(sim_dir, "input_a.hex"), "w") as f:
        for c in a_coeffs:
            f.write(f"{c:05x}\n")

    with open(os.path.join(sim_dir, "input_b.hex"), "w") as f:
        for c in b_coeffs:
            f.write(f"{c:05x}\n")

    with open(os.path.join(sim_dir, "expected_out.hex"), "w") as f:
        for c in c_coeffs:
            f.write(f"{c:05x}\n")

    # Write twiddle factor ROM
    tw = generate_twiddle_rom(q, N)
    with open(os.path.join(sim_dir, "twiddle_factors.hex"), "w") as f:
        for t in tw:
            f.write(f"{t:05x}\n")

    print(f"Generated hex files in: {os.path.abspath(sim_dir)}")
    print(f"a[0:4] = {a_coeffs[:4]}")
    print(f"b[0:4] = {b_coeffs[:4]}")
    print(f"c[0:4] = {c_coeffs[:4]}")
