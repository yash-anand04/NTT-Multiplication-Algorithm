#!/usr/bin/env python3
"""
compare_stages.py - Compare intermediate stage results with golden model
"""

import sys
sys.path.insert(0, '/memories/session/')

# Read expected output from file
with open('sim/expected_out.hex', 'r') as f:
    expected = [int(line.strip(), 16) for line in f.readlines()[:256]]

# Read actual output from testbench
with open('sim/outputs_current.txt', 'r') as f:
    actual = [int(line.split(': ')[1], 16) for line in f.readlines()[:256]]

print("Expected first 16:", [hex(x) for x in expected[:16]])
print("Actual first 16:  ", [hex(x) for x in actual[:16]])

# Check for patterns
print("\nBasic statistics:")
print(f"Expected range: min={hex(min(expected))}, max={hex(max(expected))}")
print(f"Actual range:   min={hex(min(actual))}, max={hex(max(actual))}")

# Check if there's any systematic relationship
xor_results = [expected[i] ^ actual[i] for i in range(256)]
print(f"\nXOR analysis: min_xor={hex(min(xor_results))}, max_xor={hex(max(xor_results))}")

# Check if output is bit-reversed
reversed_actual = [actual[int(bin(i)[2:].zfill(8)[::-1], 2)] for i in range(256)]
rev_matches = sum(1 for i in range(256) if expected[i] == reversed_actual[i])
print(f"Bit-reversed matches: {rev_matches}/256")

# Check if there's a scaling factor pattern
diffs = [(actual[i] - expected[i]) % 65537 if expected[i] != 0 else 0 for i in range(256)]
print(f"\n(Actual - Expected) mod 65537 analysis:")
print(f"First 16 diffs: {[hex(d) for d in diffs[:16]]}")

# Check if all differences are the same (constant offset)
non_zero_diffs = [d for d in diffs if d != 0]
if len(non_zero_diffs) > 0:
    if len(set(non_zero_diffs)) == 1:
        print(f"All differences are constant: {hex(non_zero_diffs[0])}")
    else:
        print(f"Differences vary - not a simple offset")
