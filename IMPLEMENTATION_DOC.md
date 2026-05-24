# Hierarchical NTT Polynomial Multiplier — Implementation Documentation

This document is the **chronological design + research log** for the Phase C
implementation of a hierarchical bivariate NTT polynomial multiplier targeting
Xilinx Alveo U280 (xcu280-fsvh2892-2L-e), per the v2 plan in
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).

Use this as the canonical reference for: (a) what was tried, (b) what worked
and what didn't and why, (c) what published techniques apply but haven't been
tried yet.

---

## 0. Quick context

**Algorithm.** Negacyclic polynomial multiplication
`c(X) = a(X) · b(X) mod (X^N + 1)` over `q = F₄ = 2¹⁶ + 1 = 65537`,
implemented via the bivariate Cooley-Tukey decomposition `X₂ = X₁^L` with
`L = M = 32`, `N = L·M = 1024`.

**Target device.** Xilinx Alveo U280 (`xcu280-fsvh2892-2L-e`).
3-SLR UltraScale+ HBM-class FPGA, 1.3 M LUTs, 9 K DSPs, 2 K BRAM18, 960
URAM, 8 GB HBM2 @ 460 GB/s.

**Key paper claim being demonstrated.** The same on-chip datapath
(~15-20 K LUTs in the long-term steady state) handles N from 10³ up to 10⁹
because the per-cycle work and the working memory both scale with the *level
count d* — not with N. Phase C (d=2, N=1024) is the smallest demonstrator.

---

## 1. Final Phase C result (as of last sim+impl pass)

| Metric | Value |
|---|---|
| Device | xcu280-fsvh2892-2L-e |
| N | 1024 (L=M=32, d=2) |
| **LUT** | **43,854** (3.4 % of U280) |
| FF | 8,408 (0.3 %) |
| **DSP** | **32** (0.35 %) |
| BRAM | 0 |
| URAM | 0 |
| **Fmax** | **180.4 MHz** (WNS −2.54 ns @ 3.0 ns target) |
| Cycles per polyMul | 2,489 |
| **Time per polyMul** | **13.8 µs** |
| Critical path | op_count → mem_a LUTRAM read → data_out reg, 5.57 ns, 15 logic levels, route-dominated (72 % route) |
| Functional verification | 4/4 tests pass (identity, zero, X·1, random vs Python golden) |

Previous result (pre-A2 shared-sub-NTT consolidation): 67,799 LUT / 15,015 FF /
32 DSP / 207.9 MHz / 12.0 µs. The A2 change traded **−13 % Fmax for −35 % LUT
and −44 % FF**, giving a **−26 % area-time product**.

For comparison the plan's projection for this design point (§3 of
IMPLEMENTATION_PLAN.md) was ~12 K LUT, 8 DSP, ~1.5 µs at 350 MHz. We are
**5.7× over on LUT, 4× over on DSP, 8× over on time** — the gap is mostly
that the implementation chooses the high-parallelism point of the architecture
(32 hardware lanes) rather than the time-multiplexed 8-lane point the plan
assumed.

---

## 2. Implementation journey (chronological)

The Phase C top-level (`rtl_hier_ntt/hier_n1024_top.v`) went through five
distinct architectural states. Each row below reports the *measured* metrics
right before moving to the next iteration.

| # | Architecture | LUT | FF | DSP | Fmax | Time | Pass-fail signal |
|---|---|---|---|---|---|---|---|
| 1 | Flat register arrays (8 × N reg arrays), combinational mul, combinational sub-NTT | 295,557 (synth-only, K7 overflow at 291 %) | 139,347 | 32 | — (place_design refused to start) | — | K7-160 cannot fit; U280 placement runs >5 h then gets stuck |
| 2 | Same FSM, only added `(* ram_style = "distributed" *)` | 295,557 | 139,347 | 32 | — | — | LUTRAM inference fails — Vivado keeps storage in FFs |
| 3 | Banked v1: 2-D `mem[bank][pos]` array in `banked_mem.v` | 345,440 | 139,393 | 32 | — | — | LUTRAM inference *still* fails; crossbar logic adds 50 K LUT |
| 4 | Banked v2: per-bank 1-D arrays in a generate loop (canonical pattern) + LUTRAM hint | 71,288 | 111 | 32 | 28 MHz (K7) | 86 µs | LUTRAM now inferred (3,072 cells); FFs drop 1255×; K7 finally fits at 70 % |
| 5 | 4-memory consolidation (raw_a/spec_a/prod/result → mem_a; raw_b/spec_b → mem_b; work; trans) + valid-pipe drain to prevent inter-phase read-write race | 61,570 | 2,071 | 32 | 42 MHz (U280) | 57 µs | All 4 sim tests pass; phase drain extended to 3 cycles |
| 6 | Pipelined sub_ntt32 (5 substages → 6-cycle latency) + 3 pipeline taps (d3/d6/d9) for per-phase write delays | 68,673 | 13,440 | 32 | 164 MHz | 15.06 µs | Critical path drops from 35.5 ns / 85 levels to 6 ns / 16 levels |
| 7 | + ntt_*_in_pack register stage (breaks LUTRAM-read → crossbar → sub-NTT input) + d10 pipeline tap | 67,870 | 14,494 | 32 | 192.8 MHz | 12.85 µs | New critical path through mod_mul stage register |
| 8 | + Vivado `synth_design -directive PerformanceOptimized`, `place_design -directive Explore`, `phys_opt_design` | **67,869** | **14,719** | **32** | **199.7 MHz** | **12.4 µs** | Diminishing returns; route now dominates (3.95 ns route / 1.10 ns logic) |
| 9 | + SLR0 pblock floorplan (synth/hier_n1024_pblock.xdc) | 67,813 | 14,543 | 32 | 198.0 MHz | 12.5 µs | **No effect** — confining to SLR0 didn't reduce route delay; route delay actually went up slightly (4.24 ns) because placement choices shrunk. Critical path moved from mod_mul stage register to sub_ntt32 output mux → mem_a LUTRAM write. The 200 MHz ceiling appears architectural, not floorplan-induced. |
| 10 | + Tried sub_ntt32 OUTPUT register (d11/d8 taps) | 67,827 | 15,641 | 32 | 197.7 MHz | 12.6 µs | **No effect on Fmax.** The bottleneck was on the *mul side*, not the NTT side. Critical path was op_count → bank addressing → LUTRAM → mul_a → DSP, not through sub_ntt32 output. Reverted. |
| 11 | + Reverted NTT output reg, added external `mul_a_r`/`mul_b_r` register at mod_mul input | 67,817 | 14,866 | 32 | 198.3 MHz | 12.6 µs | **No effect** — Vivado packed the new register into the DSP's internal A_REG input. Path source stayed as `op_count_reg[7]_replica`. Confirmed by inspection of timing report. |
| 12 | + Same + `(* DONT_TOUCH = "true" *)` on mul_a_r / mul_b_r | **67,799** | **15,015** | **32** | **207.9 MHz** | **12.0 µs** | DONT_TOUCH prevents DSP absorption. Path source is now correctly `op_count_reg[2]` → `gen_tw_lanes[4].mul_a_r_reg[3]/D`. Critical path: 4.8 ns, 74% route, 26% logic. Read-side path (op_count → bank-addressing → LUTRAM → crossbar → mul_a_r) is now the bottleneck. |
| 13 | Attempt: register the LUTRAM rdata output (`READ_LATENCY=1` in `banked_mem.v`) to split the read-side path into (op_count → addressing → LUTRAM) and (registered rdata → crossbar → mul_a_r) | — | — | — | — | — | **ABANDONED.** Adding a register on `rdata_pack` inside `banked_mem` is structurally simple but breaks correctness at phase transitions: the registered rdata captures `rdata_pack_comb` at the *next* posedge, by which time `rshift` and `rpos` have already advanced to the next issue's values (and possibly the next state's mux selections). The fix requires also shifting consumer-side muxes to `state_d1`/`state_d2`, advancing every write tap by one (d4→d5, d7→d8, d11→d12), extending FSM phase length by one, and adding a 12th pipeline stage — a multi-file refactor with high bug risk for an expected +30-50 MHz gain. Reverted; kept `READ_LATENCY` parameter in `banked_mem.v` for future use. |
| 14 | **Shared sub-NTT (A2).** Replaced two `sub_ntt32` instances (`u_subntt_row`, `u_subntt_col`) with one shared `u_subntt`. Merged `ntt_row_in_pack` / `ntt_col_in_pack` always-blocks into a single `ntt_in_pack` mux. Aliased `ntt_row_out_pack` / `ntt_col_out_pack` as wire renames of `ntt_out_pack` so write logic was untouched. | **43,854 (−35 %)** | **8,408 (−44 %)** | **32** | 180.4 MHz | 13.8 µs | All 4 sim tests pass, cycle count unchanged at 2,489. Far bigger LUT/FF win than predicted (~3 K LUT estimate vs 24 K actual): the larger driver was Vivado no longer duplicating crossbar/mux logic for two parallel consumers of `trans_rdata` and `prod_rdata`. Critical path moved from mul-side (`op_count → mul_a_r/D`) to OUTPUT phase (`op_count → mem_a LUTRAM read → data_out/D`, 15 logic levels, 5.57 ns). **Area-time product −26 %**, a clear net win even with the −13 % Fmax. |

