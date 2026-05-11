# Viability Analysis: Univariate-to-Multivariate Ring Transformation for an NTT Multiplier Architecture

## Correction After Implementation-Plan Review

This direction is **promising but conditional**, not automatically correct as a
dense \((2N/K)\times K\) tensor mapping.

The expression

\[
\mathbb{Z}_P[X_1, X_2]/\langle X_2^{2N/K}+1 \rangle
\quad\text{with}\quad X_2=X_1^{K/2}
\]

should not be interpreted as an independent 2-D quotient with \(K\) active X1
coefficients in every row. A correct basis for that substitution uses:

\[
L=K/2,\qquad M=2N/K,\qquad
i=i_1+L i_2,\qquad
0\le i_1<L,\quad 0\le i_2<M .
\]

So there are \(LM=N\) active coefficients. If a length-\(K\) X1 NTT is used, it
is a zero-padded linear-convolution working dimension; high X1 degrees must be
folded using \(X_1^L=X_2\), and \(X_2^M=-1\) handles the negacyclic wrap.

For the first RTL prototype, the safer implementation path is the corrected
standard 2-D Cooley-Tukey schedule in
`multivariate_ntt_multiplier_implementation_plan.md`, using a bijective
\((N/K)\times K\) tensor and the usual twisted negacyclic NTT. The
\(X_2=X_1^{K/2}\) approach should remain a second research track until a Python
model proves the mapper, fold logic, inverse mapping, and cost model.

---

## 1. Overview

The proposed research direction is based on transforming a large univariate polynomial ring:

\[
\mathbb{Z}_P[X]/\langle X^N + 1 \rangle
\]

into a multivariate representation:

\[
\mathbb{Z}_P[X_1, X_2]/\langle X_2^{2N/K}+1 \rangle
\]

using the substitution:

\[
X_2 = X_1^{K/2}
\]

The core objective is to avoid implementing one very large FNTT/NTT and instead decompose the transform into multiple smaller transforms whose dimensions divide \(K\).

This aligns extremely well with your current research direction because your architecture is already exploring:

- Mixed-radix decomposition
- Recursive stage decomposition
- Flexible radix scheduling
- Resource reuse
- Parametric RTL generation
- Timing/area optimization across FPGA and ASIC flows

This means the proposed transformation is not a completely separate architecture.
Instead, it can potentially become a higher-level decomposition layer sitting above your current NTT engine.

---

# 2. What the Transformation Actually Achieves

## 2.1 Traditional NTT Bottleneck

A large NTT of size \(N\):

\[
A(X)B(X) \bmod (X^N+1)
\]

typically requires:

- Large memory banks
- Large twiddle ROMs
- Long butterfly scheduling
- High routing congestion
- Deep timing paths
- Difficult BRAM banking
- High DSP utilization

As \(N\) scales:

- FPGA timing closure becomes difficult
- ASIC wire congestion increases
- Memory bandwidth dominates
- Crossbar complexity grows quickly

This becomes especially problematic for:

- FHE
- RLWE cryptography
- Bootstrapping accelerators
- Large polynomial multipliers

where \(N\in\{2^{14},2^{15},2^{16},2^{17}\}\).

---

## 2.2 Main Idea of the Paper Direction

Instead of computing:

\[
\text{NTT}_N
\]

compute:

\[
\text{NTT}_{N_1} \times \text{NTT}_{N_2}
\]

through algebraic restructuring.

This converts one massive transform into:

- Several smaller transforms
- Lower memory pressure
- Better locality
- Higher parallelism
- Better BRAM partitioning
- Easier pipelining
- Reduced routing congestion

Conceptually this is similar to:

- Tensor decomposition
- Good-Thomas decomposition
- Multidimensional FFTs
- Winograd style restructuring

but adapted to Fermat/negacyclic polynomial rings.

---

# 3. Compatibility With Your Existing Architecture

## 3.1 Very High Compatibility

Your current architecture already appears to contain:

- Parametric radix engine
- Recursive stage structure
- Dynamic radix scheduling
- Variable stage decomposition
- RHAT/nonuniform stage handling
- Flexible transform dimensions

This is important because the multivariate method naturally maps into:

- Hierarchical transform scheduling
- Sub-transform orchestration
- Multi-bank memory systems
- Recursive control FSMs

Meaning:

You do NOT need to redesign the butterfly datapath.

Instead:

You mainly need:

1. A higher-level decomposition controller
2. Data remapping logic
3. Auxiliary modulus management
4. Inter-transform scheduling
5. Twiddle reinterpretation

The existing BFU architecture can likely remain mostly unchanged.

---

# 4. Where It Fits in Your Current Architecture

## Proposed Hierarchical Stack

### Current Architecture

Your current flow likely resembles:

\[
\text{Input} \rightarrow \text{NTT Engine} \rightarrow \text{Pointwise Multiply} \rightarrow \text{INTT}
\]

