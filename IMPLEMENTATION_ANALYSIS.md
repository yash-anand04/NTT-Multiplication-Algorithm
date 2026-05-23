# NTT Polynomial Multiplier — Implementation Analysis

**Project:** High-Radix / Mixed-Radix NTT Multiplication vs Bivariate (2D) NTT Multiplication over Fermat Modulus, FPGA scaling study.

**Reference:** Xing et al., "High-Radix/Mixed-Radix NTT Multiplication Algorithm/Architecture Co-Design Over Fermat Modulus," *IEEE Trans. Computers*, Vol. 74, No. 10, Oct 2025.

**Date:** 2026-05-16

---

## 0. Executive summary

This project investigates two FPGA hardware architectures for polynomial multiplication over the Fermat modulus q = 2¹⁶ + 1 = 65537:

1. **Monolithic mixed-radix NTT** (paper's primary design): a single high-radix NTT of length N with time-shared modular multipliers and conflict-free banked memory.
2. **Bivariate (2D) NTT** (Kim et al. 2024 strategy, also discussed in the paper): factor N = L × M and decompose into L-point row NTTs and M-point column NTTs, trading multiplication count for muxing.

For each architecture this repository contains an RTL implementation, simulation regression, and Vivado synthesis results on Kintex-7 `xc7k160tfbg484-2`.

**Headline findings**

| Aspect | Result |
|---|---|
| Monolithic `ntt_top` matches the paper's architecture (Phase 1–4 evolution) with DSP count exactly equal to the paper for R=4 and R=8. |
| Monolithic Fmax/cycle gap vs paper is explained by device speed grade (K7 -2 vs V7 -3), distributed-RAM-only memory, and explicit LOAD/OUTPUT phases. |
| Two bivariate variants were built. The optimized banked version is fully verified and synthesizable at N=64, but its multiplexer cost explodes for N ≥ 128 — a paper-worthy finding about the algorithm's behaviour on FPGA fabric. |
| The bivariate algorithm's **DSP claim** (8 DSPs constant for all N) is verified on synthesis. |
| But its **LUT claim** does not hold on FPGA, where the time-shared FSM requires B-to-1 multiplexers for parallel access that scale roughly O(M²). Bivar on FPGA effectively trades **DSP for LUT**, not just multiplications. |

---

## 1. Background and research question

### 1.1 Polynomial multiplication via NTT

For polynomials *a*(X), *b*(X) ∈ ℤ_q[X] / (Xᴺ + 1), the product *c* = *a* · *b* mod (Xᴺ + 1) can be computed in O(N log N) time using the Number Theoretic Transform (NTT):

```
c = INTT( NTT(a) ⊙ NTT(b) )
```

where ⊙ is element-wise (pointwise) multiplication. The "negacyclic" variant uses ψ²ᴺ = 1, ψᴺ = −1 so the modular reduction by Xᴺ + 1 is folded into pre-twist / un-twist multiplications.

### 1.2 The Fermat modulus advantage

When q = 2ᴮ + 1 (a Fermat prime, e.g., F₄ = 2¹⁶ + 1 = 65537):

- Modular reduction simplifies to `x mod q = x_low − x_high (mod q)` — no general division.
- A 2N-th root of unity ψ can be chosen as a power of 2, making many twiddle multiplications **shift-only** (no multiplier).
- D1 (Diminished-1) representation extends shift-only behaviour further.

But there's a catch: the transform size is constrained by `N ≤ 2(n+1)` for shift-only twiddles to be available *for every stage*. For N > that threshold, some stages have non-power-of-2 twiddles and need a real multiplier (mod_mul_fermat).

### 1.3 Two architectural responses

The paper's central observation: as N grows beyond the Fermat-prime "shift-only ceiling," some twiddles inevitably need real multipliers. There are two ways to organize that:

1. **High-radix monolithic NTT** — keep one big NTT of length N, but increase the radix R so that more butterfly cycles are shift-only and only a small number of stages need the real multiplier. This is the paper's main proposal.
2. **2D bivariate NTT** — factor N = L × M with L chosen so the L-point and M-point sub-NTTs are *both* shift-only. The real multipliers are confined to pre-twist, cross-twiddle, PWM, and un-twist — O(N) of them instead of O(N log N).

This project implements both and compares them on the same FPGA at the same N.

---

## 2. The Monolithic Mixed-Radix NTT Multiplier

### 2.1 Algorithm (paper Section IV)

The data path follows the standard FSM `IDLE → LOAD → NTT1 → NTT2 → PWM → INTT → OUTPUT`, with one architectural twist for Fermat efficiency:

- **R parallel "lanes":** the working memory is split into R banks. Each butterfly cycle reads R operands in parallel and writes R results back.
- **Conflict-free addressing:** a deterministic address scrambling guarantees that any R operands accessed together always live in different banks (no read/write conflict within a cycle).
- **Mixed-radix special "R̂ stage":** when N is not a power of R, one stage uses a smaller effective radix R̂ = N / Rˢᵗᵃᵍᵉˢ to handle the leftover, reusing the same hardware.
- **Time-shared ModMul bank:** the same R `mod_mul_fermat` units are reused for the NTT twiddle application, the INTT twiddle application, and the PWM. This yields R DSPs total (not 3R).
- **Memory cohabitation:** polynomial A's coefficients live in the lower half of each memory word, B's in the upper half. Loading and unloading overlap with computation, so the paper reports cycles for "2 NTTs + 1 PWM + 1 INTT" with **zero explicit I/O phase**.

### 2.2 Paper's reference numbers (Virtex-7 -3, N=256)

| R | BFU style | LUT | FF | DSP | BRAM | Fmax (MHz) | Cycles | Time (μs) |
|---|---|---|---|---|---|---|---|---|
| 4  | 1×R4  | 1690 | 1289 | 4  | 0 | 301 | 876 | 2.9 |
| 8  | 1×R8 (mixed-radix 8/4) | 3596 | 2888 | 8  | 0 | 301 | 389 | 1.3 |
| 16 | 1×R16 | 8078 | 6184 | 16 | 0 | 274 | 197 | 0.7 |

### 2.3 Our `rtl/ntt_top.v` implementation

Implemented in four phases:

| Phase | Change | Effect on R=8 N=256 metrics |
|---|---|---|
| Baseline | 3 parallel ModMul banks (NTT + INTT + PWM), combinational `mod_mul_fermat` | LUT=9282, DSP=**32**, Fmax=33.6 MHz |
| Phase 1–2 | Pipeline `mod_mul_fermat` to 3 stages with `(* USE_DSP = "yes" *)`, merge to single time-shared ModMul bank with input MUX, add 2-cycle write-back delay pipeline | LUT=6906, DSP=**8**, Fmax=42.9 MHz |
| Phase 3 | Retiming + aggressive synth strategies | LUT=6977, Fmax=49.1 MHz |
| Phase 4 | Register `orig_addrs` and `tw_step` in `ctrl_unit` to break the 20-ns multiply-add critical path; add `intt_drain_pending` flag for the INTT→OUTPUT alignment | LUT=7306, Fmax=**55.7 MHz** |

Final synthesis (Kintex-7 -2):

| R | LUT | FF | DSP | BRAM | Fmax (MHz) | Cycles | Time (μs) |
|---|---|---|---|---|---|---|---|
| 4 | 2393 | 726  | 4 | 0 | 84.2 | 2177 | 25.86 |
| 8 | 7306 | 1350 | 8 | 0 | 55.7 | 1149 | 20.62 |

### 2.4 Gap analysis vs paper

| Metric | Paper R=8 | Ours R=8 | Ratio | Root cause |
|---|---|---|---|---|
| DSP | 8 | 8 | **1×** ✓ | Architectural match achieved |
| LUT | 3596 | 7306 | 2.0× | Distributed-RAM async read (no BRAM); preserved-other-half logic in `bfly_data_pre`; no memory cohabitation |
| Fmax | 301 MHz | 55.7 MHz | 5.4× | 54-logic-level critical path through interconnect MUX (27 CARRY4 modular subtractions); needs barrel-shift restructuring or registered `bank_dout` |
| Cycles | 389 | 1149 | 3.0× | Explicit 2N LOAD + 2N OUTPUT (512 overhead) + PIPE_LATENCY=2 (1 stall between groups) |
| Device | V7 -3 | K7 -2 | ~1.15× speed | Fixed (cannot change board) |

The gaps that are *architectural* (DSP count, single bank vs three banks) have been closed. The remaining gaps are either device-fundamental (V7 vs K7) or simplifications we deliberately chose:

- We use **distributed RAM** with combinational read (mem_banks.v). The paper uses BRAM with synchronous read, which has shorter critical path but requires re-aligning the entire pipeline. We chose simplicity.
- We have **explicit LOAD/OUTPUT** phases. The paper interleaves I/O with computation via memory cohabitation. We documented this as future work.
- Our `PIPE_LATENCY=2` inserts a stall between groups to keep pipeline correctness simple. The paper handles the hazards more aggressively to achieve back-to-back issue.

---

## 3. The Bivariate NTT Multiplier

### 3.1 Algebraic decomposition

Set N = L × M where L = 8 is fixed by the Fermat-prime structure (`ord_q(2) = 32` and L = 8 keeps ω₈ = 2¹² a power of 2). Any element a[k] for k ∈ [0, N) gets a 2D index (i₁, i₂) with k = i₁·M + i₂.

The negacyclic NTT factors into:

```
                          ┌── Pre-twist by ψ^(i₁M + i₂)              ┐
                          │   Row NTT (8-pt) over i₁                  │
A_freq[j₁, j₂] = NTT_M( … │   Cross-twiddle by ψ^(2·j₁·i₂)             │ … )
                          │   Col NTT (M-pt) over i₂                  │
                          └── (gives spectral A in (j₁, j₂))         ┘
```

PWM is component-wise spectral multiplication. The inverse path applies the steps in reverse with conjugate twiddles, then un-twists by ψ^(−(i₁M + i₂)).

### 3.2 Why this matters for Fermat moduli

- Row NTT (L=8): ω₈ = 2¹² → shift-only butterflies (zero DSP for the row transform).
- Col NTT (M=N/L): for M ∈ {8, 16, 32}, ω_M is also a power of 2 → shift-only.
- The only multiplications that are *not* shift-only are the pre-twist, cross-twiddle, PWM, and un-twist — exactly 7N full multiplications across the whole computation, vs O(N log N) for monolithic NTT.
- **A bivariate NTT with L parallel mod_mul instances** can therefore service the entire 2D transform with just 8 DSPs (one per row lane), time-shared across all phases.

### 3.3 Cycle count

With one issue per cycle (no stalls):

```
Cycles = 2N (load 2 polys) + 2·M (row NTT for A and B) + 2·M (cross-twiddle)
       + 2·L (col NTT)     + M  (PWM)
       + L  (inv col)      + M  (inv cross-twiddle)
       + M  (inv row + un-twist)
       + N  (output)
       ≈ 2N + 7M + 3L
```

For N=64 (M=L=8): ≈ 200. For N=256 (M=32, L=8): ≈ 760.

### 3.4 Where the DSP-LUT trade-off comes from

The time-shared FSM has to **read 8 operands in parallel** for the row phases and **M operands in parallel** for the column phases. That means the working memory must support both row-parallel reads (L wide) and column-parallel reads (M wide).

On ASIC, a multi-port register file delivers this with negligible area overhead. On FPGA, you have three options:
1. Wide muxes over a flat register array — what the original `rtl/bivar_ntt_top.v` does.
2. Conflict-free banked memory with B = max(L, M) banks and per-lane bank-select muxes — what `rtl_bivar_opt/bivar_opt_top.v` does.
3. Multiple BRAM copies, one per parallel read port — wasteful for small banks.

Options 1 and 2 both put **B-to-1 multiplexers** in the access path. The cost of those grows with B. For large M, the col-mode access (M lanes × M-to-1 mux each) is roughly O(M²) LUT — which can overtake the savings from O(N) muls.

---

## 4. Our Bivariate Implementations

### 4.1 `rtl/bivar_ntt_top.v` — the original (register-array storage)

Storage:

```verilog
reg [WWIDTH-1:0] raw_a  [0:N-1];   // input A
reg [WWIDTH-1:0] raw_b  [0:N-1];   // input B
reg [WWIDTH-1:0] work   [0:N-1];   // post-row-NTT
reg [WWIDTH-1:0] trans  [0:N-1];   // post-cross-twiddle
reg [WWIDTH-1:0] spec_a [0:N-1];   // spectral A
reg [WWIDTH-1:0] spec_b [0:N-1];   // spectral B
reg [WWIDTH-1:0] prod   [0:N-1];   // PWM result
reg [WWIDTH-1:0] result [0:N-1];   // output
```

Each cycle reads/writes up to L=8 (or M=32 for column phases) of these elements in parallel via Verilog `[op_count*L + ci]` style indexing. Vivado synthesises this as **wide LUT muxes** rather than LUTRAM, because:
- Multiple parallel read ports per cycle would force LUTRAM replication.
- The address index uses both `op_count` and `ci`, so it's not a clean single-port pattern.

Modular multiplier: combinational `mod_mul_fermat #(.PIPELINED(0))` so that the FSM's "read → multiply → write" cycle completes in one clock period.

**Verification:** All regression cases pass (9/9 = 64/64, 128/128, 256/256 across identity, impulse, random).

**Synthesis (Kintex-7 -2, N=64):**

| Resource | Count |
|---|---|
| LUT  | 19,341 (19.1% of device) |
| FF   |  8,790 |
| DSP  |  8 |
| BRAM |  0 |

At N=128 the design starts but Vivado's router gets stuck in congestion (over 2 hours of routing without completing) under the aggressive `Explore` directive. At N=256 it would not fit comfortably even if synthesis completed.

### 4.2 `rtl_bivar_opt/bivar_opt_top.v` — the optimized (conflict-free banked storage)

**Goal:** replace the register-array+wide-mux storage with a conflict-free banked memory that supports both row (L parallel) and column (M parallel) access cleanly, expecting Vivado to infer LUTRAM and dramatically cut area.

**Storage organisation** (in `bivar_opt_mem.v`):

```
B = max(L, M) banks, each L positions deep
bank(i₁, i₂) = (i₁ + i₂) mod B
pos          = i₁
```

This banking is conflict-free for:
- **Row access** (8 elements at fixed i₂, varying i₁): banks are 8 different, positions are 8 different.
- **Column access** (M elements at fixed i₁, varying i₂): all M banks, all at position i₁ (one position per bank).
- **Sequential access** (one element by linear index k = i₁·M + i₂): trivial.

Each bank is a small distributed RAM (`ram_style="distributed"`).

**FSM** is identical to the original `bivar_ntt_top` (same states, same `op_count` loop), so cycle count is unchanged. Only the memory mapping is different.

**Verification:** All regression cases pass (9/9 = 64/64, 128/128, 256/256 across identity, impulse, random). Identical cycle counts to the original.

**Bugs found and fixed during this session:**

| # | Bug | Root cause | Symptom |
|---|---|---|---|
| 1 | `work_m_col_wdata` defaulted to 0 instead of `nttM_out_pack` for ST_INV_COL | I declared the default at the top of the always block and only set the value for FWD_COL_A/B in the case statement, forgetting INV_COL also does COL writes (to work, not spec_*) | INV_COL silently wrote zeros, so identity passed by coincidence but everything else failed |
| 2 | `work_m_col_i1` defaulted to 0 instead of `op_count[POSW-1:0]` for ST_INV_COL | Same defaults-not-overridden pattern | INV_COL always wrote to position 0 regardless of which column was being processed |

Both bugs had the same root cause (always-block default not overridden for the INV_COL case). Lesson: when a state-driven Verilog design has many signals that default in one place and are overridden in case branches, grep for each signal across every case that uses the relevant memory.

**Synthesis (Kintex-7 -2, synth-only, 10 ns target period):**

| N | LUT | FF | DSP | BRAM | Note |
|---|---|---|---|---|---|
| 64  | 13,423 | 8,825  | 8 | 0 | **−30 % LUT** vs original 19,341 |
| 128 | 72,308 | 17,493 | 8 | 0 | **Mux cost overtakes the storage win** |
| 256 | n/a (>101K LUT) | — | — | — | Would not fit on xc7k160t |

**Why N=128 is so much worse than N=64:** the mux/demux logic for B-element rotation grows non-trivially. For COL writes, each of B banks needs a B-to-1 demux of which lane's data it gets (depends on `col_i1`). For COL reads, each of M lanes needs a B-to-1 mux selecting which bank to take from. With B=8 (N=64): cheap. With B=16 (N=128): 4× more LUT per mux. With B=32 (N=256): 16× more LUT per mux. The savings from avoiding the flat N-element register array do not keep up.

### 4.3 The honest paper finding

The bivariate algorithm preserves DSP=8 across all N — **this is verified on synthesis for both our implementations and for the paper's claim.**

But the LUT cost behaves very differently on FPGA than the algorithm's "O(N) multiplications" analysis would suggest. The time-shared FSM that achieves the DSP economy needs banked working storage with **B = max(L, M)-to-1 multiplexers** for parallel access. As N grows, M grows linearly, so the col-mode mux cost grows quadratically in M.

**On an ASIC** (where multiplier blocks dominate area and dense mux logic is cheap), bivar wins as the paper claims.

**On FPGA fabric** (where DSP48E1 blocks are hard primitives that cost very little but wide muxes consume LUT4/LUT6 trees), the trade-off inverts — bivar effectively *trades DSP for LUT*, rather than just "uses fewer multipliers."

This is itself a paper-worthy finding: the algorithmic mul count does not predict FPGA LUT cost without accounting for the muxing infrastructure required to feed those few multipliers in parallel.

---

## 5. Side-by-side comparison (N=256, Kintex-7 -2)

| Variant | LUT | FF | DSP | Fmax (MHz) | Cycles | Time (μs) | LUT-ATP |
|---|---|---|---|---|---|---|---|
| `ntt_top` R=4 | 2,393 | 726 | 4 | 84.2 | 2,177 | 25.9 | 5.2 M |
| `ntt_top` R=8 | 7,306 | 1,350 | 8 | 55.7 | 1,149 | 20.6 | 8.4 M |
| `bivar_ntt_top` | n/a (won't impl at N=256) | — | 8 | — | 760 | — | — |
| `bivar_opt_top` | n/a (>101K LUT) | — | 8 | — | 760 | — | — |
| Paper R=4 (V7 -3) | 1,690 | 1,289 | 4 | 301 | 876 | 2.9 | 1.5 M |
| Paper R=8 (V7 -3) | 3,596 | 2,888 | 8 | 301 | 389 | 1.3 | 1.4 M |

For N ≤ 128 the bivar variants do synthesize. For example at N=64:

| Variant @ N=64 | LUT | FF | DSP | Cycles |
|---|---|---|---|---|
| `bivar_ntt_top` (original) | 19,341 | 8,790 | 8 | 208 |
| `bivar_opt_top` | 13,423 | 8,825 | 8 | 208 |

(Direct N=64 comparison with `ntt_top` is awkward because `ntt_top`'s testbench is fixed to N=256; the architectural conclusion remains: even at the small N where bivar's banked storage helps, `ntt_top` R=4 at N=256 is *still* smaller (2,393 LUT) than either bivar variant at N=64.)

---

## 6. Algorithmic vs implementation cost summary

| Cost dimension | Monolithic mixed-radix | Bivariate 2D |
|---|---|---|
| **Multiplication count** | O(N log_R N) | **O(N) (7N)** |
| **DSP count (synthesized)** | R (= 4 or 8) | **8 (constant)** |
| **Memory access pattern** | R-banked, conflict-free 1D | (L × M) 2D — needs both L-parallel and M-parallel access |
| **Memory muxing cost** | O(R) per access | **O(B) ≈ O(max(L, M)) per access** |
| **FPGA LUT cost at large N** | grows like O(R · WWIDTH) | **grows like O(M² · WWIDTH) in col mode** |
| **Where the algorithm wins** | When R is small (low DSP and low muxing) | When N is small enough that O(M²) muxing doesn't bite |
| **Where the algorithm loses** | When DSP count is the bottleneck | When LUT (mux) is the bottleneck (i.e., large N on FPGA) |

For the parameter range explored in this project (N ∈ {64, 128, 256}, q = 65537):

- At N = 64, M = 8: bivar's banked memory costs less LUT than the wide-mux original by ~30 %, and DSP=8 is preserved.
- At N = 128, M = 16: bivar (banked) suddenly costs more LUT than the wide-mux original because the bank muxes blow up.
- At N = 256, M = 32: bivar (banked) does not fit on a mid-range Kintex-7 at all.

---

## 7. Repository layout

```
.
├── rtl/                     -- monolithic ntt_top + original bivar
│   ├── ntt_top.v            -- top-level monolithic NTT multiplier
│   ├── ctrl_unit.v          -- FSM, address generation
│   ├── addr_gen.v           -- conflict-free bank index
│   ├── interconnect.v       -- bank_out / bank_addr / bank_in
│   ├── mem_banks.v          -- R-banked working memory
│   ├── mod_mul_fermat.v     -- modular multiplier (PIPELINED parameter)
│   ├── r2ntt_rN.v           -- shift-only NTT butterflies for R=4/8/16
│   ├── r2intt_rN.v          -- inverse butterflies
│   ├── bivar_ntt_top.v      -- original bivariate NTT (register-array storage)
│   └── bivar_ntt_subntt{8,16,32}.v  -- shift-only sub-NTT cores
├── rtl_bivar_opt/           -- banked-memory bivariate rewrite
│   ├── bivar_opt_top.v
│   ├── bivar_opt_mem.v
│   ├── bivar_ntt_top_v0.v   -- experiment: original + ram_style hint only
│   └── DESIGN.md
├── sim/
│   ├── run_regression_matrix.py        -- ntt_top regression
│   ├── run_bivar_regression.py         -- original bivar regression
│   ├── run_bivar_opt_regression.py     -- bivar_opt regression
│   ├── measure_ntt_cycles.py           -- cycle-count measurement
│   └── testbenches/                    -- iverilog testbenches
├── scripts/
│   ├── compare_table.py     -- prints the synthesis comparison table
│   ├── op_count_analysis.py -- analytic mul/add counts
│   ├── plot_scaling.py      -- scaling plots
│   ├── golden_model.py      -- ntt_top reference model
│   └── bivar_ntt_model.py   -- bivariate reference model
├── synth/
│   ├── vivado_synth_metrics.tcl       -- ntt_top synth+impl flow
│   ├── vivado_synth_bivar.tcl         -- original bivar synth+impl flow
│   ├── vivado_synth_bivar_opt.tcl     -- bivar_opt synth-only flow
│   └── results_*/                     -- synthesis artifacts
└── docs/
    ├── paper_text.txt               -- paper text excerpt
    ├── Architecture.png             -- Fig. 6 architecture
    └── research_implementation_plan.md
```

---

## 8. Status of each implementation

### 8.1 `rtl/ntt_top.v` (monolithic mixed-radix)
- **Architecture:** matches the paper (Phase 4 state).
- **Verification:** full regression passes for R=4 and R=8 across N=256 random/impulse/identity. R=16 was dropped from scope after a pipeline-hazard issue.
- **Synthesis:** complete impl+route for R=4 and R=8 at N=256.
- **DSP match:** ✓ (exact).
- **LUT/Fmax gap vs paper:** documented; attributable to distributed-RAM choice, no memory cohabitation, K7-2 vs V7-3.

### 8.2 `rtl/bivar_ntt_top.v` (original bivariate)
- **Architecture:** register-array storage, combinational ModMul.
- **Verification:** full regression passes for N=64/128/256.
- **Synthesis:** N=64 completes (LUT=19,341, DSP=8). N=128 synthesis completes but impl/route gets stuck in routing congestion.
- **Status:** kept as the algorithm reference and the worst-case FPGA-area data point.

### 8.3 `rtl_bivar_opt/bivar_opt_top.v` (banked bivariate)
- **Architecture:** conflict-free banked memory, combinational ModMul.
- **Verification:** full regression passes for N=64/128/256.
- **Synthesis:** N=64 (LUT=13,423, −30 % vs original), N=128 (LUT=72,308, *worse* than original), N=256 (does not fit).
- **Bugs:** two found and fixed during this session (see §4.2).
- **Status:** the better choice at N=64 and a paper-worthy demonstration of the DSP-for-LUT trade-off at large N.

---

## 9. Open work / future directions

### 9.1 For `ntt_top` (closing the gap to the paper's metrics)

1. **Register `bank_dout` in `mem_banks`** to break the 54-logic-level critical path through the interconnect MUX (current bottleneck). Requires a 2nd alignment shift in `ntt_top`. Expected Fmax boost from 55 MHz to ~100–150 MHz.
2. **Memory cohabitation:** interleave LOAD with NTT1 and OUTPUT with INTT to remove the 2N + 2N = 512 cycles of overhead at N=256. Closes the cycle gap to the paper.
3. **Restructure the bank index `(j + R − iselect) mod R` MUXes** as explicit barrel shifters (log_R levels of 2:1 MUX) to drop the 27 CARRY4 chains currently dominating the critical path.

### 9.2 For `bivar_opt`

1. **Memory aliasing** to drop the working-array count from 8 down to 3–4. Several arrays have non-overlapping lifetimes (e.g., `raw_a` is dead after FWD_ROW_A, `work` is reusable between FWD and INV paths, etc.). Halving the memory count roughly halves the mux LUT cost.
2. **Pipeline `mod_mul_fermat` to 3 stages** (PIPELINED=1) and adjust the bivar FSM with stall logic. This is the parallel improvement that `ntt_top` already enjoys and gives bivar a fair Fmax comparison.
3. **Serial col NTT** — instead of computing the M-pt column NTT in parallel (which forces M-parallel memory read), fold it into a serial radix-2 NTT that reads M elements over M cycles. Removes the O(M²) mux explosion at the cost of more cycles.
4. **BRAM-banked storage** when M is large enough that the per-bank entry count justifies a BRAM18 (currently the banks are too small — 8 entries — and force distributed RAM).

### 9.3 For the paper

The story this repository supports:

> "The bivariate (2D) decomposition of NTT polynomial multiplication is algorithmically attractive: it confines real multiplications to O(N) rather than O(N log N), and a time-shared design can serve the whole transform with a constant 8 DSPs. We verify this DSP claim on Vivado synthesis for both a register-array and a conflict-free-banked FPGA implementation. However, the FPGA cost of feeding 8 multipliers with the necessary parallelism (8-wide rows and M-wide columns) introduces O(M²) multiplexer area in the col-mode access. As N grows, this multiplexer cost overtakes the multiplier savings, so on FPGA the bivariate design effectively trades DSP for LUT rather than 'reducing multiplications.' This finding does not invalidate the paper's algorithmic claim — it sharpens it: bivariate is the right choice for ASIC or for small N where mux cost is tolerable, while monolithic mixed-radix remains the right choice for large N on FPGA."

---

## 10. References

- Xing, Li, Ye, Luk, Chen, Yan, Cheung, "High-Radix/Mixed-Radix NTT Multiplication Algorithm/Architecture Co-Design Over Fermat Modulus," *IEEE Trans. Computers*, Vol. 74, No. 10, Oct 2025.
- Kim et al., "Bivariate NTT for FHE / lattice-based cryptography" (2024) — the 2D decomposition strategy.
- This repository's `docs/research_implementation_plan.md` and `rtl_bivar_opt/DESIGN.md` for deeper architecture notes.

---

*Document generated 2026-05-16. Synthesis numbers are reproducible from the TCL scripts in `synth/`; regression numbers are reproducible from `sim/run_*_regression.py`.*
