#!/usr/bin/env python3
"""Compute expected mem_scratch state after each INV phase for X*1 case."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fivvar_ntt_model import fivvar_poly_mul
from bivar_ntt_model import Q, get_psi, modinv
from trivar_ntt_model import _ntt_L

L = 4
N = L**5
psi = get_psi(N, Q)
inv_psi = modinv(psi, Q)
L2, L3, L4 = L*L, L*L*L, L*L*L*L

def make_tensor(flat):
    t = [[[[[0]*L for _ in range(L)] for _ in range(L)]
          for _ in range(L)] for _ in range(L)]
    for idx, v in enumerate(flat):
        i0 = idx % L; i1 = (idx//L) % L; i2 = (idx//L2) % L
        i3 = (idx//L3) % L; i4 = idx // L4
        t[i0][i1][i2][i3][i4] = v % Q
    return t

# X*1 setup: PWM result = spec_a (since spec_b = all 1's)
a = [0]*N; a[1] = 1
# Compute spec_a using the forward chain (same as fivvar_ntt_model fwd)
def fwd(flat):
    twisted = [(flat[i] * pow(psi, i, Q)) % Q for i in range(N)]
    t = make_tensor(twisted)
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for i3 in range(L):
            col = [t[i0][i1][i2][i3][i4] for i4 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k4 in range(L): t[i0][i1][i2][i3][k4] = col[k4]
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for i3 in range(L):
            for k4 in range(L):
              t[i0][i1][i2][i3][k4] = (t[i0][i1][i2][i3][k4] * pow(psi, 2*L3*i3*k4, Q)) % Q
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for k4 in range(L):
            col = [t[i0][i1][i2][i3][k4] for i3 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k3 in range(L): t[i0][i1][i2][k3][k4] = col[k3]
    for i0 in range(L):
      for i1 in range(L):
        for i2 in range(L):
          for k3 in range(L):
            for k4 in range(L):
              t[i0][i1][i2][k3][k4] = (t[i0][i1][i2][k3][k4] * pow(psi, 2*L2*i2*(L*k3+k4), Q)) % Q
    for i0 in range(L):
      for i1 in range(L):
        for k3 in range(L):
          for k4 in range(L):
            col = [t[i0][i1][i2][k3][k4] for i2 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k2 in range(L): t[i0][i1][k2][k3][k4] = col[k2]
    for i0 in range(L):
      for i1 in range(L):
        for k2 in range(L):
          for k3 in range(L):
            for k4 in range(L):
              t[i0][i1][k2][k3][k4] = (t[i0][i1][k2][k3][k4] * pow(psi, 2*L*i1*(L2*k2+L*k3+k4), Q)) % Q
    for i0 in range(L):
      for k2 in range(L):
        for k3 in range(L):
          for k4 in range(L):
            col = [t[i0][i1][k2][k3][k4] for i1 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k1 in range(L): t[i0][k1][k2][k3][k4] = col[k1]
    for i0 in range(L):
      for k1 in range(L):
        for k2 in range(L):
          for k3 in range(L):
            for k4 in range(L):
              t[i0][k1][k2][k3][k4] = (t[i0][k1][k2][k3][k4] * pow(psi, 2*i0*(L3*k1+L2*k2+L*k3+k4), Q)) % Q
    for k1 in range(L):
      for k2 in range(L):
        for k3 in range(L):
          for k4 in range(L):
            col = [t[i0][k1][k2][k3][k4] for i0 in range(L)]
            col = _ntt_L(col, inverse=False)
            for k0 in range(L): t[k0][k1][k2][k3][k4] = col[k0]
    return t  # tensor in spectral domain (k0,k1,k2,k3,k4)

spec_a = fwd(a)
# spec_b for b=delta_0: all 1's
spec_b_tensor = [[[[[1]*L for _ in range(L)] for _ in range(L)]
                  for _ in range(L)] for _ in range(L)]

# PWM tensor: spec_a * spec_b (= spec_a)
t = [[[[[spec_a[k0][k1][k2][k3][k4] * spec_b_tensor[k0][k1][k2][k3][k4] % Q
        for k4 in range(L)] for k3 in range(L)] for k2 in range(L)]
      for k1 in range(L)] for k0 in range(L)]

# Now apply INV chain step by step and dump expected state at each checkpoint
def dump_cp(label, t, layout_desc):
    """Dump a few cells from the tensor in the specified physical layout."""
    print(f"\n[{label}] layout: {layout_desc}")
    # After INV_L4 broadcast: bank=(i0+k1+k2+k3+k4)%L, pos=k1+L*k2+L^2*k3+L^3*k4
    # But the layout interpretation depends on stage.

# CK after INV_L4 (k0 -> i0): tensor coords (i0, k1, k2, k3, k4)
# Broadcast layout: phys_i0=bank, phys_i1..4=k1..4
# bank = (i0 + k1 + k2 + k3 + k4) % L, pos = k1 + L*k2 + L^2*k3 + L^3*k4
for k1 in range(L):
    for k2 in range(L):
        for k3 in range(L):
            for k4 in range(L):
                col = [t[k0][k1][k2][k3][k4] for k0 in range(L)]
                col = _ntt_L(col, inverse=True)
                for i0 in range(L): t[i0][k1][k2][k3][k4] = col[i0]

print("[CK_AFTER_INV_L4] (i0, k1, k2, k3, k4) in broadcast layout")
print("  bank=(i0+k1+k2+k3+k4)%L, pos=k1+L*k2+L^2*k3+L^3*k4")
for bank in range(L):
    cells = []
    for pos in range(8):
        k1 = pos & 3; k2 = (pos>>2) & 3; k3 = (pos>>4) & 3; k4 = (pos>>6) & 3
        i0 = (bank - k1 - k2 - k3 - k4) % L
        cells.append(t[i0][k1][k2][k3][k4])
    print(f"  bank={bank} pos0..7 = {cells}")

# XTW4 inv
for i0 in range(L):
    for k1 in range(L):
        for k2 in range(L):
            for k3 in range(L):
                for k4 in range(L):
                    t[i0][k1][k2][k3][k4] = (t[i0][k1][k2][k3][k4]
                        * pow(inv_psi, 2*i0*(L3*k1+L2*k2+L*k3+k4), Q)) % Q
print("\n[CK_AFTER_INV_XTW4] same layout, in-place mul")
for bank in range(L):
    cells = []
    for pos in range(8):
        k1 = pos & 3; k2 = (pos>>2) & 3; k3 = (pos>>4) & 3; k4 = (pos>>6) & 3
        i0 = (bank - k1 - k2 - k3 - k4) % L
        cells.append(t[i0][k1][k2][k3][k4])
    print(f"  bank={bank} pos0..7 = {cells}")

# INV_L3 (k1 -> i1)
for i0 in range(L):
    for k2 in range(L):
        for k3 in range(L):
            for k4 in range(L):
                col = [t[i0][k1][k2][k3][k4] for k1 in range(L)]
                col = _ntt_L(col, inverse=True)
                for i1 in range(L): t[i0][i1][k2][k3][k4] = col[i1]
# After INV_L3: data state (i0, i1, k2, k3, k4). axis_i1 layout: lane k1=i1, phys_i1=k1
# bank=(i0+i1+k2+k3+k4)%L; pos = i1 + L*k2 + L^2*k3 + L^3*k4
def dump_axis_i1(label, t):
    print(f"\n[{label}] axis_i1 layout: pos=i1+L*k2+L^2*k3+L^3*k4, bank=(i0+i1+k2+k3+k4)%L")
    for bank in range(L):
        cells = []
        for pos in range(8):
            i1 = pos & 3; k2 = (pos>>2) & 3; k3 = (pos>>4) & 3; k4 = (pos>>6) & 3
            i0 = (bank - i1 - k2 - k3 - k4) % L
            cells.append(t[i0][i1][k2][k3][k4])
        print(f"  bank={bank} pos0..7 = {cells}")

def dump_axis_i2(label, t):
    print(f"\n[{label}] axis_i2 layout: pos=i1+L*i2+L^2*k3+L^3*k4, bank=sum%L")
    for bank in range(L):
        cells = []
        for pos in range(8):
            i1 = pos & 3; i2 = (pos>>2) & 3; k3 = (pos>>4) & 3; k4 = (pos>>6) & 3
            i0 = (bank - i1 - i2 - k3 - k4) % L
            cells.append(t[i0][i1][i2][k3][k4])
        print(f"  bank={bank} pos0..7 = {cells}")

def dump_axis_i3(label, t):
    print(f"\n[{label}] axis_i3 layout: pos=i1+L*i2+L^2*i3+L^3*k4, bank=sum%L")
    for bank in range(L):
        cells = []
        for pos in range(8):
            i1 = pos & 3; i2 = (pos>>2) & 3; i3 = (pos>>4) & 3; k4 = (pos>>6) & 3
            i0 = (bank - i1 - i2 - i3 - k4) % L
            cells.append(t[i0][i1][i2][i3][k4])
        print(f"  bank={bank} pos0..7 = {cells}")

def dump_axis_i4(label, t):
    print(f"\n[{label}] axis_i4 layout: pos=i1+L*i2+L^2*i3+L^3*i4, bank=sum%L")
    for bank in range(L):
        cells = []
        for pos in range(8):
            i1 = pos & 3; i2 = (pos>>2) & 3; i3 = (pos>>4) & 3; i4 = (pos>>6) & 3
            i0 = (bank - i1 - i2 - i3 - i4) % L
            cells.append(t[i0][i1][i2][i3][i4])
        print(f"  bank={bank} pos0..7 = {cells}")

dump_axis_i1("CK_AFTER_INV_L3", t)

# INV_XTW3: inv(FWD_XTW3) = inv(psi^(2*L*i1*(L²*k2+L*k3+k4)))
for i0 in range(L):
    for i1 in range(L):
        for k2 in range(L):
            for k3 in range(L):
                for k4 in range(L):
                    t[i0][i1][k2][k3][k4] = (t[i0][i1][k2][k3][k4]
                        * pow(inv_psi, 2*L*i1*(L2*k2+L*k3+k4), Q)) % Q
dump_axis_i1("CK_AFTER_INV_XTW3", t)

# INV_L2 (k2 -> i2), lane=i2
for i0 in range(L):
    for i1 in range(L):
        for k3 in range(L):
            for k4 in range(L):
                col = [t[i0][i1][k2][k3][k4] for k2 in range(L)]
                col = _ntt_L(col, inverse=True)
                for i2 in range(L): t[i0][i1][i2][k3][k4] = col[i2]
dump_axis_i2("CK_AFTER_INV_L2", t)

# INV_XTW2
for i0 in range(L):
    for i1 in range(L):
        for i2 in range(L):
            for k3 in range(L):
                for k4 in range(L):
                    t[i0][i1][i2][k3][k4] = (t[i0][i1][i2][k3][k4]
                        * pow(inv_psi, 2*L2*i2*(L*k3+k4), Q)) % Q
dump_axis_i2("CK_AFTER_INV_XTW2", t)

# INV_L1 (k3 -> i3), lane=i3
for i0 in range(L):
    for i1 in range(L):
        for i2 in range(L):
            for k4 in range(L):
                col = [t[i0][i1][i2][k3][k4] for k3 in range(L)]
                col = _ntt_L(col, inverse=True)
                for i3 in range(L): t[i0][i1][i2][i3][k4] = col[i3]
dump_axis_i3("CK_AFTER_INV_L1", t)

# INV_XTW1
for i0 in range(L):
    for i1 in range(L):
        for i2 in range(L):
            for i3 in range(L):
                for k4 in range(L):
                    t[i0][i1][i2][i3][k4] = (t[i0][i1][i2][i3][k4]
                        * pow(inv_psi, 2*L3*i3*k4, Q)) % Q
dump_axis_i3("CK_AFTER_INV_XTW1", t)

# INV_L0 (k4 -> i4) + post-twist applied to FLAT (so the dump-by-layout differs)
for i0 in range(L):
    for i1 in range(L):
        for i2 in range(L):
            for i3 in range(L):
                col = [t[i0][i1][i2][i3][k4] for k4 in range(L)]
                col = _ntt_L(col, inverse=True)
                for i4 in range(L): t[i0][i1][i2][i3][i4] = col[i4]
dump_axis_i4("CK_AFTER_INV_L0_NTT_only", t)

# Post-twist
flat = [0]*N
for i4 in range(L):
    for i3 in range(L):
        for i2 in range(L):
            for i1 in range(L):
                for i0 in range(L):
                    idx = i0 + L*i1 + L2*i2 + L3*i3 + L4*i4
                    flat[idx] = (t[i0][i1][i2][i3][i4] * pow(inv_psi, idx, Q)) % Q

# Final c[i]
print("\n[CK_FINAL] flat[i] should be X = c[1]=1")
print(f"  flat[0..7] = {flat[:8]}")
