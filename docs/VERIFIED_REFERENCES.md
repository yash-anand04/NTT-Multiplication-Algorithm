# Verified References & Claim Hygiene (source of truth)

**Purpose.** This file is the *authoritative* citation list and claim-correction
record for the project. It exists to stop recurring confusion (wrong author
names, retired performance claims, false novelty). **When any other doc
disagrees with this file, this file wins.** Verified via web search on
2026-05-28; re-verify author lists / exact numbers against the primary PDFs
before submission.

---

## 1. Verified primary references

### [R1] Xing et al. — the direct same-modulus competitor ⭐
- **Title:** "High-Radix/Mixed-Radix NTT Multiplication Algorithm/Architecture
  Co-Design Over Fermat Modulus."
- **Authors:** Yile **Xing**, Guangyan Li, Zewen Ye, Ryan W. L. Luk, Donglong
  Chen, Hong Yan, Ray C. C. **Cheung**.
- **Venue:** IEEE Transactions on Computers (TC), 2025. IEEE Xplore doc 11086417.
- **What it is:** high-radix/mixed-radix NTT over Fermat modulus (q = 2ᵏ+1,
  incl. 65537) on FPGA; reports 30–85 % DSP-area×time and 70–100 % BRAM-area×time
  reduction vs prior designs. Measured to N=1024 in our extracted numbers.
- **Cite as:** **"Xing et al. (IEEE TC 2025)."**
- ⚠️ **Naming hazard (the confusion this file fixes):** older project notes call
  this **"Cheung et al."** (Cheung is the senior/last author). It is the **same
  paper** as "Xing et al." — *not* a second work. Always cite by first author:
  **Xing et al.**

### [R2] Kim, Mert et al. — the core-idea prior art ⚠️ NOVELTY-CRITICAL
- **Title:** "Exploring the Advantages and Challenges of Fermat NTT in FHE
  Acceleration."
- **Authors:** Kim, Mert, et al. (confirm full list from PDF).
- **Venue:** CRYPTO 2024 (Springer LNCS); IACR eprint **2024/314**.
- **What it is:** a **multiplier-less NTT using a Fermat number as auxiliary
  modulus**, made scalable by a **univariate-to-multivariate polynomial-ring
  transformation**; ~1,200× speed-up vs software for HE benchmarks.
- ⚠️ **This is the single biggest prior-art overlap.** The project's headline
  framing — *"multivariate" Fermat-modulus NTT with shift-only (multiplier-less)
  butterflies* — is **exactly what [R2] introduced in 2024.** The univariate→
  multivariate ring map and the shift-only Fermat property are **theirs, not
  ours.** Cite [R2] and do **not** claim either as a contribution.

### [R3] Koçer et al. — closest architectural sibling
- **Title:** "IO-Optimized Design-Time Configurable Negacyclic Seven-Step NTT
  Architecture for FHE Applications" (also: E. Koçer, MSc thesis "Hierarchical
  NTT Architectures on FPGA," Sabancı University).
- **Venue:** IACR eprint **2024/1889**; GLSVLSI 2025.
- **What it is:** hierarchical **7-step** negacyclic NTT on FPGA; ~7.96× latency
  speed-up vs SOTA at ring size 2¹⁶ (64-bit). This is the closest published
  *hierarchical/multi-step NTT FPGA* design to ours.
- **Cite as:** "Koçer et al. (2024/2025)."

### [R4] Adjacent FPGA NTT designs (relevant, surfaced 2026-05-28; verify numbers)
- **EMINEM** — "Efficient FPGA Implementation of Mixed-Radix NTT … for Falcon,
  Dilithium, HAWK," ACM TRETS.
- **CFNTT** — "Scalable Radix-2/4 NTT Multiplication Architecture with an
  Efficient Conflict-free Memory Mapping Scheme," IACR TCHES. (Directly relevant
  to our conflict-free banking claim.)
- **HF-NTT** — "Hazard-Free Dataflow Accelerator for NTT," arXiv 2410.04805.
- "High-Performance Pipelined NTT Accelerators with Homogeneous Digit-Serial
  Modulo Arithmetic," arXiv 2507.12418.
