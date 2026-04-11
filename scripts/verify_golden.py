#!/usr/bin/env python3
"""
Test golden model to verify expected outputs are actually correct
"""
import sys
sys.path.insert(0, '../scripts')
from golden_model import *

# Load inputs
with open('input_a.hex') as f:
    a = [int(line.strip(), 16) for line in f.readlines()[:256]]
with open('input_b.hex') as f:
    b = [int(line.strip(), 16) for line in f.readlines()[:256]]
with open('expected_out.hex') as f:
    expected_c = [int(line.strip(), 16) for line in f.readlines()[:256]]

# Compute step by step
print("=== Golden Model Verification ===")
print(f"a[0:4] = {a[:4]}")
print(f"b[0:4] = {b[:4]}")

#Compute NTT
omega_2N = get_omega_2N(65537, 256)
print(f"\nomega_2N = {omega_2N}")
print(f"omega_2N^(N/2) = {pow(omega_2N, 128, 65537)} (should be -1 mod q = 65536)")

# NTT on a
a_ntt = ntt_reference(a[:], omega_2N)
print(f"\nAfter NTT(a):")
print(f"a_ntt[0:4] = {a_ntt[:4]}")

# NTT on b
b_ntt = ntt_reference(b[:], omega_2N) 
print(f"\nAfter NTT(b):")
print(f"b_ntt[0:4] = {b_ntt[:4]}")

# Pointwise multiply
c_ntt = [(a_ntt[i] * b_ntt[i]) % 65537 for i in range(256)]
print(f"\nAfter PWM:")
print(f"c_ntt[0:4] = {c_ntt[:4]}")

# INTT
c = intt_reference(c_ntt[:], omega_2N)
print(f"\nAfter INTT:")
print(f"c[0:4] = {c[:4]}")

# Compare with expected
print(f"\nExpected c[0:4] = {expected_c[:4]}")
matches = sum(1 for i in range(256) if c[i] == expected_c[i])
print(f"\nMatches with expected: {matches}/256")
