# `bivar_opt`: Optimized Bivariate NTT Multiplier

## Why an independent rewrite

The existing `rtl/bivar_ntt_top.v` was prototyped against the algebraic structure (working data held in Verilog `reg [WWIDTH-1:0] arr [0:N-1]` register arrays accessed by wide muxes). On a Kintex-7 -2 with N=64 it uses **19,341 LUTs** because each access pattern is implemented as a per-lane M-to-1 mux over a flat register array. At N=128 Vivado's router got stuck in congestion for over 2 hours.

The algorithm itself is sound — the FPGA mapping is what costs area. An independent implementation that maps the working arrays onto a conflict-free banked memory recovers the area budget the paper's DSP-ATP analysis assumes.

## Target architecture

### Storage
- 2 polynomials × 32 banks × 8 entries × 17 bits = 8704 bits total. Each bank is small (8 entries) so distributed RAM (LUTRAM) is the right primitive. Expected LUT cost for storage alone ≈ 17 LUT/bank × 32 banks × 2 polys = **~1.1K LUTs**, vs current 19K.
- Banking formula: `bank(i1, i2) = (i1 + i2) mod 32`, position within bank = `i1`. This is **conflict-free for both row reads (varying i1, fixed i2) and column reads (fixed i1, varying i2)** — exactly the two access patterns bivar's 2D NTT needs.

### Pipeline
- 3-stage pipelined `mod_mul_fermat` (matching `ntt_top` for fair Fmax comparison).
- Per-cycle issue with stall when needed.
- In-place computation: overwrite the same memory across phases (pre-twist → row-NTT → cross-twiddle → col-NTT → spectral form), eliminating the `raw_a/work/trans/spec_a` separate arrays.

### FSM phases (in-place)
1. `LOAD_A`, `LOAD_B`: stream input poly into respective conflict-free memory (1 element / cycle × N = N cycles each).
2. `PRE_TWIST + ROW_NTT`: for each `i2` in 0..M-1, read 8-element row → pre-twist via ModMul → row-NTT-8 (combinational) → write back. M cycles per poly.
3. `XTW`: cross-twiddle, in-place. M cycles per poly.
4. `COL_NTT`: for each `i1` in 0..L-1, read 32-element column → col-NTT-M (combinational) → write back. L cycles per poly.
5. `PWM`: read row from mem_A and mem_B, multiply, write back to mem_A. M cycles.
6. Inverse symmetric.
7. `OUTPUT`: stream mem_A out (N cycles).

### Estimated metrics (N=256)
- LUT: ~3-5K (vs current 19K at N=64).
- DSP: 8 (same).
- Fmax: ~80-150 MHz (3-stage pipelined ModMul like ntt_top).
- Cycles: 2N + 2M + M + L + M + L + M + M = ~750.

## Status (after first attempt)

### Done
- Folder created: `rtl_bivar_opt/`.
- **`bivar_opt_mem.v`** — conflict-free banked memory module with row/col/seq access modes. Compiles cleanly.
- **`bivar_opt_top.v`** — full top-level FSM, ModMul bank, sub-NTT instantiation, banked memories for all 8 working arrays. ~470 lines. Compiles cleanly.
- **`sim/testbenches/tb_bivar_opt_capture.v`** — testbench.
- **`sim/run_bivar_opt_regression.py`** — regression script.
- **v0 experiment** (just `ram_style="distributed"` hint on the original) — proved that the hint alone gives 0% LUT reduction (still 19,341 LUTs). Full restructuring is the only path.

### Bugs found and fixed

**Bug 1 (FIXED):** `work_m_col_wdata` defaulted to 0 instead of `nttM_out_pack` for `ST_INV_COL`.

**Bug 2 (FIXED):** `work_m_col_i1` defaulted to 0 instead of `op_count[POSW-1:0]` for `ST_INV_COL`. So INV_COL was always writing to position 0 in work memory, regardless of which column was being processed.

### Final regression result (all pass)

| N | identity | impulse | random | cycles |
|---|---|---|---|---|
| 64 | 64/64 ✓ | 64/64 ✓ | 64/64 ✓ | 208 |
| 128 | 128/128 ✓ | 128/128 ✓ | 128/128 ✓ | 392 |
| 256 | 256/256 ✓ | 256/256 ✓ | 256/256 ✓ | 760 |

Cycle counts match the original `bivar_ntt_top` exactly (same FSM, just different memory mapping).

### Synthesis results (Kintex-7 -2, synth-only, 10 ns target)

| N | Original LUT | bivar_opt LUT | bivar_opt DSP | Reduction |
|---|---|---|---|---|
| 64 | 19,341 | **13,423** | 8 | -30% |
| 128 | (couldn't impl) | 72,308 | 8 | **WORSE** |
| 256 | n/a | n/a (won't fit) | — | — |

**Key finding:** The conflict-free banking has its own LUT cost that scales with `B = max(L,M)`. For each bank's COL write, a B-to-1 demux routes the right lane data; for COL read, a B-to-1 mux per lane selects the right bank. With M=8 (N=64): 8-bank muxes are cheap. With M=16 (N=128): 16-bank muxes are 4× more expensive. With M=32: 32-bank muxes 8× more. So the LUT cost grows roughly **quadratically** in M for col mode (M lanes × M-to-1 mux each).

**The paper claim** that bivar uses "only 8 DSPs" is correct (synth confirms DSP=8 for all N). But the LUT area required by the time-shared FSM and its associated multiplexers grows fast on FPGA fabric. This is an honest paper-worthy finding.

### Original "Known bug 2" notes (now resolved)
- For `a=delta_0, b=delta_1` test (simplest non-trivial case), expected output is `[0, 1, 0, ..., 0]`.
- Got: nonzero at `idx ∈ {1, 9, 17, 25, 33, 41, 49, 57}` (i.e., all 8 positions with `i2=1`).
- Pattern: my INV_ROW writes nonzero to ALL `i1` lanes for the relevant `i2`, not just `i1=0`.

**Hand-traced analysis says:** every intermediate value matches expectation through INV_XTW (trans row at `i2=1` should be `[psi^1, psi^1, ..., psi^1]`), and INV_NTT-8 of this constant should give `[psi^1, 0, ..., 0]`, which after un-twist gives a delta at `i1=0`. But simulation produces non-constant `mul_out` across the 8 lanes.

**Hypothesis:** the bivar_ntt_subntt8 module's INV mode interaction with my refactored data layout differs from the original bivar in some subtle way — possibly related to whether the input to the INV-NTT is supposed to be in bit-reversed order or natural order, or how the post-INV-NTT lane index maps to `i1` vs `j1`.

### Debug strategy for next session
1. Add `$display` to `bivar_opt_top.v` to dump `ntt8_in_pack`, `ntt8_out_pack`, and `mul_out_pack` during the INV_ROW phase at `op_count=1` for the `a=δ_0, b=δ_1` test.
2. Run the original bivar with the same input and same dumps to see where the values diverge.
3. The bit-reversal expectation between FWD path and INV path is the most likely place — my refactor stores data via banked memory but the INV-NTT may expect bit-reversed input that I'm not providing.

### Realistic effort estimate
- 0.5-1 day of debug iteration to find and fix the indexing bug, then verify regression + run synth.

## Decision point for the user

1. **Continue debugging** — schedule another session to find the indexing bug.
2. **Hand off** — the memory module + top + testbench + design doc is a complete starting point. The bug is bounded to a layout-interpretation issue in one of the inverse phases.
3. **Pivot back to documenting the original bivar** — accept its high LUT cost as the paper finding.