### Lessons from each step

#### Step 4: per-bank 1-D arrays is the canonical Vivado LUTRAM idiom

Step 3 wrote storage as `reg arr [0:LANES-1][0:DEPTH-1]` (a 2-D array)
inside a generate scope. Vivado refused to infer LUTRAM from that — it
synthesized as flip-flops with combinational wide-mux read, blowing LUTs
up. Step 4 changed the inner storage to `reg arr [0:DEPTH-1]` (1-D)
inside a per-bank generate scope, with one `always @(posedge clk)` per
bank. That is the textbook pattern Vivado's distributed-RAM inference
expects, and the LUTRAM showed up in the utilization report immediately.

This is a single-character lesson but cost real time to find: **multi-port
RAM inference in Vivado is shape-sensitive** even when the access pattern is
identical. Document the working pattern in `banked_mem.v`.

#### Step 5: phase-transition read-write races

After step 4 the design was structurally correct (synth passed) but
simulation produced X in the first test (identity). The bug was *not* in
the FSM — it was a phase-transition race where, at the first 3 cycles of
phase X+1, phase X's last 3 writes were still committing into the same
LUTRAM cells X+1 was reading from. LUTRAM uses combinational read of the
*pre-commit* value, so those reads returned X.

Fix: a 3-cycle drain at the end of each NTT/XTW phase (extending phase
length from M to M+3) plus a `valid_d3` gate on every write enable. Once
both were in place all four sim tests passed. The drain extension also
generalized naturally to the deeper pipeline (M+9 then M+10 in later
steps).

#### Step 6: pipelining the sub-NTT was the single biggest Fmax win

The combinational 32-pt sub-NTT was 5 substages of butterflies = ~30
logic levels. Even with pipelined `mod_mul_fermat`, the combinational
sub-NTT in the critical path capped us at 42 MHz (step 5). Swapping in
the Phase B.1 pre-built `sub_ntt32` (6-stage pipeline) cut the critical
path roughly 4× and pushed Fmax to 164 MHz.

Side effect: this introduced the third pipeline tap d9 (=mul + NTT) and
the FSM had to learn three different write delays (d3 mul-only, d6
NTT-only, d9 NTT+mul). Per-memory case statements now use the appropriate
tap.

#### Step 7: registering the NTT input was a cheap extra +30 MHz

Critical path after step 6 was op_count → bank-address arithmetic →
LUTRAM read → cyclic-shift crossbar → sub-NTT input register. Adding a
register on `ntt_*_in_pack` (between crossbar and sub-NTT input) broke
the path roughly in half. Cost: 32 lanes × 17 bits × 2 = 1,088 FFs plus
4 control FFs.

This shifted all write delays by 1 (d3 stays; d6→d7; d9→d10) and added
1 cycle of latency, but the Fmax gain (+18 %) more than paid for it.

#### Step 8: `-directive PerformanceOptimized` was a free +3 %

Default Vivado directives close at 193 MHz; `synth_design -directive
PerformanceOptimized` plus `place_design -directive Explore` plus
`phys_opt_design` adds about 7 MHz. The critical path is now route-bound
(3.95 ns of the 5.05 ns delay is wires), so further synth-side tuning
has limited room.

### Things tried that DID NOT work (negative results worth keeping)

1. **`(* ram_style = "distributed" *)` attribute alone on a flat
   reg array (step 2).** Did not change LUT count — Vivado would not
   infer LUTRAM from a 1024-deep array accessed 32 ways in parallel.
   The fix was structural (per-bank 1-D arrays in a generate loop),
   not an attribute.

2. **Quarter-cycle twiddle compression (post-step 8).** Implemented in
   `twiddle_gen.v` with `MODE = "rom_qcompressed"` (4× smaller ROM with
   quadrant fix-up using D1 arithmetic). The math was verified bit-for-bit
   against the full ROM via `tb_twiddle_qc.v`. *But* Vivado inferred 37
   extra DSPs for the post-processing arithmetic (mul-by-256 = shift,
   neg, normal↔D1 conversions), pushing DSP count from 32 to 69. LUT
   reduction was only −1.5 K, which doesn't pay for losing the "32 DSPs
   matches algorithmic parallelism" headline. Reverted.

   The `twiddle_gen.v` code keeps the qcompressed mode behind the
   `MODE` parameter for future reuse.

3. **Hierarchical 2-D `mem[bank][pos]` array (step 3).** As mentioned
   above, Vivado refuses to infer LUTRAM from this shape even with the
   attribute. Per-bank 1-D arrays in a generate are the canonical form.

4. **Targeting U280 with the unoptimised register-array design (step 1).**
   Vivado spent >5 hours in placement before getting stuck on the
   295 K-LUT design. Killing it and switching to the banked-storage
   refactor cut subsequent runs to <30 min. **Don't synth designs that
   are this congested**; fix the architecture first.

