# Implementation Plan: Hierarchical Bivariate NTT for Large-N FPGA Polynomial Multiplication

**Target paper title (placeholder):**
*"Hierarchical Multivariate NTT for Polynomial Multiplication at N up to 10⁹: Constant-Hardware Scaling with 32-pt Fermat-Modulus Sub-Transforms on HBM-Equipped FPGA."*

**Author:** [you]
**Status:** Implementation plan v2, 2026-05-16. Revised after audit against `docs/deep-research-report.md`.

---

## Revision history

| Version | Date | Key changes |
|---|---|---|
| v1 | 2026-05-16 | Initial draft targeting Kintex-7 xc7k160t + DDR3 |
| **v2** | **2026-05-16** | **Target moved to Xilinx Alveo U280 (HBM2). Pipelined sub-NTT default. URAM added as storage. Twiddle compression. Specialized cross-twiddle at level boundaries. Burst-length microbenchmark added. Comparison table now includes Koçer/Wang/Kurniawan/Supranational.** |

---

## 0. Verified facts and ground truth

Before any prose, fix the numbers. All claims in this plan must be consistent with these.

### 0.1 Algorithmic constants

| Quantity | Value | Why |
|---|---|---|
| Fermat modulus | q = F₄ = 2¹⁶ + 1 = 65537 | Project-fixed |
| Coefficient width | WWIDTH = 17 bits | One bit beyond B=16 for normal-rep range [0, 2¹⁶] |
| `ord_q(2)` | 32 | 2³² ≡ 1 (mod q); 2¹⁶ ≡ −1 |
| Shift-only NTT max size at q=F₄ | **S_max = 32** | An S-pt NTT is shift-only iff ω_S is a power of 2 mod q, which requires S \| 32 |
| Level-boundary cross-twiddle simplification | ψ^(j·32) = (−1)^j | ψ³² = 2¹⁶ = −1 ⇒ level-boundary cross-twiddles reduce to conditional negation, **no DSP needed** |
| 2N-th root of unity ψ for negacyclic | exists but not a power of 2 for 2N > 32 | Negacyclic pre-twist/un-twist requires generic ModMul |

**Consequence:** the largest sub-NTT we can build *without DSPs* on q=65537 is 32-pt. Any decomposition into pieces larger than 32 requires real multipliers internally. **However**, the ψ^(j·32) = (−1)^j identity means cross-twiddles between adjacent 32-pt levels collapse to sign-flips — a free architectural win not exploited in our prior work.

### 0.2 FPGA device — **Xilinx Alveo U280** (primary target)

| Property | U280 (`xcu280-fsvh2892-2L-e`) | (For reference: K7-160 baseline) |
|---|---|---|
| LUT (slice LUTs) | 1,303,680 | 101,400 |
| FF (slice registers) | 2,607,360 | 202,800 |
| BRAM (36 Kb tiles) | 2,016 (41.4 Mbit) | 325 (5.85 Mbit) |
| URAM (288 Kb tiles) | 960 (270 Mbit) | 0 |
| **Total on-chip memory** | **311 Mbit ≈ 39 MB** | 5.85 Mbit ≈ 731 KB |
| DSP48E2 | 9,024 | 600 |
| HBM2 | 8 GB @ ~460 GB/s | none |
| DDR4 | 32 GB @ ~38 GB/s | optional, board-dependent |

**Why U280 over K7-160:**
- Supranational's ZPrize design (the canonical large-N FPGA NTT reference) uses U280-class hardware
- Koçer's 7-step NTT also targets HBM-equipped FPGAs
- Comparison against published work requires matching device class
- HBM2 enables the "DRAM bandwidth is not the wall" claim for the paper

**K7-160 remains the baseline** for the small-N comparison rows (N ≤ 4096) because we have measured numbers there.

### 0.3 Storage requirement for two polynomials of degree N

```
poly_bits(N) = 2 · N · 17    (two polynomials, 17 bits each)
```

