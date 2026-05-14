# Research Implementation Plan
# 2D Bivariate NTT vs Monolithic NTT: A Hardware Scaling Study

**Goal:** Produce a research paper demonstrating how the 2D Cooley-Tukey NTT
decomposition scales compared to a monolithic mixed-radix NTT as the polynomial
degree N grows, with measured silicon-level evidence from FPGA synthesis.

**Target venue:** Mid-tier conference or journal in hardware security /
reconfigurable computing (e.g. CHES, FPL, TRETS, JETCAS).

---

## Current State of the Repository

### What is already done

| Item | Status |
|---|---|
| `ntt_top` RTL (monolithic, R=4/8/16) | Complete, verified |
| `ntt_top` synthesis at N=256, R=4/8/16 | Complete (Virtex-7 xc7k160t) |
| `bivar_ntt_top` RTL (2D, L=8, M=32) | Complete, verified (55/55 test cases) |
| `bivar_ntt_top` synthesis at N=256 | **Not done** |
| `bivar_ntt_model.py` algebraic model | Complete, passes 200 random checks |
| Synthesis TCL + metrics scripts | Complete for `ntt_top`, needs extension |

### What is missing (the entire research gap)

1. `bivar_ntt_top` synthesis results at N=256
2. Both designs synthesised at N=64, 128, 512 (scaling sweep)
3. `bivar_ntt_top` parameterised for N values other than 256
4. Column NTT cores for M=8, 16, 64 (currently only M=32 exists)
5. Simulation regression for all new N values
6. Comparative analysis scripts and plots
7. The paper itself

---

## Baseline Data (Already Collected)

`ntt_top` on Virtex-7 xc7k160tfbg484-2, N=256:

| Radix | LUT | FF | DSP | Fmax (MHz) | Cycles | Time (μs) | LUT·ATP |
|---|---|---|---|---|---|---|---|
| R=4 | 3,763 | 59 | 16 | 44.2 | 876 | 19.8 | 3,296,388 |
| R=8 | 9,282 | 70 | 32 | 33.6 | 389 | 11.6 | 3,610,698 |
| R=16 | 20,008 | 77 | 64 | 28.3 | 197 | 7.0 | 3,941,576 |

Observation: adding more DSPs reduces cycles but raises LUT cost and lowers Fmax.
R=8 is the most balanced point (lowest LUT·ATP and reasonable DSP count). It will
be the primary baseline for comparison against `bivar_ntt_top`.

---

## Phase 0 — Synthesis Baseline for bivar_ntt_top at N=256

**Goal:** Get the first data point for the 2D design at the same N as the existing
baseline. This is the minimum needed before any scaling work.

### 0.1 Create a bivar synthesis TCL script

Copy `synth/vivado_synth_metrics.tcl` and modify for `bivar_ntt_top`:

- Change `-top` from `ntt_top` to `bivar_ntt_top`
- Replace `-generic "R=$radix"` with `-generic "L=8" -generic "M=$m_dim"`
- Add a `cycles_map` entry for bivar cycle counts (formula: `2N + 7M + 3L` with
  L=8 fixed; see Phase 2 for derivation)
- Output to `synth/results_bivar_n${n_degree}/`

### 0.2 Run synthesis

```
vivado -mode batch -source synth/vivado_synth_bivar.tcl -tclargs 256
```

### 0.3 Record the result

Expected first data point (simulation-derived cycle count is 760):

| Design | N | LUT | FF | DSP | Fmax | Cycles | Time (μs) |
|---|---|---|---|---|---|---|---|
| bivar_ntt_top | 256 | TBD | TBD | TBD | TBD | 760 | TBD |

**Decision gate:** If DSP count < 32 (the R=8 baseline), the core claim holds.
If DSP count ≥ 32, investigate why and decide whether to continue.

---

## Phase 1 — Parameterise bivar_ntt_top for Variable N

**Goal:** Make the RTL accept any N = L × M where L=8 (fixed by the Fermat prime
structure) and M is a power of 2. This drives the entire scaling sweep.

