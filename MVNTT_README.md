# Multivariate NTT Polynomial Multiplier

Implementation of a 2-D shift-only NTT polynomial multiplier over the Fermat
prime q = 65537 for the negacyclic ring Z_q[X]/(X^256 + 1).

---

## Contents

- [Parameters](#parameters)
- [What Was Implemented](#what-was-implemented)
- [Architecture](#architecture)
- [Simulation Results](#simulation-results)
- [Baseline Comparison](#baseline-comparison)
- [Extending to the True Kim et al. Ring Embedding](#extending-to-the-true-kim-et-al-ring-embedding)

---

## Parameters

| Symbol | Value | Meaning |
|--------|-------|---------|
| N | 256 | Polynomial degree |
| q | 65537 | Fermat prime (2^16 + 1) |
| K | 16 | Fermat parameter |
| L = K/2 | 8 | Row (X1) dimension |
| M = 2N/K | 32 | Column (X2) dimension |
| ψ | 15028 | Primitive 2N-th root of unity mod q |
| ω = ψ² | — | Primitive N-th root of unity mod q |

---

## What Was Implemented

### Algorithm: 2-D Cooley-Tukey NTT (Track A)

The multiplier decomposes the length-N negacyclic NTT into a 2-D schedule over
an L × M grid, using the **row-major index map**:

```
i  =  i1 * M  +  i2,    i1 ∈ [0, L),  i2 ∈ [0, M)
k  =  j1  +  L * j2,    j1 ∈ [0, L),  j2 ∈ [0, M)
```

The factorisation of the negacyclic DFT exponent under this map is:

```
n * (2k + 1)  =  (i1*M + i2) * (2*(j1 + L*j2) + 1)

              =  (i1*M + i2)                    ← pre-twist: ψ^{i1*M + i2}
               + 2*M * i1*j1                    ← row NTT:   ω_L^{i1*j1}
               + 2   * i2*j1                    ← cross-twiddle: ψ^{2*i2*j1}
               + 2*L * i2*j2                    ← col NTT:   ω_M^{i2*j2}
               + 2*N * j1*i2  ≡ 0 (mod 2N)     ← vanishes
```

Each term maps cleanly to a separate hardware stage with no residual cross-terms.
This is the mathematical guarantee that the 2-D schedule is exact.

### Why All Butterfly Twiddles Are Shift-Only

For the Fermat prime q = 2^16 + 1, ord_q(2) = 32. The roots of unity used in
both sub-NTTs happen to be powers of 2:

| Sub-NTT | Root | Value | Representation | Butterfly |
|---------|------|-------|----------------|-----------|
| L = 8 pt row | ω_L = ψ^{2M} = ψ^64 | 4096 = 2^12 | WEXP = 12 | bit-rotate |
| M = 32 pt col | ω_M = ψ^{2L} = ψ^16 | 65529 = −8 = 2^{19} mod q | WEXP = 19 | bit-rotate + negate |

No `mod_mul_fermat` is needed in any butterfly stage. The only modular
multiplications in the design are:

| Stage | Count (parallel) | Cycles |
|-------|-----------------|--------|
| Pre-twist A | 8 lanes × 32 groups = 256 | 32 |
| Cross-twiddle A | 8 lanes × 32 groups = 256 | 32 |
| Pre-twist B | 256 | 32 |
| Cross-twiddle B | 256 | 32 |
| Pointwise multiply | 8 lanes × 32 groups = 256 | 32 |
| Un-twist (inv row) | 256 | 32 |
| **Total mod_mul** | **4 × 256 = 1024** | |

### RTL Files

| File | Role |
|------|------|
| `rtl/bivar_ntt_top.v` | Top-level FSM, memory, datapath |
| `rtl/bivar_ntt_subntt8.v` | Natural-order 8-pt NTT/INTT wrapper |
| `rtl/bivar_ntt_subntt32.v` | Natural-order 32-pt NTT/INTT wrapper |
| `rtl/r2ntt_r8.v` | 8-pt DIT NTT core (WEXP = 12, shift-only) |
| `rtl/r2intt_r8.v` | 8-pt DIF INTT core (WEXP = 12) |
| `rtl/r2ntt_r32.v` | 32-pt DIT NTT core (WEXP = 19, shift-only) |
| `rtl/r2intt_r32.v` | 32-pt DIF INTT core (WEXP = 19) |
| `rtl/mod_mul_fermat.v` | Combinational Fermat multiplier (8 instances) |
| `rtl/twiddle_rom.v` | Lookup ψ^e for e ∈ [0, 2N) |
| `rtl/d1_arith.v` | Diminished-1 arithmetic primitives |
| `rtl/r2_butterfly.v` | Shift-only butterfly (forward) |
| `rtl/r2intt_butterfly_pow2.v` | Shift-only butterfly (inverse, divides by 2) |

### Software Model

`scripts/bivar_ntt_model.py` implements and verifies the algebraic foundation:

- `bivar_multiply_via_fold` — explicit term-by-term fold with X1^L = X2 and
  X2^M = -1 (200 random checks pass).
- `run_bivar_checks` — mapper bijection, K-pt zero-padded linear convolution
  correctness, random campaign.
- `estimate_bivar_cost` — analytic operation count estimator.

---

## Architecture

### FSM Pipeline (14 states)

```
IDLE → LOAD → FWD_ROW_A → FWD_XTW_A → FWD_COL_A
                        → FWD_ROW_B → FWD_XTW_B → FWD_COL_B
                        → PWM
                        → INV_COL → INV_XTW → INV_ROW
                        → OUTPUT → DONE
```

### Memory Layout

| Array | Size | Layout | Contents |
|-------|------|--------|----------|
| `raw_a`, `raw_b` | 256 | `[i1*M + i2]` | Input coefficients |
| `work` | 256 | `[i2*L + j1]` | Post-row-NTT scratch |
| `trans` | 256 | `[j1*M + i2]` | Post-cross-twiddle (transposed) |
| `spec_a`, `spec_b` | 256 | `[j1*M + j2]` | Frequency-domain spectrum |
| `prod` | 256 | `[j1*M + j2]` | Pointwise product |
| `result` | 256 | `[i1*M + i2]` | Final coefficients |

### Datapath Width

8 parallel `mod_mul_fermat` lanes (17-bit each) operate simultaneously on one
row group per cycle. The 8-pt and 32-pt sub-NTTs are fully combinational
(shift-only) and produce outputs in one cycle.

---

## Simulation Results

### How Tests Are Run

The regression script has two independent tiers that run back-to-back:

```
python sim/run_bivar_regression.py --random-count 50
```

**Tier 1 — Software algebraic model** (`scripts/bivar_ntt_model.py`, pure Python,
no RTL). Verifies the mathematical foundations of the bivariate ring embedding
across multiple parameter scales.

**Tier 2 — RTL simulation** (`iverilog` + `vvp`). Compiles all RTL files with the
testbench, streams polynomial pairs into the hardware design, captures all 256
output coefficients, and checks each one against the reference.

For every test case the reference answer is computed by `poly_mul_direct`: a
direct O(N²) negacyclic convolution that multiplies every pair of input terms,
adds them to the correct output index, and subtracts when the sum of indices
wraps past N (the negacyclic rule). This reference has no NTT structure at all
— it is too slow for real use but impossible to get wrong — so any mismatch in
the RTL output is unambiguously a hardware bug.

---

### RTL Test Cases

| Test Case | Polynomials Used | What It Stresses | Coefficients Correct | Cycles |
|-----------|-----------------|-----------------|---------------------|--------|
| impulse | a = δ = [1,0,…,0], b = δ | Trivial identity: δ·δ = δ | 256 / 256 | 760 |
| identity | a = δ = [1,0,…,0], b = random | Multiplying by 1 returns b unchanged | 256 / 256 | 760 |
| zero | a = [0,0,…,0], b = random | All-zero input must give all-zero output | 256 / 256 | 760 |
| all-(q−1) | a = b = [65536,…,65536] | Maximum coefficient value everywhere | 256 / 256 | 760 |
| alternating | a = [1, q−1, 1, q−1,…], b = random | Sign alternation across every coefficient | 256 / 256 | 760 |
| random × 50 | a, b both uniformly random over Z_q | Full arithmetic stress with no structure | 256 / 256 each | 760 |
| **Total** | | | **55 cases, all pass** | |

**Why the first three cases alone are not enough.**

The impulse, identity, and zero cases can pass even when the NTT is completely
wrong. During development, when both the WEXP and the index convention were
broken, these three still showed 256/256 matches:

- **zero**: the input is all zeros, so the output is always all zeros regardless
  of what the transform does.
- **impulse** (δ·δ = δ): only coefficient 0 is non-zero in both inputs and the
  output. A degenerate pipeline that copies coefficient 0 correctly and zeros
  everything else passes trivially.
- **identity** (1·b = b): many broken transforms still return their input
  unchanged when one operand is the multiplicative identity, because the forward
  and inverse transforms cancel out most errors.

The real correctness gate is **random**. With 256 output coefficients each drawn
from Z_{65537}, the probability that a broken hardware result matches the correct
answer by accident is (1/65537)^256 ≈ 10^{−1240}. A single passing random case
is effectively impossible without a correct implementation. Running 50
independent random cases (different seeds, no shared structure) makes any
residual doubt negligible.

**What the hard cases specifically stress:**

- **all-(q−1)**: every coefficient equals q−1 ≡ −1 mod q. Every product term is
  (−1)·(−1) = 1, and there are N=256 such terms per output coefficient. This
  saturates the modular arithmetic at maximum magnitude, exposing overflow bugs
  in `mod_mul_fermat` or incorrect reduction in the butterfly adders.
- **alternating**: a = [1, −1, 1, −1, …]. This pattern has its energy
  concentrated at frequency N/2, which exercises the mid-frequency twiddle
  factors specifically. Any off-by-one in the twiddle exponent computation shows
  up here before it would show up in random data.

---

### Cycle Count Breakdown

| Stage | Cycles | Detail |
|-------|--------|--------|
| LOAD | 256 | One coefficient streamed in per cycle (N=256 total) |
| FWD_ROW_A | 32 | Pre-twist + 8-pt NTT, M=32 row groups × 1 cycle/group |
| FWD_XTW_A | 32 | Cross-twiddle ψ^{2·i₂·j₁}, M=32 groups × 1 cycle/group |
| FWD_COL_A | 8 | 32-pt NTT, L=8 column groups × 1 cycle/group |
| FWD_ROW_B | 32 | Same as FWD_ROW_A for polynomial B |
| FWD_XTW_B | 32 | Same as FWD_XTW_A for polynomial B |
| FWD_COL_B | 8 | Same as FWD_COL_A for polynomial B |
| PWM | 32 | Pointwise multiply, L=8 lanes × M=32 cycles |
| INV_COL | 8 | Inverse 32-pt INTT, L=8 column groups |
| INV_XTW | 32 | Inverse cross-twiddle, M=32 groups |
| INV_ROW | 32 | Inverse 8-pt INTT + un-twist, M=32 row groups |
| OUTPUT | 256 | One coefficient streamed out per cycle (N=256 total) |
| **Total** | **760** | |

Each of the NTT stages (FWD_ROW, FWD_COL, INV_COL, INV_ROW) takes one clock
cycle per group because the sub-NTT cores (`bivar_ntt_subntt8`,
`bivar_ntt_subntt32`) are fully combinational — all butterfly stages are just
wire routing with bit-rotates and conditional negations, no registered pipeline
stages. The multiplier stages (FWD_XTW, PWM, INV_XTW, INV_ROW un-twist) also
take one cycle per group because `mod_mul_fermat` is combinational with a
single-cycle result registered at the output.

---

### Model Tier Results (Python algebraic model)

The model tier tests the **mathematical correctness of the bivariate ring
embedding** in pure software, independently of any RTL. It runs before the RTL
tier every time the regression is invoked.

The notation `pair=N:K` means: test the bivariate embedding for a polynomial of
degree N using Fermat parameter K (where q = 2^K+1). The derived dimensions are
L = K/2 and M = N/L, and `active` confirms that L×M = N (the basis is
bijective).

```
model pair=16:8  PASS  L=4  M=4   active=16
model pair=32:8  PASS  L=4  M=8   active=32
model pair=256:16 PASS  L=8  M=32  active=256
```

For each pair, `run_bivar_checks` (in `scripts/bivar_ntt_model.py`) runs three
independent checks:

**Check 1 — Mapper round-trip.**
Maps a random length-N polynomial into the L×M bivariate tensor and back.
Confirms the index map `i = i2·L + i1` is a bijection with no lost or
duplicated coefficients.

**Check 2 — K-pt zero-padded linear convolution (8 random pairs per pair).**
Takes two random L-element sequences, zero-pads each to length K=2L, runs a
K-pt cyclic NTT, multiplies pointwise, runs the inverse NTT, and checks the
result equals the direct linear convolution. This validates that a zero-padded
K-pt NTT correctly computes linear (not cyclic) convolution — the property
required by the fold rule `X1^L = X2`.

**Check 3 — Full polynomial multiplication via fold (200 random pairs per pair).**
For each pair of random length-N polynomials, computes the product using
`bivar_multiply_via_fold` (explicit term-by-term fold with `X1^L → X2` and
`X2^M = -1` rules) and compares against `poly_mul_direct`. This is the core
proof that the Kim et al. algebraic ring embedding produces the correct
negacyclic polynomial product.

The three parameter pairs are chosen deliberately:

| Pair | N | K | L | M | Purpose |
|------|---|---|---|---|---------|
| 16:8 | 16 | 8 | 4 | 4 | Small N: exhaustive coefficient-level checks possible |
| 32:8 | 32 | 8 | 4 | 8 | Intermediate: asymmetric L≠M grid |
| 256:16 | 256 | 16 | 8 | 32 | Full hardware scale: matches RTL parameters exactly |

The small-N pair (16:8) runs an additional exhaustive sweep over all coefficient
value combinations (limited to a small range) to eliminate any sampling bias in
the random checks. The full-scale pair (256:16) uses 200 random polynomials
with values uniformly distributed over all of Z_{65537}, matching the RTL's
operating conditions exactly.

---

## Baseline Comparison

Synthesis results on Xilinx Virtex-7 (xc7k160t-fbg484-2), N=256, q=65537.
The baseline is the existing monolithic mixed-radix `ntt_top`.

| Metric | `ntt_top` R=4 | `ntt_top` R=8 | `ntt_top` R=16 | `bivar_ntt_top` |
|--------|--------------|--------------|---------------|-----------------|
| Butterfly mod_mul | Yes | Yes | Yes | **None** |
| Cycles | 876 | 389 | 197 | 760 |
| LUT | 3,763 | 9,282 | 20,008 | not yet synthesized |
| DSP | 16 | 32 | 64 | not yet synthesized |
| Fmax (MHz) | 44 | 34 | 28 | not yet synthesized |

The key structural difference: `bivar_ntt_top` uses **zero DSPs for NTT
butterfly stages**. All butterfly multiplications are single-cycle bit-rotates
or conditional negations in D1 representation. DSPs are used only for the 8
`mod_mul_fermat` lanes (pre-twist, cross-twiddle, PWM, un-twist).

---

## Extending to the True Kim et al. Ring Embedding

### What Is Different

The current RTL implements a standard 2-D Cooley-Tukey decomposition. It
reorganizes the computation of a length-N negacyclic NTT but stays in the same
ring. The Kim et al. approach is fundamentally different: it **embeds the
univariate polynomial ring into a bivariate ring**:

```
Z_q[X] / (X^N + 1)   →   Z_q[X1, X2] / ⟨X1^L − X2,  X2^M + 1⟩
```

via the substitution X2 = X1^L. The two defining relations are:

```
X1^L = X2           (fold rule: X1 carries into X2 at degree L)
X2^M = -1           (negacyclic rule in X2 only)
```

Under this embedding, the active coefficient basis is:

```
{ X1^i1 · X2^i2  |  i1 ∈ [0, L),  i2 ∈ [0, M) }     L · M = N
```

Crucially, **products in X1 that reach degree L are not cyclic-wrapped** —
they are folded into the next X2 degree via the fold rule. This means the X1
direction requires **linear convolution**, not cyclic.

### Why the Current RTL Is Not This

The current `bivar_ntt_top.v` uses:
- L=8 pt **cyclic** NTTs in the row direction (pre-twist converts negacyclic
  to cyclic, then cyclic NTT)
- M=32 pt **cyclic** NTTs in the column direction

Kim et al. would use:
- K=16 pt **zero-padded** NTTs in the X1 direction (L=8 non-zero inputs,
  L=8 zero-padding → implements linear convolution of degree ≤ 2L−2 = 14)
- M=32 pt **negacyclic** NTTs in the X2 direction (X2^M = -1 directly,
  no pre-twist needed in X1)

The fold rule means that terms with X1 degree a1+b1 ≥ L from the row
multiplication get assigned to the X2 slot (i2+1) instead, with negacyclic
wrap at X2^M = -1. This is what `bivar_multiply_via_fold` in
`scripts/bivar_ntt_model.py` computes correctly.

### RTL Changes Required

**1. Replace `bivar_ntt_subntt8` with a K=16 pt zero-padded NTT**

The row NTT must be K=16 pt with only the lower L=8 lanes active:

```verilog
// Zero-pad L=8 inputs to K=16 before feeding r2ntt_r16
wire [K*WWIDTH-1:0] row_in_padded;
assign row_in_padded[0 +: L*WWIDTH]       = pre_twisted_row;  // 8 active
assign row_in_padded[L*WWIDTH +: L*WWIDTH] = {L*WWIDTH{1'b0}}; // 8 zeros

bivar_ntt_subntt16 u_row_ntt (  // K=16 pt, WEXP=6 (ω16 = ψ^32 = 2^6)
    .inverse  (inverse_row),
    .in_norm  (row_in_padded),
    .out_norm (row_out_k16)     // 16 frequency values
);
```

The 16-pt root ω₁₆ = ψ^{32} = 64 = 2^6 (WEXP=6) is already implemented
in `rtl/r2ntt_r16.v`.

**2. Add fold/carry logic after the row NTT**

The K=16 frequency-domain values split into two halves. The upper half
(indices L..K-1) represents the contribution of degree-≥-L products, which
fold into the X2 direction:

```verilog
// Lower half [0..L-1]: direct contribution to current i2 slot
// Upper half [L..K-1]: fold → add to the i2+1 slot with implicit X2 carry
for (ci = 0; ci < L; ci = ci + 1) begin
    work_lo[i2*L + ci] <= row_out_k16[ci*WWIDTH +: WWIDTH];
    work_hi[i2*L + ci] <= row_out_k16[(ci+L)*WWIDTH +: WWIDTH];
end
// After all rows processed, combine:
// work[i2][j1] = work_lo[i2][j1] + fold(work_hi[i2-1][j1])
// with negacyclic wrap at i2=0 (work_hi[-1] → negate)
```

**3. Eliminate the X1 pre-twist**

Under the ring embedding, polynomial coefficients are placed directly into the
bivariate tensor — there is no negacyclic pre-twist in the X1 direction because
the ring structure (X2^M = -1) already encodes the negacyclic property.

The X2-direction negacyclic property is handled by the M=32 pt column NTT
itself (no separate pre-twist column is needed).

**4. Update the column NTTs to negacyclic M=32 pt**

The column NTTs operate directly on the negacyclic ring in X2. The twiddles
are ψ^{2i2+1} per element (the standard negacyclic pre-twist absorbed into the
column NTT indexing), which uses ω_M = ψ^{16} = 2^{19} mod q — the same WEXP=19
already implemented in `rtl/r2ntt_r32.v`.

### Why the Ring Embedding Version Matters

**1. Mathematically cleaner decomposition**

Standard 2-D NTT reorganizes the same negacyclic computation. The ring
embedding genuinely changes the algebraic structure so that:
- The X1 direction has **no negacyclic wrap at all** (only fold via X1^L = X2)
- The negacyclic property lives entirely in X2 (X2^M = -1)

This separation of concerns simplifies the twiddle structure and makes the
hardware stages more orthogonal.

**2. Elimination of pre-twist in one dimension**

Standard Track A requires N=256 pre-twist multiplications and N=256 un-twist
multiplications. In the true ring embedding:
- X1-direction pre-twist is **not needed** (the ring handles it algebraically)
- Only the X2-direction requires negacyclic handling

This removes one full pass of N mod_mul operations from both forward and
inverse paths.

**3. Generalisability to larger N without multiplier explosion**

For large N (e.g. N = 2^14 for FHE), standard 2-D NTT still requires
O(N log N) twiddle multiplications. The ring embedding decomposes the problem
so that the twiddle overhead grows with the sub-transform sizes (L and M)
rather than with N directly, making it more amenable to hierarchical reuse.

**4. Hardware resource saving at scale**

Because the fold rule replaces what would otherwise be a cyclic wrap (requiring
additional mod_mul to apply the negacyclic sign flip), the ring embedding avoids
these multiplications entirely for the X1 dimension. At N=256, L=8, M=32, the
saving is modest. At N=2^15, L=128, M=256, the saving becomes substantial.

**5. The true architectural novelty of Kim et al.**

The paper's claim is not merely that twiddles are powers of 2 (which Track A
also achieves for this Fermat prime). The claim is that the **bivariate ring
structure itself** enables a decomposition that is impossible in a standard
2-D NTT: you can multiply two polynomials without ever performing an L-point
negacyclic NTT. The fold rule replaces it with a simpler linear-convolution
step whose output is smaller (degree ≤ 2L−2 < 2L) and can be zero-padded to
K=2L and processed with a cyclic K-pt NTT — the simplest possible kernel.

In short: the ring embedding version would use **fewer twiddle multiplications,
no X1 pre-twist, and would generalise more cleanly to parameter sets where the
shift-only property might not hold for a standard 2-D decomposition**.

### Verification Path for the Ring Embedding RTL

The software proof already exists. `scripts/bivar_ntt_model.py` correctly
implements and verifies the algebraic fold approach for N=256, K=16 with 200
random polynomial pairs. The steps to extend this to RTL are:

1. Instantiate `r2ntt_r16` / `r2intt_r16` (already in `rtl/`) for the K=16
   row NTTs — these use WEXP=6 (ω₁₆ = 2^6) and are already shift-only.
2. Add fold-combine logic (a single pass of additions and conditional negations,
   no multipliers).
3. Reuse `bivar_ntt_subntt32` unchanged for the M=32 column NTTs.
4. Remove the X1 pre-twist stage from the FSM.
5. Validate against `run_bivar_regression.py` (same testbench, same reference).