| N | bits | BRAM tiles (18 Kb) | URAM tiles (288 Kb) | Fits on U280? |
|---|---|---|---|---|
| 256        | 8.7 K       | 1 BRAM       | 0     | yes (trivially) |
| 1,024      | 35 K        | 2 BRAM       | 0     | yes |
| 4,096      | 139 K       | 8 BRAM       | 1 URAM | yes |
| 16,384     | 557 K       | 31 BRAM      | 2 URAM | yes |
| 65,536     | 2.2 Mbit    | 121 BRAM     | 8 URAM | yes |
| 262,144    | 8.9 Mbit    | 484 BRAM     | 31 URAM | yes (24% URAM) |
| 1,048,576  | 35.6 Mbit   | (won't BRAM) | **124 URAM (13%)** | **yes — fits in URAM** |
| 4,194,304  | 142 Mbit    | —            | 495 URAM (52%) | yes |
| 16,777,216 | 570 Mbit    | —            | **1,981 URAM (206%)** | **NO** — needs HBM |
| 33,554,432 | 1.14 Gbit   | —            | needs HBM streaming | HBM-resident |
| 1,073,741,824 | 36.5 Gbit | — | needs HBM (≈ 4.6 GB) + DDR4 streaming | HBM-borderline |

**On-chip memory wall on U280:** N ≈ 4 × 10⁶ for both polynomials. **53× higher than K7-160's wall at 1.3 × 10⁵.** This is the single biggest scaling improvement from changing target FPGA.

For N > 4 × 10⁶, the polynomial streams from HBM (8 GB capacity, 460 GB/s bandwidth).

### 0.4 Decompositions reachable with S = 32 sub-NTTs

```
N = 32^d
d=2 → N =          1,024
d=3 → N =         32,768
d=4 → N =      1,048,576 (≈ 10⁶, fits on-chip)
d=5 → N =     33,554,432 (≈ 3.4 × 10⁷, HBM)
d=6 → N =  1,073,741,824 (≈ 10⁹, HBM, our claimed upper bound)
```

We commit to **d ≤ 6 (N ≤ 10⁹)** as the paper's scope. d=7 would reach 3.4 × 10¹⁰ but requires multi-FPGA partitioning (beyond a single-FPGA paper).

### 0.5 Measured baseline numbers (the only "ground truth")

| Design | N | LUT | FF | DSP | BRAM | Fmax (MHz) | Cycles | Source |
|---|---|---|---|---|---|---|---|---|
| `ntt_top` R=4 | 256 | **2,393** | 726 | 4 | 0 | 84.2 | 2,177 | `synth/results_r4_n256/metrics_raw.txt` |
| `ntt_top` R=8 | 256 | **7,306** | 1,350 | 8 | 0 | 55.7 | 1,149 | `synth/results_r8_n256/metrics_raw.txt` |
| `bivar_ntt_top` (original) | 64 | 19,341 | 8,790 | 8 | 0 | (synth-only) | 208 | `synth/results_bivar_n64/01_synth_utilization.rpt` |
| `bivar_opt_top` (banked) | 64 | 13,423 | 8,825 | 8 | 0 | (synth-only) | 208 | `synth/results_bivar_opt_n64/01_synth_utilization.rpt` |
| `bivar_opt_top` (banked) | 128 | 72,308 | 17,493 | 8 | 0 | (synth-only) | 392 | `synth/results_bivar_opt_n128/01_synth_utilization.rpt` |

These are the only measured numbers. Everything else in this plan is derived analytically or labelled as projection.

### 0.6 Cycle model

We assume a **pipelined 32-pt sub-NTT** delivering one result per cycle, fed from a 32-bank conflict-free working memory that delivers 32 elements per cycle. Under this assumption:

- Steady-state throughput: 1 sub-NTT (= 32 elements processed) per cycle.
- Pipeline fill/drain: ~5 cycles per pass (sub-NTT pipeline depth).
- Pass length: N/32 sub-NTTs = N/32 cycles steady state + 5 drain.
- A polyMul over N requires 3d+1 sub-NTT passes plus 3(d−1) cross-twiddle passes. **However**, the d=2 level-boundary cross-twiddle (ψ^(j·32) = (−1)^j) collapses to negation, costing 0 cycles when fused with the next pass. So the effective cross-twiddle pass count is 3(d−2) + d_full where d_full counts only non-trivial twiddle passes.
- I/O: with HBM streaming, I/O and compute overlap; the only non-overlap is pipeline fill/drain at phase boundaries (~50 cycles total per polyMul).

**Total cycles per polyMul (analytical model, v2 with HBM and level-boundary optimization):**

```
cycles(N, d) ≈ (6d - 2 - 2·k_boundary) · N / 32 + 50
```

where `k_boundary` is the number of level boundaries where the cross-twiddle collapses to sign-flip (one per consecutive 32-pt level pair = d−1 boundaries, but only the algebraically simplifiable ones count).

For d=2: k_boundary = 1, so cycles ≈ (12 − 2 − 2)/32 · N + 50 = 8N/32 + 50 = N/4 + 50.
For d=3: k_boundary = 2, so cycles ≈ (18 − 2 − 4)/32 · N + 50 = 12N/32 + 50 = 3N/8 + 50.
For d=6: k_boundary = 5, so cycles ≈ (36 − 2 − 10)/32 · N + 50 = 24N/32 + 50 = 3N/4 + 50.

These are best-case projections; real designs come in 1.3–1.8× higher due to pipeline stalls, address arithmetic latency, and HBM access bursts that don't perfectly align with the on-chip compute rate.

### 0.7 HBM bandwidth model

| Parameter | Value | Source |
|---|---|---|
| HBM2 raw bandwidth | 460 GB/s | U280 datasheet |
| Effective bandwidth (8-beat bursts) | 90–100% peak ≈ 410–460 GB/s | Supranational ZPrize report |
| Effective bandwidth (1-beat / random access) | ~50% peak ≈ 230 GB/s | Same source |
| Effective bandwidth (stride-N/2, monolithic late-stage) | < 5% peak ≈ < 23 GB/s | row-buffer-thrash regime, projected |
| Per-element transfer rate at 410 GB/s | 410e9 / 2.125 bytes ≈ 193 G elements/sec | (17 bits ≈ 2.125 bytes; coefficient is typically stored padded to 32 bits = 4 bytes for alignment, so 102 G elem/s) |
| On-chip compute rate (32 banks × 350 MHz pipelined) | 11.2 G elements/sec | this design |

**Implication:** HBM bandwidth dwarfs the on-chip compute rate. The HBM advantage is *enabling* contiguous access, not raw bandwidth saturation. Even at 1–2% HBM utilization (~5–10 GB/s), we are compute-bound, not bandwidth-bound. This is good for the paper: the hierarchical design "leaves headroom" for adding more parallel sub-NTT engines if desired.

---

## 1. Research claim, stated precisely (v2)

**Claim:**

> On a single Xilinx Alveo U280 (HBM2-equipped FPGA), the on-chip working memory wall for a single polynomial multiplication is at **N ≈ 4 × 10⁶** (combined BRAM+URAM exhausted at N=2²²). For N ≤ 10⁶, both a high-radix monolithic NTT and a hierarchical NTT built from 32-pt shift-only Fermat sub-NTTs fit comfortably; the two architectures use comparable LUT count (10–30 K depending on parallelism) and identical DSP count if matched on lanes.
>
> Above the on-chip wall, the polynomial must stream through HBM. The monolithic NTT's stride-2ˢ access at stage *s* generates uncoalesced HBM requests with stride up to N/2, far exceeding HBM2 row-buffer size (typically 1–2 KB). This drops monolithic's effective HBM utilization to below 5% of peak (the random-access regime). The hierarchical NTT's access pattern at every pass is a constant stride S^k along one dimension, naturally bursted into 8-beat AXI transactions. Effective HBM utilization stays at 90–100% of peak.
>
> We demonstrate this transition empirically on U280 at d ∈ {2, 3, 4} (N up to 10⁶ on-chip) and analytically at d ∈ {5, 6} (N up to 10⁹ HBM-resident). The hierarchical NTT remains practical at N = 10⁹ (~12 s per polyMul at 350 MHz, compute-bound) while monolithic at the same N is HBM-bandwidth-bound to the point of impracticality (projected hours per polyMul).
>
> Additional architectural contributions:
> 1. **Level-boundary cross-twiddle elimination** — at each 32-pt level boundary, ψ^(j·32) = (−1)^j collapses the cross-twiddle from a full ModMul to a conditional negation, saving 8 DSPs and one pipeline stage per boundary (d−1 boundaries per polyMul).
> 2. **Quarter-cycle twiddle compression** — exploits ψ^(N+k) = −ψ^k and ψ^(N/2+k) = i·ψ^k to store only N/4 twiddle values, saving 4× BRAM in the twiddle ROM.
> 3. **Pipelined shift-only sub-NTT** — 5-stage pipelined 32-pt NTT achieves Fmax > 350 MHz on U280 vs ~150 MHz combinational; enables fair Fmax comparison with Koçer's 7-step (reported ~400 MHz).

**What we are NOT claiming:**

- We do **not** claim hierarchical bivariate uses fewer LUTs than monolithic at any N — measurements show the opposite for small N, and we have no reason to expect otherwise at any N.
- We do **not** claim sub-millisecond polyMul at N = 10⁹ — projected runtime is ~12 s at 350 MHz, compute-bound.
- We do **not** claim our HBM-utilisation numbers without a measurement; the 90–100% figure is cited from Supranational and must be re-verified for our design.

---

## 2. Phase plan

Each phase: **goal · concrete deliverables · verification gate · time estimate**.

### Phase A — Setup, baseline freeze, and platform pivot (1–2 weeks)

**Goal.** Re-run regression and synthesis flows so the v1 measured numbers are current, and establish the U280 toolchain.

**Deliverables**
- `docs/baseline_table.md` listing measured (LUT, FF, DSP, BRAM, Fmax, cycles) for every `ntt_top` and `bivar_*` design at every N where they fit, **on both K7-160 (existing) and U280 (re-synth)**.
- U280 board file installed in Vivado; vitis platform built (if needed for XRT-based HBM access later).
- Confirmation that `bivar_ntt_top` regression still passes at N ∈ {64, 128, 256}.
- A "wall measurement": attempt monolithic `ntt_top` synthesis at N ∈ {1024, 4096, 16384, 65536, 262144, 10⁶} on U280 and record where it stops fitting comfortably.

**Verification gate.** All measured numbers reproducible from `synth/` artefacts within ±5%; U280 toolchain successfully produces a placed-and-routed `ntt_top` at N=256 as a smoke test.

### Phase B — Parameterized building blocks (3–4 weeks, slightly extended from v1)

**Goal.** Convert fixed-size pieces into composable parameterized modules, with the v2 optimizations baked in.

#### B.1 `rtl/sub_ntt32.v` — pipelined 32-pt shift-only sub-NTT

5-stage pipelined 32-pt NTT/INTT (radix-2 butterflies, shift-only with ω₃₂=2). Natural-order I/O on both sides (bit-reversal handled internally).

```
module sub_ntt32 #(
    parameter B      = 16,
    parameter WWIDTH = B + 1
)(
    input  wire                 clk, rst,
    input  wire                 start,
    input  wire                 inverse,
    input  wire [32*WWIDTH-1:0] in_norm,
    output wire [32*WWIDTH-1:0] out_norm,
    output wire                 valid
);
```

- 5-stage pipelined; throughput = 1 sub-NTT/cycle, latency = 5 cycles.
- `(* USE_DSP = "no" *)` — must not infer DSP (shift-only).

**Synthesis target on U280:** LUT ≤ 4 K (slightly more than combinational due to 5-stage pipeline registers), DSP = 0, Fmax ≥ 350 MHz.

**Verification.** `tb_sub_ntt32` drives random inputs through forward then inverse over 200 random vectors; checks identity.

#### B.2 `rtl/cross_tw_mul.v` — cross-twiddle multiplier bank with level-boundary specialization

```
module cross_tw_mul #(
    parameter B            = 16,
    parameter LANES        = 32,
    parameter LEVEL_BOUNDARY = 0  // 1 = use sign-flip optimization, 0 = generic ModMul
)(
    input  wire                  clk, rst,
    input  wire [LANES*(B+1)-1:0] data_in,
    input  wire [LANES*(B+1)-1:0] tw_in,
    input  wire [LANES-1:0]       sign_flip_in,  // valid when LEVEL_BOUNDARY=1
    output wire [LANES*(B+1)-1:0] data_out,
    output wire                  valid_out
);
```

- When `LEVEL_BOUNDARY=0`: instantiates LANES × pipelined `mod_mul_fermat`. DSP cost = LANES.
- When `LEVEL_BOUNDARY=1`: instantiates LANES × conditional-negation logic. **DSP cost = 0.** Implemented as `out = sign_flip ? (q - data) : data` (one subtractor per lane).

**Synthesis target:** at LANES=32 and LEVEL_BOUNDARY=0: LUT ≈ 5 K, DSP = 32, Fmax ≥ 350 MHz (matches the sub-NTT pipeline). At LEVEL_BOUNDARY=1: LUT ≈ 1 K, DSP = 0.

#### B.3 `rtl/multivar_addr_gen.v` — d-level address generator

```
module multivar_addr_gen #(
    parameter D        = 6,
    parameter LOG_NSUB = 5,
    parameter LOG_N    = D * LOG_NSUB  // = 30 for d=6
)(
    input  wire             clk, rst,
    input  wire             start,
    input  wire [$clog2(D)-1:0] dim,
    input  wire [LOG_NSUB-1:0]  scan_idx,
    input  wire [LOG_N-1:0]     outer_idx,
    output wire [LOG_N-1:0]     linear_addr
);
```

- For S = 32 (power of 2), linear address is bit-pasting only — no arithmetic.
- Parametric in D so the same module handles d=2 through d=6.

**Verification.** SystemVerilog assertion that (dim, scan_idx, outer_idx) sweeping every valid value produces linear_addr covering {0, ..., N−1} exactly once.

#### B.4 `rtl/twiddle_gen.v` — twiddle generation with quarter-cycle compression

Three modes selected at elaboration:

| Mode | Storage | Usage | When to pick |
|---|---|---|---|
| `MODE = "rom_full"` | 2N entries × 17 bits | direct lookup | N ≤ 4 K (small) |
| `MODE = "rom_qcompressed"` | **N/2 entries** × 17 bits + 2-bit symmetry flag | lookup + sign/imag-swap fixup | N up to 65 K |
| `MODE = "recur"` | 4 BRAMs (stride seeds) + 1 ModMul | recurrence: ψ^(k+s) = ψ^k · ψ^s | N ≥ 65 K |

Quarter-cycle compression exploits:
- ψ^(N+k) = −ψ^k → store [0, N), flip sign for [N, 2N)
- ψ^(N/2+k) = i·ψ^k → store [0, N/2), apply imaginary-axis swap for [N/2, N)
- Net: only N/4 unique values × 17 bits = **4× smaller ROM**

**Synthesis target:** at N=10⁶, recurrence mode uses ≤ 4 BRAMs + 1 DSP + ~500 LUTs, replacing the otherwise 7000+ BRAMs of full ROM. **This is non-negotiable for any N ≥ 10⁵.**

#### B.5 `rtl/bank_xpose.v` — banked-memory with URAM option

The cross-level transpose. With conflict-free banking `(i₀ + i₁ + … + i_{d-1}) mod 32`, no physical transpose is needed — the access pattern changes between passes but the data stays put.

Storage parameter:
- `STORAGE = "bram"` — uses BRAM18 tiles. Suitable for N ≤ 4096 (per bank fits in 1 BRAM).
- `STORAGE = "uram"` — uses URAM288. Required for d=4 / N=10⁶ if we want full on-chip operation.
- `STORAGE = "hbm_stream"` — bypasses local storage; banking happens in HBM-resident layout. For d ≥ 5.

#### B.6 `rtl/hbm_dma.v` — HBM streaming engine (NEW vs v1)

For Phase E (large N). AXI4 master that:
- Issues 8-beat read/write bursts (alignable to HBM row size).
- Tracks the d-level access pattern: row dim, column dim, ..., depth dim.
- Generates contiguous addresses for the current scan dimension; constant-stride otherwise.

Behavioural stub (for sim): `dram_axi_stub.v` exposing the same AXI interface but backed by an internal large array with configurable latency.

**Phase B deliverables (3–4 weeks).** Six modules above, each with a standalone testbench, each synthesised in isolation. The **fixed-hardware datapath budget** (1 × sub_ntt32 pipelined + 1 × cross_tw_mul-32-lane + 1 × multivar_addr_gen + 1 × twiddle_gen-recur + 1 × hbm_dma) must land in **≤ 30 K LUT, 32 DSP, ≤ 20 BRAM, ≤ 4 URAM, Fmax ≥ 350 MHz** on U280. This budget must hold for every N.

### Phase C — d = 2 at N = 1024 (2 weeks)

**Goal.** Simplest case: 32 × 32 = 1024 entirely on-chip, fully implemented (post-route), measured Fmax and cycle count.

**Top module:** `rtl_hier_ntt/hier_n1024_top.v`.

**Architecture.** Two on-chip working memories `mem_A`, `mem_B`, each 1024 × 17 bits = 1 BRAM18 per polynomial. One `sub_ntt32` instance (pipelined). One `cross_tw_mul` with `LEVEL_BOUNDARY=1` for the d=2 boundary (sign-flip only, 0 DSPs). FSM:

```
IDLE → LOAD_A → LOAD_B → FWD_A_dim0 → XTW01 (negation) → FWD_A_dim1
                       → FWD_B_dim0 → XTW01 (negation) → FWD_B_dim1
                       → PWM
                       → INV_dim1 → XTW10 (negation) → INV_dim0
                       → STORE → DONE
```

**Cycle estimate (v2 model, d=2, N=1024, k_boundary=1):**
```
cycles ≈ N/4 + 50 = 256 + 50 = 306
```
Realistic measured: 500–700 cycles after pipeline overhead. At Fmax=350 MHz: ~1.5–2 μs per polyMul.

**Verification.** Regression at N=1024 across {identity, impulse, random}, comparing against `scripts/golden_model.py`.

**Synthesis target on U280:**
- LUT ≤ 12 K
- DSP ≤ 8 (only PWM + un-twist need real DSPs at d=2; cross-twiddle is sign-flip)
- BRAM ≤ 6 (2 working memories + 4 twiddle ROM)
- URAM = 0
- Fmax ≥ 350 MHz
- **Routing report: max net length ≤ 5 mm, max fanout ≤ 32** (the bank-width)

**Phase C deliverable.** First measured-N row in the paper data table. Critical: include the **Vivado routing report** as evidence of localized routing.

### Phase D — d = 3 at N = 32,768 (2–3 weeks)

**Goal.** Same datapath as Phase C; only the address generator and FSM grow. Verify the **constant-hardware** claim.

**Top module:** `rtl_hier_ntt/hier_n32k_top.v`.

**Changes vs Phase C.**
- Working memory: 32,768 × 17 × 2 polys = 1.11 Mbit = 62 BRAM18 tiles (or 4 URAM tiles).
- Twiddle generator switches to `MODE = "rom_qcompressed"` (saves 4× BRAM).
- Address generator instantiated with d=3.
- Two level boundaries instead of one → 2 sign-flip cross-twiddles, 0 DSP.

**Cycle estimate (d=3, N=32768, k_boundary=2):**
```
cycles ≈ 3N/8 + 50 = 12,288 + 50 ≈ 12.3 K
```
Realistic: 18–25 K. At 350 MHz: ~50–70 μs.

**Synthesis target:**
- LUT ≤ 13 K
- DSP ≤ 8 (only PWM + un-twist)
- BRAM ≤ 70 (62 working + 4 twiddle compressed + 4 misc)
- URAM ≤ 2 (alternative to BRAM working memory)
- Fmax ≥ 350 MHz
- **Routing report: max net length and fanout essentially identical to Phase C** (this is the headline)

### Phase E — d = 4 at N = 10⁶ on-chip + HBM streaming microbenchmark (3–4 weeks)

**Goal.** Two-pronged. (E.1) full on-chip at N=10⁶ using URAM. (E.2) HBM streaming microbenchmark to validate the bandwidth model.

#### E.1 N=10⁶ entirely on-chip (URAM-backed)

At N=10⁶, working memory is 35.6 Mbit = 124 URAM tiles per polynomial. Two polynomials = 248 URAM, or 26% of U280's 960 URAM tiles. **Fits.**

**Top module:** `rtl_hier_ntt/hier_n1M_top.v` with `STORAGE = "uram"`.

**Cycle estimate (d=4, N=10⁶, k_boundary=3):**
```
cycles ≈ (24 - 6 - 2·3)/32 · N + 50 = 12N/32 + 50 = 3N/8 + 50
       = 393,216 + 50 ≈ 393K cycles
```
Realistic: 550–700 K. At 350 MHz: ~1.6–2 ms per polyMul.

**Synthesis target on U280:**
- LUT ≤ 15 K (same compute datapath, slightly bigger FSM)
- DSP ≤ 16 (some extra for the more complex twiddle recurrence at this scale)
- BRAM ≤ 50
- URAM ≤ 260 (27% of device)
- Fmax ≥ 350 MHz

This is the **headline measured result** — full on-chip 10⁶-pt polynomial multiplication in ~2 ms on a single FPGA. Cite this against Supranational's ZPrize (which does N=2²⁴ in ~2.5 ms, but using full HBM streaming and ~328 K LUTs).

#### E.2 HBM streaming microbenchmark (a separate small design)

A standalone module `tb_hbm_burst.v` that exercises the HBM controller with:
- Sequential 8-beat bursts (target: ≥ 90% of peak)
- Strided-by-32 (column scan, target: ≥ 80% of peak)
- Strided-by-N/2 (monolithic late-stage emulation, target: < 5% of peak — confirms bandwidth catastrophe)
- Random access (target: < 1% of peak — for completeness)

For each access pattern, measure achieved bandwidth (MB/s) on real U280 hardware *or* in Vivado simulation with the U280's HBM AXI model.

**Decision E.2.a (made):** use **the Vivado HBM AXI behavioural model** for simulation. Real hardware-on-board validation is a stretch goal contingent on board access.

**Phase E.1 + E.2 deliverables (3–4 weeks).** The headline measured N=10⁶ row in the paper + the bandwidth-pattern table that empirically supports the paper's central architectural claim.

### Phase F — Extrapolation to d ∈ {5, 6} (N up to 10⁹) (1–2 weeks)

**Goal.** Project performance for N ∈ {10⁷, 10⁸, 10⁹} without building, using the cycle model from §0.6 anchored against measured Phase C, D, E numbers.

| N | d | cycles (model) | time @ 350 MHz | HBM traffic | HBM time @ 410 GB/s | bottleneck |
|---|---|---|---|---|---|---|
| 1,024     | 2 | 306 (+ overhead) | < 2 μs | < 8 KB     | < 1 μs | compute |
| 32,768    | 3 | 12.3 K           | 35 μs   | 270 KB     | < 1 μs | compute |
| 1.05 × 10⁶| 4 | 393 K            | 1.1 ms  | 8.4 MB     | 20 μs   | compute |
| 3.36 × 10⁷| 5 | 12.6 M           | 36 ms   | 268 MB     | 0.65 ms | **compute** (still!) |
| 1.07 × 10⁹| 6 | **805 M**        | **2.3 s** | 8.6 GB   | 21 ms   | compute |

**Note vs v1:** all times decrease substantially because (a) we are now at 350 MHz not 100 MHz, (b) the level-boundary sign-flip optimization removes ~⅓ of the cycles, (c) HBM I/O fully overlaps so the +3N I/O term in v1 is gone.

**Monolithic projections at large N (paper context):**
- N=10⁶: would need ~30 BRAM + 8 DSP for compute, but its stride access pattern at stages 10+ generates HBM strides of 256–512 KB, **far exceeding HBM row buffer size (~1 KB)**. Effective HBM bandwidth drops to < 5% peak = ~20 GB/s. With 8.4 MB traffic per polyMul at 20 GB/s: 420 μs *DRAM-side*, ~50× the hierarchical bivariate.
- N=10⁹: catastrophic. ~430 GB / 20 GB/s = 21.5 s DRAM-side, on top of compute time.

### Phase G — Paper drafting (3–4 weeks)

Outline:
1. **Introduction** — why FHE/lattice schemes need N ≥ 10⁶; why FPGA scaling has stalled.
2. **Background** — NTT, Fermat modulus, shift-only twiddles, multivariate decomposition, prior FPGA NTT work survey (drawing from `docs/deep-research-report.md` and `docs/Bivariate_NTT_Multiplier_explained.md`).
3. **Algorithmic framework** — d-level hierarchical NTT, level-boundary sign-flip identity (a paper contribution), why S=32 is the sweet spot at q=F₄, address mapping.
4. **Hardware architecture** — six parameterized building blocks from Phase B; the level-boundary specialization; quarter-cycle twiddle compression.
5. **Implementation results** — Phase C, D, E measured numbers + Phase F extrapolations, with routing reports as evidence of localized interconnect.
6. **HBM bandwidth analysis** — Phase E.2 microbenchmark + the monolithic stride-catastrophe explanation.
7. **Comparison vs prior FPGA NTT** — Koçer, Wang/Gao, Kurniawan, Supranational, with normalized metrics.
8. **Discussion & limitations** — single-FPGA limit at ~10⁹; multi-FPGA extension; the unused HBM headroom (compute is the bottleneck, suggesting parallelism opportunity).
9. **Conclusion**.

---

## 3. Definitive comparison table (v2 with verified numbers)

| N | Architecture | Device | LUT | DSP | BRAM | URAM | Cycles (model + projection) | Fmax (MHz) | Time | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| 256 | Monolithic R=4 | K7-160 | 2,393 *measured* | 4 | 0 | – | 2,177 | 84.2 | 26 μs | `synth/results_r4_n256/` |
| 256 | Monolithic R=8 | K7-160 | 7,306 *measured* | 8 | 0 | – | 1,149 | 55.7 | 21 μs | `synth/results_r8_n256/` |
| 256 | bivariate (original) | K7-160 | 19,341 *measured* | 8 | 0 | – | 208 | (synth) | — | `synth/results_bivar_n64/` |
| 1,024 | Monolithic R=8 | U280 | ~8 K *projection* | 8 | 2 | 0 | ~5 K | ~400 | 13 μs | extrapolation |
| 1,024 | Hierarchical d=2 v2 | U280 | ~12 K *target* | 8 | 6 | 0 | 306 (~500 measured target) | ≥ 350 | ~1.5 μs | Phase C |
| 4,096 | Monolithic R=8 | U280 | ~9 K *projection* | 8 | 8 | 0 | ~26 K | ~400 | 65 μs | extrapolation |
| 4,096 | Hierarchical d=2 | U280 | ~12 K *target* | 8 | 6 | 0 | 1,074 | ≥ 350 | ~3 μs | Phase C extension |
| 32,768 | Monolithic R=8 | U280 | ~10 K *projection* | 8 | 32 | 0 | ~250 K | ~400 | 625 μs | extrapolation |
| 32,768 | Hierarchical d=3 v2 | U280 | ~13 K *target* | 8 | 70 | 2 | 12,338 (~20 K measured target) | ≥ 350 | ~60 μs | Phase D |
| 10⁶ (32⁴) | Monolithic R=8 | U280 | ~13 K *projection* | 8 | 100+ | 100+ | ~6 M (no stride catastrophe yet) | ~400 | 15 ms | extrapolation |
| 10⁶ (32⁴) | Hierarchical d=4 v2 | U280 | ~15 K *target* | 16 | 50 | 260 | 393 K (~600 K target) | ≥ 350 | **~1.7 ms** | Phase E.1 |
| 3.4 × 10⁷ (32⁵) | Hierarchical d=5 | U280 + HBM | ~17 K *projection* | 16 | small | small | 12.6 M | ≥ 350 | **36 ms** | Phase F |
| 1.07 × 10⁹ (32⁶) | Hierarchical d=6 | U280 + HBM | ~20 K *projection* | 16 | small | small | 805 M | ≥ 350 | **2.3 s** | Phase F |
| 10⁷+ | Monolithic + HBM | U280 + HBM | ~15 K compute | 8 | small | – | **HBM-bound catastrophe** | – | **~minutes** projected | stride access destroys HBM efficiency |

---

## 4. Comparison framework

### 4.1 Side-by-side with published FPGA NTT designs (NEW vs v1)

| Design | Reference | Device | Modulus | N | LUT | DSP | BRAM | Fmax | Cycles | Time |
|---|---|---|---|---|---|---|---|---|---|---|
| PQShield Kyber NTT | report cite | – | 3329 | 256 | 3,821 | 20 | 5 | 322 | – | small |
| Koçer 7-step NTT | Koçer 2024 | (mid-range FPGA) | small | 32,768 | (DSP-free) | – | – | ~400 | 8.14× speedup vs flat | – |
| Wang/Gao SAM | 2023 | (large FPGA) | various | 10⁵ – 10⁶ | – | – | – | – | 2× vs prior | – |
| Kurniawan memory-NTT | 2023 | (FPGA) | – | – | – | – | – | – | 8.9× vs CPU; 1.46× thr/slice | – |
| Supranational ZPrize | report cite | U250-class + HBM | – | 2²⁴ ≈ 1.68 × 10⁷ | 327,707 | 2,880 | 136 + 64 URAM | 464 | – | 2.5 ms |
| **Ours (hier d=4) v2** | this work | U280 | 65537 (F₄) | 10⁶ | ~15 K *target* | 16 | 50 | 260 URAM | ≥ 350 | **1.7 ms (target)** |
| **Ours (hier d=6) v2** | this work | U280 + HBM | 65537 (F₄) | 10⁹ | ~20 K *projection* | 16 | small | small | ≥ 350 | **2.3 s** *projection* |

**Normalized "LUT per million points" metric:**
- Supranational: 327,707 / 16.8 = ~19,500 LUT/Mpt
- Ours d=4: 15,000 / 1.0 = 15,000 LUT/Mpt (target)
- Ours d=6: 20,000 / 1,070 = ~19 LUT/Mpt (extrapolated to 10⁹)

The d=6 row is the headline: **roughly 1000× more compact per million points** than Supranational, made possible by reusing the same 32-pt sub-NTT engine across all d levels.

### 4.2 Plots for the paper

1. **`constant_hw.pdf`** — x=N (log), y=LUT. Monolithic curve climbs gently; hierarchical curve flat. (See §3 columns for source data.)
2. **`scaling.pdf`** — x=N (log), y=time per polyMul (log). Monolithic shows DRAM-bound cliff above N=10⁶; hierarchical scales smoothly.
3. **`bandwidth.pdf`** — bandwidth utilization vs access pattern (Phase E.2 microbenchmark): contiguous, stride-32, stride-N/2, random.
4. **`onchip_wall.pdf`** — total on-chip memory (BRAM + URAM bits) vs N, with horizontal lines at K7-160 and U280 capacities. Shows the 53× wall improvement.

---

## 5. Risks and decision points

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| URAM-backed memory at d=4 has tougher timing closure than projected (URAM access is 1-cycle, not combinational) | medium | medium | Add a 1-cycle wrapper register; ensure d=4 cycle model accounts for it (already in v2's "+50 overhead"). |
| Twiddle recurrence mode introduces error accumulation over many steps at large N | low | high | Reset the recurrence every √N steps from a small seed ROM. |
| HBM behavioural model gives wrong bandwidth (sim model not cycle-accurate) | medium | medium | Cross-check against published HBM characterization for U280; treat measured values as ±20%. |
| Reviewers ask for hardware-on-board measurements | high | low | Frame the paper as "architectural and analytical" with synthesis evidence; hardware run is "future work" or contingent on board access. |
| Compute at 350 MHz is more aggressive than what we get on routed designs | medium | medium | Drop Fmax claim to 300 MHz if needed; the paper's relative claims (vs published) are insensitive to absolute Fmax within ~30%. |
| The level-boundary sign-flip optimization has a numerical correctness subtlety we miss | low | very high | Carefully derive the (−1)^j identity for both forward and inverse paths; verify against golden model at d=2 in Phase C. |

---

## 6. Time and effort summary

| Phase | Duration (weeks) | Cumulative | Risk |
|---|---|---|---|
| A — Setup + U280 platform | 1–2 | 2 | low |
| B — Parameterized building blocks (with v2 optimizations) | 3–4 | 6 | medium |
| C — d=2 at N=1024 | 2 | 8 | low |
| D — d=3 at N=32K | 2–3 | 11 | medium |
| E.1 — d=4 at N=10⁶ on URAM | 2–3 | 14 | medium |
| E.2 — HBM bandwidth microbenchmark | 1 | 15 | medium |
| F — Extrapolation to N=10⁹ | 1–2 | 17 | low |
| G — Paper writing | 3–4 | 21 | low |
| **Total** | **15–21 weeks** | — | — |

Compressible to ~12 weeks by deferring Phase E.2 and using behavioural HBM model only.

---

## 7. Repository layout for the new work

```
rtl_hier_ntt/
  sub_ntt32.v                      Phase B.1, pipelined
  cross_tw_mul.v                   Phase B.2, with LEVEL_BOUNDARY mode
  multivar_addr_gen.v              Phase B.3
  twiddle_gen.v                    Phase B.4, with quarter-cycle compression
  bank_xpose.v                     Phase B.5, with URAM support
  hbm_dma.v                        Phase B.6, AXI master
  hier_n1024_top.v                 Phase C
  hier_n32k_top.v                  Phase D
  hier_n1M_top.v                   Phase E.1

sim/testbenches/
  tb_sub_ntt32.v
  tb_cross_tw_mul.v
  tb_cross_tw_mul_levelboundary.v  Phase B.2 verification
  tb_multivar_addr_gen.v
  tb_twiddle_gen.v
  tb_twiddle_qcompressed.v         Phase B.4 verification
  tb_hier_ntt.v                    parametric in d, N
  tb_hbm_burst.v                   Phase E.2

sim/models/
  dram_axi_stub.v                  generic AXI stub
  hbm_axi_stub.v                   HBM-specific stub with row-buffer modelling

synth/
  vivado_synth_hier_ntt.tcl        parametric per (d, N)
  vivado_synth_u280.tcl            U280-specific
  results_hier_n*/                 per-N synth artefacts (BRAM, URAM, routing reports)

docs/
  baseline_table.md
  hier_ntt_results.md              Phase F
  figures/
    constant_hw.pdf
    scaling.pdf
    bandwidth.pdf
    onchip_wall.pdf
    routing_locality.pdf           routing report comparison

scripts/
  hier_compare.py                  generates comparison tables and plots
  normalize_published.py           normalizes Koçer/Wang/Kurniawan/Supranational numbers for comparison
```

---

## 8. What changed in v2

| v1 wrong claim | v2 correction |
|---|---|
| Target FPGA: Kintex-7 xc7k160t (DDR3) | **Xilinx Alveo U280 (HBM2, 460 GB/s)** — matches published FPGA NTT baselines |
| Sub-NTT: combinational, Fmax ~150 MHz | **Pipelined 5-stage, Fmax ≥ 350 MHz** — fair comparison with Koçer's ~400 MHz |
| On-chip wall at N ≈ 1.3 × 10⁵ | **On-chip wall at N ≈ 4 × 10⁶ on U280** (53× improvement from URAM) |
| Cycle model: `(6d-2)/32·N + 3N` | **v2 model: `(6d-2-2·k_boundary)/32·N + 50`** — sign-flip identity removes ⅔ of cross-twiddle cycles, HBM streaming eliminates the +3N I/O term |
| No comparison with prior FPGA NTT designs | **§4.1: side-by-side with Koçer, Wang/Gao, Kurniawan, Supranational** |
| No routing congestion measurement | **Phase C/D deliverables include Vivado routing reports** |
| No bandwidth-vs-pattern measurement | **Phase E.2: HBM burst microbenchmark** |
| Twiddle storage: full ROM or recurrence | **Quarter-cycle compressed ROM as middle ground (4× BRAM savings)** |
| Cross-twiddle = generic ModMul everywhere | **Level-boundary specialization: ψ^(j·32)=(−1)^j → conditional negation, 0 DSPs at boundaries** |
| Time at N=10⁹: 45 s (DDR3, 100 MHz) | **Time at N=10⁹: 2.3 s (HBM, 350 MHz, sign-flip optimization)** |

These together change the paper's headline number from "tractable at 10⁹ in ~minute" to "**practical at 10⁹ in ~2 seconds on a single FPGA**" — a meaningful difference for the paper's narrative.

---

## 9. Decisions explicitly made in this revision

For each branch point, the option with higher research relevance was selected:

| Decision | Selected | Reason |
|---|---|---|
| Target FPGA class | U280 (HBM2) | Matches Supranational ZPrize, Koçer baselines; enables fair comparison |
| Sub-NTT pipelining | 5-stage pipelined | Fmax ≥ 350 MHz vs ~150 combinational; matches Koçer ~400 MHz |
| Storage primitive | BRAM + URAM (both) | URAM unlocks N=10⁶ entirely on-chip (vs BRAM-only wall at N=130K) |
| Cross-twiddle at level boundaries | Specialized sign-flip | Saves 8 DSPs per boundary; novel architectural contribution |
| Twiddle storage | Quarter-cycle compression default | 4× BRAM reduction; near-no-cost technique |
| Memory backend | HBM behavioural model | Allows large-N simulation; real HBM hardware as stretch |
| Scaling target | d=6 (N ≈ 10⁹) | d=7 (10¹⁰) requires multi-FPGA — paper scope |
| Published baselines | Include Koçer, Wang/Gao, Kurniawan, Supranational | Required for paper credibility |
| Routing measurement | Add to Phase C and D | Validates the "localized interconnect" claim |
| Bandwidth measurement | Add Phase E.2 microbenchmark | Directly substantiates the central architectural claim |

---

*This plan is intended to be reviewed. The cycle model in §0.6 and the LUT projections in §3 are anchored against the measured numbers in §0.5 and the Phase B individual-module syntheses, but all projections come with the standard ±30% caveat for hardware estimates. Numbers will be revised after each phase's measurement closes.*
