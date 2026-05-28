#!/usr/bin/env python3
"""
compare_metrics.py
Honest area-time comparison of our hierarchical cells vs the same-modulus
competitor (Xing et al., IEEE TC 2025) at the overlapping N.

Metrics:
  time_us      = cycles / Fmax(MHz)         [µs]
  LUT_ATP      = LUT * time_us              [LUT·µs]   (lower better)
  DSP_ATP      = DSP * time_us              [DSP·µs]   (lower better)
  thru_Mels    = N / time_us                [Melem/s]  (higher better)
  thru_per_DSP = thru_Mels / DSP            [Melem/s/DSP]
  thru_per_kLUT= thru_Mels / (LUT/1000)     [Melem/s/kLUT]

NOTE: the Xing row is transcribed from prior project notes (N=1024, 1xR16);
      VERIFY against the primary PDF before publication (see
      docs/VERIFIED_REFERENCES.md [R1]).
"""

# (label, L, d, N, LUT, DSP, BRAM, Fmax_MHz, cycles)
OURS = [
    ("hier d2 L8 ", 8, 2, 64,    5698,  8,  0, 222, 329),
    ("hier d2 L16", 16,2, 256,   14477, 16, 0, 222, 793),
    ("hier d2 L32", 32,2, 1024,  36839, 32, 0, 180, 2489),
    ("hier d3 L4 ", 4, 3, 64,    2116,  4,  7, 222, 589),
    ("hier d3 L8 ", 8, 3, 512,   5452,  8, 14, 222, 2253),
    ("hier d3 L16", 16,3, 4096,  13320, 16,28, 222, 12493),
    ("hier d3 L32", 32,3, 32768, 36539, 32,56, 236, 82112),
    ("hier d4 L4 ", 4, 4, 256,   2158,  4,  7, 222, 2197),
    ("hier d4 L8 ", 8, 4, 4096,  5624,  8, 14, 222, 19733),
    ("hier d5 L4 ", 4, 5, 1024,  2305,  4,  7, 222, 9565),
    ("hier d5 L8 ", 8, 5, 32768, 6171,  8, 50, 222, 180573),
    ("hier d6 L4 ", 4, 6, 4096,  2360,  4,  7, 222, 43429),
    ("hier d7 L4 ", 4, 7, 16384, 2543,  4, 25, 222, 197101),
]

# Same-modulus competitor (q=65537). VERIFY numbers vs primary PDF.
XING = [
    ("Xing 1xR16*", None, None, 1024, 9783, 16, 0, 274, 712),  # 712 ~= 2.6us*274
]

def metrics(row):
    label, L, d, N, lut, dsp, bram, fmax, cyc = row
    t_us = cyc / fmax
    return {
        "label": label, "N": N, "LUT": lut, "DSP": dsp, "BRAM": bram,
        "Fmax": fmax, "cyc": cyc, "t_us": t_us,
        "LUT_ATP": lut * t_us, "DSP_ATP": dsp * t_us,
        "thru": N / t_us,
        "thru_per_DSP": (N / t_us) / dsp,
        "thru_per_kLUT": (N / t_us) / (lut / 1000.0),
    }

def fmt(m):
    return (f"{m['label']:11s} N={m['N']:6d} LUT={m['LUT']:6d} DSP={m['DSP']:3d} "
            f"t={m['t_us']:8.2f}us  LUT-ATP={m['LUT_ATP']:10.0f}  DSP-ATP={m['DSP_ATP']:8.1f}  "
            f"thru={m['thru']:7.2f}Mel/s  /DSP={m['thru_per_DSP']:7.2f}  /kLUT={m['thru_per_kLUT']:7.2f}")

print("="*150)
print("ALL OUR CELLS")
print("="*150)
for r in OURS:
    print(fmt(metrics(r)))

print("\n" + "="*150)
print("HEAD-TO-HEAD AT N=1024 (the only overlap with Xing)")
print("="*150)
overlap = [r for r in OURS if r[3] == 1024] + XING
ms = [metrics(r) for r in overlap]
for m in ms:
    print(fmt(m))

print("\n--- who wins each metric at N=1024 (lower ATP / higher thru is better) ---")
for key, better in [("t_us","min"), ("LUT","min"), ("DSP","min"),
                    ("LUT_ATP","min"), ("DSP_ATP","min"),
                    ("thru","max"), ("thru_per_DSP","max"), ("thru_per_kLUT","max")]:
    win = (min if better=="min" else max)(ms, key=lambda m: m[key])
    print(f"  {key:14s} ({better}): {win['label'].strip()} = {win[key]:.2f}")

print("\n* Xing cycles derived from reported 2.6us @ 274MHz; verify vs PDF.")
