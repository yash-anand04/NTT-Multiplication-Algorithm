#!/usr/bin/env python3

N = 256
q = 65537

a = [0] * N
b = [0] * N
a[0] = 1
b[0] = 1

# Negacyclic convolution expected result: delta at 0
c = [0] * N
c[0] = 1

for name, vec in [("input_a.hex", a), ("input_b.hex", b), ("expected_direct.hex", c)]:
    with open(name, "w") as f:
        for x in vec:
            f.write(f"{x:05x}\n")

print("Wrote impulse vectors: a[0]=1, b[0]=1")