---

### Proposed Enhanced Architecture

With multivariate decomposition:

\[
\text{Input}
\rightarrow
\text{Polynomial Mapper}
\rightarrow
\text{Sub-NTT Scheduler}
\rightarrow
\text{Small NTT Engines}
\rightarrow
\text{Tensorized Pointwise Multiply}
\rightarrow
\text{Inverse Mapper}
\]

This adds a new abstraction layer.

Your existing mixed-radix NTT becomes the reusable compute kernel.

---

# 5. Major Hardware Advantages

## 5.1 Smaller Transform Engines

Instead of:

- One 16384-point NTT

You may execute:

- Multiple 64-point
- 128-point
- 256-point

sub-transforms.

Advantages:

- Smaller twiddle ROM
- Better timing
- Lower fanout
- Easier floorplanning
- Better DSP reuse
- More predictable routing

This is extremely valuable for ASIC scalability.

---

## 5.2 Improved Memory Locality

Large NTTs are often memory-bound.

The multivariate approach allows:

- Localized memory banks
- Reduced global shuffling
- Reduced BRAM port pressure
- Better SRAM banking
- Better cache reuse in software-hardware co-design

This may become one of the strongest advantages.

---

## 5.3 Better Parallelization

Independent sub-transforms can execute:

- Concurrently
- Pipelined
- Time-multiplexed

depending on area constraints.

This creates a large design space:

| Mode | Benefit |
|---|---|
| Fully parallel | Maximum throughput |
| Time multiplexed | Minimum area |
| Semi-parallel | Balanced ATP |

This fits perfectly with your current ATP exploration work.

---

## 5.4 Better Scalability

This approach becomes more attractive as:

\[
N \uparrow
\]

because routing and memory complexity grow superlinearly in conventional architectures.

For very large FHE accelerators, this may outperform monolithic NTTs.

---

# 6. Major Challenges

This direction is promising, but there are significant complications.

---

# 6.1 Data Mapping Complexity

The biggest challenge is not the butterfly engine.

It is:

- Index remapping
- Tensor reshaping
- Coefficient permutation
- Address generation

The mapping between:

\[
X \leftrightarrow (X_1, X_2)
\]

must be performed efficiently.

If implemented naively:

- Routing explodes
- BRAM conflicts occur
- Crossbar cost dominates
- Latency advantage disappears

Therefore the success of this idea heavily depends on:

# The Mapping Unit

This is likely where your research novelty should focus.

---

# 6.2 Auxiliary Fermat Modulus Switching

The proposal references:

"Auxiliary Fermat Modulus" switching.

This is extremely important.

The transformed sub-rings may require:

- Different primitive roots
- Different modulus domains
- Intermediate modulus conversion
- CRT reconstruction
- Basis switching

This introduces:

- Additional modular reduction stages
- Conversion overhead
- Control complexity
- ROM expansion

You must verify:

\[
\text{Overhead} < \text{Saved Complexity}
\]

Otherwise the decomposition loses its benefit.

---

# 6.3 Twiddle Management

A multidimensional transform changes:

- Twiddle access patterns
- Root generation
- Stage ordering
- Address schedules

Your current radix scheduler may need extension to support:

- Nested stage traversal
- Dimension-aware twiddles
- Inter-dimension synchronization

---

# 6.4 Increased Control Complexity

Your current controller probably manages:

- Stage count
- Butterfly scheduling
- Memory ping-pong
- Twiddle sequencing

The new system requires:

- Transform graph orchestration
- Dimension switching
- Sub-transform synchronization
- Modulus-domain tracking
- Mapper coordination

This may substantially increase FSM complexity.

A microcoded controller may become preferable.

---

# 7. Most Promising Research Contribution

## The Automated Mapping Unit

This is probably the strongest publication angle.

Not the algebra itself.

The algebraic decomposition already exists conceptually.

What can become novel is:

# Hardware-aware dynamic multivariate transform orchestration.

Specifically:

## Possible Contributions

### 1. Automated Ring Mapper

A hardware unit that:

- Maps univariate coefficients into multidimensional layout
- Optimizes bank placement
- Minimizes shuffle cost
- Generates addresses dynamically

---

### 2. Dimension-Adaptive Scheduler

A scheduler that dynamically selects:

- Radix
- Sub-transform dimensions
- Parallelism factor
- Memory banking strategy

based on:

- FPGA resources
- ASIC constraints
- Throughput targets

---

### 3. Auxiliary Modulus Pipeline

A hardware pipeline for:

- Modulus switching
- Domain conversion
- CRT reconstruction
- Intermediate reductions

optimized for:

- Low latency
- Low BRAM footprint
- Shared arithmetic units

---

### 4. Hybrid Recursive NTT

Combining:

- Your recursive mixed-radix engine
- Multidimensional decomposition

into:

# A hierarchical recursive multidimensional NTT.

