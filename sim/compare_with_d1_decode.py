#!/usr/bin/env python3

q = 65537
N = 256

with open("input_a.hex") as f:
    a = [int(x.strip(), 16) for x in f.readlines()[:N]]
with open("input_b.hex") as f:
    b = [int(x.strip(), 16) for x in f.readlines()[:N]]
with open("outputs_random_current.txt") as f:
    rtl = [int(x.split(": ")[1].strip(), 16) for x in f.readlines()[:N]]

exp = [0] * N
for i in range(N):
    ai = a[i]
    for j in range(N):
        p = (ai * b[j]) % q
        s = i + j
        k = s % N
        if s >= N:
            exp[k] = (exp[k] - p) % q
        else:
            exp[k] = (exp[k] + p) % q

cyc = [0] * N
for i in range(N):
    ai = a[i]
    for j in range(N):
        p = (ai * b[j]) % q
        cyc[(i + j) % N] = (cyc[(i + j) % N] + p) % q

# Normal compare
m_norm = sum(1 for i in range(N) if rtl[i] == exp[i])

# D1 decoded compare
rtl_d1_to_norm = [0 if x == 65536 else (x + 1) % q for x in rtl]
m_d1 = sum(1 for i in range(N) if rtl_d1_to_norm[i] == exp[i])

print("normal matches:", m_norm)
print("d1-decoded matches:", m_d1)
print("cyclic(x^N-1) matches:", sum(1 for i in range(N) if rtl[i] == cyc[i]))
print("expected[0:8]:", [f"{x:05x}" for x in exp[:8]])
print("rtl[0:8]:     ", [f"{x:05x}" for x in rtl[:8]])
print("rtl_d1[0:8]:  ", [f"{x:05x}" for x in rtl_d1_to_norm[:8]])
