# Theory and Architectures of the Bivariate Number Theoretic Transform Multiplier

## Introduction to Multi-Dimensional Number Theoretic Transforms

The execution of lattice-based cryptography and Fully Homomorphic Encryption (FHE) is heavily dominated by polynomial multiplication over modular rings. To accelerate these computationally intensive operations, the Number Theoretic Transform (NTT) is widely deployed as a specialized variant of the Discrete Fourier Transform (DFT) operating over a finite integer ring $\mathbb{Z}_q$. While univariate NTTs successfully reduce the asymptotic complexity of polynomial multiplication from $O(N^2)$ to $O(N \log N)$, physical hardware implementations face severe bottlenecks when scaling to the very large polynomial degrees required for homomorphic security.

The primary physical constraints of large univariate NTTs reside in the memory subsystem. As the transform length $N$ increases, the memory stride of the butterfly operations doubles at each consecutive stage of the algorithm, leading to highly non-contiguous, stride-heavy data accesses that cause severe cache-miss penalties and memory bank conflicts on conventional CPUs, GPUs, and hardware accelerators. To bypass these physical limitations, researchers and hardware designers map the long univariate 1D transform into a multi-dimensional or bivariate space.

The bivariate NTT multiplier operates on the theoretical principle of dimensional decomposition, mapping a long 1D NTT of size $N = N_1 N_2$ into a highly parallelizable 2D row-column structure of dimensions $N_1 \times N_2$. In doing so, the massive stride-dependent data flow is localized within small, high-speed on-chip memory blocks, dramatically reducing memory bandwidth requirements and enabling conflict-free parallel memory accesses.

Simultaneously, a distinct yet complementary mathematical paradigm has emerged in FHE: the algebraic bivariate representation of Torus polynomials. This representation maps univariate polynomials to bivariate structures over a formal variable representing the decomposition base, eliminating the need for the Residue Number System (RNS) and allowing external homomorphic products to be computed directly via bivariate transforms.

This report analyzes the mathematical formulations, hardware constraints, and architectural implementations that define the modern state of the art in bivariate NTT multiplication.

---

## Mathematical Formulations and Dimensional Mapping

The core mathematical objective of the bivariate NTT multiplier is to establish a rigorous bijection between a 1D sequence and a 2D grid such that a 1D cyclic convolution is computed using highly parallel 2D transform operations. The mapping strategies differ fundamentally depending on whether the decomposed dimensions $N_1$ and $N_2$ are mutually prime.

### The Prime-Factor (Good-Thomas) Transform Mapping

When the dimensions $N_1$ and $N_2$ are chosen such that they are co-prime, meaning:

[
\gcd(N_1, N_2) = 1
]

The Prime-Factor Transform (PFT) mapping is applied to split the 1D NTT into a pure 2D NTT without requiring intermediate twiddle factor multiplications.

The input index $j$ and output index $i$ of the 1D sequence of length $N = N_1 N_2$ are mapped to the 2D indices $(j_1, j_2)$ and $(i_1, i_2)$ via:

[
j = a j_1 + b j_2 \pmod N
]

where:

* $0 \le j_1 \le N_1 - 1$
* $0 \le j_2 \le N_2 - 1$

Similarly:

[
i = c i_1 + d i_2 \pmod N
]

where:

* $0 \le i_1 \le N_1 - 1$
* $0 \le i_2 \le N_2 - 1$

To ensure that the 1D cyclic convolution maps perfectly to a 2D cyclic convolution, the coefficients $a, b, c,$ and $d$ are selected using the Chinese Remainder Theorem (CRT).

By setting:

* $a = N_2$
* $b = 1$
* $c = 1$
* $d = N_1$

The 1D NTT of a sequence $A$ over the finite ring $\mathbb{Z}_q$ becomes:

[
Z[N_1 i_1 + i_2] =
\sum_{j_2=0}^{N_2-1}
\left(
\sum_{j_1=0}^{N_1-1}
A[N_2 j_1 + j_2] \cdot \omega^{i_1 j_1}
\right)
\cdot
\omega^{i_2 j_2}
\pmod q
]

Here, $\omega$ is a primitive $N$-th root of unity modulo $q$.

Because $N_1$ and $N_2$ are mutually prime, the cross terms in the exponent vanish, isolating the row and column transforms:

[
\omega^{N_2} = \psi_1
]

where $\psi_1$ is a primitive $N_1$-th root of unity modulo $q$.

Similarly:

[
\omega^{N_1} = \psi_2
]

