# Multivariate / 2-D NTT Multiplier - Corrected Implementation Plan

This document corrects the implementation strategy for a 2-D / multivariate NTT
polynomial multiplier over the negacyclic ring

\[
\mathbb{Z}_q[X]/\langle X^N + 1 \rangle .
\]

## 0) Viability Verdict

The strategy is **viable**, but the previous version was **not precise enough to
implement safely**.

The main issue is that two different ideas were being mixed:

1. **A standard 2-D Cooley-Tukey schedule for an \(N\)-point twisted NTT**.
   This is mathematically clean and should be the first implementation track.
2. **A paper-style algebraic embedding using \(X_2 = X_1^{K/2}\)**.
   This can be researched, but it is not the same as a normal
   \((2N/K) \times K\) dense tensor. If interpreted literally, it creates
   \(2N\) tensor slots for only \(N\) coefficients and the mapper is not a
   simple bijection.

Recommended decision:

- **Implement Track A first**: standard 2-D decomposition of the twisted
  negacyclic NTT. This validates the mapper, transpose, banking, and reuse of
  the existing NTT core without introducing algebraic ambiguity.
- **Treat Track B as a later research extension**: only proceed after a Python
  model proves the \(X_2=X_1^{K/2}\) embedding, the high-degree carry/fold logic,
  and the inverse mapping.

---

## 1) Parameters and Hard Constraints

### 1.1 Track A - Recommended First RTL Target

Use a normal 2-D factorization of the length-\(N\) NTT:

\[
N = K \cdot M,\qquad M = N/K .
\]

Where:

- \(N\): negacyclic polynomial degree, power of two.
- \(K\): X1 / row transform size, power of two.
- \(M\): X2 / column transform size.
- Tensor shape: \(M \times K\).
- Total tensor entries: \(MK=N\), so the map is bijective.

This track does **not** require an auxiliary Fermat modulus or domain switching
just to be correct. CRT/RNS is only needed if the chosen modulus set requires it.

### 1.2 Track B - Paper-Style \(X_2=X_1^{K/2}\) Research Target

If you pursue the diagram's embedding, define

\[
L = K/2,\qquad M = 2N/K = N/L .
\]

Then the valid active basis is:

\[
X^i \mapsto X_1^{i_1}X_2^{i_2},
\qquad i = i_1 + L i_2,
\qquad 0 \le i_1 < L,\quad 0 \le i_2 < M .
\]

This gives \(LM=N\) active coefficients. A full \(M \times K\) buffer may still
be used internally, but only \(K/2\) X1 positions are active before row
multiplication. The length-\(K\) X1 NTT is then a **zero-padded linear
convolution engine**, not a proof that the logical tensor has \(K\) independent
columns.

The algebraic relations that must be modeled are:

\[
X_1^L = X_2,\qquad X_2^M = -1 .
\]

After multiplying along the X1 dimension, terms with X1 degree \(d \ge L\) must
be folded by:

\[
X_1^d X_2^{i_2}
= X_1^{d-L} X_2^{i_2+1},
\]

with negacyclic wrap when \(i_2+1=M\):

\[
X_2^M=-1 .
\]

This carry/fold path is the part that makes Track B substantially riskier than
Track A.

### 1.3 Modulus Strategy

For Track A, choose \(q\) such that a primitive \(2N\)-th root exists:

\[
2N \mid (q-1).
\]

Let:

\[
\psi = \text{primitive }2N\text{-th root},\qquad
\omega=\psi^2 .
\]

Then \(\omega\) is a primitive \(N\)-th root used for the cyclic NTT after the
negacyclic pre-twist.

Example:

- \(q=65537\), \(q-1=2^{16}\).
- Supports \(2N \le 2^{16}\), so \(N \le 2^{15}\).

For Track B, the implementation needs roots for the length-\(K\) X1 NTT and the
length-\(M\) negacyclic X2 dimension. For power-of-two parameters with \(K\ge2\),
the Track A condition \(2N\mid(q-1)\) is a conservative sufficient condition.

---

## 2) Correct Track A Math Specification

This is the implementation path to use first.

### 2.1 Twisted Negacyclic NTT

To multiply in \(\mathbb{Z}_q[X]/(X^N+1)\), first convert each input polynomial
to a cyclic NTT by twisting:

\[
b_i = a_i \psi^i .
\]

Then compute the ordinary \(N\)-point NTT of \(b\) using
\(\omega=\psi^2\). The inverse performs an inverse cyclic NTT followed by:

\[
a_i = b_i \psi^{-i}.
\]

Apply \(N^{-1}\) exactly once unless the inverse sub-NTT kernels already include
their own \(K^{-1}\) and \(M^{-1}\) scaling.

### 2.2 2-D Index Map

Use the decimation-in-time row-first map:

\[
i = i_1 M + i_2,
\qquad 0 \le i_1 < K,\quad 0 \le i_2 < M .
\]

Store the tensor as:

\[
A[i_2][i_1] = a[i_1M+i_2]\psi^{i_1M+i_2}.
\]

Important: if you instead store \(i=i_2K+i_1\), the twiddle formulas below
change. Do not mix the formulas with a different mapper.

### 2.3 Forward 2-D NTT

Define:

\[
\omega_K = \omega^M,\qquad \omega_M=\omega^K .
\]

1. **K-point row NTTs**

\[
R[i_2][j_1]
= \sum_{i_1=0}^{K-1} A[i_2][i_1]\omega_K^{i_1j_1}.
\]

2. **Cross twiddle**

\[
C[i_2][j_1] = R[i_2][j_1]\omega^{i_2j_1}.
\]

3. **M-point column NTTs**

\[
Y[j_1][j_2]
= \sum_{i_2=0}^{M-1} C[i_2][j_1]\omega_M^{i_2j_2}.
\]

4. **Frequency index**

\[
j = j_1 + K j_2 .
\]

This gives the same result as the length-\(N\) twisted NTT.

### 2.4 Inverse 2-D NTT

Reverse the exact schedule:

1. Load \(Y[j_1][j_2]\).
2. Run inverse \(M\)-point NTTs along the X2 dimension.
3. Multiply by the inverse cross twiddle:

\[
\omega^{-i_2j_1}.
\]

4. Run inverse \(K\)-point NTTs along the X1 dimension.
5. Apply the inverse twist:

\[
a[i_1M+i_2] = A[i_2][i_1]\psi^{-(i_1M+i_2)}.
\]

6. Apply total inverse scaling once:

\[
N^{-1} \bmod q .
\]

If the inverse \(K\)- and \(M\)-point cores already scale by \(K^{-1}\) and
\(M^{-1}\), then the total \(N^{-1}\) has already been applied.

---

## 3) Corrected Hardware Architecture

### 3.1 Track A Pipeline

1. **Input loader / twist mapper**
   - Reads \(a_i\), \(b_i\).
   - Computes or looks up \(\psi^i\).
   - Writes \(A[i_2][i_1]\) using \(i=i_1M+i_2\).

2. **X1 row NTT engine**
   - Runs \(M\) independent \(K\)-point NTTs.
   - Reuses the existing small mixed-radix NTT core.

3. **Cross-twiddle engine**
   - Multiplies each row-output value by \(\omega^{i_2j_1}\).
   - This is a real cost and must be counted separately from stage twiddles.

4. **Transpose / write-with-swapped-indices**
   - Recommended first implementation: double-buffered transpose.
   - Write \(C[i_2][j_1]\) into the next memory as \(C_T[j_1][i_2]\).
   - Then X2 reads are contiguous and simple.

5. **X2 column NTT engine**
   - Runs \(K\) independent \(M\)-point NTTs.

6. **Pointwise multiply**
   - Multiplies transformed A and B at matching \((j_1,j_2)\).

7. **Inverse path**
   - Inverse X2 NTT.
   - Inverse transpose.
   - Inverse cross twiddle.
   - Inverse X1 NTT.
   - Inverse twist and final mapper back to coefficient order.

### 3.2 Memory Strategy

Use **S1: double-buffered transpose** for the first RTL prototype.

- `MemA`: source layout for the current dimension.
- `MemB`: destination layout after swapped-index write.
- Pros: simplest control and easiest verification.
- Cons: roughly doubles the working memory footprint.

Do not attempt an in-place blocked transpose until the double-buffered version
has a measured baseline.

### 3.3 Banking Rule

The mapper must prove both:

- **Bijection**: every coefficient index maps to exactly one tensor coordinate.
- **Conflict freedom**: the selected lane pattern can read/write all operands
  without illegal same-bank collisions.

A candidate first banking rule is:

\[
bank = (i_1 + \alpha i_2) \bmod B
\]

where \(\alpha\) is selected by the banking simulator. This should be verified
for all row, column, transpose, and inverse access patterns before RTL freeze.

---

## 4) Software Baseline Before RTL

### 4.1 Mandatory Python Models

Build these in order:

1. **Direct negacyclic convolution**
   - Slow but simple golden reference.

2. **Existing 1-D twisted NTT**
   - Confirms root generation, twist, inverse twist, and scaling.

3. **Track A 2-D NTT**
   - Must match the 1-D twisted NTT exactly for all tested vectors.

4. **Track A full multiplier**
   - Forward 2-D NTT for A and B.
   - Pointwise multiply.
   - Inverse 2-D NTT.
   - Compare against direct negacyclic convolution.

Only after these pass should RTL work begin.

### 4.2 Required Test Vectors

- all zero
- one-hot impulse
- identity / multiplication by 1
- all \(q-1\)
- alternating signs
- maximum coefficient stress
- random seeds with repeatable seed logging
- exhaustive tests for very small \(N\), such as \(N=8,16,32\)

### 4.3 Cost Model

The estimator must count:

- K-point row NTT cycles
- M-point column NTT cycles
- cross-twiddle modular multiplies
- twist and inverse-twist multiplies
- transpose reads/writes
- memory bank conflicts and stalls
- twiddle ROM footprint
- total cycles as a function of lane count \(P\)

Proceed to RTL only if the 2-D schedule shows a plausible benefit after
including transpose and cross-twiddle overhead.

---

## 5) RTL Build Plan

### M0 - Math and Parameter Lock

- Select Track A parameters: \(N\), \(K\), \(M=N/K\), \(q\), \(P\), bank count.
- Generate primitive roots and verify:

\[
\psi^{2N}=1,\quad \psi^N=-1,\quad \omega^N=1 .
\]

- Freeze the exact index map \(i=i_1M+i_2\).

### M1 - Mapper and Banking Prototype

- Implement tensor index generation.
- Implement address generation for row, transpose, column, and inverse paths.
- Verify bijection and conflict freedom in simulation.

### M2 - Reusable Small NTT Core

- Parameterize the existing NTT core for lengths \(K\) and \(M\).
- Confirm forward and inverse behavior, including scaling convention.
- Support external twiddle streams or ROM addressing per dimension.

### M3 - Forward Row Path

- Loader with twist.
- X1 row NTTs.
- Cross-twiddle multiply.
- Double-buffered transpose write.

### M4 - Forward Full 2-D NTT

- Add X2 column NTTs.
- Compare RTL output against the Python Track A 2-D model.

### M5 - Full Multiplier

- Forward transform for both operands.
- Pointwise multiply.
- Inverse X2 path.
- Inverse transpose.
- Inverse cross twiddle.
- Inverse X1 path.
- Inverse twist and output reorder.

### M6 - Performance and Area Evaluation

Compare against the existing monolithic or mixed-radix baseline:

- LUT / FF / DSP / BRAM
- Fmax
- latency
- throughput
- area-time product
- memory traffic
- energy estimate if available

### M7 - Optional Track B Prototype

Only begin this after Track A is correct and measured.

For Track B, the minimum software proof must include:

- active \(M \times L\) mapper, where \(L=K/2\)
- zero-padded length-\(K\) X1 convolution behavior
- high-degree fold \(X_1^L=X_2\)
- negacyclic wrap \(X_2^M=-1\)
- inverse remap to the original univariate coefficient order
- comparison against direct negacyclic convolution

---

## 6) Verification Plan

### 6.1 Unit Tests

- root generation tests
- twist / inverse-twist tests
- mapper bijection tests
- transpose correctness tests
- bank conflict tests
- K-point NTT tests
- M-point NTT tests
- cross-twiddle exponent tests

### 6.2 End-to-End Tests

- Python direct convolution vs Python 1-D NTT
- Python 1-D NTT vs Python Track A 2-D NTT
- Python Track A 2-D NTT vs RTL forward transform
- Python full multiplier vs RTL full multiplier

### 6.3 Rejection Conditions

Do not proceed to hardware optimization if any of these occur:

- mapper has collisions or unused active coordinates
- inverse transform only works for special vectors
- scaling is applied twice or not at all
- cross-twiddle formulas depend on an undocumented index convention
- transpose cost erases the expected performance benefit
- Track B requires hidden data expansion beyond the cost model

---

## 7) Risk Register

1. **Wrong tensor interpretation**
   - Risk: treating \(2N/K \times K\) as a dense bijective map for \(N\)
     coefficients.
   - Mitigation: Track A uses \(N/K \times K\); Track B explicitly uses only
     \(K/2\) active X1 basis coefficients.

2. **Cross-twiddle overhead dominates**
   - Mitigation: count it explicitly and evaluate ROM vs on-the-fly generation.

3. **Transpose dominates memory traffic**
   - Mitigation: start with double-buffered transpose, measure it, then optimize.

4. **Bank conflicts reduce parallel utilization**
   - Mitigation: build a banking simulator before RTL freeze.

5. **Auxiliary modulus switching hides the real cost**
   - Mitigation: do not include modulus/domain switching in Track A unless the
     target parameter set truly requires CRT/RNS.

6. **Track B carry/fold path becomes more expensive than expected**
   - Mitigation: keep Track B out of the first RTL prototype and validate it in
     software with explicit operation counts.

---

## 8) Recommended Starting Point

For the first working prototype:

- \(N \in \{2^{14},2^{15}\}\)
- \(q=65537\) for a simple single-modulus demo, or another prime with
  \(2N\mid(q-1)\)
- \(K\) near \(\sqrt{N}\), adjusted to match available memory banks and NTT core
  sizes
- Track A 2-D Cooley-Tukey schedule
- double-buffered transpose
- no auxiliary modulus switching

The first success criterion is correctness against direct negacyclic
convolution. The second is a measured hardware benefit against the existing
baseline after including mapper, transpose, twist, and cross-twiddle costs.

