#!/usr/bin/env python3
"""
Generate correct expected outputs using a simple, straightforward NTT
"""
import sys
import os

# Parameters
q = 65537        # F4 = 2^16 + 1
N = 256          # Polynomial degree
B = 16

def mod_q(x):
    """Reduce x modulo q = 2^B + 1"""
    low = x & ((1 << B) - 1)
    high = x >> B
    r = low - high
    if r < 0:
        r += q
    if r >= q:
        r -= q
    return r

def get_omega_2N(q, N):
    """Get primitive 2N-th root of unity mod q"""
    g = 3  # primitive root mod 65537
    omega = pow(g, (q - 1) // (2 * N), q)
    return omega

def ntt_simple(x, omega):
    """Simple NTT without preprocessing: X[k] = sum_n x[n] * omega^(kn)"""
    N = len(x)
    X = []
    for k in range(N):
        val = 0
        for n in range(N):
            val = (val + x[n] * pow(omega, (k * n) % (2 * N), q)) % q
        X.append(val)
    return X

def intt_simple(X, omega_inv):
    """Simple INTT with N^{-1} scaling in output"""
    N = len(X)
    N_inv = pow(N, q-2, q)  # Fermat inverse: a^{q-2} ≡ a^{-1} (mod q)
    x = []
    for n in range(N):
        val = 0
        for k in range(N):
            val = (val + X[k] * pow(omega_inv, (n * k) % (2 * N), q)) % q
        x.append((val * N_inv) % q)
    return x

# Test on small example first
print("=== Test with N=4 ===")
test_in = [1, 2, 3, 4]
omega_small = pow(3, (q-1)//8, q)
print(f"omega_8 = {omega_small}")

X_test = ntt_simple(test_in, omega_small)
x_test = intt_simple(X_test, pow(omega_small, q-2, q))
print(f"Input:  {test_in}")
print(f"NTT:    {X_test}")
print(f"INTT:   {x_test}")
print(f"Match:  {[test_in[i] == x_test[i] for i in range(4)]}")

# Load actual inputs
print("\n=== Generate expected outputs for N=256 ===")
sim_dir = '.'
with open(os.path.join(sim_dir, 'input_a.hex')) as f:
    a_coeffs = [int(line.strip(), 16) for line in f.readlines()[:256]]
with open(os.path.join(sim_dir, 'input_b.hex')) as f:
    b_coeffs = [int(line.strip(), 16) for line in f.readlines()[:256]]

omega_2N = get_omega_2N(q, N)
omega_2N_inv = pow(omega_2N, q-2, q)

print(f"omega_2N = {omega_2N}")

# NTT on a and b
print("Computing NTT(a)...")
a_ntt = ntt_simple(a_coeffs, omega_2N)
print("Computing NTT(b)...")
b_ntt = ntt_simple(b_coeffs, omega_2N)

# Point-wise multiply
c_ntt = [(a_ntt[i] * b_ntt[i]) % q for i in range(N)]

# INTT
print("Computing INTT(c)...")
c_coeffs = intt_simple(c_ntt, omega_2N_inv)

# Write correct expected output
with open(os.path.join(sim_dir, "expected_out_correct.hex"), "w") as f:
    for c in c_coeffs:
        f.write(f"{c:05x}\n")

print(f"a[0:4] = {a_coeffs[:4]}")
print(f"b[0:4] = {b_coeffs[:4]}")
print(f"c[0:4] = {c_coeffs[:4]}")
print(f"\nWrote correct expected outputs to: expected_out_correct.hex")
