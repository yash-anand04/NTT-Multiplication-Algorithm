// Test: compare golden model first few operations with RTL
// This will help debug if the algorithm itself is correct

import sys
sys.path.insert(0, '.')

# Import golden model functions
exec(open('scripts/golden_model.py').read())

# Get inputs
from scripts.golden_model import norm_to_d1, d1_to_norm, d1_add, d1_sub, d1_mul_2k
from scripts.golden_model import NTT_DIT_mixed, q, omega

# Generate test inputs
input_a = [14592, 3278, 36048, 32098]  # first 4 elements from input_a.hex
input_b = [60068, 13104, 9602, 27938]  # first 4 elements from input_b.hex

print("Input A:", input_a)
print("Input B:", input_b)

# Compute what golden model expects for first butterfly
print("\n=== First Butterfly (DIT, stage 0, b=0, g=0) ===")
print("Should combine elements at: 0+0*64=0, 0+1*64=64, 0+2*64=128, 0+3*64=192")
print("So should butterfly input_a[0,64,128,192] and input_b[0,64,128,192]")

# Load all inputs
with open('sim/input_a.hex', 'r') as f:
    all_input_a = [int(line.strip(), 16) for line in f.readlines()]
with open('sim/input_b.hex', 'r') as f:
    all_input_b = [int(line.strip(), 16) for line in f.readlines()]

print(f"\na[0,64,128,192] = {all_input_a[0]}, {all_input_a[64]}, {all_input_a[128]}, {all_input_a[192]}")
print(f"b[0,64,128,192] = {all_input_b[0]}, {all_input_b[64]}, {all_input_b[128]}, {all_input_b[192]}")

# What should the first butterfly produce?
# For now just show raw values - RTL should store intermediate results somewhere
print("\n=== Expected to find in NTT1 stage 0 after first r2_4 butterfly ===")
print("(Waiting for RTL to compute...)")
