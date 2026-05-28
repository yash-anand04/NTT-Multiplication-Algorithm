#!/usr/bin/env python3
"""
plot_figures.py - publication figures from the measured U280 grid.
Outputs PDFs to docs/figures/ (Agg backend, vector output).

Fig.2  fixed-width compute scaling : LUT (left) + DSP/BRAM (right) vs N at L=4
Fig.3  shift-only vs DSP kernel     : grouped bar chart, N=4096 d=4 L=8
Fig.4  area-time product vs N       : LUT-ATP and DSP-ATP, two clean panels
"""
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# --- global publication style ---------------------------------------------
plt.rcParams.update({
    "font.size": 13, "axes.titlesize": 13, "axes.labelsize": 13,
    "xtick.labelsize": 12, "ytick.labelsize": 12, "legend.fontsize": 11,
    "lines.linewidth": 2, "lines.markersize": 8, "figure.dpi": 150,
    "savefig.bbox": "tight", "axes.grid": True, "grid.alpha": 0.3,
})
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "figures")
os.makedirs(OUT, exist_ok=True)

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
t_us = lambda fmax, cyc: cyc / fmax
XING = dict(N=1024, LUT=9783, DSP=16, Fmax=274, cyc=712)  # [VERIFY vs PDF]

# ---- Fig.2: fixed-width compute scaling at L=4 -----------------------------
l4 = sorted([g for g in GRID if g[0] == 4], key=lambda g: g[2])
N   = [g[2] for g in l4]; lut=[g[3] for g in l4]
dsp = [g[4] for g in l4]; bram=[g[5] for g in l4]; dd=[g[1] for g in l4]

fig, axL = plt.subplots(figsize=(6.4, 4.2))
axL.set_xscale("log", base=2)
ln1, = axL.plot(N, lut, "o-", color="tab:blue", label="LUT")
axL.set_xlabel(r"$N=L^{d}$   (L=4,  d=3$\rightarrow$7)")
axL.set_ylabel("LUT", color="tab:blue")
axL.tick_params(axis="y", labelcolor="tab:blue")
axL.set_ylim(0, 3000)
for x, y, d in zip(N, lut, dd):
    axL.annotate(f"d={d}", (x, y), textcoords="offset points",
                 xytext=(0, 10), ha="center", fontsize=11)
axR = axL.twinx()
ln2, = axR.plot(N, dsp, "^--", color="tab:red", label="DSP")
ln3, = axR.plot(N, bram, "s:", color="tab:green", label="BRAM tiles")
axR.set_ylabel("DSP  /  BRAM tiles")
axR.set_ylim(0, 30); axR.grid(False)
axL.set_title("Fixed-width compute as depth grows (L=4):\n"
              r"$256\times$ N for +20\% LUT, DSP fixed at 4")
axL.legend(handles=[ln1, ln2, ln3], loc="center left", framealpha=0.9)
fig.savefig(os.path.join(OUT, "fig2_constant_hw_L4.pdf")); plt.close(fig)

# ---- Fig.3: shift-only vs DSP kernel (N=4096, d=4, L=8) --------------------
metrics = ["LUT", "DSP", r"$F_{max}$ (MHz)"]
dsp_based  = [11040, 37, 61]
shift_only = [5624,  8,  222]
x = np.arange(len(metrics)); w = 0.38
fig, ax = plt.subplots(figsize=(6.4, 4.2))
b1 = ax.bar(x - w/2, dsp_based, w, label="DSP-based kernel", color="0.55")
b2 = ax.bar(x + w/2, shift_only, w, label="shift-only kernel", color="tab:blue")
ax.set_yscale("log"); ax.set_ylim(8, 60000)
ax.set_xticks(x); ax.set_xticklabels(metrics)
ax.set_ylabel("value (log scale)")
ax.set_title("Shift-only vs DSP-based 8-pt sub-NTT (N=4096):\n"
             r"$-49\%$ LUT, $-78\%$ DSP, $3.6\times$ $F_{max}$")
ax.legend(loc="upper right", framealpha=0.9)
for bars in (b1, b2):
    for r in bars:
        ax.annotate(f"{int(r.get_height())}",
                    (r.get_x()+r.get_width()/2, r.get_height()),
                    textcoords="offset points", xytext=(0, 4),
                    ha="center", fontsize=11)
fig.savefig(os.path.join(OUT, "fig3_shiftonly_vs_dsp.pdf")); plt.close(fig)

# ---- Fig.4: ATP vs N, two clean stacked panels -----------------------------
Ns   = [g[2] for g in GRID]
lutatp = [g[3]*t_us(g[6], g[7]) for g in GRID]
dspatp = [g[4]*t_us(g[6], g[7]) for g in GRID]
xt = t_us(XING["Fmax"], XING["cyc"])
fig, (a1, a2) = plt.subplots(2, 1, figsize=(6.4, 6.4), sharex=True)
a1.set_xscale("log", base=2); a1.set_yscale("log")
a1.scatter(Ns, lutatp, color="tab:blue", s=45, label="ours")
a1.scatter([XING["N"]], [XING["LUT"]*xt], color="black", marker="*", s=240,
           label="Xing et al.", zorder=5)
a1.set_ylabel(r"LUT-ATP (LUT$\cdot\mu$s)")
a1.set_title("Area-time product vs N (lower is better)")
a1.legend(framealpha=0.9)
a2.set_xscale("log", base=2); a2.set_yscale("log")
a2.scatter(Ns, dspatp, color="tab:red", s=45, label="ours")
a2.scatter([XING["N"]], [XING["DSP"]*xt], color="black", marker="*", s=240,
           label="Xing et al.", zorder=5)
a2.set_ylabel(r"DSP-ATP (DSP$\cdot\mu$s)"); a2.set_xlabel("N")
a2.legend(framealpha=0.9)
fig.savefig(os.path.join(OUT, "fig4_atp_vs_n.pdf")); plt.close(fig)

# ---- Fig.5: measured vs predicted cycle count -----------------------------
def predicted(L, d, N):  # base closed form, no fitted parameter
    return (6*d - 2)*(N//L + 12) + 2*N
meas = [g[7] for g in GRID]
pred = [predicted(g[0], g[1], g[2]) for g in GRID]
pct  = [100.0*(m-p)/m for m, p in zip(meas, pred)]
maxerr = max(pct)

fig, ax = plt.subplots(figsize=(5.0, 4.2), layout="constrained")
ax.set_xscale("log"); ax.set_yscale("log")
lo, hi = 250, 300000
ax.plot([lo, hi], [lo, hi], "k--", lw=1.2, label="ideal $y=x$")
ax.scatter(pred, meas, color="tab:blue", s=55, zorder=5,
           label="measured (13 configs)")
ax.set_xlim(lo, hi); ax.set_ylim(lo, hi)
ax.set_aspect("equal")
ax.set_xlabel("predicted cycles  (Eq.~2)")
ax.set_ylabel("measured cycles")
ax.set_title("Parameter-free cycle model vs measurement")
ax.annotate(f"all points within {maxerr:.1f}%\n($\\leq$13 cycles)",
            xy=(0.97, 0.06), xycoords="axes fraction", ha="right",
            fontsize=11, bbox=dict(boxstyle="round", fc="white", ec="0.6"))
ax.legend(loc="upper left", framealpha=0.9)
fig.savefig(os.path.join(OUT, "fig5_cycle_model.pdf")); plt.close(fig)

print("wrote fig2/3/4/5 to docs/figures/")