### 1.1 Understand the fixed constraint

The shift-only property comes from q = 2^K+1 = 65537 with K=16. The row NTT
dimension is fixed at L = K/2 = 8 because:

- ω_L = ψ^{2M} must be a power of 2, which it is for any M that is a power of 2
  (since ord_q(2) = 32, and ψ^{2M} cycles through powers of 2 as M varies)
- L=8 gives ω_8 = ψ^{64} = 2^{12} (WEXP=12, shift-only)

M scales freely: for each target N, M = N/8. However, the column NTT root
ω_M = ψ_N^{16} depends on N because ψ_N (the primitive 2N-th root of unity) is
different for each N.

Since q = 65537 and 2 is a primitive 32nd root of unity mod q (ord_q(2) = 32),
ψ_N^{16} is a power of 2 only when N ≤ 256:

| N | M | Column NTT | ω_M = ψ_N^{16} | Power of 2? | WEXP |
|---|---|---|---|---|---|
| 64 | 8 | 8-pt | 3^{8192} = 2^{12} = 4096 | **YES** | 12 (reuses r2ntt_r8) |
| 128 | 16 | 16-pt | 3^{4096} = 2^{6} = 64 | **YES** | 6 (reuses r2ntt_r16) |
| 256 | 32 | 32-pt | 3^{2048} = 65529 = −8 = 2^{19} | **YES** | 19 (current r2ntt_r32) |
| 512 | 64 | 64-pt | 3^{1024} ≠ any power of 2 | **NO** | N/A — requires mod_mul |

**Critical constraint:** The shift-only property (pure barrel-shift butterflies,
no DSP multipliers in the butterfly core) holds only for N ≤ 256 with L=8 and
q=65537. For N=512 (M=64), the column NTT root is not a power of 2 and the column
butterfly must use a full modular multiplier. This changes the DSP count and timing
profile for N=512 significantly, making it a qualitatively different architecture
point rather than a smooth extrapolation.

### 1.2 Add missing column NTT cores

Currently only `r2ntt_r32` / `r2intt_r32` (M=32) exist. Need:

**For N=64 (M=8):** Column NTT is 8-pt — `r2ntt_r8` / `r2intt_r8` already exist.
Only need a new wrapper `bivar_ntt_subntt8_col.v` (or reuse `bivar_ntt_subntt8`
with M=8 parameter). No new butterfly cores needed.

**For N=128 (M=16):** Need `bivar_ntt_subntt16.v` wrapping `r2ntt_r16` /
`r2intt_r16` (both already exist with WEXP=6). No new butterfly cores needed.

**For N=512 (M=64):** The column root 3^{1024} is NOT a power of 2, so the
shift-only butterfly cannot be used. A full 64-pt NTT core using `mod_mul_fermat`
in the butterfly is required. This is a substantially more expensive design
(more DSPs, higher LUT, lower Fmax). Mark N=512 as a **stretch goal**; the
primary sweep is N=64, 128, 256.

### 1.3 Parameterise bivar_ntt_top

Modify `rtl/bivar_ntt_top.v` to accept N, L, M as parameters and select the
correct column NTT via a `generate` block or by instantiating a common
`bivar_ntt_subntt_col` module that is parameterised internally.

Key changes:
- `op_count` width: currently 8-bit (sufficient for M≤256); extend to 10-bit
  for M=128
- `TW_BITS = $clog2(2*N)`: already parametric
- `ntt32_in_pack` → `nttM_in_pack [M*WWIDTH-1:0]`: width must be parameter-driven
- FSM loop bounds: `op_count == M-1` and `op_count == L-1` are already
  parametric if M and L are parameters

### 1.4 Write and run simulation for each new N

For each new N, before any synthesis:

```
python sim/run_bivar_regression.py --random-count 50
```

Do not proceed to synthesis until random cases pass 256/256 (or N/N for that
parameter value).

---

## Phase 2 — Parameterise the ntt_top Synthesis Sweep