where $\psi_2$ is a primitive $N_2$-th root of unity modulo $q$.

This reduction allows the row-wise and column-wise transforms to execute independently, reducing arithmetic complexity and simplifying hardware routing.

### Bivariate Cyclic Convolution for Non-Co-Prime Dimensions

When $N_1$ and $N_2$ are not mutually prime, as is typical in power-of-two cyclotomic rings where:

[
N = 2^m
]

The Prime-Factor Transform cannot be applied.

Instead, a Cooley-Tukey four-step decomposition is used with index substitutions:

[
j = j_1 N_2 + j_2
]

and:

[
i = i_1 + i_2 N_1
]

The resulting transform becomes:

[
Z[i_1 + i_2 N_1] =
\sum_{j_2=0}^{N_2-1}
\left(
\omega_N^{j_2 i_1}
\cdot
\left(
\sum_{j_1=0}^{N_1-1}
A[j_1 N_2 + j_2]
\cdot
\omega_{N_1}^{j_1 i_1}
\right)
\right)
\cdot
\omega_{N_2}^{j_2 i_2}
\pmod q
]

Unlike the co-prime case, this formulation introduces intermediate twiddle-factor multiplications:

[
\omega_N^{j_2 i_1}
]

between the column and row transforms.

To handle cyclic convolution under this layout, the 1D $z$-transform is mapped into a bivariate polynomial representation.

The exponent term:

[
z^{n_2 + m_2}
]

is reduced modulo:

[
z^{N_2} - 1
]

by expressing:

[
n_2 + m_2 = y_{n_2,m_2} N_2 + \beta_{n_2,m_2}
]

where:

[
y_{n_2,m_2} = \left\lfloor \frac{n_2 + m_2}{N_2} \right\rfloor
]

and:

[
\beta_{n_2,m_2} = (n_2 + m_2) \bmod N_2
]

The carry term introduces a cyclic shift represented algebraically by:

[
\alpha^{k_1 y_{n_2,m_2}}
]

If $\alpha$ is chosen as a power of two, this shift becomes implementable using low-cost hardware bit shifts.

---

## The Bivariate Representation in Fully Homomorphic Encryption

A major advancement in high-precision homomorphic encryption is the transition away from classical univariate Residue Number System (RNS) representations toward an algebraic bivariate polynomial representation.

### Gadget Decomposition and the Bivariate Ring Structure

In standard FHE schemes such as TFHE, BGV, and BFV, external products require gadget decomposition.

A polynomial coefficient modulo $q$ is decomposed into digits relative to a base:

[
B = 2^k
]

Traditional RNS implementations perform this decomposition numerically using CRT reconstruction and modular reductions.

The bivariate formulation instead maps:

[
\mathbb{T}[X] / (X^N + 1)
]

into the quotient ring:

[
\mathcal{R} \cong \mathbb{Z}/(X^N + 1, Y^D - B)
]

where:

* $X$ represents the polynomial dimension.
* $Y$ encodes the decomposition base.

Under this representation, decomposition digits become coefficients of powers of $Y$, transforming external products into a single bivariate polynomial multiplication.

This enables acceleration using a unified bivariate NTT or FFT.

### Noise Propagation and Scheme-Switching Advantages

The bivariate representation significantly simplifies noise propagation.

In CKKS and other leveled schemes, traditional RNS arithmetic requires strict level alignment and exact scaling-factor management.

The bivariate structure instead bounds decomposition algebraically through:

[
Y^D - B
]

eliminating exact-level clamping.

Additionally, because different ciphertext structures share a common algebraic space, efficient transitions become possible between:

* LWE
* GLWE
* GGSW

without expensive modulus switching or key switching.

Libraries such as *Poulpy* and *Squid* leverage this representation to decouple cryptographic schemes from backend arithmetic implementations while maintaining performance comparable to hand-optimized AVX2/FMA implementations.

---

## Hardware Implementations and Co-Processor Designs

To achieve high energy efficiency and low latency, the mathematical advantages of the bivariate NTT must be mapped onto specialized hardware architectures.

### Systolic Array Mapping and Area-Energy Optimization

The grid structure of the 2D bivariate NTT maps naturally onto systolic arrays.

Traditional 1D NTTs require long-range routing due to growing memory strides across stages.

By decomposing the transform into a 2D structure using the Prime-Factor Transform, the computation can execute on a regular 2D systolic array without changing the underlying interconnect structure.

The coefficients and roots of unity stream through the array in a pipelined fashion.

