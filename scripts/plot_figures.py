#!/usr/bin/env python3
"""
plot_figures.py — generate publication figures from the measured U280 grid.
Outputs PDFs to docs/figures/ (no GUI / Agg backend).

Fig.2  constant-hardware-in-d : LUT/DSP/BRAM vs N at L=4 (d=3..7)
Fig.3  shift-only vs DSP kernel : bar chart at N=4096, d=4
Fig.4  ATP vs N : LUT-ATP and DSP-ATP across the full grid + Xing point
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "figures")
os.makedirs(OUT, exist_ok=True)

# ---- measured data (U280, 4.5 ns target) -----------------------------------
# (L, d, N, LUT, DSP, BRAM, Fmax, cycles)
GRID = [
    (8, 2, 64,    5698,  8,  0, 222, 329),
    (16,2, 256,   14477, 16, 0, 222, 793),
    (32,2, 1024,  36839, 32, 0, 180, 2489),
    (4, 3, 64,    2116,  4,  7, 222, 589),
    (8, 3, 512,   5452,  8, 14, 222, 2253),
    (16,3, 4096,  13320, 16,28, 222, 12493),
    (32,3, 32768, 36539, 32,56, 236, 82112),
    (4, 4, 256,   2158,  4,  7, 222, 2197),
    (8, 4, 4096,  5624,  8, 14, 222, 19733),
    (4, 5, 1024,  2305,  4,  7, 222, 9565),
    (8, 5, 32768, 6171,  8, 50, 222, 180573),
    (4, 6, 4096,  2360,  4,  7, 222, 43429),
    (4, 7, 16384, 2543,  4, 25, 222, 197101),
]
def t_us(fmax, cyc): return cyc / fmax
XING = dict(N=1024, LUT=9783, DSP=16, Fmax=274, cyc=712)  # [VERIFY vs PDF]

# ---- Fig.2: constant-hardware-in-d at L=4 ----------------------------------
l4 = sorted([g for g in GRID if g[0] == 4], key=lambda g: g[1])
N   = [g[2] for g in l4]
lut = [g[3] for g in l4]
dsp = [g[4] for g in l4]
bram= [g[5] for g in l4]
fig, ax1 = plt.subplots(figsize=(6, 4))
ax1.set_xscale("log", base=2)
ax1.plot(N, lut, "o-", color="tab:blue", label="LUT")
ax1.plot(N, bram, "s--", color="tab:green", label="BRAM (×100)")  # scaled to share axis
ax1.set_xlabel("N = $L^d$  (L=4, d=3..7)")
ax1.set_ylabel("LUT  /  BRAM×100")
ax1.set_ylim(0, max(lut)*1.25)
for x, y, d in zip(N, lut, [g[1] for g in l4]):
    ax1.annotate(f"d={d}", (x, y), textcoords="offset points", xytext=(0, 8),
                 ha="center", fontsize=8)
# replot BRAM scaled
ax1.lines[1].set_ydata([b*100 for b in bram])
ax2 = ax1.twinx()
ax2.plot(N, dsp, "^-", color="tab:red", label="DSP")
ax2.set_ylabel("DSP", color="tab:red")
ax2.set_ylim(0, 16)
ax2.tick_params(axis="y", labelcolor="tab:red")
ax1.set_title("Constant compute hardware as depth d grows (L=4)\n"
              "256× N for +20% LUT; DSP fixed at 4")
h1, lb1 = ax1.get_legend_handles_labels()
h2, lb2 = ax2.get_legend_handles_labels()
ax1.legend(h1 + h2, lb1 + lb2, loc="upper left", fontsize=8)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "fig2_constant_hw_L4.pdf"))
plt.close(fig)

# ---- Fig.3: shift-only vs DSP kernel (N=4096, d=4) -------------------------
labels = ["LUT", "DSP", "Fmax (MHz)"]
dsp_based = [11040, 37, 61]      # sub_ntt_simple variant
shift_only = [5624, 8, 222]      # bidir
import numpy as np
x = np.arange(len(labels)); w = 0.36
fig, ax = plt.subplots(figsize=(6, 4))
b1 = ax.bar(x - w/2, dsp_based, w, label="DSP-based kernel", color="tab:gray")
b2 = ax.bar(x + w/2, shift_only, w, label="shift-only bidir kernel", color="tab:blue")
ax.set_yscale("log")
ax.set_xticks(x); ax.set_xticklabels(labels)
ax.set_title("Shift-only vs DSP-based sub-NTT (N=4096, d=4, L=8)\n"
             "−49% LUT, −78% DSP, 3.6× Fmax")
ax.legend(fontsize=9)
for bars in (b1, b2):
    for r in bars:
        ax.annotate(f"{int(r.get_height())}", (r.get_x()+r.get_width()/2, r.get_height()),
                    textcoords="offset points", xytext=(0, 3), ha="center", fontsize=8)
fig.tight_layout()
fig.savefig(os.path.join(OUT, "fig3_shiftonly_vs_dsp.pdf"))
plt.close(fig)

# ---- Fig.4: ATP vs N (full grid + Xing) ------------------------------------
fig, ax = plt.subplots(figsize=(6.5, 4))
ax.set_xscale("log", base=2); ax.set_yscale("log")
for g in GRID:
    L, d, n, lu, ds, br, fm, cy = g
    t = t_us(fm, cy)
    ax.scatter(n, lu * t, color="tab:blue", s=28)
    ax.scatter(n, ds * t * 1000, color="tab:red", marker="x", s=34)  # ×1000 to share axis
# Xing point
tx = t_us(XING["Fmax"], XING["cyc"])
ax.scatter(XING["N"], XING["LUT"]*tx, color="black", marker="*", s=160, label="Xing LUT-ATP", zorder=5)
ax.scatter(XING["N"], XING["DSP"]*tx*1000, color="green", marker="*", s=160, label="Xing DSP-ATP×1000", zorder=5)
ax.scatter([], [], color="tab:blue", label="ours LUT-ATP")
ax.scatter([], [], color="tab:red", marker="x", label="ours DSP-ATP×1000")
ax.set_xlabel("N"); ax.set_ylabel("Area-Time Product (LUT·µs  /  DSP·µs×1000)")
ax.set_title("Area-time product vs N (lower is better)\n"
             "Xing dominates at the N=1024 overlap")
ax.legend(fontsize=8, loc="upper left")
fig.tight_layout()
fig.savefig(os.path.join(OUT, "fig4_atp_vs_n.pdf"))
plt.close(fig)

print("wrote:")
for f in ["fig2_constant_hw_L4.pdf", "fig3_shiftonly_vs_dsp.pdf", "fig4_atp_vs_n.pdf"]:
    print("  docs/figures/" + f)