**Goal:** Collect baseline `ntt_top` data at N=64, 128, 512 to complete the
comparison. (N=256 already exists.)

The existing `vivado_synth_metrics.tcl` already supports arbitrary N via
`-generic "N=$n_degree"`. The cycle counts for new N values need to be added
to the `cycles_map` dict in the TCL, derived from simulation:

```
python sim/run_regression_matrix.py  # already exists, run for each new N
```

Expected cycle count formula for `ntt_top` R=8 (N=2^k):
- Each radix-8 stage processes N/8 butterfly groups in N/8 cycles (one BFU)
- Number of R=8 stages: floor(k/3), remainder handled by R=2/4 stages
- Total ≈ LOAD(N) + NTT_stages × (N/R) × R + PWM(N) + OUTPUT(N)

Collect by simulation, then hard-code into the TCL cycles_map for synthesis runs.

---

## Phase 3 — Full Synthesis Sweep

Run both designs across all target N values on the same device
(Virtex-7 xc7k160tfbg484-2) with the same clock constraint (3 ns target period).

### Target matrix

| N | ntt_top R=8 | bivar_ntt_top L=8 | Notes |
|---|---|---|---|
| 64 | Synthesise | Synthesise | bivar col = 8-pt, WEXP=12 |
| 128 | Synthesise | Synthesise | bivar col = 16-pt, WEXP=6 |
| 256 | **Done** | Synthesise (Phase 0) | bivar col = 32-pt, WEXP=19 |
| 512 | Synthesise | Stretch goal | bivar col needs mod_mul (not shift-only) |

N=512 bivar is a stretch goal because M=64 requires a generic NTT butterfly
core with `mod_mul_fermat` rather than shift-only butterflies. The column NTT
root 3^{1024} is not a power of 2 mod 65537. The primary claim is N=64/128/256.

### Automation

Extend `synth/vivado_run_all_metrics.ps1` with bivar entries:

```powershell
# Existing
vivado -mode batch -source synth_metrics.tcl -tclargs 8 64
vivado -mode batch -source synth_metrics.tcl -tclargs 8 128
vivado -mode batch -source synth_metrics.tcl -tclargs 8 256
vivado -mode batch -source synth_metrics.tcl -tclargs 8 512

# New bivar entries
vivado -mode batch -source synth_bivar_metrics.tcl -tclargs 64
vivado -mode batch -source synth_bivar_metrics.tcl -tclargs 128
vivado -mode batch -source synth_bivar_metrics.tcl -tclargs 256
vivado -mode batch -source synth_bivar_metrics.tcl -tclargs 512
```

---

## Phase 4 — Analysis and Paper Metrics

### 4.1 Derived cycle count formula for bivar_ntt_top

With L=8 fixed and M=N/8, the exact cycle count per polynomial multiplication:

```
Cycles(N) = LOAD + FWD_A + FWD_B + PWM + INV + OUTPUT
          = N + (2M + M + L) + (2M + M + L) + M + (L + M + M) + N
          = 2N + 7M + 3L
          = 2N + 7(N/8) + 24
          = (23/8)N + 24
```

| N | Predicted | Verified by sim |
|---|---|---|
| 64 | 208 | To verify |
| 128 | 392 | To verify |
| 256 | 760 | **760 ✓** |
| 512 | 1496 | To verify |
| 1024 | 2968 | To verify |

### 4.2 Key metrics to extract from each synthesis run

From the post-implementation utilization and timing reports:

| Metric | Source | Relevance |
|---|---|---|
| Slice LUTs | `02_impl_utilization.rpt` | Logic area (primary area metric) |
| DSP48E1 count | `02_impl_utilization.rpt` | Multiplier cost (the key claim) |
| Slice Registers (FF) | `02_impl_utilization.rpt` | Pipeline depth indicator |
| Block RAM tiles | `02_impl_utilization.rpt` | Memory cost |
| WNS (ns) | `02_impl_timing.rpt` | Timing slack → derive Fmax |
| Fmax (MHz) | Derived: 1000/(period − WNS) if WNS < 0 | Clock rate |
| Latency (μs) | Cycles / Fmax | End-to-end time |
| LUT × Cycles (LUT-ATP) | Computed | Area-time product |
| DSP × Cycles (DSP-ATP) | Computed | Multiplier-time product |

