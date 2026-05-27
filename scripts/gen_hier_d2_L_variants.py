#!/usr/bin/env python3
"""
Generate hier_d2_L{L}_top.v variants from hier_n1024_top.v template,
for L ∈ {8, 16}.  Phase C uses LOG_LANES/LOG_DEPTH symbolically so
substitution is mostly parameter changes.  For d=2: N = L^2, M = L.
"""
import os
import sys

TEMPLATE = "rtl_hier_ntt/hier_n1024_top.v"


def make_variant(L: int):
    log_lanes = (L).bit_length() - 1   # log2(L)
    # For d=2: M = L, LOG_DEPTH = log2(M) = log2(L) = log_lanes

    with open(TEMPLATE) as f:
        src = f.read()

    # Substitutions (order matters)
    subs = [
        ("module hier_n1024_top", f"module hier_d2_L{L}_top"),
        ("_HIER_N1024_TOP_GUARD",  f"_HIER_D2_L{L}_TOP_GUARD"),
        ("parameter L       = 32",  f"parameter L       = {L}"),
        ("parameter M       = 32",  f"parameter M       = {L}"),
        # LOG_LANES localparam (in case it's literal): use string replacement on the localparam line
        ("localparam integer LOG_LANES = 5",  f"localparam integer LOG_LANES = {log_lanes}"),
        ("localparam integer LOG_DEPTH = 5",  f"localparam integer LOG_DEPTH = {log_lanes}"),
        # sub-NTT instance
        ("sub_ntt32_bidir", f"sub_ntt{L}_bidir"),
        # banked_mem instantiation: pass LOG_LANES/LOG_DEPTH explicitly
        # (default of banked_mem is 5 = built for L=32)
        ("banked_mem #(.WWIDTH(WWIDTH), .LANES(LANES), .DEPTH(DEPTH), \\\n                     .READ_LATENCY(0))",
         "banked_mem #(.WWIDTH(WWIDTH), .LANES(LANES), .DEPTH(DEPTH), \\\n                     .LOG_LANES(LOG_LANES), .LOG_DEPTH(LOG_DEPTH), \\\n                     .READ_LATENCY(0))"),
    ]

    out = src
    for old, new in subs:
        out = out.replace(old, new)

    outpath = f"rtl_hier_ntt/hier_d2_L{L}_top.v"
    with open(outpath, "w") as f:
        f.write(out)
    print(f"wrote {outpath}  (L={L}, LOG_LANES={log_lanes}, N=L^2={L**2})")


def main():
    for L in [8, 16]:
        make_variant(L)


if __name__ == "__main__":
    main()
