# PAPER DRAFT v0 (2026-05-28)

**Working title:**
*An FPGA Design-Space Exploration of Multivariate Fermat-Modulus NTT for
Negacyclic Polynomial Multiplication: Constant-Hardware Scaling in Decomposition
Depth.*

**Status:** first draft skeleton with real measured numbers and the honest
framing locked in `IMPLEMENTATION_DOC.md` §19–§20 and `docs/VERIFIED_REFERENCES.md`.
Items marked **[VERIFY]** need a primary-source check before submission;
**[FIG]** marks a figure to generate.

> Framing discipline (do not violate): this is a **design-space-exploration /
> scaling-study** paper. We do **not** claim a new algorithm (the multivariate
> Fermat NTT is Kim et al., CRYPTO 2024) and we do **not** claim to beat SOTA
> (Xing et al., IEEE TC 2025, dominates at the overlapping N). The contribution
> is the systematic measurement and the depth-scaling law.

---

## Abstract (draft)

Number-theoretic transforms (NTTs) over a Fermat modulus q = 2¹⁶+1 admit
*multiplier-less* (shift-only) butterflies, and the transform can be factored
into a hierarchy of small sub-transforms via a univariate-to-multivariate
polynomial-ring map (Kim et al., CRYPTO 2024). We present a **measured
design-space exploration** of an FPGA implementation of this multivariate Fermat
NTT for negacyclic polynomial multiplication, sweeping lane width L ∈ {4,8,16,32}
and decomposition depth d ∈ {2,…,7} — all 13 configurations valid under the
Fermat-prime constraint (N = Lᵈ ≤ 32,768) — on a Xilinx Alveo U280. Every
configuration is functionally verified against a reference model and synthesized
to place-and-route. The central empirical finding is a **constant-hardware
scaling law**: at fixed L, logic (LUT) and multiplier (DSP) usage stay
essentially flat as depth d — and hence N = Lᵈ — grows; e.g. at L=4 the design
uses 4 DSPs and 2.1–2.5 K LUT across d=3…7 (a 256× span in N for +20 % LUT). We
trace this to a transpose-free conflict-free memory organization whose
interconnect width is O(L), independent of d and N. We report a candid
comparison against a state-of-the-art iterative Fermat-modulus NTT, which is more
area-time-efficient at the small N where both have data; our design's distinct
points are minimal absolute resource footprint and validated operation across the
full Fermat-valid depth range.

---

## 1. Introduction

- Polynomial multiplication mod (Xᴺ+1) is the kernel of lattice cryptography and
  FHE; NTT reduces it to O(N log N). [VERIFY refs]
- Fermat-prime moduli (q = 2ᵏ+1) make twiddles powers of two → shift-only
  butterflies (no DSP in the butterfly core). Decades-old idea (Fermat Number
  Transform); recently revisited for FHE (Kim et al., CRYPTO 2024 [R2]; Xing et
  al., IEEE TC 2025 [R1]).
- The multi-step / multidimensional NTT (Bailey four-step; Koçer seven-step
  [R3]) factors a large transform into small sub-transforms with cross-twiddles,
  trading interconnect for locality.
- **Gap we fill:** there is no systematic, fully-measured FPGA characterization
  of *how cost scales with decomposition depth d* for the multivariate Fermat
  NTT. We provide it across the entire Fermat-valid (L,d) grid.
- **Contributions (honest):**
  1. A complete, P&R-measured L×d design map (13 configs, N=64…32,768) on U280.
  2. An empirical **constant-hardware-in-d** scaling law, explained
     architecturally.
  3. A **transpose-free** conflict-free banking scheme with O(L) interconnect,
     verified to hold for arbitrary d.
  4. A candid area-time comparison vs SOTA, including where we lose.
- **Explicit non-claims:** not a new algorithm ([R2]); not faster/smaller-ATP
  than SOTA at overlapping N ([R1]); N capped at 32,768 by the modulus.

## 2. Background

- **Negacyclic NTT / twisted convolution.** ψ = 2N-th root; pre-twist by ψⁱ,
  forward NTT, pointwise multiply, inverse NTT, post-twist by ψ⁻ⁱ. [VERIFY]
- **Fermat modulus q = F₄ = 65537.** ord(2)=32 ⇒ an S-point NTT is shift-only
  iff S | 32 ⇒ **S_max = 32**. 2N | (q−1)=65536 ⇒ **N ≤ 32,768** (the hard
  ceiling; state plainly).
