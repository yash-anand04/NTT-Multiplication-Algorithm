#!/usr/bin/env python3
"""
Generate hier_d3_L{L}_top.v variants from hier_n32k_top.v template, for
L ∈ {4, 8, 16}.  Substitution-based: replaces bit-width and module-name
literals.  Output files are sibling RTL modules differing only in L.
"""
import os
import sys

TEMPLATE = "rtl_hier_ntt/hier_n32k_top.v"


def make_variant(L: int):
    log_lanes = (L).bit_length() - 1   # log2 for power-of-2 L
    log_depth = 2 * log_lanes
    logn      = 3 * log_lanes

    with open(TEMPLATE) as f:
        src = f.read()

    mask_bits = log_lanes
    mask_value = (1 << log_lanes) - 1
    mask_hex = f"{mask_bits}'h{mask_value:x}"
    zero_const = f"{mask_bits}'d0"

    # Order matters: do longer / more specific patterns first
    subs = [
        ("module hier_n32k_top", f"module hier_d3_L{L}_top"),
        ("_HIER_N32K_TOP_GUARD",  f"_HIER_D3_L{L}_TOP_GUARD"),
        ("parameter L       = 32",  f"parameter L       = {L}"),
        ("parameter LOGN    = 15",  f"parameter LOGN    = {logn}"),
        ("localparam integer LOG_LANES = 5",  f"localparam integer LOG_LANES = {log_lanes}"),
        ("localparam integer LOG_DEPTH = 10", f"localparam integer LOG_DEPTH = {log_depth}"),
        ("[14:10]", f"[{3*log_lanes-1}:{2*log_lanes}]"),
        ("[9:5]",   f"[{2*log_lanes-1}:{log_lanes}]"),
        ("[4:0]",   f"[{log_lanes-1}:0]"),
        ("5'h1f",   mask_hex),
        ("5'd0",    zero_const),
        ("sub_ntt32_bidir", f"sub_ntt{L}_bidir"),
    ]

    out = src
    for old, new in subs:
        out = out.replace(old, new)

    outpath = f"rtl_hier_ntt/hier_d3_L{L}_top.v"
    with open(outpath, "w") as f:
        f.write(out)
    print(f"wrote {outpath}  (L={L}, LOG_LANES={log_lanes}, LOG_DEPTH={log_depth}, N=L^3={L**3})")


def main():
    for L in [4, 8, 16]:
        make_variant(L)


if __name__ == "__main__":
    main()
