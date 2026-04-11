#!/usr/bin/env python3
"""
Verify ntt_reference against manual radix-2 test
"""
import sys
sys.path.insert(0, '../scripts')
from golden_model import *

# Simple test: N=4, compute NTT manually
test_vals = [1, 2, 3, 4]  # Some test values
omega_8 = pow(15028, (2*512)//8, 65537)  # ω_8 for 2N=512

print(f"Test values: {test_vals}")
print(f"omega_8 = {omega_8}")

# Manually compute 4-point NTT
X = test_vals[:]
print(f"\nManual Radix-2 DIT NTT:")
print(f"Input: {X}")

# Y[k]= sum_n X[n] * omega^(n*k)
# Let's compute with radix-2 butterfly
result = ntt_reference(X, omega_8, 4)
print(f"ntt_reference result: {result}")

# Double-check with direct DFT computation
dft_result = []
for k in range(4):
    val = 0
    for n in range(4):
        val = (val + X[n] * pow(omega_8, n*k, 65537)) % 65537
    dft_result.append(val)
print(f"Direct DFT result: {dft_result}")

if result == dft_result:
    print("✓ ntt_reference matches direct DFT")
else:
    print("✗ ntt_reference DOES NOT match DFT!")
    print(f"  ntt_reference: {result}")
    print(f"  Direct DFT:    {dft_result}")