- **Multivariate / multi-step factorization.** N = Lᵈ; treat the coefficient
  vector as a d-dimensional L×…×L tensor; L-point NTT along each axis with
  cross-twiddles between axes. The univariate→multivariate ring map is [R2].
- **Prior art and our position** (one paragraph, from `VERIFIED_REFERENCES.md`):
  [R2] introduced the multivariate Fermat NTT (algorithm); [R1] is the SOTA
  iterative FPGA implementation at this modulus; [R3], Wang/Gao, Kurniawan,
  Supranational are the multi-step/banked-NTT lineage. **Our work is the
  implementation+DSE, not the algorithm.**

## 3. Architecture

- **Shared L-lane datapath.** One shift-only L-point bidirectional sub-NTT
  (forward/inverse selectable), one L-lane modular-multiplier array (for
  pre/post-twist, cross-twiddles, and pointwise multiply), time-multiplexed
  across all 2d−1 NTT phases and d−1 cross-twiddle phases. DSP count = L.
- **Conflict-free transpose-free banking** (§19.6 — this is the implementation
  contribution). Bank = (Σ iⱼ) mod L guarantees the L elements along *any* axis
  fall in L distinct banks → single-cycle conflict-free access. Switching the
  swept axis between passes is **pure address remapping** (rpos/rshift); data
  stays in place. Storage = three banked memories total (two operands + one
  in-place scratch); **no corner-turn/transpose buffer**. Interconnect = an
  **L-wide barrel rotation**, not an L×L crossbar.
- **FSM / cycle schedule.** LOAD → (FWD chain A: L0,XTW1,…,L_{d−1}) → (FWD chain
  B) → PWM → (INV chain) → OUTPUT. d-parameterized; the d=2…7 tops are emitted
  by a validated generator (`gen_hier_dN_L4.py`) from one template.
- **Timing-correctness note (brief).** The sub-NTT direction is gated by a
  delayed-state signal so the last issue of each phase is not mis-typed
  (FWD↔INV); see [internal §]. [Keep short — it's a correctness detail, not a
  contribution.]
- **[FIG] Fig.1:** datapath + banked-memory block diagram.

## 4. Methodology

- Device: Xilinx Alveo U280 (`xcu280-fsvh2892-2L-e`); target 4.5 ns.
- Verification: each config tested (identity, zero, X·1, and **random vs a
  reference model** `nvar_ntt_model.py`) — all 13 PASS.
- Cycle model: `cycles ≈ (6d−2)·N/L + 2N + drain(d)`; validated to ≤27 cycles
  against measurement at six depths (d=2…7).
- Reproducibility: RTL generator + generic golden + single synth script
  (`vivado_synth_newcells.tcl`).

## 5. Results

### 5.1 Full measured grid (all 13 Fermat-valid cells)
*(insert the §19.2 table verbatim — U280, 4.5 ns target.)*

### 5.2 Constant-hardware-in-d (the headline) — L=4, d=3→7
| d | N | LUT | DSP | BRAM | Fmax | Time |
|---|---|---|---|---|---|---|
| 3 | 64 | 2,116 | 4 | 7 | 222 MHz | 2.65 µs |
| 4 | 256 | 2,158 | 4 | 7 | 222 MHz | 9.89 µs |
| 5 | 1,024 | 2,305 | 4 | 7 | 222 MHz | 43.0 µs |
| 6 | 4,096 | 2,360 | 4 | 7 | 222 MHz | 195.4 µs |
| 7 | 16,384 | 2,543 | 4 | 25 | 222 MHz | 887.0 µs |

→ **256× N for +20 % LUT, DSP fixed at 4, BRAM flat until N forces more banks.**
**[FIG] Fig.2:** LUT/DSP/BRAM vs N (log x), showing the flat compute curve.

### 5.3 L-sweep at fixed d=3 (cost vs lane width)
| L | N | LUT | DSP | Time | cyc/coef |
|---|---|---|---|---|---|
| 4 | 64 | 2,116 | 4 | 2.65 µs | 9.20 |
| 8 | 512 | 5,452 | 8 | 10.1 µs | 4.40 |
| 16 | 4,096 | 13,320 | 16 | 56.2 µs | 3.05 |
| 32 | 32,768 | 36,539 | 32 | 347 µs | 2.51 |
→ DSP scales exactly as L; LUT ≈ L^1.4; cyc/coef ≈ 16/L + 2.5.