- "FPGA based high speed parallel modular polynomial multiplier for lattice
  based cryptosystems," ScienceDirect 2025.

### [R5] Carried over from the prior survey — REAL but numbers UNVERIFIED
These appear in `docs/deep-research-report.md` with auto-generated `【NN†Lxx】`
markers (a research-tool artifact, **not** a real citation anchor — ignore them).
The works are real; the exact LUT/DSP/Fmax figures must be re-checked against the
primary sources before any are cited:
- PQShield Kyber NTT (q=3329, N=256).
- Supranational "Nantucket" ZPrize NTT (U250-class, N=2²⁴, HBM).
- Wang & Gao "SAM" (2023) — multi-dimensional FPGA NTT.
- Kurniawan et al. (2023) — memory-based conflict-free NTT.
- Bailey (1989) — four-step FFT (the algorithmic ancestor of all multi-step NTT).

---

## 2. Claims that are RETIRED or WRONG (do not repeat)

| Claim that appears in older docs | Status | Correct statement |
|---|---|---|
| "Practical at N up to 10⁹ / 10⁶ on-chip, HBM-streaming" | **RETIRED** | F₄ caps N at **32,768** (2N must divide q−1 = 65 536). No ψ exists above that. Large N needs CRT or a bigger Fermat prime — out of scope. |
| "Level-boundary cross-twiddle ψ^(j·32) = (−1)^j saves 8 DSPs/boundary" | **WRONG** | Only holds for N ≤ 32 (`IMPLEMENTATION_PLAN.md` §10.6). Does not apply to our N; saved cycles, not DSPs, even where it would. |
| "We contribute the multivariate / Fermat shift-only NTT algorithm" | **NOT A CONTRIBUTION** | Multivariate Fermat NTT = [R2] Kim et al. 2024; shift-only FNT is decades old; multi-step NTT = Bailey 1989 / Koçer [R3]. |
| "Cheung et al. (2025)" as a paper distinct from "Xing et al." | **SAME PAPER** | One paper [R1]; cite as Xing et al. |
| "Hierarchical beats monolithic at our N (the original thesis)" | **NOT WINNABLE at F₄'s N≤32K** | A competent iterative design ([R1]) beats us on LUT/time at N≤1024; a flat N=32K NTT fits fine on U280. Do not build a strawman home-monolithic comparison. |

## 3. What we MAY legitimately claim (design-study framing)

A **measured FPGA design-space exploration** of a multivariate Fermat NTT
(algorithm from [R2]), specifically:
1. Constant compute hardware (LUT flat, DSP=L) as decomposition depth d grows
   (measured d=2…7 at L=4) — a *measurement*, not an algorithm.
2. A complete L×d ATP design map, N = 64…32 768 (all 13 F₄-valid cells).
3. Shift-only bidir kernel beating our own DSP-based variant (measured).
4. Transpose-free conflict-free banking for arbitrary d (verified, §19.6).

⚠️ **CORRECTION (2026-05-28) — DO NOT claim a DSP-ATP win over Xing.** An earlier
note here claimed "DSP-area×time is where shift-only wins." **That is false.**
Computed head-to-head at the only overlap (N=1024, `scripts/compare_metrics.py`):
Xing [R1] **wins every area-time-efficiency metric** — time (2.6 µs vs our
13.8/43 µs), LUT-ATP, **DSP-ATP** (~42 vs our 172–442 DSP·µs), throughput, and
both normalized throughputs. We only have lower **absolute** LUT (2,305 vs 9,783)
and **absolute** DSP (4 vs 16) — because our cell is smaller *and ~16× slower*.
**The honest framing is NOT a head-to-head efficiency win.** Our claimable value
is (a) the systematic DSE + constant-hardware-in-d scaling law, (b) demonstrated
operation to N=32,768 at the same modulus (a regime [R1] did not report), and
(c) the lowest *absolute* resource footprint (4 DSP) for area-constrained,
latency-tolerant use. Report the comparison honestly; do not cherry-pick a metric.

---

*Maintained as the project's citation source of truth. Update here first, then
propagate. Re-verify all author lists and numeric figures against primary PDFs
before submission.*