This sounds publication-worthy already.

---

# 8. Expected FPGA Impact

## Likely Improvements

| Metric | Expected Result |
|---|---|
| Fmax | Increase |
| Routing congestion | Significant decrease |
| BRAM locality | Better |
| DSP utilization | Better reuse |
| ATP | Potential improvement |
| Scalability | Much better |

---

## Potential Regressions

| Metric | Risk |
|---|---|
| LUT count | Higher control overhead |
| Latency | Extra mapping stages |
| Verification complexity | Much harder |
| Address generation | More expensive |

---

# 9. ASIC Relevance

This direction is even more valuable for ASIC.

Why?

Because ASIC bottlenecks are often:

- Wire congestion
- Global interconnect
- SRAM bandwidth
- Clock distribution

not arithmetic.

Multivariate decomposition reduces:

- Long global wires
- Massive crossbars
- Large SRAM monoliths

and enables:

- Local compute clusters
- Hierarchical NoC structures
- Banked SRAM fabrics

This is highly relevant to:

- FHE ASIC accelerators
- AI accelerators using polynomial arithmetic
- Post-quantum cryptography engines

---

# 10. Integration Strategy With Your Existing Work

## Recommended Path

Do NOT attempt a full redesign immediately.

Instead:

---

## Phase 1 — Mathematical Validation

Validate:

- Ring equivalence
- Correctness
- Modulus switching
- Twiddle reconstruction
- Numerical stability

in Python/Matlab.

---

## Phase 2 — Software Architectural Simulator

Build:

- Cycle estimator
- Memory traffic estimator
- Shuffle cost estimator
- Banking simulator

This is extremely important.

The method may fail if permutation overhead dominates.

---

## Phase 3 — Integrate With Existing RTL Engine

Reuse:

- Existing BFUs
- Existing radix engine
- Existing modular arithmetic

Only add:

- Mapper
- Scheduler
- Domain controller

This minimizes implementation risk.

---

## Phase 4 — Compare Against Baseline

Compare:

| Architecture | Baseline |
|---|---|
| Monolithic mixed-radix NTT | Your current design |
| Multivariate hierarchical NTT | Proposed design |

Evaluate:

- LUT
- FF
- DSP
- BRAM
- Fmax
- ATP
- Energy
- Scalability

---

# 11. Publication Potential

This direction has strong publication potential if framed correctly.

The novelty should NOT be:

"We implemented Kim et al."

Instead:

Potential contribution framing:

## Option A

"Hardware-Aware Multivariate Recursive NTT Architecture for Large-Scale Polynomial Multiplication"

---

## Option B

"Adaptive Multidimensional NTT Decomposition With Automated Ring Mapping for FPGA/ASIC Accelerators"

---

## Option C

"Hierarchical Mixed-Radix Multivariate NTT Architecture With Dynamic Auxiliary Modulus Switching"

---

# 12. Overall Viability Assessment

## Technical Viability: PROMISING BUT CONDITIONAL

The standard 2-D Cooley-Tukey schedule is mathematically solid and
architecturally compatible with your current work.

The \(X_2=X_1^{K/2}\) multivariate embedding is also promising, but only after
the active \(K/2\)-wide basis, high-degree fold path, inverse mapping, and
cost model are proven in software.

---

## RTL Implementation Difficulty: HIGH

The mapper/scheduler complexity is substantial.

This is not a small modification.

---

## Probability of Measurable Gains: MODERATE

Especially for:

- Large NTT sizes
- FPGA routing bottlenecks
- ASIC implementations
- Memory-dominated systems

This may become moderate-to-high after the transpose, cross-twiddle, and
Track-B fold overheads are measured instead of assumed.

---

## Most Critical Risk

The permutation, cross-twiddle, fold/carry, and any modulus-switching overhead
may outweigh the transform savings.

This must be evaluated quantitatively.

---

# 13. Final Recommendation

Yes, this direction is viable and fits your architecture well, but it should be
implemented in two stages: first the corrected standard 2-D NTT schedule, then
the \(X_2=X_1^{K/2}\) embedding only after software proof.

However:

The main innovation should not be the decomposition itself.

The strongest research contribution is likely:

# A hardware-efficient multidimensional transform orchestration framework.

Specifically:

- Automated mapping
- Memory-aware scheduling
- Dynamic modulus-domain management
- Recursive hierarchical transform execution

Your existing mixed-radix architecture already provides a strong foundation because:

- You already support flexible decomposition
- You already explore radix scheduling
- You already use recursive structure
- Your architecture is naturally hierarchical

This makes your project a very good candidate for extending into multivariate NTT research.

The best next step is probably:

1. Build a software model of the decomposition
2. Measure shuffle overhead
3. Define the mapper architecture
4. Reuse your current BFU datapath
5. Prototype a small multidimensional RTL version
6. Compare against your monolithic baseline

If done carefully, this could become a strong publication direction.