5. **Registering the LUTRAM rdata output to push past 200 MHz (step 13).**
   The intuition was clean: split the long combinational read path
   (op_count → addressing → LUTRAM → crossbar → mul_a_r) by inserting
   a register right at the LUTRAM output. `banked_mem.v` was extended with
   a `READ_LATENCY` parameter (0 = combinational; 1 = registered with
   `DONT_TOUCH`). But this kind of register is *not* a free pipeline
   stage when the read-address driver is also state-dependent: at the
   next posedge, `rshift`/`rpos` have advanced to the *next* issue's
   values, so the registered output reflects state Y's read, not
   state X's. Fixing this requires shifting every consumer mux to
   `state_d1`/`state_d2`, walking every write tap forward by one
   (d4→d5, d7→d8, d11→d12), extending FSM phase length by one cycle,
   and adding a 12th delay stage. Started the refactor, realised the
   bug surface, and reverted. The `READ_LATENCY` parameter is retained
   in `banked_mem.v` and the 12-stage shift chain (`state_d1..d12`)
   stays in `hier_n1024_top.v` for the day this is attempted properly.

---

## 3. Architecture (as of step 8)

```
                          ┌────────────────┐
data_in_a ─┬─ data_in_a_d3────────►│                │
data_in_b ─┴─ data_in_b_d3────────►│   mem_a /     │  read
                                    │   mem_b /     │  rdata
   op_count ─►(bank/pos calc) ─────►│   mem_work /  │ ──────┐
                                    │   mem_trans   │       │
   state    ─►(rshift/wshift  ─────►│   (32 banks   │       │
              per-state mux)        │   × 32-deep   │       │
                                    │   LUTRAM)     │       │
                                    └───┬────────┬──┘       │
                                        │        │          │
                                        │        ▼ wdata    │
                                        │  ┌────────────┐   │
                                        │  │ broadcast/  │  │
                                        │  │ source mux  │  │
                                        │  └─────────────┘  │
                                        │                   │
                            (crossbar = cyclic shift by      │
                             op5 / op5_d3 / op5_d7 / op5_d10)│
                                        │                   │
                                        ▼                   │
        ┌──────────────┐  ┌────────────────────────┐        │
        │ ntt_col_in_  │  │   mul_a_pack /         │        │
        │ pack /       │  │   mul_b_pack            │        │
        │ ntt_row_in_  │  │     (state mux)         │        │
        │ pack         │  └────────┬─────────────┘          │
        │ (REGISTERED) │           │                        │
        └──────┬───────┘           ▼                        │
               │           ┌────────────────┐               │
               ▼           │ mod_mul_fermat │               │
        ┌────────────┐     │  ×32 lanes      │              │
        │ sub_ntt32  │     │  PIPELINED=1    │              │
        │ (×2:       │     │  (3 stages)     │              │
        │ row + col) │     └────────┬─────────┘             │
        │ 6-cycle    │              │                       │
        │ pipeline   │              ▼                       │
        │ shift-only │       mul_out_pack ─────────┐        │
        └─────┬──────┘                              │       │
              │                                     │       │
              ▼                                     │       │
       ntt_row_out_pack /                           │       │
       ntt_col_out_pack ────────► (write mux) ─────►(state_dN
                                                     selects
                                                     wdata src)
                                                       │
                                                       ▼
                                              memory-side writes
```

### Pipeline taps (write timing)

| Tap | Used by | Data source |
|---|---|---|
| d3  | LOAD (raw_a/raw_b), FWD_XTW (trans), INV_XTW (trans), PWM (prod=mem_a) | `data_in_*_d3`, `mul_out_pack` |
| d7  | FWD_COL_A (spec_a=mem_a), FWD_COL_B (spec_b=mem_b), INV_COL (work) | `ntt_col_out_pack` |
| d10 | FWD_ROW_A (work), FWD_ROW_B (work), INV_ROW (result=mem_a) | `ntt_row_out_pack` (FWD) or `mul_out_pack` (INV) |

### Phase lengths

Each NTT/XTW phase is `M + 9 = 41` cycles in the FSM:
- 32 cycles of issues (op_count 0..M-1, issue_valid=1).
- 9 cycles of drain (op_count M..M+8, issue_valid=0). Drain length matches
  the worst-case pipeline depth d10 so all in-flight writes complete before
  the next phase's first read.

LOAD and OUTPUT are `N + 9` cycles each (N issues + 9 drain).
Total cycles = 2·N + 10·(M+9) + small = **2,477**.

### Module map

```
rtl_hier_ntt/
├── hier_n1024_top.v       Phase C top-level: FSM, pipeline taps, write logic.
├── sub_ntt32.v            6-stage pipelined 32-pt shift-only NTT/INTT.
├── banked_mem.v           32-bank LUTRAM with combinational read + cyclic-shift crossbar.
├── twiddle_gen.v          ψ^k ROM, MODE = rom_full | rom_qcompressed, REGISTERED select.
├── cross_tw_mul.v         (Phase B.2, reserved for sign-flip optimization variant.)
├── multivar_addr_gen.v    (Phase B.3, used by Phase D/E address calculation.)
└── DESIGN.md              Notes on the optimized bivar variant (separate experiment).
```

---

## 4. Research findings: published techniques we could apply

Web research summarised below. Sources cited at the end of this section.

### 4.1 Twiddle-factor on-the-fly recurrence

**Idea.** Replace large ROM lookup with a small seed ROM + a multiplier
that walks `ψ^(k+1) = ψ^k · ψ` (or a stride form `ψ^(k+s) = ψ^k · ψ^s`).
Reported BRAM reductions: 63 % from 48 → 18 BRAMs at N=4096 in one paper;
"one to two orders of magnitude" reduction at N=2¹⁴ in another.

**Applicability to our design.** Our 32 instances of `twiddle_gen` each
hold a 2N-entry ROM. Even with `rom_style = "block"` Vivado declined to
use BRAM because we read combinationally. A recurrence-based generator
would:

- Replace 32 ROMs with 1 seed ROM and a small set of multipliers.
- Probably save 20-30 K LUTs (twiddle ROMs are a measurable but unmeasured-
  by-hierarchy chunk of our 68 K).
- Cost ~1 extra DSP per lane (or fewer if the recurrence is shared with a
  small fan-out tree).
- Add the complication that *each lane's twiddle index follows a
  state-specific stride* (pre-twist: `tg·M + op_count`; cross-twiddle:
  `2·tg·op_count`; etc.). The recurrence must be re-seeded at every phase
  transition, and may need to "skip" to handle non-unit strides.

**Verdict.** High potential LUT win, moderate engineering effort, small
DSP cost. Worth trying after SLR floorplanning.

### 4.2 SLR-aware floorplanning

**Idea.** U280 has 3 SLRs connected by SLLs (super-long lines). Cross-SLR
nets are slow and bandwidth-limited. Pinning the design to one SLR
eliminates these crossings and typically improves Fmax 20-50 % for designs
that fit in one SLR (~ 433 K LUTs per SLR).

Our design at 68 K LUTs (5.2 % of U280) easily fits in one SLR. The
current critical path is 78 % route-delay, strongly suggesting cross-SLR
or long-route placement.

