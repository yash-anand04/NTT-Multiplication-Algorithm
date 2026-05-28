# Comprehensive Peer Review Evaluation

**Manuscript Title:** A Measured Design-Space Exploration of Multivariate Fermat-Modulus NTT on FPGA: Constant-Hardware Scaling in Decomposition Depth  
**Reviewer Recommendation:** Major Revision (Suitable for high-quality IEEE Transactions/Conferences after addressing architectural and formatting gaps)  
**Confidence Level:** High (Expertise in RTL design, FPGA acceleration, and NTT/Polynomial Multiplication architectures)

---

## 1. Executive Summary
The manuscript presents a comprehensive, post-route design-space exploration of a multivariate Number-Theoretic Transform (NTT) implementation over a Fermat-prime modulus ($q = 2^{16} + 1$) on a Xilinx Alveo U280 FPGA. The authors sweep across sub-transform lane widths ($L \in \{4, 8, 16, 32\}$) and decomposition depths ($d \in \{2, \dots, 7\}$) across 13 valid configurations where the problem size $N = L^d \le 32768$. 

The core architectural claim is a **constant-hardware scaling law**: at a fixed lane width, logic (LUT) and multiplier (DSP) utilization remain virtually flat as the decomposition depth $d$ (and consequently the problem size $N$) scales. This behavior is attributed to a time-multiplexed shared datapath combined with a transpose-free, conflict-free memory banking mechanism that relies on an $O(L)$ barrel shifter rather than a full crossbar. The paper also includes a highly transparent head-to-head comparison with a state-of-the-art iterative Fermat-modulus NTT accelerator, noting that the hierarchical design is less area-time efficient at small sizes but offers unique scaling properties and a minimal absolute footprint.

---

## 2. Key Technical Strengths
* **Rigorous Empirical Grounding:** Unlike many high-level synthesis or theoretical hardware papers, this work carries all 13 configurations completely through the physical design pipeline (synthesis, placement, and routing) to achieved timing closure on an industrial Alveo U280 board. This provides highly reliable hardware metrics ($F_{max}$, LUT, FF, BRAM) instead of pre-layout estimates.
* **Effective Memory Architecture:** The use of the conflict-free index mapping formula $b(i) = (\sum_{j=0}^{d-1} i_j) mod L$ effectively resolves the classical multi-step FFT/NTT corner-turn problem. By eliminating the need for a secondary transpose ping-pong buffer or an $O(L^2)$ crossbar interconnect, the authors successfully bound the routing overhead to a fixed-width barrel shifter.
* **Candid and Objective Evaluation:** Section VI provides an admirable, low-bias comparison with prior work (Xing et al. [6]). Acknowledging that the proposed architecture is outpaced on area-time product (ATP) at $N=1024$ shows academic integrity and accurately delineates the specific engineering envelope where a hierarchical time-multiplexed approach is advantageous (minimal absolute footprint and wide scaling vs. high-throughput streaming).

---

## 3. Major Technical Concerns & Analysis Gaps

### A. The "Constant-Hardware" Misnomer and Memory Underutilization
The central thesis emphasizes "constant-hardware scaling in decomposition depth." While this holds true for logic primitives (LUTs and DSPs), it masks a critical aspect of FPGA resource allocation regarding Block RAMs (BRAMs).
* **BRAM Quantization Effects:** In Table I and Table II, for $L=4$, the BRAM utilization stays locked at exactly **7 tiles** for $N=64, 256, 1024,$ and $4096$, before jumping sharply to **25 tiles** at $N=16384$. 
* **Physical Reality:** A single Xilinx BRAM36 can store 36 Kbits. At $N=64$ with a 17-bit coefficient representation ($q = 2^{16}+1$), the data storage requirement for three arrays (two operands + one in-place buffer) is a meager $3 	imes 64 	imes 17 = 3.26	ext{ Kbits}$. The fact that it consumes 7 tiles at $N=64$ is a direct artifact of hardware quantization—specifically, needing $L=4$ independent memory banks plus additional ROMs for twiddle factors. 
* **Reviewer Critique:** The flat resource curve for small $N$ is not an architectural choice but rather an artifact of underutilization. At small sizes, the design is severely padded by the minimum allocation quantum of the hardware. The authors should explicitly analyze memory utilization efficiency (bits used vs. bits allocated) to clarify this trend.

