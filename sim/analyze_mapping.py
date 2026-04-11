#!/usr/bin/env python3

q = 65537
N = 256

# Direct expected
with open("input_a.hex") as f:
    a = [int(x.strip(), 16) for x in f.readlines()[:N]]
with open("input_b.hex") as f:
    b = [int(x.strip(), 16) for x in f.readlines()[:N]]

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

with open("outputs_random_current.txt") as f:
    rtl = [int(x.split(": ")[1].strip(), 16) for x in f.readlines()[:N]]

def bitrev8(x):
    b = "{0:08b}".format(x)
    return int(b[::-1], 2)

def count_matches(mapped):
    return sum(1 for i in range(N) if exp[i] == mapped[i])

print("identity:", count_matches(rtl))

# bit-reversed index permutations
rtl_bitrev = [rtl[bitrev8(i)] for i in range(N)]
print("rtl[bitrev(i)] -> exp[i]:", count_matches(rtl_bitrev))

exp_bitrev = [exp[bitrev8(i)] for i in range(N)]
print("rtl[i] -> exp[bitrev(i)]:", sum(1 for i in range(N) if rtl[i] == exp_bitrev[i]))

# cyclic shifts
best_shift = -1
best_match = -1
for s in range(N):
    m = sum(1 for i in range(N) if exp[i] == rtl[(i + s) % N])
    if m > best_match:
        best_match = m
        best_shift = s
print("best cyclic shift matches:", best_match, "at shift", best_shift)

# value multiset overlap
common = len(set(exp) & set(rtl))
print("unique common values:", common)