### 4.3 Analysis scripts to write

**`scripts/plot_scaling.py`**
- Reads all `metrics_raw.txt` files for both designs
- Plots LUT vs N, DSP vs N, Cycles vs N, Latency vs N, ATP vs N
- Marks the crossover point (N where bivar becomes better on each metric)
- Output: publication-quality PDF figures (matplotlib, no GUI required)

**`scripts/compare_table.py`**
- Generates a LaTeX-formatted comparison table
- Columns: design, N, LUT, DSP, Fmax, Cycles, Latency, LUT-ATP, DSP-ATP
- Rows sorted by N within each design group

**`scripts/op_count_analysis.py`** (theory section support)
- For both designs, count mod_mul operations as a function of N
- `ntt_top` R=8: multiplications per butterfly × butterfly count = f(N)
- `bivar_ntt_top`: only 4 × N/L multiplications (pre-twist, cross-twiddle, PWM,
  un-twist) = 4 × N/8 per cycle × number of mult-active cycles
- Show analytically why DSP count should differ

### 4.4 Expected story the data should tell

The hypothesis (which will be confirmed or refuted by measurement):

**DSP count:** `bivar_ntt_top` should use fewer DSPs because no mod_mul is needed
inside butterfly stages. `ntt_top` R=8 uses 32 DSPs (4 per butterfly unit × 8
butterflies); `bivar_ntt_top` uses only 8 × 1 DSP lanes (8 parallel mod_mul for
pre-twist/cross-twiddle/PWM/un-twist). As N scales, `ntt_top` may need to add
more butterfly units (and DSPs) while `bivar_ntt_top` keeps the same 8 lanes.

**LUT count:** Both designs use similar ROM-like structures for twiddle lookup.
`bivar_ntt_top` adds transpose memory and cross-twiddle stage. LUT cost may be
comparable or slightly higher for `bivar_ntt_top` due to the larger combinational
column NTT as M grows.

**Latency:** `bivar_ntt_top` has more cycles per multiplication (760 vs 389 at
N=256) because the 2D schedule has explicit transpose stages the 1D pipeline
hides. The question is whether a higher Fmax (from simpler combinational paths)
compensates.

**ATP crossover:** The paper's core claim. Identify the N at which
LUT·Cycles(bivar) < LUT·Cycles(ntt) or DSP·Cycles(bivar) < DSP·Cycles(ntt).

---

## Phase 5 — Paper Structure

### Suggested title

*"Hardware Cost Scaling of 2D Cooley-Tukey NTT Decomposition for Negacyclic
Polynomial Multiplication over Fermat Primes: An FPGA Implementation Study"*

### Sections

**1. Introduction**
- Motivation: polynomial multiplication for post-quantum crypto, FHE
- Problem: monolithic NTT hardware cost grows super-linearly with N
- Claim: 2D decomposition reduces DSP cost at the expense of cycle count;
  crossover point measured at N = ?
- Contributions listed explicitly

**2. Background**
- Negacyclic NTT and the twisted convolution
- 2D Cooley-Tukey decomposition (the math, one page)
- Shift-only butterfly property of Fermat primes (one paragraph)
- Related work: cite Kim et al. (2024) and distinguish our contribution
  (we measure hardware cost; they derive the algebra)

**3. Architecture**

3.1 Monolithic `ntt_top` (brief, already published implicitly)
3.2 Bivariate `bivar_ntt_top` — full description
- FSM pipeline diagram (14 states)
- Module hierarchy (`bivar_ntt_subntt8`, `bivar_ntt_subnttM`, `mod_mul_fermat`)
- Cycle count formula derivation
- Why all butterfly twiddles are shift-only (key architectural claim)