### B. Scalability Bounds and Practical Post-Quantum/FHE Context
* **Hard Ceiling at $N \le 32768$:** The chosen Fermat modulus $q = 2^{16}+1$ restricts the maximum transform length due to the primitive root constraint ($2N \mid q-1$). Modern Fully Homomorphic Encryption (FHE) parameters require polynomials of degree $N = 2^{13}$ to $2^{16}$ *per residue channel*, frequently scaling to mega-point multi-ring contexts. 
* **Algorithmic Limitation:** While the paper notes that Residue Number System (RNS) decomposition is out of scope, the lack of discussion on how this single-engine block scales inside a multi-channel RNS framework weakens its relevance to practical FHE workloads. If the engine is fundamentally capped at $32	ext{K}$, its primary utility shifts exclusively to lower-parameter lattice cryptography (e.g., Kyber/Dilithium, which use much smaller $N$), where iterative high-throughput engines like Xing et al. already dominate.

### C. Algorithmic Novelty vs. Prior Art
The authors explicitly state, *"We make no claim to a new algorithm."* However, the exact boundary between their work and Kim et al. (2024) [5] needs tighter definition. Is the banking formula $b(i) = (\sum i_j) mod L$ a direct port of Kim's univariate-to-multivariate mapping, or is it an independent optimization developed for this design space? If it is a direct port, the architectural novelty is thin, shifting the paper's weight entirely onto the sweep results.

---

## 4. Minor Issues, Structural Faults, and Typos

### A. Severe Table I Layout & Data Inconsistencies
Table I contains major data-entry anomalies and formatting structural shifts in its first column, which severely impacts legibility:
* **Inconsistent Column Packing:** In the first column (labeled `"Ld"`), the parameter encoding shifts arbitrarily:
  * Rows 1-3 use a combined single token or space-separated layout: `"82"` (presumably $L=8, d=2$), `"16 2"`, and `"32 2"`.
  * Rows 4-7 suddenly **invert the order** to $d$ then $L$: `"3 4"` ($d=3, L=4$), `"83"` ($L=8, d=3$), `"16 3"`, and `"3 32"` ($d=3, L=32$).
  * Rows 8-13 alternate unpredictably: `"44"` ($L=4, d=4$), `"8 4"` ($L=8, d=4$), `"5 4"` ($d=5, L=4$), `"5 8"` ($d=5, L=8$), `"6 4"` ($d=6, L=4$), and `"7 4"` ($d=7, L=4$).
* **Correction Required:** The authors must split `"Ld"` into two distinct columns: **Lane Width ($L$)** and **Decomposition Depth ($d$)**, sorting the rows sequentially by either $N$ or $L$ to eliminate this confusing mix.

### B. Cycle Count Formulation vs. Table Data
In Section IV, Equation (2) defines the cycle count model:
$$	ext{cycles}(d, N) pprox (6d - 2)rac{N}{L} + 2N + 	ext{drain}(d)$$
Let us verify this model for $L=4, d=5, N=1024$:
$$	ext{cycles} pprox (6(5) - 2)rac{1024}{4} + 2(1024) = 28 	imes 256 + 2048 = 7168 + 2048 = 9216$$
Table I lists the actual cycle count for this configuration as **9565**. This leaves a remainder of **349 cycles** for $	ext{drain}(d)$. 
* **Critique:** The paper states Equation (2) matches the simulation to *"within 27 cycles at every measured depth."* A $	ext{drain}(d)$ component that accounts for 349 cycles is significantly larger than 27 cycles. The text must explicitly define the analytical function or bounded range for $	ext{drain}(d)$ rather than treating it as an unquantified curve-fitting parameter.

### C. Micro-formatting and Text Anomalies
* **Source 120 (Table II):** In row 4, the number of coefficients is written as `"4.096"` instead of `"4096"` or `"4,096"`. The period creates a false decimal interpretation.
* **Source 121 (Table III):** For $L=32, N=32768$, the LUT count is listed as `"36.539"`. This should be formatted consistently with other large entries (e.g., `"36 539"` or `"36539"`) to prevent confusion with floating-point values.

---

## 5. Actionable Recommendations for Revision

1. **De-couple 'Hardware' into Logic and Memory:** Revise the "constant-hardware" phrasing in the title or abstract to read *"Constant Logic and Interconnect Scaling."* This provides a more scientifically accurate description that acknowledges that memory capacity ($N$) scales while compute resources ($L$) remain invariant.
2. **Add a Memory Efficiency Metric:** Introduce a column or short discussion in Section V evaluating Memory Bit Efficiency:
   $$\eta_{	ext{mem}} = rac{3 	imes N 	imes 17}{	ext{BRAM Capacity Allocated}}$$
   This will elegantly explain why the BRAM footprint stays flat at 7 tiles before scaling out.
3. **Formalize the $	ext{drain}(d)$ Parameter:** Provide a small expression or bounded explanation for the pipeline drain overhead to support Equation (2).
4. **Fix Table I Layout:** Re-structure the table with distinct columns for $L$ and $d$, and standardize the numeric representations (remove accidental decimals/periods from `4.096` and `36.539`).