### 5.4 Shift-only vs DSP-based kernel (same N=4096, d=4)
| Kernel | LUT | DSP | Fmax |
|---|---|---|---|
| DSP-based (`sub_ntt_simple`) | 11,040 | 37 | 61 MHz |
| **shift-only bidir** | **5,624** | **8** | **222 MHz** |
→ −49 % LUT, −78 % DSP, 3.6× Fmax. **[FIG] Fig.3 (bar chart).**

## 6. Comparison vs SOTA (honest — §20)

- Head-to-head at the only overlap, N=1024 (Table from §20.1). **[VERIFY Xing
  numbers vs primary PDF.]**
- **State plainly:** Xing [R1] wins time, LUT-ATP, DSP-ATP, throughput, and both
  normalized throughputs. We hold only lower *absolute* LUT/DSP (a minimal-area,
  ~16× slower point) and validated N-reach to 32,768 at the same modulus.
- Do **not** claim an efficiency win. The comparison's purpose is to position the
  design honestly, not to crown it.

## 7. Discussion & Limitations

- **Hard N ceiling = 32,768** under F₄; the large-N (10⁶/10⁹) story requires CRT
  across ≤32 K sub-products or a larger Fermat prime (F₅) — future work.
- Hierarchical decomposition is **not** the efficient choice at small N; a good
  iterative design wins there. Our regime of interest is the *scaling
  characterization* and minimal-footprint corner.
- Single device family (U280); single modulus (F₄). [Optional: add energy and a
  2nd device — G6.]
- Post-route routing-locality metrics (max fanout/net length) are argued
  structurally + via the flat LUT curve; a direct `report_design_analysis`
  figure is a nice-to-have.

## 8. Conclusion

A complete, measured FPGA design-space exploration of the multivariate Fermat
NTT shows that decomposition depth is a near-free scaling knob — compute hardware
stays constant as N = Lᵈ grows — enabled by a transpose-free O(L)-interconnect
banking scheme. We characterize the full Fermat-valid (L,d) grid and compare
candidly against SOTA. The work is a scaling/DSE contribution, not a performance
record; its value is reproducible measurement and architectural insight into
where hierarchical Fermat-NTT decomposition does and does not pay off.

---

## References (verified — see docs/VERIFIED_REFERENCES.md)

- **[R1]** Y. Xing, G. Li, Z. Ye, R. W. L. Luk, D. Chen, H. Yan, R. C. C. Cheung,
  "High-Radix/Mixed-Radix NTT Multiplication Algorithm/Architecture Co-Design
  Over Fermat Modulus," *IEEE Transactions on Computers*, 2025.
- **[R2]** Kim, Mert, et al., "Exploring the Advantages and Challenges of Fermat
  NTT in FHE Acceleration," *CRYPTO 2024* (IACR eprint 2024/314). **[VERIFY full
  author list.]**
- **[R3]** E. Koçer et al., "IO-Optimized Design-Time Configurable Negacyclic
  Seven-Step NTT Architecture for FHE Applications," IACR eprint 2024/1889 /
  GLSVLSI 2025.
- Bailey (1989) four-step FFT; Wang & Gao SAM (2023); Kurniawan et al. (2023);
  Supranational ZPrize; PQShield Kyber NTT; EMINEM (ACM TRETS); CFNTT (TCHES);
  HF-NTT (arXiv 2410.04805). **[VERIFY numbers before citing as comparison.]**

## Figures (generated by `scripts/plot_figures.py` → `docs/figures/`)
- Fig.1 datapath/banking block diagram — **TODO** (hand-drawn / TikZ).
- Fig.2 constant-hardware curve (L=4, d=3→7) — ✅ `fig2_constant_hw_L4.pdf`.
- Fig.3 shift-only vs DSP kernel bar chart — ✅ `fig3_shiftonly_vs_dsp.pdf`.
- Fig.4 ATP vs N (full grid + Xing point) — ✅ `fig4_atp_vs_n.pdf`.

(Regenerate any time with `python scripts/plot_figures.py`; data is the measured
U280 grid embedded in the script. Xing point flagged [VERIFY].)