Intermediate data remains localized between neighboring processing elements (PEs), minimizing external memory traffic.

A synthesized 22nm CMOS implementation demonstrated:

* 53.04 mm² silicon area
* 3296 cycles for a 4096-point transform
* 1794.92 nJ energy consumption

An additional advantage is hardware reuse:

The same systolic array can accelerate deep neural network workloads alongside NTT operations.

### Conflict-Free Parallel Memory and 10T SRAM Arrays

In highly parallel NTT accelerators, memory-bank conflicts often dominate performance limitations.

The GD-NTT accelerator addresses this using a custom 10T SRAM architecture supporting simultaneous row-wise and column-wise accesses.

This allows:

* conflict-free operand retrieval
* elimination of pipeline stalls
* simultaneous row/column access

Combined with glitch-driven clocking techniques, GD-NTT achieves between:

[
1.5\times \text{ to } 28\times
]

throughput-per-area improvement over conventional architectures.

Similarly, BASALISC employs a conflict-free two-dimensional memory hierarchy to sustain:

[
32\ \text{Tb/s}
]

radix-256 NTT throughput without pipeline stalls.

### Twiddle Factor Generation and Bandwidth Conservation

Twiddle-factor storage is a major area overhead in scalable NTT accelerators.

The ESC-NTT architecture introduces a dedicated Twiddle Factor Generator (TFG) that computes roots of unity on the fly.

Instead of storing large BRAM tables, the TFG derives subsequent twiddle factors using modular multipliers and stepping factors.

This reduces twiddle-factor bandwidth by:

[
68.7%
]

while enabling seamless parameter switching with no pipeline bubbles.

### Processing-In-Memory and Near-Memory Accelerators

Processing-In-Memory (PIM) and Compute-near-Memory (CNM) architectures reduce the cost of data movement between memory and compute units.

The Local Horizontal Folding (LHF) algorithm maps butterfly dataflow onto local scratchpads near memory arrays.

This reduces memory traffic by more than:

[
50%
]

while doubling throughput in 2D NTT configurations.

The DRAMatic system further accelerates FHE workloads using UPMEM PIM hardware.

Its massively parallel DPU-based architecture offloads full sub-polynomial NTTs directly into DRAM-adjacent compute units.

Compared to stage-by-stage offloading approaches, DRAMatic reduces communication overhead by:

[
36\times
]

---

## Comparative Analysis of Bivariate Hardware Architectures

| Architecture                 | Platform                | Key Idea                         | Main Advantage                       |
| ---------------------------- | ----------------------- | -------------------------------- | ------------------------------------ |
| Optimal Systolic Array (SAA) | 22nm CMOS ASIC          | 2D Prime-Factor systolic mapping | General-purpose spatial acceleration |
| GD-NTT                       | Near-memory computing   | 10T SRAM row/column access       | Eliminates bank conflicts            |
| ESC-NTT                      | Xilinx Alveo U280       | On-the-fly twiddle generation    | Saves twiddle bandwidth              |
| DRAMatic                     | UPMEM PIM               | DPU-based sub-polynomial NTTs    | Reduces communication overhead       |
| BASALISC                     | Custom RISC accelerator | Conflict-free radix-256 layout   | 32 Tb/s throughput                   |
| LHF-NTT                      | Compute-near-memory     | Local scratchpad folding         | Reduces memory accesses              |
| Hartley NTT (HNTT)           | FPGA                    | GF(3)-based Hartley transform    | Eliminates multiplication overhead   |

---

## Conclusions and Future Outlook

The bivariate Number Theoretic Transform multiplier represents a major advancement in both cryptographic mathematics and hardware architecture.

By transforming large univariate NTTs into structured multi-dimensional computations, bivariate NTTs dramatically reduce memory bottlenecks and improve scalability for post-quantum cryptography and Fully Homomorphic Encryption.

At the algorithmic level, the transition from RNS arithmetic toward algebraic bivariate polynomial representations simplifies gadget decomposition, reduces noise-management complexity, and enables efficient interoperability between different ciphertext structures.

At the hardware level, multi-dimensional layouts map naturally onto:

* systolic arrays
* conflict-free memory systems
* near-memory accelerators
* Processing-In-Memory architectures

These designs localize dataflow and reduce energy-intensive memory movement.

As confidential computing becomes increasingly important in cloud and edge systems, co-design approaches that jointly optimize algebraic formulations and hardware architectures will become central to the next generation of high-performance secure processors.

