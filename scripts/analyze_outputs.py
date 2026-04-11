#!/usr/bin/env python3
"""
Analyze differences between actual and expected outputs
to identify systematic errors (endianness, stage, etc.)
"""

# Load actual outputs from last test run
actual = [
    0x0882b, 0x05c04, 0x00bf7, 0x087d4, 0x0bff7, 0x09b35, 0x02422, 0x0f5e4, 
    0x037df, 0x09ca8, 0x009c2, 0x09277, 0x08e15, 0x0f590, 0x00c78, 0x06452,
    0x0dd71, 0x0452c, 0x0b98c, 0x00319, 0x07637, 0x00e65, 0x0a3f5, 0x00cb3,
    0x0e452, 0x0c90e, 0x07fbb, 0x0d918, 0x0666a, 0x0137f, 0x0c527, 0x09534
]

# Load expected from golden model
expected = [
    0x072b8, 0x0931f, 0x021b3, 0x02df9, 0x0889a, 0x0cc5d, 0x01ef8, 0x05bb2,
    0x043cc, 0x0d08e, 0x02973, 0x072c2, 0x0a54d, 0x01a9a, 0x03388, 0x023a7,
    0x0fba0, 0x00de9, 0x08e80, 0x043a4, 0x098c3, 0x0d88e, 0x0d50f, 0x0df86,
    0x038f3, 0x0f79c, 0x00bfb, 0x0b1b2, 0x0a63f, 0x01ba8, 0x0c314, 0x08ee1
]

print("=== OUTPUT COMPARISON ===\n")
print("Index | Expected | Actual   | Diff      | XOR      | Endian?")
print("------|----------|----------|-----------|----------|--------")

for i in range(min(len(actual), len(expected))):
    exp = expected[i]
    act = actual[i]
    diff = exp - act if exp > act else act - exp
    xor_val = exp ^ act
    
    # Check if it's an endianness swap (bytes reversed)
    exp_swapped = ((exp & 0xFF) << 8) | ((exp >> 8) & 0xFF)
    endian_match = "YES" if xor_val == exp_swapped else ""
    
    print(f"{i:5d} | {exp:08x} | {act:08x} | {diff:9d} | {xor_val:08x} | {endian_match}")

print("\n=== PATTERN ANALYSIS ===")
print(f"First 8 expected: {[hex(x) for x in expected[:8]]}")
print(f"First 8 actual:   {[hex(x) for x in actual[:8]]}")

# Check if it's a circular shift or rotation issue
print("\nChecking for common transformations:")
print(f"  Bit reversal: {bin(expected[0] ^ (int(bin(expected[0])[2:].zfill(17)[::-1], 2)))}")
print(f"  Circular shift by 1: {(expected[0] << 1) | (expected[0] >> 16)}")

# Look for missing FFT stages
print("\n=== Stage Hypothesis ===")
print("If only 3 of 4 NTT stages completed, what would transformation look like?")
print(f"Ratio actual/expected: {[actual[i]/expected[i] if expected[i] > 0 else 0 for i in range(min(8, len(actual)))]}")
