#!/usr/bin/env python3

import sys

q = 65537
N = 256
out_file = sys.argv[1] if len(sys.argv) > 1 else "outputs_after_modmul_fix.txt"

with open("input_a.hex") as f:
    a = [int(x.strip(), 16) for x in f.readlines()[:N]]

with open("input_b.hex") as f:
    b = [int(x.strip(), 16) for x in f.readlines()[:N]]

with open(out_file) as f:
    lines = f.readlines()[:N]
    rtl = [int(line.split(": ")[1].strip(), 16) for line in lines]

# Direct negacyclic convolution mod (x^N + 1)
c = [0] * N
for i in range(N):
    ai = a[i]
    for j in range(N):
        prod = (ai * b[j]) % q
        ij = i + j
        k = ij % N
        if ij >= N:
            c[k] = (c[k] - prod) % q
        else:
            c[k] = (c[k] + prod) % q

matches = sum(1 for i in range(N) if c[i] == rtl[i])
print(f"matches: {matches}/{N}")
print("expected[0:16]:", [f"{x:05x}" for x in c[:16]])
print("rtl[0:16]:     ", [f"{x:05x}" for x in rtl[:16]])
