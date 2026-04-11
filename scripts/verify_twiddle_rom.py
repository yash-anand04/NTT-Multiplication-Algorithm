#!/usr/bin/env python3
"""
Verify twiddle ROM values are correct
"""
import sys
import os

q = 65537
N = 256
R = 4

def get_omega_2N(q, N):
    """Get primitive 2N-th root of unity mod q"""
    g = 3
    omega = pow(g, (q - 1) // (2 * N), q)
    return omega

omega_2N = get_omega_2N(q, N)

# Load ROM from file
sim_dir = '.'
with open(os.path.join(sim_dir, 'twiddle_factors.hex')) as f:
    rom_values = [int(line.strip(), 16) for line in f.readlines()[:2*N]]

print(f"q = {q}, omega_2N = {omega_2N}")
print(f"2N = {2*N}")

# Expected values: omega_2N^k for k = 0..2N-1
print("\nComparing first 20 twiddle factors:")
print(f"{'k':>4} | {'Expected':>10} | {'ROM':>10} | Match")
print("-" * 45)

errors = 0
for k in range(min(20, 2*N)):
    expected = pow(omega_2N, k, q)
    actual = rom_values[k]
    match = "✓" if expected == actual else "✗"
    if expected != actual:
        errors += 1
    print(f"{k:4d} | {expected:10d} | {actual:10d} | {match}")

# Check all 2N values
all_match = 0
for k in range(2*N):
    if pow(omega_2N, k, q) == rom_values[k]:
        all_match += 1

print(f"\nTotal matches: {all_match}/{2*N}")
if all_match == 2*N:
    print("✓ All twiddle factors are correct!")
else:
    print(f"✗ Twiddle ROM has {2*N - all_match} errors")