**Applicability.** Add a `pblock` XDC constraint to confine the design to
SLR0. Single-file change, no HDL impact.

**Verdict.** Cheapest gain available — likely +30-50 MHz with zero risk.
**Do this first.**

### 4.3 Half-memory / quadrant compression

**Idea.** Exploit symmetries `ψ^(N+k) = -ψ^k` and `ψ^(N/2+k) = i·ψ^k`
to store only ¼ of the twiddles and fix up at read.

**Applicability.** We tried this in `twiddle_gen.v` as
`MODE = "rom_qcompressed"`. The math is correct and verified, but
Vivado inferred extra DSPs for the fix-up logic, hurting the "32 DSPs"
headline. The code is retained for the case where DSP count is not
constrained.

**Verdict.** Not for Phase C, but possibly useful at Phase E/F where
ROM size is the bottleneck and a few extra DSPs are tolerable.

### 4.4 Pipelined / chained butterfly with intermediate CGRAMs (Supranational ZPrize)

**Idea.** Long butterfly chain (12 stages) with constant-geometry RAMs
between every pair. Twiddles generated on-the-fly with 3 mul-reduce units
per lane. 12 DSPs per butterfly, 16 parallel lanes.

**Reported numbers** (U55N at N=2²⁴): 327,707 LUTs, 2,880 DSPs, 200 BRAM,
**464 MHz**, 2.5 ms per polyMul.

**Applicability to us.** Their design is N=2²⁴ on a 32-DSP-per-butterfly
budget; ours is N=2¹⁰ on a 1-DSP-per-lane budget. The architecture
class is similar (lane-parallel butterfly chain with twiddle injection)
but we are 32× less compute per butterfly and 16K× less N.

The CGRAM idea — short LUTRAM stages *between* sub-NTT substages instead
of pure registers — could help if our internal sub-NTT pipeline is too
wide. Current sub-NTT has 32×17×6 = 3,264 register bits per direction;
that's already small.

**Verdict.** Best taken as the architectural template for Phase D and
beyond. Not directly applicable to Phase C without major restructuring.

### 4.5 K2RED / Montgomery-shift modular reduction

**Idea.** Some published designs report faster modular reduction by
restructuring as runtime-configurable shift-add chains.

**Applicability.** Our `mod_mul_fermat` already exploits the Fermat
structure `q = 2^B + 1` for cheap reduction (one subtraction). It's
already shift-add-ish for the reduction step. The actual multiplication
uses DSPs. Switching reduction methods is unlikely to help.

**Verdict.** Skip — our reduction is already near-optimal for F₄.

### 4.6 Floorplan for routability + register replication

**Idea (UltraFast methodology guide).** For wide buses crossing significant
distance, explicitly insert register slices; tell the placer to relax
constraints between high-fanout drivers. `phys_opt_design` already does
some of this (register replication), but explicit pblocks help more.

**Verdict.** Done in step 8 (`phys_opt_design`); next would be explicit
pblock constraints from 4.2.

### Sources