**4. Verification**
- Software model (`bivar_ntt_model.py`): 200 random checks at (N,K) = (16:8),
  (32:8), (256:16)
- RTL regression: 55 cases, all 256/256 (table of test cases and what each one
  tests — see MVNTT_README.md)
- Explain why the random cases are the true correctness gate

**5. Implementation and Results**
- Target device: Virtex-7 xc7k160tfbg484-2
- Synthesis methodology (Vivado 2022.2, target period, directives)
- Table: all metrics for both designs across N=64, 128, 256, 512
- Plots: LUT vs N, DSP vs N, Latency vs N, ATP vs N (from plot_scaling.py)
- Discussion: where and why the crossover occurs

**6. Discussion**
- Limitations: only one FPGA family; combinational sub-NTT may not map well to
  hard DSP chains at large M; N=1024 may hit routing limits
- Generalisation: the WEXP=19 shift-only property holds for all M with fixed L=8
  over q=65537, enabling the same architecture for any power-of-2 N up to ~16K

**7. Conclusion**
- Restate measured crossover N
- Claim: for large-N polynomial multipliers, 2D decomposition reduces multiplier
  cost at the cost of more pipeline stages; the break-even point is at N ≈ ?

### Target length: 8 pages (conference) or 12 pages (journal)

---

## Phase 6 — Stretch Goals (if time permits)

These strengthen the paper but are not required for submission:

| Goal | Effort | Impact |
|---|---|---|
| Synthesise on Artix-7 or UltraScale+ | Low (change device in TCL) | Shows generalisability |
| Power analysis (Vivado power report) | Low | Adds energy metric |
| Compare against one published implementation | Medium | Required for top venues |
| N=1024 data point | Medium (need R=128 core) | Extends the scaling curve |
| Pipelining mod_mul for higher Fmax | High | Changes architecture significantly |
| True Kim et al. ring embedding RTL | Very high | Separate paper contribution |

---

## Milestone Checklist

```
[ ] Phase 0: bivar_ntt_top synthesised at N=256             (1 Vivado run)
[ ] Phase 1a: r2ntt_r64 / r2intt_r64 implemented            (RTL, ~50 lines each)
[ ] Phase 1b: bivar_ntt_subntt64 wrapper                    (RTL, ~30 lines)
[ ] Phase 1c: bivar_ntt_top parameterised for N=64,128,512  (RTL changes)
[ ] Phase 1d: regression passes for N=64, 128, 512          (simulation)
[ ] Phase 2:  ntt_top synthesised at N=64, 128, 512         (3 Vivado runs)
[ ] Phase 3:  bivar_ntt_top synthesised at N=64, 128, 512   (3 Vivado runs)
[ ] Phase 4a: plot_scaling.py generates all figures         (Python script)
[ ] Phase 4b: compare_table.py generates LaTeX table        (Python script)
[ ] Phase 4c: crossover N identified                        (analysis)
[ ] Phase 5:  paper draft written                           (writing)
[ ] Phase 6:  one published comparison added (optional)     (literature search)
```

**Minimum viable paper path:** Phase 0 → Phase 2 → Phase 3 → Phase 4 → Phase 5.
Phases 1 and the N=512 data points are the critical path items that do not yet
exist in the repository.

---

## Notes on What NOT to Claim

- Do not claim the shift-only property as a contribution — Kim et al. (2024)
  already identified it. Cite them.
- Do not claim the 2D NTT algorithm as a contribution — Cooley-Tukey (1965)
  and its 2D generalisations are textbook.
- Do not claim lower latency than `ntt_top` — the 2D design is slower in
  cycles at N=256 (760 vs 389). This is a trade-off, not a regression; frame it
  honestly.
- The contribution is: **first measured, multi-N hardware comparison** of
  monolithic vs 2D NTT decomposition for negacyclic polynomial multiplication on
  FPGA, with explicit identification of the DSP-count crossover point.
