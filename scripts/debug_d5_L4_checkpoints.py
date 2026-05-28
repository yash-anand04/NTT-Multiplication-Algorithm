#!/usr/bin/env python3
"""Compute expected RTL mem state at key checkpoints for hier_d5_L4 X*1 test.

X*1: a[1]=1 (others 0), b[0]=1 (others 0).  c = a*b = X (only c[1]=1).

Checkpoints:
  CK_LOAD:    after LOAD, mem_a[bank, pos] holds a[i].
              For X*1: only bank=1 pos=0 has 1 (since i=1 -> i0=1).
  CK_PWM:     after PWM, mem_a holds spec_a * spec_b.
              For X*1: spec_a = FWD(a), spec_b = all-1's.
              So mem_a holds FWD(a) values.
  CK_OUTPUT:  mem_a holds c (final), expect c[1]=1, others 0.

Layout: physical pos = i1 + L*i2 + L^2*i3 + L^3*i4
        bank = (i0 + i1 + i2 + i3 + i4) mod L
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fivvar_ntt_model import fivvar_poly_mul
from bivar_ntt_model import Q, get_psi, modinv
from trivar_ntt_model import _ntt_L

L = 4
N = L**5
psi = get_psi(N, Q)

def logical_to_phys(i):
    i0 = i % L
    i1 = (i // L) % L
    i2 = (i // L**2) % L
    i3 = (i // L**3) % L
    i4 = i // L**4
    bank = (i0 + i1 + i2 + i3 + i4) % L
    pos = i1 + L*i2 + L*L*i3 + L*L*L*i4
    return bank, pos

# X*1 case
a = [0]*N; a[1] = 1
b = [0]*N; b[0] = 1

# Forward NTT of a (using same algorithm as fivvar_poly_mul's fwd)
def fwd_a(flat):
    twisted = [(flat[i] * pow(psi, i, Q)) % Q for i in range(N)]
    # tensor [i0][i1][i2][i3][i4]
    t = [[[[[0]*L for _ in range(L)] for _ in range(L)]
          for _ in range(L)] for _ in range(L)]
    for idx, v in enumerate(twisted):
        i0 = idx % L; i1 = (idx//L) % L; i2 = (idx//(L*L)) % L
        i3 = (idx//(L**3)) % L; i4 = idx // (L**4)
        t[i0][i1][i2][i3][i4] = v % Q
    L2, L3 = L*L, L*L*L
    # Stage 0: NTT along i4
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for i3 in range(L):
            col = [t[i0][i1][i2][i3][i4] for i4 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k4 in range(L): t[i0][i1][i2][i3][k4] = col[k4]
    # XTW1
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for i3 in range(L):
            for k4 in range(L):
              t[i0][i1][i2][i3][k4] = (t[i0][i1][i2][i3][k4] * pow(psi, 2*L3*i3*k4, Q)) % Q
    # Stage 1: NTT along i3
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for k4 in range(L):
            col = [t[i0][i1][i2][i3][k4] for i3 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k3 in range(L): t[i0][i1][i2][k3][k4] = col[k3]
    # XTW2
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for k3 in range(L):
            for k4 in range(L):
              t[i0][i1][i2][k3][k4] = (t[i0][i1][i2][k3][k4] * pow(psi, 2*L2*i2*(L*k3+k4), Q)) % Q
    # Stage 2: NTT along i2
    for i0 in range(L):
      for i1 in range(L):
        for k3 in range(L):
          for k4 in range(L):
            col = [t[i0][i1][i2][k3][k4] for i2 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k2 in range(L): t[i0][i1][k2][k3][k4] = col[k2]
    # XTW3
    for i0 in range(L):
      for i1 in range(L):
        for k2 in range(L):
          for k3 in range(L):
            for k4 in range(L):
              t[i0][i1][k2][k3][k4] = (t[i0][i1][k2][k3][k4] * pow(psi, 2*L*i1*(L2*k2+L*k3+k4), Q)) % Q
    # Stage 3: NTT along i1
    for i0 in range(L):
      for k2 in range(L):
        for k3 in range(L):
          for k4 in range(L):
            col = [t[i0][i1][k2][k3][k4] for i1 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k1 in range(L): t[i0][k1][k2][k3][k4] = col[k1]
    # XTW4
    for i0 in range(L):
      for k1 in range(L):
        for k2 in range(L):
          for k3 in range(L):
            for k4 in range(L):
              t[i0][k1][k2][k3][k4] = (t[i0][k1][k2][k3][k4] * pow(psi, 2*i0*(L3*k1+L2*k2+L*k3+k4), Q)) % Q
    # Stage 4: NTT along i0
    for k1 in range(L):
      for k2 in range(L):
        for k3 in range(L):
          for k4 in range(L):
            col = [t[i0][k1][k2][k3][k4] for i0 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k0 in range(L): t[k0][k1][k2][k3][k4] = col[k0]
    # Flatten by (k0,k1,k2,k3,k4) -> i = k0 + L*k1 + L^2*k2 + L^3*k3 + L^4*k4
    flat_out = [0]*N
    for k4 in range(L):
      for k3 in range(L):
        for k2 in range(L):
          for k1 in range(L):
            for k0 in range(L):
              # flat index uses original variable layout
              flat_out[k0 + L*k1 + L*L*k2 + L*L*L*k3 + L*L*L*L*k4] = t[k0][k1][k2][k3][k4]
    return flat_out

spec_a = fwd_a(a)
spec_b = fwd_a(b)

# Print spec_a values that are nonzero
print(f"# Checkpoint CK_PWM: mem_a holds spec_a * spec_b for X*1 case")
print(f"# Nonzero spec_a entries (first 16):")
nonzero_a = [(i, v) for i, v in enumerate(spec_a) if v != 0]
print(f"# total nonzero in spec_a: {len(nonzero_a)}")
for i, v in nonzero_a[:8]:
    bank, pos = logical_to_phys(i)
    print(f"#   spec_a[{i}]={v}  -> bank={bank} pos={pos}")

# Print expected mem_a contents after PWM at specific (bank, pos)
# After PWM: mem_a[bank, pos] = spec_a[i] * spec_b[i] where (bank,pos) corresponds to k-tuple
# Note: spec_a layout in mem_a is k0+L*k1+...+L^4*k4 with (k1..k4) as pos bits, k0 as bank addend.
# Actually after FWD_L4 writes broadcast: bank=(k1+k2+k3+k4+k0) mod L; pos=k1+L*k2+L^2*k3+L^3*k4

# Dump (bank, pos) -> spec_a*spec_b for first few
print(f"\n# CK_PWM mem_a state (spec_a*spec_b) at first 20 (bank, pos):")
ct = 0
for bank in range(L):
    for pos in range(min(DEPTH := L**4, 32)):
        # Recover (k0,k1,k2,k3,k4) from (bank, pos):
        k1 = pos & 3
        k2 = (pos >> 2) & 3
        k3 = (pos >> 4) & 3
        k4 = (pos >> 6) & 3
        k0 = (bank - k1 - k2 - k3 - k4) % L
        idx = k0 + L*k1 + L*L*k2 + L*L*L*k3 + L*L*L*L*k4
        v = (spec_a[idx] * spec_b[idx]) % Q
        if v != 0 and ct < 20:
            print(f"  bank={bank} pos={pos} -> idx={idx} v={v}")
            ct += 1

# Final output expected: c = X, so c[1]=1
print("\n# CK_OUTPUT expected: c[1]=1, others=0")