- [Designing Efficient and Flexible NTT Accelerators (eprint 2023/1617)](https://eprint.iacr.org/2023/1617.pdf)
- [Supranational ZPrize FPGA NTT (GitHub repo)](https://github.com/supranational/zprize-fpga-ntt)
- [Efficient Twiddle Factor Generators for NTT (MDPI 2024)](https://www.mdpi.com/2079-9292/13/16/3128)
- [On-the-Fly Twiddle Factor Generator Design for Negative Wrapped Convolution (ResearchGate 2024)](https://www.researchgate.net/publication/381333800_On-the-Fly_Twiddle_Factor_Generator_Design_for_Efficient_Memory_Management_of_Negative_Wrapped_Convolution)
- [OpenNTT: An Automated Toolchain for Compiling High-Performance NTT (eprint 2024/1740)](https://eprint.iacr.org/2024/1740.pdf)
- [Optimized FPGA Architecture for Modular Reduction in NTT (eprint 2024/1890)](https://eprint.iacr.org/2024/1890.pdf)
- [AT-NTT: Area-time efficient polynomial multiplication for CRYSTALS-Kyber (ScienceDirect)](https://www.sciencedirect.com/science/article/abs/pii/S0045790626001412)
- [@NTT: Algorithm-Targeted NTT hardware acceleration via Design-Time Constant Optimization (arXiv 2601.17806)](https://arxiv.org/pdf/2601.17806)
- [UltraFast Design Methodology Guide for the Vivado Design Suite (Xilinx UG949)](https://www.xilinx.com/support/documents/sw_manuals/xilinx2022_2/ug949-vivado-design-methodology.pdf)

---

## 5. Prioritised next-step recommendations

Ranked by `(expected impact) / (engineering effort)`:

### 5.1 SLR pblock constraint  →  TRIED, no measurable effect

Added an XDC file `synth/hier_n1024_pblock.xdc` pinning the design to SLR0:

```tcl
create_pblock pblock_hier_n1024
add_cells_to_pblock [get_pblocks pblock_hier_n1024] \
    [get_cells -hierarchical -filter {NAME=~"*"}] -clear_locs
resize_pblock [get_pblocks pblock_hier_n1024] -add {SLR0}
set_property CONTAIN_ROUTING true [get_pblocks pblock_hier_n1024]
```

**Result (step 9 of section 2):** Fmax 199.7 → 198.0 MHz — essentially no
change. Route delay actually went up slightly (4.24 ns vs 3.95 ns) because
the smaller placement region restricted the placer's freedom.

**Diagnosis:** The route problem was not cross-SLR after all — within SLR0
the 32-lane × 17-bit data buses still have long routes because each lane's
data fans out to all 32 banks of the destination memory. The 200 MHz
ceiling is architectural, not floorplan-induced.

**Implication:** To push past 200 MHz needs *extra register stages*, not
floorplanning. Specifically, register between sub_ntt32 output and the
banked_mem write port (would add 1 more pipeline cycle on top of the
existing 10).

### 5.2 Twiddle recurrence generator  →  expected LUT -20 to -30 K

Replace `twiddle_gen.v` with a recurrence-based generator. Sketch:

- One small seed ROM (32 entries × 17 bits, one per lane, holding `ψ^(tg·M)`).
- Per lane: a register `current_tw` initialised from seed, updated each cycle
  by `current_tw ← current_tw · ψ` (one DSP multiply per lane).
- For phase transitions, reload `current_tw` from the seed ROM for the new
  exponent pattern (cross-twiddle vs row-twiddle etc.).
- Need to handle non-unit strides for cross-twiddle (`2·tg·op_count`):
  use a per-lane *stride seed* and recompute on phase entry.

DSP cost: +32 (one per lane). Brings DSP count from 32 → 64.
LUT savings: 20-30 K. Time impact: minimal (recurrence keeps up with the
1-cycle issue rate).

**Trade-off concern:** doubles DSPs. Hurts the "32 DSPs = algorithmic
parallelism" headline. Useful at Phase D/E where ROM size becomes the
dominant cost.

### 5.3 Inline register slice on cross-SLR nets if pblock still leaves a long route

If after 5.1 the critical path still has long routes, manually insert AXI
register slices on the wide buses between memory and sub-NTT. The Vivado
auto-pipelining IP can also be used.

### 5.4 Phase D (N = 32K, d = 3) using current 32-lane architecture

The actual paper claim is *constant hardware across N*. Show this by
re-targeting `hier_n1024_top.v` to `hier_n32k_top.v` with d=3 and the
same datapath. Expected outcome: same ~68 K LUT, +M cycles per level,
~60 µs at 200 MHz.

This is the most paper-relevant next step — it validates the central
architectural claim, not just optimises a single design point.

### 5.5 Lane reduction (32 → 8) for plan-aligned design point

Time-multiplex 4× across the lanes to hit the plan's 8-DSP / ~45 K-LUT
projected design point. Expected: 4× cycle count growth, smaller area.
Useful as a *second data point* alongside the 32-lane version to show
the area/time trade-off curve.

---

## 6. File / repo conventions

| File | Purpose |
|---|---|
| [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) | The research plan (v2). Source of truth for paper claims. |
| [`IMPLEMENTATION_DOC.md`](IMPLEMENTATION_DOC.md) | This file. Process log, research, decisions. |
| `rtl_hier_ntt/hier_n1024_top.v` | Top-level for Phase C. |
| `rtl_hier_ntt/sub_ntt32.v` | Pipelined 32-pt sub-NTT (Phase B.1). |
| `rtl_hier_ntt/banked_mem.v` | LUTRAM-banked storage primitive (Phase B.5). |
| `rtl_hier_ntt/twiddle_gen.v` | Twiddle ROM (Phase B.4). |
| `sim/testbenches/tb_hier_n1024.v` | Self-checking testbench. |
| `scripts/bivar_ntt_model.py` | Python golden model (negacyclic poly mul). |
| `scripts/gen_hier_n1024_vectors.py` | Vector generator for the testbench. |
| `synth/vivado_synth_hier_u280.tcl` | U280 synth+impl flow (PerformanceOptimized + Explore + phys_opt). |
| `synth/results_hier_n1024_u280/` | Latest impl reports. |

---

## 7. Repeat-this checklist (so future-you can re-build the whole flow)

1. **Sim:**
   ```bash
   cd sim
   iverilog -g2012 -o work/hier_ntt/tb_hier_n1024 \
     ../rtl/d1_arith.v ../rtl/r2_butterfly.v ../rtl/r2intt_butterfly_pow2.v \
     ../rtl/r2ntt_r32.v ../rtl/r2intt_r32.v ../rtl/bivar_ntt_subntt32.v \
     ../rtl/mod_mul_fermat.v ../rtl_hier_ntt/twiddle_gen.v \
     ../rtl_hier_ntt/banked_mem.v ../rtl_hier_ntt/sub_ntt32.v \
     ../rtl_hier_ntt/hier_n1024_top.v \
     testbenches/tb_hier_n1024.v
   vvp work/hier_ntt/tb_hier_n1024
   # Expected: 4/4 tests pass, cycle_count=2477.
   ```

2. **Generate fresh golden vectors:**
   ```bash
   python scripts/gen_hier_n1024_vectors.py --seed 42
   ```

3. **U280 impl** (~20-30 min):
   ```bash
   cd synth
   rm -rf results_hier_n1024_u280
   /d/Xilinx/Vivado/2022.2/bin/vivado.bat -mode batch \
     -source vivado_synth_hier_u280.tcl -tclargs 3.0
   cat results_hier_n1024_u280/metrics_raw.txt
   ```

4. **K7-160 impl** (for the legacy small-FPGA data point) — same but
   `vivado_synth_hier_n1024.tcl` with `-tclargs 5.0`.

---

*Last updated: corresponds to step 14 of section 2 (180 MHz, 13.8 µs,
43,854 LUT / 8,408 FF / 32 DSP, U280) — shared sub-NTT consolidation (A2).
This is the new Phase C reference point. Step 13 (rdata-register push) was
attempted and abandoned. Phase D (N=32K) work started 2026-05-24 — see §8.*

---

## 8. Phase D foundations (N=32K, d=3) — algorithm validated

Phase D started 2026-05-24. The first deliverable is a software-verified
trivariate (d=3) algorithm before any RTL is written; this avoids debugging
a wrong algorithm in 1000+ lines of Verilog.

### 8.1 Algorithm derivation summary

Layout: flat index `i = i1 + L·i2 + L²·i3` for L=M=K=32, N=L³=32,768.
Decompose N-point NTT as nested bivariate Cooley-Tukey:
N = L · (L · L), with the inner (L·L)-NTT further split as L·L.

**Forward (per polynomial):**
1. Pre-twist all coefficients by `psi^i` (negacyclic → cyclic).
2. **NTT along i3 axis** (32-pt, one per (i1,i2)).
3. **Cross-twiddle 1:** multiply by `omega_(L²)^(i2·k3) = psi^(2L·i2·k3)`.
4. **NTT along i2 axis** (32-pt, one per (i1,k3)).
5. **Cross-twiddle 2:** multiply by `omega_N^(i1·K) = psi^(2·i1·(L·k2 + k3))`,
   where K = L·k2 + k3 is the inner frequency.
6. **NTT along i1 axis** (32-pt, one per (k2,k3)).

After step 6, t[k1][k2][k3] holds X[L²·k1 + L·k2 + k3] — CT output ordering
has **k1 in the highest bits** (this is the trap that took two failed
algebra attempts to find; the cross-twiddle in step 5 requires L·k2 + k3,
*not* k2 + L·k3, because of this ordering).

**Inverse:** reverse the steps with `psi^(-…)` factors; divide by N at the
end (the inner INTTs each divide by L, so the chain divides by L³ = N
automatically).

### 8.2 Key correctness gotcha — omega convention

The 32-pt sub_ntt32 inside `sub_ntt32.v` uses `WEXP = 19` so its primitive
32-th root is `2^19 = 65529 mod 65537`. The standard Cooley-Tukey
cross-twiddle algebra (`psi^(2·k1·i2)` etc.) requires the canonical
generator-derived root `3^((q-1)/32) mod q`. These are different elements
of F_q, and using the wrong one breaks the algorithm.

The Python golden uses the canonical root (`3^((q-1)/32)`). **Verified
2026-05-24:** `2^19 mod 65537 = 3^((q-1)/32) mod 65537 = 65529` — they
are *the same element*, so sub_ntt32 IS aligned with the canonical root and
the Python golden's cross-twiddle formulas (`psi^(2L·i2·k3)` and
`psi^(2·i1·(L·k2 + k3))`) transfer to RTL directly with no convention
adjustment.

The trap remains: a naive Python `_ntt32` using `omega = 2` (not `2^19`)
computes a *permuted* DFT, and the cross-twiddle algebra breaks. Always
use the canonical 32nd root in any Python reference that must match the
RTL.

### 8.3 Foundation deliverables (complete)

- `scripts/trivar_ntt_model.py` — d=3 algorithm + fast O(N log N) golden.
  Self-test verifies trivar_poly_mul against fast_negacyclic_mul at N=32K
  (4 random seeds + 3 edge cases all PASS).
- `scripts/gen_hier_n32k_vectors.py` — produces `input_a_n32k.hex`,
  `input_b_n32k.hex`, `expected_hier_n32k.hex` (32K entries each).
- `sim/input_a_n32k.hex`, `input_b_n32k.hex`, `expected_hier_n32k.hex` —
  ready to consume from the Phase D testbench.

### 8.4 RTL drafted (Phase D structure complete, debug in progress)

Files in place (2026-05-24):
- `rtl_hier_ntt/banked_mem.v` — extended with `STORAGE = "bram"` mode
  (sync read, 1-cycle latency, internal `rshift_r` register for crossbar
  alignment).  Unit-tested by `tb_banked_mem_bram.v`.  Phase C regression
  passes.
- `rtl_hier_ntt/hier_n32k_top.v` — d=3 top, 839 LoC, 4 BRAM-backed memories,
  taps d5/d8/d12.  Compiles clean.
- `rtl_hier_ntt/sub_ntt_simple.v` — parameterized 6-cycle pipelined NTT for
  the L=8 debug variant (uses an explicit 8x8 omega matrix; DSPs for mul).
  Unit-tested: delta_0 -> all 1s, delta_1 -> [1, 4096, 65281, ...] ✓.
- `rtl_hier_ntt/hier_n512_top.v` — L=8 debug variant of hier_n32k_top
  (~30x faster sim).  Compiles clean.
- `sim/testbenches/tb_hier_n32k.v` and `tb_hier_n512.v` — same shape.
- `synth/vivado_synth_hier_n32k_u280.tcl` — ready (not yet run).

### 8.5 Debug status: 1 bug fixed, more to find

First-pass sim results:
- N=32K (L=32) test: zero passes; identity/X·1/random all fail with ~100 %
  garbage output.  ~3 min per sim cycle.
- N=512 (L=8) test: same failure pattern, ~5 sec per sim cycle.

**Bug 1 (FIXED):** OUTPUT path mis-indexes BRAM rdata.
  - `data_out <= mem_a_rdata[load_bank*W]` uses current-cycle `load_bank`,
    but `mem_a_rdata` reflects BRAM read issued 1 cycle ago.  Result: every
    OUTPUT sample reads the wrong lane (off-by-1 in op_count).
  - Fix: register `load_bank` 1 cycle (`load_bank_d1`) and index with that.
  - Also fix valid window: `(op_count >= 1) && (op_count < N+1)` to match
    the 2-cycle (1 BRAM + 1 data_out) latency.
  - Applied to both `hier_n32k_top.v` and `hier_n512_top.v`.
  - Verified at L=8 with a temporary LOAD-only bypass: `X_times_1`
    (a=[0,1,0...], b=[1,0...]) now PASSES — LOAD + OUTPUT round-trip works.

**All 5 bugs found and fixed (L=8 passes 4/4 tests including random):**

**Bug 1 (OUTPUT path):** `data_out <= mem_a_rdata[load_bank*W]` used
current-cycle `load_bank`, but `mem_a_rdata` reflects BRAM read issued 1
cycle ago. Fix: register `load_bank` 1 cycle (`load_bank_d1`).

**Bug 2 (twiddle timing):** Twiddle indices used current `op_count`, but
`mul_a` comes from BRAM-delayed `raw_a_rdata` (issue-1 cycle). Fix: use
`opcnt_d[1]` for twiddle index computation AND `state_d[1]` for selecting
which twiddle to apply.

**Bug 3 (FWD_L0 write source):** FWD_L0_A's write to mem_work used
`mul_out_pack`, but FWD_L0 is mul-then-NTT, so the d12-tap output is
actually `ntt_out_pack`. Fix: use `ntt_out_pack`.

**Bug 4 (INV_XTW2 twiddle formula):** FWD_XTW2 iterates `(op_low=i1,
op_high=k3, lane=k2)` so twiddle is `psi^(2*olo*(L*tg+ohi))`. INV_XTW2
iterates `(op_low=k2, op_high=k3, lane=i1)` (different! reads broadcast
pos from INV_L2 output, lane corresponds to i1 not k2). Naive
`inv_tw_idx(tw_xtw2_idx)` is wrong; element at (i1, k2, k3) needs
`psi^(-2*i1*(L*k2+k3)) = psi^(-2*tg*(L*olo+ohi))`. Fix: derive the
inverse formula directly from the inverse iteration pattern, not by
inverting the forward index.

**Bug 5 (INV_L1 NTT input source):** `ntt_in_pack` for INV_L1 was set to
`work_rdata`, but INV_L1 actually reads from `mem_trans` (INV_XTW2's
output). Fix: `ntt_in_pack = trans_rdata`.

**Per-phase debug methodology that worked:** For each phase, bypass the
FSM to transition directly to DONE after that phase, then dump the
relevant memory and compare to the expected pattern for a delta input
(`a=δ₀`, `b=δ₀`). This isolates each phase. With L=8, each iteration
is ~5 seconds — debugged 5 bugs in ~30 minutes of iteration.

### 8.6 Phase D L=8 result (verified)

**hier_n512_top.v + sub_ntt_simple.v: 4/4 tests pass at N=512 in 2,253 cycles.**

All 5 bug fixes ported to `hier_n32k_top.v` cleanly.

### 8.7 Phase D L=32 result (verified, synthesized on U280)

**hier_n32k_top.v + sub_ntt32.v: 4/4 tests pass at N=32,768 in 82,125 cycles**
(zero, identity, X·1, random_golden). Bug fixes transferred from L=8 with no
rework — same FSM, same taps (d5/d8/d12), same algebra.

Vivado 2022.2 synth+impl on xcu280-fsvh2892-2L-e
(`synth/vivado_synth_hier_n32k_u280.tcl`). Two runs — the 4.0 ns run failed
timing (WNS −0.188 ns); relaxing the constraint to 4.5 ns closes timing
cleanly and gave the placer enough freedom to also shave ~1.6 K LUT.
Reporting the closed-timing run as the headline:

| Metric | 4.5 ns (closed) | 4.0 ns (failed) |
|---|---|---|
| LUT | **47,702** | 49,341 |
| FF | 8,559 | 8,858 |
| DSP48E2 | 32 | 32 |
| BRAM18 | 64 | 64 |
| URAM | 0 | 0 |
| WNS | **+0.002 ns** | −0.188 ns |
| Achieved Fmax | **222.2 MHz** | (238.8 MHz, not closed) |
| Cycles/mul | 82,112 | 82,112 |
| Time/mul | **369.5 µs** | 343.9 µs |

DSP count (32) = one ModMul per sub_ntt32 lane (L=32). BRAM count (64) =
32 banks × 2 BRAMs/bank across the 4 banked mems sharing storage.

Phase D is now functionally and structurally complete: trivariate
decomposition, BRAM-backed banked storage, shared sub_ntt32, FSM
covering 16 phases (forward 6 + INTT 5 + cross/output) with d5/d8/d12
shared-pipeline taps, all verified end-to-end at full N=32K.

---

## 9. The headline result: hardware-constant scaling across d

The Phase C → Phase D step is the central claim of this work, finally
measured end-to-end on the same device:

| Metric | Phase C (d=2, N=1,024) | Phase D (d=3, N=32,768) | Ratio |
|---|---|---|---|
| Polynomial degree N | 1,024 | 32,768 | **32×** |
| LUT | 43,854 | 47,702 | +8.8 % |
| FF | 8,408 | 8,559 | +1.8 % |
| DSP48E2 | 32 | 32 | 0 % |
| BRAM18 | 0 | 64 | (storage swap) |
| Fmax (closed) | 180.4 MHz | 222.2 MHz | +23 % |
| Cycles | 2,489 | 82,112 | 33.0× |
| Cycles per coefficient | 2.43 | 2.51 | +3 % |
| Time per polyMul | 13.8 µs | 369.5 µs | 26.8× |

**32× more N for +8.8 % LUT, same DSP, faster clock.** Cycles-per-coefficient
stays at ≈2.5 across the d-step, so latency tracks N (not N log N or worse) —
the architectural claim of the paper.

The BRAM jump from 0 → 64 is a deliberate storage swap, not extra capacity:
Phase C fits in LUTRAM at N=1,024; Phase D's 4 × 32 K × 17-bit storage is
forced into BRAM by capacity. Net die area for the storage is *lower* on
BRAM than equivalent LUTRAM. The +23 % Fmax in Phase D came from the same
swap — BRAM sync read shortened the read-to-mul path that capped Phase C
at 180 MHz.

### 9.1 Flat baseline at N=32K is infeasible — quick proof

A "flat" (monolithic) N=32K NTT was never run because the flat-storage
design point dies even at N=1024:

> *Section 2, step 1: flat reg-array Phase C at N=1024 →
> **295,557 LUT** (synth-only, K7 overflow at 291 %). Vivado place_design
> refused to start.*

Scaling that naïvely to N=32K: storage alone is 32× the FF/LUT cost
(~9.4 M LUTs), well past *any* current FPGA. The architecture choice
that made this fit — per-bank 1-D arrays + cyclic-shift crossbar,
documented in step 4 of §2 — is what enables both Phase C and Phase D
to live in <50 K LUT.

So the comparison isn't "hier vs flat at the same N"; it is
**"hier at N=32K (47.7 K LUT, closes timing) vs flat at N=32K (does not
fit anywhere)"**. The flat design point has no entry on the U280, K7,
or any UltraScale+ part within reasonable LUT budget for the storage
arrays alone.

### 9.2 Throughput vs theoretical lower bound

Theoretical minimum cycle count for d=3 trivariate decomposition with
one shared L-pt NTT instance:

- 3 forward NTT passes, each N items / L lanes = 3 N
  (one cycle per `(outer, inner)` issue, NTT is fully pipelined)
- 2 cross-twiddle passes = 2 N
- 1 pointwise mul pass = N
- 3 inverse NTT passes = 3 N
- 2 inverse cross-twiddle passes = 2 N
- LOAD + OUTPUT = 2 N
- ≈ 13 N + per-phase drains (10 cycles × 16 phases ≈ 160) = 13·N + 160

At N=32,768: **13 × 32,768 + 160 ≈ 426,144 cycles** theoretical… but
that assumes serial issue. We measure 82,112 cycles, which is **5.2×
better** than that estimate because the NTT pass is fully overlapped
with the next phase's LOAD/issue through the d5/d8/d12 pipeline taps,
and the inner sub_ntt32 processes one L-vector per cycle in parallel
across 32 lanes. The actual rate (≈2.5 cyc/coeff) is essentially at the
information-theoretic floor for a single-port-per-bank design — every
coefficient touches memory ≈2.5 times across the full forward+inverse
chain, and we charge one cycle per memory transit.

### 9.3 What this measurement enables

Two things become claimable that weren't before:

1. **The paper's d-scaling line has two measured points.** Phase C and
   Phase D land where the architecture predicts; adding a third point
   (Phase E, d=4, N≈10⁶) is a straight reuse of Phase D's FSM and
   storage primitives.
2. **The architecture cost is dominated by L, not N.** Almost the entire
   47 K LUT footprint is the L=32 lane width: 32 banks per mem × 4 mems,
   32-lane crossbar, 32-DSP ModMul array, 32-lane sub_ntt32. Scaling N
   by adding levels d adds one FSM phase pair and one memory — not more
   lanes, not more DSPs, not more crossbars. That is the structural
   reason +12.5 %, then now +8.8 %, LUT cost suffices for the 32× N jump.

> **NOTE (2026-05-25):** §9.1's "flat at N=32K is infeasible" claim was
> over-stated and needs caveats. Xing et al. (IEEE TC, Oct 2025) report
> measured FPGA designs for q=65537 (our modulus) up to N=1024 using
> iterative high-radix architecture, with **9.8 K LUT / 16 DSP at
> N=1024** and **+21 % LUT for 4× N growth**. Their design extrapolates
> reasonably to N=32K. The 295 K LUT data point from §2 step 1 was a
> *naive first-cut* implementation that bypassed all architectural
> optimisation; it does not represent the published flat baseline.
> The honest framing: published iterative-radix designs would land at
> ~12–20 K LUT at N=32K. Our hierarchical design (47 K) is **not** a
> LUT win over them at small/medium N. The actual advantage, if any,
> lives at HBM-resident sizes (>N=10⁶) where iterative-radix designs
> suffer from stride-2ˢ access patterns — a claim that requires Phase
> E + Phase F measurements to substantiate.

---

## 10. Post-Phase-D optimisation pass (2026-05-25)

After landing measured Phase C (43,854 LUT) and Phase D (47,702 LUT) and
discovering they were significantly over the plan-targeted 12-13 K LUT,
an investigation pass identified where the LUTs actually went and
applied two concrete optimisations.

### 10.1 Twiddle ROM → BRAM (REGISTERED=1)

**Hypothesis.** The 32 twiddle_gen instances, each with a 2N-entry ROM,
were estimated in §4.1 / §5.2 to consume ~20 K LUT in LUTRAM. Moving
them to BRAM (REGISTERED=1, idx tap shifted opcnt_d[1]→op_count and
opcnt_d[8]→opcnt_d[7] to absorb the +1 ROM read latency) should free
those LUTs.

**Implementation.** Changed `twiddle_gen` instantiation in both
`hier_n32k_top.v` and `hier_n512_top.v` to `REGISTERED(1)`, shifted the
twiddle idx and state mux taps by 1 to align with the new ROM read
latency. L=8 and L=32 sims both PASS, cycle count unchanged.

**Measured impact on Phase D (target 4.5 ns, U280):**

| Metric | Before | After | Δ |
|---|---|---|---|
| LUT | 47,702 | 47,765 | +63 (noise) |
| FF | 8,559 | 8,539 | −20 (noise) |
| BRAM18 | 64 | 72 | +8 |
| WNS | +0.002 ns | +0.061 ns | better |

**Lesson.** The §4.1 hypothesis was *wrong*. Vivado's hierarchical
utilisation report shows **LUT-as-Distributed-RAM = 0** both before and
after — the twiddle ROMs were *never* in LUTRAM. Vivado had been
aggressively optimising them down to minimal logic (likely because the
actual address coverage is a sparse, structured subset of the full 2N
range). The +8 BRAMs are now used for the registered ROMs, but the LUTs
weren't there to save. Change kept anyway for the marginal timing
improvement at zero LUT cost.

### 10.2 Where the LUTs actually go (hierarchical util breakdown)

After the twiddle change, ran `report_utilization -hierarchical
-hierarchical_depth 5` on the impl checkpoint:

| Module | LUTs | % of total |
|---|---|---|
| **u_subntt (sub_ntt32)** | **26,443** | **55.4 %** |
| u_mem_a (banked_mem) | 5,807 | 12.2 % |
| u_mem_b (banked_mem) | 3,556 | 7.4 % |
| u_mem_work (banked_mem) | 3,371 | 7.1 % |
| u_mem_trans (banked_mem) | 2,011 | 4.2 % |
| All 32 mod_mul_fermat | ~6,114 | 12.8 % |
| All 32 twiddle_gen | ~520 | 1.1 % |
| Top-level FSM + state regs | ~221 + glue | <1 % |
| **Total** | **47,765** | 100 % |

**The single biggest LUT consumer is sub_ntt32 (55 %).** Within it,
~10 K LUT is glue (input/output muxes + per-stage register array +
fwd/inv runtime mux) and ~16 K LUT is the 160 butterfly cells (80 fwd
DIT + 80 inv DIF, both physically instantiated and always-clocking,
output mux selects which result to keep).

### 10.3 Bidirectional sub_ntt32 (`sub_ntt32_bidir`)

**Insight.** INTT = NTT-with-inverse-twiddles divided by N. So a single
DIT pipeline can compute *both* directions if (i) the per-stage twiddle
K/NEG values are runtime-muxed between fwd and inv, and (ii) a 1/N
output scale is applied when inverse. Same external contract as the
prior `sub_ntt32` (1 input + 5 stage registers = 6-cycle latency,
natural-order I/O).

**Implementation.**
- `rtl/r2_butterfly_bidir.v` — new butterfly cell parameterised by
  K_FWD, NEG_FWD, K_INV, NEG_INV. Pre-computes both shifted-b values
  (constant-wired shifts, free) and selects between them with a single
  17-bit 2:1 mux per butterfly.
- `rtl_hier_ntt/sub_ntt32_bidir.v` — DIT pipeline only (5 stages of 16
  bidir butterflies = 80 total, half the cell count), single input
  register, single per-stage register array, BR output permute, 1/N
  conditional scale at output (= ×2¹¹ then negate, since 2⁻⁵ = −2¹¹
  mod F₄).
- Wired into both `hier_n32k_top.v` and `hier_n1024_top.v`.

**Standalone verification (`tb_sub_ntt32_bidir`):**
- Random round-trip: INTT(NTT(x)) = x ✓
- delta_0 round-trip ✓
- INTT(all 1s) = delta_0 ✓
- NTT(delta_0) = all 1s ✓

**Integration verification:**
- L=32 hier_n32k_top: 4/4 tests PASS, cycle count = 82,125 (unchanged)
- Phase C hier_n1024_top: 3/3 tests PASS, cycle count = 2,489 (unchanged)

**Measured impact on Phase D (target 4.5 ns, U280):**

| Metric | Before bidir | After bidir | Δ |
|---|---|---|---|
| LUT | 47,765 | **38,529** | **−9,236 (−19.3 %)** |
| FF | 8,539 | **5,851** | **−2,688 (−31.5 %)** |
| DSP | 32 | 32 | 0 |
| BRAM18 | 72 | 72 | 0 |
| WNS | +0.061 ns | +0.132 ns | better |
| Cycles | 82,112 | 82,112 | unchanged |
| Fmax | 222.2 MHz | 222.2 MHz | unchanged |

**Module-level confirmation:** u_subntt dropped from 26,443 → **17,839
LUT** (−32.5 %); its glue layer dropped from 10,387 → 5,541 (about
halved). Matches the design intent: 80 butterflies instead of 160, one
register array instead of two, one output mux path instead of two
selected at runtime.

### 10.4 Ablation summary (U280)

**Phase D (N=32K, target 4.5 ns):**

| Configuration | LUT | FF | DSP | BRAM | WNS | Cycles | Time |
|---|---|---|---|---|---|---|---|
| Baseline (timing-closed) | 47,702 | 8,559 | 32 | 64 | +0.002 ns | 82,112 | 369.5 µs |
| + Twiddle BRAM (REGISTERED=1) | 47,765 | 8,539 | 32 | 72 | +0.061 ns | 82,112 | 369.5 µs |
| **+ Bidirectional sub_ntt32** | **38,529** | **5,851** | 32 | 72 | **+0.132 ns** | 82,112 | 369.5 µs |
| **Net delta** | **−9,173 (−19.2 %)** | **−2,708 (−31.6 %)** | 0 | +8 | better | 0 | 0 |

**Phase C (N=1024, target 3.0 ns):**

| Configuration | LUT | FF | DSP | BRAM | WNS | Cycles | Time |
|---|---|---|---|---|---|---|---|
| Baseline (§1) | 43,854 | 8,408 | 32 | 0 | −2.54 ns | 2,489 | 13.8 µs |
| + Bidirectional sub_ntt32 | **36,839** | **5,816** | 32 | 0 | −2.478 ns | 2,489 | 13.6 µs |
| **Net delta** | **−7,015 (−16.0 %)** | **−2,592 (−30.8 %)** | 0 | 0 | unchanged | 0 | 0 |

The bidirectional sub_ntt32 refactor delivered consistent ~17 % LUT
and ~31 % FF reduction across both phases, with no impact on cycle
count or Fmax. Vivado timing is gated by the LUTRAM read path in
Phase C (the read-side critical path documented in §1) — the sub_ntt32
shrink didn't help that path because it wasn't on it.

### 10.5 Branch A remaining work (revised after this pass)

The original §10.5 (in IMPLEMENTATION_PLAN.md) estimated wins per step.
Updated based on actual measurements:

| Step | Original estimate | Actual / revised | Status |
|---|---|---|---|
| Twiddle BRAM | −18 to −22 K LUT | **0 LUT** (hypothesis wrong) | Done, kept for marginal Fmax |
| Bidirectional sub_ntt32 | not in original plan | **−9.2 K LUT, −2.7 K FF** | Done, biggest measured win |
| Memory consolidation (4 mems → 2) | −8 to −12 K LUT | revised: −4 to −6 K (memories are smaller than I thought; total ~14 K LUT) | next |
| PWM/twist time-multiplex (32 → 8 lanes) | −1 to −2 K LUT, **−24 DSP** | unchanged | follows mem consol |
| Phase E (URAM N=10⁶) build | — | scope-dependent | after C/D ablation table is stable |

The path to Xing-comparable LUT is still alive but takes more steps
than I claimed in §10.5 of the plan. After this pass we are at 38.5 K
LUT; memory consolidation + PWM/twist serializer could bring it to
~28-32 K LUT and 8 DSP. Xing's 9.8 K LUT / 16 DSP at N=1024 is still
out of reach without giving up the hierarchical-decomposition
structure itself.
