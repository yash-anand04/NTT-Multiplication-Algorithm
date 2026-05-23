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

### 8.4 Outstanding (Phase D RTL work)

- `rtl_hier_ntt/hier_n32k_top.v` — d=3 top-level FSM. ~1000 LoC.
- Memory architecture decision. 32K × 17 bits per memory = 544 Kbit. LUTRAM
  would cost ~17 K LUTs per memory (untenable). Must move to BRAM
  (~30 BRAM18 per memory) or URAM (2 URAM tiles per memory). Either
  requires extending `banked_mem.v` with synchronous read — same pipeline
  shift refactor that was abandoned for the Phase C rdata-register attempt,
  but cleaner here because there's no Phase-C state to preserve.
- `sim/testbenches/tb_hier_n32k.v` — same shape as `tb_hier_n1024.v`.
- `synth/vivado_synth_hier_n32k_u280.tcl` + pblock.
