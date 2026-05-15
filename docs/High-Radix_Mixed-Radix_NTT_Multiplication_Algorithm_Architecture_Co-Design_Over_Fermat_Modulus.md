IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025 3519

## High-Radix/Mixed-Radix NTT Multiplication Algorithm/Architecture Co-Design Over Fermat Modulus


Yile Xing, _Student_ _Member,_ _IEEE_, Guangyan Li, Zewen Ye, _Student_ _Member,_ _IEEE_,
Ryan W. L. Luk, _Member,_ _IEEE_, Donglong Chen, _Member,_ _IEEE_, Hong Yan, _Life_ _Fellow,_ _IEEE_,
and Ray C. C. Cheung, _Senior_ _Member,_ _IEEE_



_**Abstract**_ **—Polynomial** **multiplication** **using** **Number** **Theoretic**
**Transform** **(NTT)** **is** **crucial** **in** **lattice-based** **post-quantum** **cryp-**
**tography** **(PQC)** **and** **fully** **homomorphic** **encryption** **(FHE),** **with**
**modulus** _**q**_ **significantly** **affecting** **performance.** **Fermat** **moduli**
**of** **the** **form** **2** **[2]** _**[n]**_ **+ 1,** **such** **as** **65537,** **offer** **efficiency** **gains** **due**
**to** **simplified** **modular** **reduction** **and** **powers-of-2** **twiddle** **factors**
**in** **NTT.** **While** **Fermat** **moduli** **have** **been** **directly** **applied** **or**
**explored** **for** **incorporation** **into** **existing** **schemes,** **Fermat** **NTT-**
**based** **polynomial** **multiplication** **designs** **remain** **underexplored**
**in** **fully** **exploiting** **the** **benefits** **of** **Fermat** **moduli.** **This** **work**
**presents** **a** **high-radix/mixed-radix** **NTT** **architecture** **tailored** **for**
**Fermat** **moduli,** **which** **improves** **the** **utilization** **of** **the** **powers-**
**of-2** **twiddle** **factors** **in** **large** **transform** **sizes.** **In** **most** **cases,** **our**
**design** **achieves** **a** **30%–85%** **reduction** **in** **DSP** **area-time** **product**
**(ATP)** **and** **a** **70%–100%** **reduction** **in** **BRAM** **ATP** **compared**
**to** **state-of-the-art** **designs** **with** **smaller** **or** **equivalent** **modulus,**
**while** **maintaining** **competitive** **LUT** **and** **FF** **ATP,** **underscoring**
**the** **potential** **of** **Fermat** **NTT-based** **polynomial** **multipliers** **in**
**lattice-based** **cryptography.**


_**Index**_ _**Terms**_ **—Polynomial** **multiplication,** **Fermat** **number**
**transform,** **high** **radix,** **mixed** **radix,** **conflict-free** **memory** **access.**


Received 7 October 2024; revised 10 June 2025; accepted 7 July 2025.
Date of publication 21 July 2025; date of current version 10 September
2025. This work was supported in part by Hong Kong Innovation and
Technology Commission (InnoHK Project CIMDA), in part by the CityUHK
Project under Grant 9440356, in part by ITF Project under Grant ITS/098/22,
in part by Guangdong Provincial Key Laboratory of IRADS under Grant
2022B1212010006, in part by Guangdong and Hong Kong Universities
“1+1+1” Joint Research Collaboration Scheme, in part by Guangdong Basic
and Applied Basic Research Foundation under Grant 2024A1515011274, in
part by Guangdong Province General Universities Key Field Project (New
Generation Information Technology) under Grant 2023ZDZX1033, and in
part by UIC Research under Grant UICR04202401-21. Recommended for
acceptance by K. Gaj. _(Corresponding_ _author:_ _Donglong_ _Chen.)_
Yile Xing, Guangyan Li, Ryan W. L. Luk, Hong Yan, and Ray C. C.
Cheung are with the Department of Electrical Engineering, City University
of Hong Kong, Hong Kong SAR 999077, China (e-mail: [ylxing2-c@my.](mailto:ylxing2-c@my.cityu.edu.hk)
[cityu.edu.hk;](mailto:ylxing2-c@my.cityu.edu.hk) [guangyali5-c@my.cityu.edu.hk;](mailto:guangyali5-c@my.cityu.edu.hk) [ryanluk5-c@my.cityu.edu.hk;](mailto:ryanluk5-c@my.cityu.edu.hk)
[h.yan@cityu.edu.hk;](mailto:h.yan@cityu.edu.hk) [r.cheung@cityu.edu.hk).](mailto:r.cheung@cityu.edu.hk)
Zewen Ye is with the College of Information Science & Electronic
Engineering, Zhejiang University, Hangzhou 310027, China, and also with
the Department of Electrical Engineering, City University of Hong Kong,
Hong Kong SAR 999077, China (e-mail: [lucas.zw.ye@outlook.com).](mailto:lucas.zw.ye@outlook.com)
Donglong Chen is with Beijing Normal-Hong Kong Baptist University,
Zhuhai 519087, China (e-mail: [donglongchen@uic.edu.cn).](mailto:donglongchen@uic.edu.cn)
Digital Object Identifier 10.1109/TC.2025.3590972



I. INTRODUCTION

ATTICE-BASED cryptography offers strong security
guarantees and efficient arithmetic for both post-quantum
# **L**
cryptography (PQC) and fully homomorphic encryption (FHE).
A key operation in lattice-based schemes is polynomial multiplication based on the number theoretic transform (NTT), which
plays an important role in overall efficiency [1], [2], [3].
The use of Fermat moduli in NTT offers significant advantages [4], [5], [6]. Fermat moduli take the form of
_Fn_ = 2 _[b]_ + 1 = 2 [2] _[n]_ + 1, enabling efficient modular reduction
via _x_ mod _Fn_ = ( _xlow_ - _−_ _xhigh_ ) mod _Fn_, where _xlow_ = _x_
mod 2 _[b]_ and _xhigh_ = _x/_ 2 _[b]_ [�] . Moreover, its modular multiplications by powers of 2 can be done with shifts alone [7]. Fermat
number transform (FNT), which refers to an NTT over a Fermat
modulus, enables the use of power-of-2 twiddle factors, thus reducing computational complexity. However, the power-of-twobased twiddle factors impose a strict constraint _N_ _≤_ 2 _[n]_ [+1] on
the transform size _N_, which also corresponds to the polynomial
degree. This limitation makes it challenging to directly support
many existing parameter sets, as most PQC and FHE schemes
rely on non-Fermat moduli and large _N_ .
Currently, a notable scheme that does not face the challenges
associated with Fermat moduli is Hawk [8], which explicitly
recommends the Fermat modulus _F_ 4 = 65537 in its specification document. Another modulus option in Hawk is 12289.
Hawk is the only lattice-based candidate in the second round of
the Additional Digital Signatures for the NIST PQC standardization process.
Additionally, although the Dilithium specification does not
recommend a Fermat modulus, Abdulrahman et al. [6] propose
switching the original large modulus 8380417 to a small Fermat
modulus 257 for computing the small products _cs_ 1 and _cs_ 2 in
Dilithium. The switching results in a speed-up of 33.1%-37.6%
for the relevant operations (basemul + INTT) of the signing
procedure on Cortex-M4.
Most importantly, Kim et al. [4] recently address the challenge by proposing a strategy to integrate Fermat moduli into
the FHE scheme CKKS, which could potentially be extended to
other similar scenarios involving non-Fermat moduli and very
large transform sizes. The strategy consists of two key steps:



0018-9340 © 2025 IEEE. All rights reserved, including rights for text and data mining, and training of artificial intelligence and similar technologies.
Personal use is permitted, but republication/redistribution requires IEEE permission. See https://www.ieee.org/publications/rights/index.html for more information.


Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


3520 IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025



1). Adoption of auxiliary Fermat modulus - After decomposing
the original a very large modulus _Q_ into small components
_qi_ using the RNS technique, a sufficiently large auxiliary Fermat modulus is introduced to replace _qi_ . 2). Polynomial Ring
Transformation - The original large polynomial degree _N_ is
decomposed into smaller sub-transforms _Ni_, enabling efficient
computations using Fermat moduli.
Developing efficient FNT-based polynomial multiplication in
hardware is essential not only for supporting existing schemes
like [8] and methods such as [6], but also for facilitating the
transition of approach in [4] to other potential schemes. Furthermore, it encourages more research focused on Fermat modulusbased cryptographic schemes, pursuing breakthroughs in high
efficiency from a parameter perspective.
However, FNT-based polynomial multiplication design remains insufficiently explored. One challenge is how to better
leverage FNT’s property of powers-of-2 twiddle factors.
Regarding the transform size constraint _N_ _≤_ 2 _[n]_ [+1] for enabling power-of-2 twiddle factors, an optical communication
work [9], based solely on simulations of a fully unrolled structure, demonstrates that high-radix structures can effectively
utilize power-of-2 twiddle factors even when _N_ _>_ 2 _[n]_ [+1] . Moreover, high-radix NTT enables greater parallelism and throughput while reducing the number of computation cycles and memory accesses, regardless of the chosen modulus. To leverage
these advantages, we design our FNT-based polynomial multiplier using high-radix and mixed-radix architectures, where
the mixed-radix design specifically addresses cases where _N_ is
not a power of the radix _R_ .
As high-radix designs introduce highly parallel processing,
they may result in excessive resource consumption and significant frequency degradation when radix _R_ is large. Most existing high-radix/mixed-radix designs, primarily based on R2 and
R4 configurations over other moduli, have not adequately addressed these issues. In the context of Fermat moduli, the challenges can be framed as follows: How can multiplications by
powers-of-2 and those involving the unavoidable non-powersof-2 twiddle factors be efficiently handled? Additionally, how
can resource reuse mechanisms be further optimized? Our work
goes beyond merely adopting Fermat moduli, it tackles these
challenges and fully exploits the properties of FNT in ways that
prior works have not explored.


_A._ _Related_ _Works_


_1)_ _NTT_ _Over_ _Fermat_ _Modulus:_ Ma et al. [5] propose an
FPGA implementation of PQC schemes with fixed parameters
_q_ = 65537 and _N_ = 256. This work adopts a simple R2-NTT
architecture with a special modular multiplier design. Combined with D1 representation, the partial products are obtained
by shifting and using multiplexers, followed by an accumulation
process to construct the modular multiplier without using DSP.
This work does not leverage the property that twiddle factors
in FNT can be powers of 2. Instead, it simply takes advantage
of the fact that, under the Fermat modulus, multiplication by
powers of 2 avoids modular reduction operation.



Works in other fields [9], [10], [11], [12], [13], [14], [15]
aim to utilize FNT to achieve a high-accuracy convolution at
a lower complexity compared to FFT-based methods in their
areas. Although these works have different applications, the
techniques combined with FNT are versatile. One important
technique is the D1 representation, which is usually combined
with FNT to simplify modular multiplication by a power of 2.
_2)_ _High-Radix/Mixed-Radix_ _NTT_ _Hardware_ _Design:_ In
cryptographic hardware works, high-radix NTT over general
moduli has been explored in works [16], [17], [18], [19], [20].
However, the radix _R_ is subject to two limitations in these
works. First, _R_ is typically limited to 4. Due to the complicated
NTT/INTT butterfly operations, more datapaths and interconnect networks [16], [20], higher radix will dramatically increase
the resource usage. Second, _R_ is usually constrained to be a
factor of _N_, limiting the configuration flexibility.
Duong-Ngoc and Lee [21] propose an R4&R2 mixed-radix
NTT architecture which can break the second limitation. However, the design does not reuse R2 and R4 butterfly units in each
stage, leading to substantial resource usage.
Li et al. [22], Guo and Li [23] explore the split-radix NTT,
which has a lower theoretical complexity than R4 NTT. However, the asymmetry of the split-radix butterfly complicates
the implementation, and the algorithm cannot fully exploit its
theoretical advantages in pipelined hardware implementations.
Many works explore designs with multiple butterfly units in
parallel [16], [17], [24], [25], [26]. Generally, by applying the
_m×_ radix- _R_ ( _m, R ≥_ 2) butterfly style instead of 1*R2 style, the
ideal cycles is reduced from _O_ ( _[N]_ 2 [log] _[ N]_ [)] [to] _[O]_ [(] _Rm_ _[N]_ [log] _[R][ N]_ [)][.]

However, it has been shown that an NTT kernel with multiple
R2 butterfly units is less efficient than an R4 NTT kernel [16].
Therefore, a unified mixed-radix architecture that can support large radix- _R_ as well as more _N_ is a promising research
direction to improve efficiency.
As for the conflict-free memory mapping for the temporary
data, Zhang et al. [24] propose a 2*R2 design and supports 4
data in parallel but require 8 address generators to determine
the reading and writing addresses. Chen et al. [16] reduce the
number of address generators by half and insert registers to get
writing addresses from reading addresses.


_B._ _Major_ _Contributions_


This paper proposes a polynomial multiplier based on highradix/mixed-radix FNT. The main contributions are as follows:

_•_ We propose high-radix and mixed-radix NTT/INTT with
merged pre-/post-processing algorithms. Specifically, the
transform processes are modularized, ensuring that D1
representation is employed for concentrated multiplications by power-of-2 constants in R2NTT/R2INTT module,
while retaining the benefits of normal representation for
multiplications by normal numbers in ModMuls module.
This modularization also facilitates PWM calculations and
supports complete polynomial multiplication.

_•_ We introduce a low-complexity conflict-free memory mapping scheme and extend it to support mixed-radix operations. This method reduces the complexity of memory



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


XING et al.: HIGH-RADIX/MIXED-RADIX NTT MULTIPLICATION ALGORITHM/ARCHITECTURE CO-DESIGN 3521



mapping and improves frequency and efficiency in highradix cases by requiring only one bank index as the select
signal for memory mapping interconnections.

_•_ We propose a polynomial multiplication architecture based
on FNT, configurable to a broader range of degree _N_ and
radix _R_ configurations. The architecture accommodates
radix _R_ = 4 _,_ 8 _,_ 16 and their mixed combinations, providing flexibility to meet varying latency and area constraints
with high efficiency. The architecture allows small-radix
stages to reuse the R2NTT, R2INTT and ModMul modules
from large-radix stages.

_•_ Our implementation shows that the R8 and R16 configurations offer comparable or better efficiency than the R4
configuration. In most cases, our design achieves a 30%–
85% reduction in DSP ATP and a 70%–100% reduction
in BRAM ATP compared to state-of-the-art designs with
smaller or equivalent modulus, while maintaining competitive LUT and FF ATP.


II. PRELIMINARY


_A._ _NTT-Based_ _Polynomial_ _Multiplication_


NTT is generally a Discrete Fourier Transform (DFT) over a
finite field Z _q_ = Z _/q_ Z. NTT and its inverse transform (INTT)
are defined as:



**9** _T_ _←_ _ω · a_ idx+Δidx mod _q_ ;

**10** _a_ idx+Δidx _←_ _a_ idx _−_ _T_ mod _q_ ;

**11** _a_ idx _←_ _a_ idx + _T_ mod _q_ ;


**12** _A ←_ _a_ ;


**Algorithm** **2:** R2INTT: Radix-2 DIF-INTTRN

**Input** **:** A vector _A_ of length _N_, modulus _q_, inversion
of a _N_ -th primitive root of unity _ωN_ _[−]_ [1] [in] [Z] _[q]_ [.]
**Output:** Output vector _a_ .

**1** **for** _s ←_ log( _N_ ) _−_ 1 **to** 0 **do**



**Algorithm** **1:** R2NTT: Radix-2 DIT-NTTNR

**Input** **:** A vector _a_ of length _N_, modulus _q_, _N_ -th
primitive root of unity _ωN_ in Z _q_ .
**Output:** Output vector _A_ .

**1** **for** _s ←_ 0 **to** log( _N_ ) _−_ 1 **do**

**2** _M_ _←_ 2 _[s]_ [+1] ;



**3** _ωM_ _←_ _ωN_ _[N/M]_ mod _q_ ;



**4** Δidx _←_ _N/_ 2 _[s]_ [+1] ;



**5** **for** _b ←_ 0 **to** 2 _[s]_ _−_ 1 **do**



**6** _ω ←_ _ωM_ [bit-rev][(] _[b]_ [)] mod _q_ ;



**7** **for** _g ←_ 0 **to** _N/_ 2 _[s]_ [+1] _−_ 1 **do**



**8** idx _←_ _b · N/_ 2 _[s]_ + _g_ ;



**3** _ωM_ _[−]_ [1] _[←]_ [(] _[ω]_ _N_ _[−]_ [1][)] _[N/M]_ [mod] _[q]_ [;]



**4** Δidx _←_ _N/_ 2 _[s]_ [+1] ;



_Ak_ = NTT _N_ ( _a_ ) _k_ =



_N_ - _−_ 1

_anωN_ _[nk]_ [mod] _[ q,]_ _[k]_ [ = 0] _[,]_ [ 1] _[, . . ., N]_ _[−]_ [1]
_n_ =0



**2** _M_ _←_ 2 _[s]_ [+1] ;



_N_         - _−_ 1
_an_ = INTT _N_ ( _A_ ) _n_ = _N_ _[−]_ [1] _AkωN_ _[−][nk]_ mod _q,_

_k_ =0



**5** **for** _b ←_ 0 **to** 2 _[s]_ _−_ 1 **do**



_n_ = 0 _, . . ., N_ _−_ 1


where _ωN_ is a primitive _N_ -th root of unit in Z _q_, i.e., _ωN_ _[N]_ _[≡]_ [1]
(mod _q_ ) and _ωN_ _[i]_ _[̸≡]_ [1] [(mod] _[q]_ [)] [for] [any] _[i]_ [ = 1] _[, ..., N]_ _[−]_ [1][.] [NTT]
also has the circular convolution property analogous to DFT.
Similar to the Fast Fourier transfor (FFT) for DFT, NTT supports a divide-and-conquer method to reduce the computational
complexity from _O_ ( _N_ [2] ) to _O_ ( _N_ log _N_ ). An iterative R2 DITNTT _NR_ algorithm and DIF-INTT _RN_ algorithm are provided in
Algorithms 1 and 2 respectively.

multiplication can be performed with the negative wrapped convolution method based on NTT. The coefficients of the product
_a_ ( _x_ ) _b_ ( _x_ ) = [�] _[N]_ _n_ =0 _[−]_ [1] _[c][n][x][n]_ [can] [be] [expressed] [by:]

_cn_ = (INTT _N_ (NTT _N_ ( _an · ω_ 2 _[n]_ _N_ [)] _[⊙]_ [NTT] _[N]_ [(] _[b][n]_ _[·][ ω]_ 2 _[n]_ _N_ [)))] _[n]_ _[·][ω]_ 2 _[−]_ _N_ _[n]_


where _ω_ 2 _N_ is a primitive (2 _N_ ) _th_ root of unit in Z _q_, thereby
_ωN_ _≡_ _ω_ 2 [2] _N_ [(mod] _[q]_ [)][.] [The] [point-wise] [multiplication] [inside]
NTTs and outside INTT are called pre-processing and postprocessing respectively.
Researchers make efforts to simplify the negative weighted
convolution by improving the FFT-like structure in NTT/INTT.
The works successfully eliminates the pre-processing [27], the
post-processing [28], the scaling factor _N_ _[−]_ [1] [24] and also the



**6** _ω_ _[−]_ [1] _←_ ( _ωM_ _[−]_ [1][)][bit-rev][(] _[b]_ [)] [mod] _[q]_ [;]



**7** **for** _g ←_ 0 **to** _N/_ 2 _[s]_ [+1] _−_ 1 **do**



**8** idx _←_ _b · N/_ 2 _[s]_ + _g_ ;



**9** _T_ _←_ 2 _[−]_ [1] ( _A_ idx + _A_ idx+Δidx) mod _q_ ;

**10** _A_ idx+Δidx _←_ 2 _[−]_ [1] _ω_ _[−]_ [1] ( _A_ idx _−_ _A_ idx+Δidx) mod _q_ ;

**11** _A_ idx _←_ _T_ ;


**12** _a ←_ _A_ ;


bit-reverse operation before NTT and after INTT [16], which
contribute to a scramble-free FFT-like structure for NTT/INTT
with _ω_ 2 _[±]_ _N_ _[n]_ [and] _[N][ −]_ [1] [merged] [in each] [stage.]


_B._ _NTT_ _Over_ _Fermat_ _Modulus_ _and_ _Diminished-1_
_Representation_


NTT over Fermat number modulus, i.e., _q_ = _Fn_ = 2 _[b]_ + 1 =
2 [2] _[n]_ + 1, is known as the Fermat number transform (FNT) [29],
which enables shifting operations to replace multiplications inside transforms when applying the power-of-2 twiddle factors.
This property highly depends on the relationship between _q_
and _N_ . Table I lists two commonly used modulus _F_ 3 and _F_ 4,
their corresponding root of unity _ωN_ and the degree _N_ . For
commonly used Fermat modulus _F_ 2 to _F_ 6, the twiddle factors
are all a power of 2 when _N_ _≤_ 2 _[n]_ [+1] [29].



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


3522 IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025



TABLE I
THE ROOT OF UNITY _ωN_ FOR DIFFERENT _N_ IN FNT


_Fn_ _ω_ 2 _ω_ 4 _ω_ 8 _ω_ 16 _ω_ 32 _ω_ 64 _ω_ 128 _ω_ 256 ... _ω_ 65536


1 1 1 1
_F_ 3 = 257 2 [8] 2 [4] 2 [2] 2 2 2 2 4 2 8 2 16

1 1 1 1
_F_ 4 = 65537 2 [16] 2 [8] 2 [4] 2 [2] 2 2 2 2 4 2 8 ... 2 4096


**Algorithm** **3:** Arithmetics Operations in Diminished-1



Norm_to_D1( _in_ )
**if** _in_ _==_ _0_ **then**

out _←_ 2 _[b]_ ;
**else**

out _←_ in _−_ 1;

**return** _out_


D1_to_Norm( _in_ )
**if** _in_ _==_ 2 _[b]_ **then**

out _←_ 0;
**else**

out _←_ in + 1;

**return** _out_


Mul_by_2 _[k]_ ( _k,_ _in_ )
**if** _in_ _==_ 2 _[b]_ **then**

out _←_ in;
**else**

**if** _k_ _≥_ _0_ **then**



Addition( _in1,_ _in2_ )
**if** _in1_ _==_ 2 _[b]_ **then**

out _←_ in2;
**else** **if** _in2_ _==_ 2 _[b]_ **then**

out _←_ in1;
**else**

out _←_ in1 + in2;
out _←_ out[ _b −_ 1 : 0]+ _∼_ out[ _b_ ];

**return** _out_


Negation( _in_ )
**if** _in_ _==_ 2 _[b]_ **then**

out _←_ 2 _[b]_ ;
**else**

out _←{_ 1 _[′]_ _b_ 0 _, ∼_ in[ _b −_ 1 : 0] _}_ ;

**return** _out_



and optimizing the throughput rate in polynomial multiplication. Two main memory access strategies exist for NTT architectures: constant-geometry NTT and in-place NTT. In con
ture inherently avoids read-the-same-bank (RSB) conflicts but
still requires mechanisms to handle read-after-write (RAW)
conflicts. To eliminate redundant storage, some works, such
as [16], [17], [24], [30], [33], favor in-place NTT, where
temporary data are read from and written to the same addresses within the banks. This approach requires addressing
both RSB and RAW conflicts, which we also tackle in our
design.
RSB conflict occurs when different data points in the same
bank are required in the same cycle. [30], [33] propose a similar
compact memory scheme to avoid the RSB conflict. Assuming
there are _R_ banks for the temporary data, the mapped bank
index and address for each data point with an original address
are as follows:



_⌈_ [log] log _[ N]_ _R_
BankIndex =



OrigAddr[(log _R_ )

_i_ =0



OrigAddr = _b_ log _N_ _−_ 1 _...... b_ 2 log _R−_ 1 _. . . b_ log _R_

~~�~~ ~~��~~            log _R_ _bits_



_b_ log _R−_ 1 _. . . b_ 0 _,_

~~�~~ ~~��~~ log _R_ _bits_




[log] log� _[ N]_ _R_ _[⌉][−]_ [1]



out _←|k|_ -bit left invert circular shift for in[ _b −_ 1 : 0]
**else**

out _←|k|_ -bit right invert circular shift for in[ _b −_ 1 : 0]


**return** _out_


Considering _b_ + 1 bits is required for representing all the possible results for Fermat number _Fn_ = 2 _[b]_ + 1, our work does not
use only _b_ bits to represent data or ignore the number 2 _[b]_ as [29].
It is because we would like to avoid a highly improbable but
plausible chance of the polynomial coefficients being affected
by errors when the value _−_ 1 occurs during NTT computation.
Instead, we follow [7] to apply D1 representation, which represents the original number _x_ as _x −_ 1. _b_ bits are used to represent
numbers from 1 to 2 _[b]_, while an extra bit is used to represent
0. For example, with modulus _F_ 2 = 17 = 10001 _B_, the number
from 00001 _B_ to 10000 _B_ in normal binary representation is
represented as 00000 _B_ to 01111 _B_ in D1 respectively, while
the number 00000 _B_ is represented as 10000 _B_ .
The computations about D1 are listed in Algorithm 3. The
bit-width of inputs and outputs are _b_ + 1. The utilization of
D1 reduces modular multiplication by constant powers of 2 to
approximately a circular shift.


_C._ _Memory_ _Access_ _Conflicts_


Scalability across varying numbers of parallel butterfly units
and different radices is essential for managing parallelism




_·_ ( _i_ + 1) : (log _R_ ) _i_ ] mod _R,_

BankAddr = _b_ log _N_ _−_ 1 _. . . . . . b_ 2 log _R−_ 1 _. . . b_ log _R._


A 4-bank memory mapping is shown in Fig. 1(a). Zhang et al.

[24] note that this method still encounters an RSB conflict in
one stage of a 2*R2 design, as illustrated in Fig. 1(b), and they
handle this stage specifically. This design supports 4 operations
in parallel but requires 8 address generators to determine the
bank indexes for reading and writing. Chen et al. [16] and
Mu et al. [17] address this by new schemes with increased
complexity. Chen et al. [16] reduce the number of address generators by half and inserts registers to get writing addresses from
reading addresses. Fortunately, the original scheme introduces
no RSB conflict when there is only one radix- _R_ butterfly unit.
Our design further reduces the address generator to only 1,
minimizing logic and register usage.
RAW conflict occurs when the data is fetched again before
it completes the pipeline of the previous stage, as shown in
Fig. 1(c). The cycles between reading and storage should be
less or equal to the minimum cycles between fetching the same
data points, i.e., _mRN_ [2] [, in] [an] _[m]_ [*radix-] _[R]_ [design.]
This type of conflict is usually not a concern in most works
where _N_ is large or _R_ is small. However, it is very likely to
happen in high-radix designs. Mu et al. [17] pursue a fullypipelined design, sacrificing many choices of _R_ when RAW
conflict happens. Our design simply inserts stalls to avoid RAW
conflict as Fig. 1(d). The added cycles and the registers consumption due to stalls are acceptable compared to the gaining
from high radix, especially when _N_ is relatively large.



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


XING et al.: HIGH-RADIX/MIXED-RADIX NTT MULTIPLICATION ALGORITHM/ARCHITECTURE CO-DESIGN 3523


(a) (b)


(c) (d)


Fig. 1. Two types of conflict. The bank indexes are indicated by different colors. (a): 4-bank memory mapping by [30] ( _≤_ 64 points). (b): A read-the-samebank (RSB) conflict example in 16-points 2*R2 design. _{a_ 4 _, a_ 1 _}_, _{a_ 6 _, a_ 3 _}_, _{a_ 12 _, a_ 9 _}_ and _{a_ 14 _, a_ 11 _}_ are required at the same cycle but located in the same
bank. (c): A read-after-write (RAW) conflict example in 16-point 1*R4 design. _a_ 3 is read again in stage 2 before its result from stage 0 is written into the
bank. (d): Inserting stalls to delay the writing operations thereby avoiding RAW conflict.



III. HIGH-RADIX/MIXED-RADIX NTT AND INTT


Building upon the derivation ideas from [16], [34], we provide a detailed derivation of high-radix DIT-NTT and DIFINTT with pre/post-processing. Furthermore, we extend the
discussion by proposing our high-radix/mixed-radix algorithms
specifically tailored for FNT and its inverse transform.


_A._ _High-Radix_ _DIT-NTT_ _With_ _Merged_ _Pre-Processing_


The radix- _R_ length- _N_ DIT-NTT with merged pre-processing
can be obtained by



By denoting _{aRi_ + _r}_ as _{si,r}_, the above equation can be
written as



_N_
_R_ ~~�~~ _[−]_ [1]




_[k]_ [+1)] _[i]_
_N_ + _ω_ 2 [(2] _N_ _[k]_ [+1)]

_R_



_N_
_R_ ~~�~~ _[−]_ [1]



_si,_ 1 _ω_ [(2] 2 _N_ _[k]_ [+1)] _[i]_

_R_

_i_ =0



_R_



_A_ k =


=



_R_ - _−_ 1

_ω_ 2 _[r]_ _N_ [(2] _[k]_ [+1)]
_r_ =0



_si,_ 0 _ω_ [(2] 2 _N_ _[k]_ [+1)] _[i]_

_R_

_i_ =0



_N_ mod _q,_

_R_



+ _. . ._ + _ω_ 2 [(] _[R]_ _N_ _[−]_ [1)(2] _[k]_ [+1)]



_N_
_R_ ~~�~~ _[−]_ [1]



_si,R−_ 1 _ω_ [(2] 2 _N_ _[k]_ [+1)] _[i]_

_R_

_i_ =0



_N_ mod _q_

_R_



_N_
_R_ ~~�~~ _[−]_ [1]



_si,rω_ [(2] 2 _N_ _[k]_ [+1)] _[i]_

_R_

_i_ =0



_N_
_R_ ~~�~~ _[−]_ [1]

_aRi_ +1 _ω_ 2 [(2] _N_ _[k]_ [+1)(] _[Ri]_ [+1)]
_i_ =0



where _k_ = 0 _, ..., N_ _−_ 1. Due to the periodicity, it can be further
expressed as



_A_ k =


=


=



_N_ - _−_ 1

_anω_ 2 _[n]_ _N_ _[ω]_ _N_ _[kn]_ [mod] _[ q]_
_n_ =0


_N_
_R_ ~~�~~ _[−]_ [1]

_aRiω_ 2 [(2] _N_ _[k]_ [+1)(] _[Ri]_ [)] +
_i_ =0



_N_
_R_ ~~�~~ _[−]_ [1]

_aRiω_ 2 [(2] _N_ _[k]_ [+1)(] _[Ri]_ [)] + _ω_ 2 [(2] _N_ _[k]_ [+1)]
_i_ =0



where _l_ = 0 _, ...,_ _[N]_



_Al_ + _NR_ _[j]_ [=]


=



(2( _l_ + _R_ _[j]_ [)+1)] _[i]_

2 _N_



_R_ - _−_ 1



_r_ (2( _l_ + _R_ _[j]_ [)+1)]

2 _N_



_N_
_R_ ~~�~~ _[−]_ [1]



_si,rω_ (2(2 _Nl_ + _[N]_ _R_

_R_

_i_ =0



2 _N_ _R_ mod _q_

_R_



_ω_ 2 _rN_ (2( _l_ + _[N]_ _R_
_r_ =0



_R_ - _−_ 1

_ωR_ _[rj][ω]_ 2 _[r]_ _N_ [(2] _[l]_ [+1)]
_r_ =0



_N_ mod _q,_

_R_



_N_
_R_ ~~�~~ _[−]_ [1]



_si,rω_ [(2] 2 _N_ _[l]_ [+1)] _[i]_

_R_

_i_ =0



+ _. . ._ +



_N_
_R_ ~~�~~ _[−]_ [1]

_aRi_ + _R−_ 1 _ω_ 2 [(2] _N_ _[k]_ [+1)(] _[Ri]_ [+] _[R][−]_ [1)] mod _q_
_i_ =0



_N_
_R_ ~~�~~ _[−]_ [1]

_aRi_ +1 _ω_ 2 [(2] _N_ _[k]_ [+1)(] _[Ri]_ [)]
_i_ =0



where _l_ = 0 _, ...,_ _[N]_ _R_ _[−]_ [1] _[, j]_ [ = 0] _[, ..., R][ −]_ [1][. The steps of NTT with]

merged pre-processing can be summarized as:
1) Derive _R_ _N_ [-][point] NTT with merged pre



     - _R_      processing� _Sl,r|l_ = 0 _, ...,_ - _[N]_ _R_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1)

of _si,r|i_ = 0 _, ...,_ _[N]_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1) from




  - _R_

_[N]_ _R_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1) from



+ _. . ._ + _ω_ 2 [(] _[R]_ _N_ _[−]_ [1)(2] _[k]_ [+1)]



_N_
_R_ ~~�~~ _[−]_ [1]

_aRi_ + _R−_ 1 _ω_ 2 [(2] _N_ _[k]_ [+1)(] _[Ri]_ [)] mod _q._
_i_ =0



Derive _R_ - _R_ [-][point] NTT with� merged pre
processing _Sl,r|l_ = 0 _, ...,_ _[N]_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1)



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


3524 IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025


_{an|n_ = 0 _, ..., N_ _}_ as Eqs. 1 and 2.



_N_
_R_ ~~�~~ _[−]_ [1]



_Sl,r_ =



_si,rω_ [(2] 2 _N_ _[l]_ [+1)] _[i]_

_R_

_i_ =0



_N_ _mod_ _q,_ (1)

_R_



_si,r_ = _aRi_ + _r_ = _an._ (2)

~~�~~             2) Derive _{s_ ˆ _l,r}_ by multiplying _Sl,r_ from Step 1 by
_ω_ 2 _[r]_ _N_ [(2] _[l]_ [+1)] as Eq. 3:



_s_ ˆ _l,r_ = _Sl,rω_ 2 _[r]_ _N_ [(2] _[l]_ [+1)] _mod_ _q,_ (3)




     -      
_[N]_ _R_ _[R]_ [-point] [NTT] _S_ ˆ _l,j|j_ = 0 _, ..., R −_ 1 ( _l_ =



3) Compute _[N]_



0 _, ...,_ _[N]_




_[N]_ _R_ _[−]_ [1)] [of] _[{][s]_ [ˆ] _[l,r][|][r]_ [ = 0] _[, ..., R][ −]_ [1] _[}]_ [(] _[l]_ [ = 0] _[, ...,]_ _[N]_ _R_



0 _, ...,_ _[N]_ _R_ _[−]_ [1)] [of] _[{][s]_ [ˆ] _[l,r][|][r]_ [ = 0] _[, ..., R][ −]_ [1] _[}]_ [(] _[l]_ [ = 0] _[, ...,]_ _[N]_ _R_ _[−]_

1) from Step 2 as Eq. 4.



_S_ ˆ _l,j_ =


2 _N_



_R_ - _−_ 1

_s_ ˆ _l,rωR_ _[rj]_ [mod] _[ q,]_ (4)
_r_ =0



where _ωR_ = _ω_ 2 _RN_ [mod] _[ q]_ [. The final result can be obtained]

by Eq. 5:



_Ak_ = _A_ l+ NR _[j]_ [=] _[S]_ [ˆ] _[l,j][.]_ (5)



Fig. 2(a) demonstrates the symbols’ relationship. Step 3 can be
performed by unroll R2NTT as Algorithm 1. For _q_ = _Fn_ and
_R ≤_ 2 _[n]_ [+1], Step 3 requires no multiplications, only shifts, since
_ωR_ is a power of 2, as discussed in Section II-B. By recursively
decomposing Step 1 with radix _R_, the computation complexity
can be reduced from _O_ ( _N_ [2] ) to _O_ ( _N_ log _R N_ ).
Additionally, one key configuration is to maintain _ωR_ as the

2 _N_

same _ω_ 2 _RN_ [from] [the] [original] [size] _[N]_ [and] _[ω]_ [2] _[N]_ [throughout] [the]

decomposition. This ensures that twiddle factors remain unchanged across different _R_ -point NTTs, allowing for the design
of one fixed _R_ -point NTT module. The upper part of Fig. 2(b)
shows the flow of a high-radix NTT with pre-processing, which
alternates between multiplications and NTTs. The left part of
Fig. 3(a) show an R16 NTT butterfly. In this way, for a Fermat modulus, a NTT with merged pre-processing can leverage power-of-2 constant multiplications without the constraint
_N_ _<_ 2 _[n]_ [+1], only requiring _R ≤_ 2 _[n]_ [+1] .


_B._ _High-Radix_ _DIF-INTT_ _With_ _Merged_ _Post-Processing_


The radix- _R_ length- _N_ DIF-INTT with merged postprocessing can be obtained by




 _N_
=
_R_




- _−_ 1
_ω_ _[−]_ 2 _N_ _[i]_

_R_



Fig. 2. The flow of high-radix/mixed-radix NTT/INTT with pre/postprocessing.



_R_ _[ω]_ _R_ _[−][jn]_ ) _ωN_ _[−][ln]_ mod _q._



= _N_ _[−]_ [1] _ω_ 2 _[−]_ _N_ _[n]_



_N_
_R_ ~~�~~ _[−]_ [1]


_l_ =0



_R_ - _−_ 1



( _Al_ + _jNR_
_j_ =0



N [as] _[{][S]_ [ ˆ] _[l,j][}]_ [,] [it] [can] [be] [written as]

R _[j][}]_



By denoting _{A_ l+ N




  _N_
_an_ =
_R_




- _−_ 1
_ω_ 2 _[−]_ _N_ _[n]_



_N_
_R_ ~~�~~ _[−]_ [1]


_l_ =0



⎛



_S_ ˆ _l,jωR_ _[−][jn]_
_j_ =0



_R_   - _−_ 1
⎝ _R_ _[−]_ [1]



⎞



⎠ _ωN_ _[−][ln]_ mod _q,_



where _k_ = 0 _, ..., N_ _−_ 1. Due to the periodicity, it can be further
expressed as




   _N_
_aRi_ + _r_ =
_R_




- _l_ =0

mod _q_




- _−_ 1 _NR_ ~~�~~ _[−]_ [1]
_ω_ 2 _[−]_ _N_ [(] _[Ri]_ [+] _[r]_ [)]




- _R_ - _−_ 1
_R_ _[−]_ [1] ( _S_ [ˆ] _l,jωR_ _[−][j]_ [(] _[Ri]_ [+] _[r]_ [)] )

_j_ =0




_· ωN_ _[−][l]_ [(] _[Ri]_ [+] _[r]_ [)]







_l_ =0



��� _R_ - _−_ 1
_R_ _[−]_ [1]



_N_
_R_ ~~�~~ _[−]_ [1]



_S_ ˆ _l,jωR_ _[−][jr]_
_j_ =0





mod _q,_



_AkωN_ _[−][kn]_ mod _q_



_an_ = _N_ _[−]_ [1] _ω_ 2 _[−]_ _N_ _[n]_


= _N_ _[−]_ [1] _ω_ 2 _[−]_ _N_ _[n]_


_N_
_R_ ~~�~~ _[−]_ [1]



_N_ - _−_ 1




_−_ ( _l_ + [2] _R_ _[N]_
_RN_ _[ω]_ _N_




_· ω_ 2 _[−]_ _N_ [(2] _[l]_ [+1)] _[r]_





_· ω_ _[−]_ _N_ _[li]_
_R_



_k_ =0

- _N_
_R_ ~~�~~ _[−]_ [1]


_l_ =0



_R_  - _[l,r]_  
_[N]_ _R_ _[−]_ [1)] [of] _S_ ˆ _l,j|j_ = 0 _, ..., R −_ 1 ( _l_ = 0 _, ...,_ _[N]_ _R_



Compute _[N]_ _R_ _[R]_ [-point] - [INTT] _[{][s]_ [ˆ] _[l,r][|][r]_ [ = 0] - _[, ..., R][ −]_ [1] _[}]_ [(] _[l]_ [ =]

0 _, ...,_ _[N]_ _[−]_ [1)] [of] _S_ ˆ _l,j|j_ = 0 _, ..., R −_ 1 ( _l_ = 0 _, ...,_ _[N]_ _[−]_



where _i_ = 0 _, ...,_ _[N]_



where _i_ = 0 _, ...,_ _[N]_ _R_ _[−]_ [1] _[, r]_ [ = 0] _[, ..., R][ −]_ [1][.] [The] [steps] [of] [INTT]

with merged post-processing can be summarized as:
1) Compute _[N]_ _[R]_ [-point] [INTT] _[{][s]_ [ˆ] _[l,r][|][r]_ [ = 0] _[, ..., R][ −]_ [1] _[}]_ [(] _[l]_ [ =]



_AlωN_ _[−][ln]_ +



_N_
_R_ ~~�~~ _[−]_ [1]


_l_ =0




_−_ ( _l_ + _[N]_ _R_

_NR_ _[ω]_ _N_



_Al_ + _N_




_−_ ( _l_ + _R_ [)] _[n]_

_N_



_R_ ~~�~~   
1) from _Ak|k_ = 0 _, ..., N_ as Eqs. 6 and 7 as



_R_ _[−]_



+


+



_l_ =0


_N_
_R_ ~~�~~ _[−]_ [1]


_l_ =0



_Al_ + 2 _N_



_A_ ( _R−_ 1) _N_
_l_ +




_−_ ( _l_ + [(] _[R][−]_ _R_ [1)] _[N]_
_R_ 1) _N_ _ωN_




_−_ ( _l_ + _R_ [)] _[n]_

_N_ + _..._



mod _q_








_−_ ( _l_ + _R_ ) _n_

_N_



_R_     - _−_ 1
_s_ ˆ _l,r_ = _R_ _[−]_ [1] _S_ ˆ _l,jωR_ _[−][jr]_ mod _q,_ (6)

_j_ =0



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


XING et al.: HIGH-RADIX/MIXED-RADIX NTT MULTIPLICATION ALGORITHM/ARCHITECTURE CO-DESIGN 3525


Fig. 3. R16 butterfly units are applied to R16 cases and R4 cases.



2 _N_

where _ωR_ = _ω_ 2 _RN_ [mod] _[ q]_ [.]



_S_ ˆ _l,j_ = _A_ l+ N



NR _[j]_ [=] _[ A][k][,]_ (7)




    -     2) Derive _Sl,r_ by multiplying _{s_ ˆ _l,r}_ from Step 1 by
_ω_ 2 _[−]_ _N_ [(2] _[l]_ [+1)] _[r]_ as Eq. 8:



_Sl,r_ = ˆ _sl,rω_ 2 _[−]_ _N_ [(2] _[l]_ [+1)] _[r]_ mod _q._ (8)



3) Derive _R_ _N_



Derive _R_ - _R_ [-point] INTT �with merged post
processing _si,r|i_ = 0 _, ...,_ _[N]_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1) of




    - _R_     p ~~�~~ rocessing _si,r|i_ = 0� _, ...,_ _[N]_ _R_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1) of

_Sl,r|l_ = 0 _, ...,_ _[N]_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1) from Step 2




~~�~~ _i,r_ - _R_
_Sl,r|l_ = 0 _, ...,_ _[N]_ _R_ _[−]_ [1] ( _r_ = 0 _, ..., R −_ 1) from Step 2

as Eqs. 9 and 10.




  -   - _−_ 1
_N_
_si,r_ = _ω_ _[−]_ 2 _N_ _[i]_
_R_ _R_



_N_
_R_ ~~�~~ _[−]_ [1]


_l_ =0



_Sl,rω_ _[−]_ _N_ _[li]_ (9)
_R_ [mod] _[ q,]_



Additionally, one key configuration is to maintain _ωR_ _[−]_ [1] as

2 _N_

the same _ω_ 2 _RN_ [from] [the] [original] [size] _[N]_ [and] _[ω]_ [2] _[N]_ [throughout]

the decomposition. This ensures that twiddle factors remain
unchanged across different _R_ -point INTTs, allowing for the
design of one fixed _R_ -point INTT module. The lower part
of Fig. 2(b) shows the flow of a high-radix INTT with postprocessing, which alternates between INTTs and modular multiplications. The left part of Fig. 3(b) show an R16 INTT
butterfly.
In this way, for a Fermat modulus, an INTT with merged
post-processing can leverage power-of-2 constant multiplications without the constraint _N_ _<_ 2 _[n]_ [+1], only requiring
_R ≤_ 2 _[n]_ [+1] .


_C._ _Proposed_ _High-Radix/Mixed-Radix_ _Algorithms_ _for_
_DIT-NTT_ _and_ _DIF-INTT_


In this subsection, we propose an improved iterative algorithms for high-radix and mixed-radix NTT and INTT. The iterative algorithms for high-radix/mixed-radix NTT with merged
pre-processing and INTT with merged post-processing are detailed in Algorithms 4 and 5, respectively. To clarify, in this paper, one complete process of ModMuls and an R2NTT/R2INTT



_an_ = _aRi_ + _r_ = _si,r,_ (10)


Fig. 2(a) demonstrates the symbols relationship. Step 1 can
be performed by an unroll R2INTT as Algorithm 2. For _q_ = _Fn_
and _R ≤_ 2 _[n]_ [+1], Step 1 consumes no multiplications, only shifts,
since _ωR_ _[−]_ [1] is a power of 2, as discussed in Section II-B. By
recursively decomposing Step 3 with radix _R_, the computation
complexity can be reduced from _O_ ( _N_ [2] ) to _O_ ( _N_ log _R N_ ).



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


3526 IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025


**Algorithm** **4:** High-radix/Mixed-radix NTT _NR_ with merged pre-processing

**Input** **:** A vector _a_ of length _N_, modulus _q_, 2 _N_ -th primitive root of unity _ω_ 2 _N_ in Z _q_, radix _R_ .
**Output:** Output vector _A_ .



**1** _ωR ←_ _ω_ 2N [2N] _[/R]_ ;

**2** **for** _s ←_ 0 **to** _⌊_ log( _N_ ) _/_ log( _R_ ) _⌋−_ 1 **do**

**3** _M_ _←_ _R_ _[s]_ [+1] ;

**4** _ω_ 2 _M_ _←_ _ω_ 2 _[N/M]_ _N_ mod _q_ ;



**5** Δidx _←_ _N/R_ _[s]_ [+1] ;



**6** **for** _b ←_ 0 **to** _R_ _[s]_ _−_ 1 **do**



**7** **for** _g ←_ 0 **to** _N/R_ _[s]_ [+1] _−_ 1 **do**



**16** **if** _s ̸_ = log( _N_ ) _/_ log( _R_ ) **then**

**17** _R_ ˆ _←_ _N/R_ _[s]_ ;

**18** _ω_ 2 _M_ _←_ _ω_ 2 _N_ ;

**19** **for** _b ←_ 0 **to** _R_ _[s]_ _−_ 1 **by** _R/R_ [ˆ] **do**

**20** idx _←_ _b ·_ _R_ [ˆ] ;

// unroll from line 20 to 27

**21** **for** _r_ 1 _←_ 0 **to** _R_ [ˆ] _−_ 1 **do**



**8** idx _←_ _b · N/R_ _[s]_ + _g_ ;

// unroll from line 9 to 14



**23** _Tr_ 1 _·_ _R_



**22** **for** _r_ 2 _←_ 0 **to** _[R]_




_[R]_ _R_ ˆ _[−]_ [1] **[do]**



**9** **for** _r ←_ 0 **to** _R −_ 1 **do**

**10** _Tr_ _←_ _a_ idx+Δidx _·r_ _· ω_ 2 _[r]_ _M_ _[·]_ [(2] _[·]_ [bit-rev][(] _[b]_ [)+1)] mod _q_
// ModMul

**11** _Tr_ _←_ Norm_to_D1( _Tr_ );


**12** _T_ _←_ R2NTT( _T, R, q, ωR_ )

**13** **for** _r ←_ 0 **to** _R −_ 1 **do**

**14** _a_ idx+Δidx _·r_ _←_ D1_to_Norm( _Tr_ );


**15** _s ←_ _s_ + 1;


is called a ‘stage’, while a single layer of R2 butterfly operations
within the R2NTT is termed a ‘substage’. Our optimization can
be captured in three main points.

_•_ **First,** **we** **maximize** **the** **concentration** **of** **power-of-2**
**constant** **multiplications** **into** **the** **fixed** **R2NTT** **and**
**R2INTT** **using** **high-radix** **methods.**
By setting _q_ = _Fn_ and _R ≤_ 2 _[n]_ [+1], all the twiddle factors
in R2NTT/R2INTT are powers of 2 because _ωR_ is a power
of 2 as discussed in Section II-B. The R2NTT/R2INTT is
static in different stages due to a fixed _ωR_ . It is important
to note that there can be multiple _R_ -th roots of unity or
_N_ -th roots of unity in Z _q_ . However, _ωR_ must be _ω_ 2 [2] _N_ _[N/R]_
for the selected _ω_ 2 _N_ to ensure correctness.
In other designs, although many twiddle factors are
powers of 2 at various stages (especially _ω_ [0] = 1), these
twiddle factors are not fixed in the butterfly module, requiring flexible multipliers to handle different twiddle factors.
In contrast, our algorithm separates static power-of2 multiplications in R2NTT/R2INTT and dynamic nonpower-of-2 multiplications in ModMuls. This allows specific constant processing to be applied to R2NTT/R2INTT,
and the ModMuls hardware can be reused for PWM between NTT and INTT.

_•_ **Second,** **we** **reuse** **the** _R_ **-point** **R2NTT** **and** **R2INTT**
**for** **the** **special** **radix-** _R_ [ˆ] **stage** **in** **mixed-radix** **cases.**
To address cases where _R_ is not a root of _N_, we propose
a mixed-radix approach by applying a radix- _R_ [ˆ] stage at the
end of NTT and the beginning of INTT, as illustrated in
Fig. 2(c). Fig. 3(a) and 3(b) demonstrate how to extract
four R4 butterfly unit from an R16 unit in NTT and INTT,



_RR_ ˆ [+] _[r]_ [2] _[ ←]_ _[a]_ [idx][+] _[r]_ [1+] _[r]_ [2] _[·]_ _R_ [ ˆ] _[·][ ω]_ 2 _[r]_ _M_ [1] _[·]_ [(2] _[·]_ [bit-rev][(] _[b]_ [+] _[r]_ [2)+1)]

mod _q_ // ModMul



_RR_ ˆ [+] _[r]_ [2] _[ ←]_ [Norm_to_D1][(] _[T][r]_ [1] _[·]_ _R_ _[R]_ ˆ



**24** _Tr_ 1 _·_ _R_



_R_ _[R]_ ˆ [+] _[r]_ [2][)][;]



**25** _T_ _←_ The first log _R_ [ˆ] substages of R2NTT( _T, R, q, ωR_ );
// Algorithm 1 with line 1 having _s_ from
0 to log _R_ [ˆ] _−_ 1

**26** **for** _r_ 1 _←_ 0 **to** _R_ [ˆ] _−_ 1 **do**



**27** **for** _r_ 2 _←_ 0 **to** _[R]_




_[R]_ _R_ ˆ _[−]_ [1] **[do]**




_[R]_ _R_ ˆ [+] _[r]_ [2][)][;]



**28** _a_ idx+ _r_ 1+ _r_ 2 _·R_ ˆ _[←]_ [D1_to_Norm][(] _[T]_ _r_ 1 _·_ _[R]_



**29** _A ←_ _a_ ;


respectively. The ModMuls is fully reused, while the first
log _R_ [ˆ] substages of radix- _R_ R2NTT and the last log _R_ [ˆ] substages of radix- _R_ R2INTT are reused to construct radix- _R_ [ˆ]
R2NTT and R2INTT respectively.

_•_ **Third,** **we** **strategically** **apply** **D1** **representation** **in**
**R2NTT** **and** **R2INTT** **and** **normal** **representation** **in**
**ModMuls.**
The D1 representation exhibits varying levels of efficiency for different arithmetic operations in Z _Fn_, as illustrated in Algorithm 3. Modular multiplications by a
power of 2 benefit the most, requiring only circular shifting. Modular addition offers neither significant benefits
nor disadvantages, while modular subtraction is similar to
addition since it can be treated as a negation followed by
a modular addition.
However, modular multiplication by non-powerof-2 numbers in D1 is more complex. The direct
computation is illustrated as _D_ 1( _x · ω_ ) mod _q_ =
_x · ω_ _−_ 1 mod _q_ = ( _x_ _−_ 1) _·_ ( _ω_ _−_ 1) + _x_ + _ω −_ 2
mod _q_ = _D_ 1( _x_ ) _· D_ 1( _ω_ ) + _D_ 1( _x_ ) + _D_ 1( _ω_ ) mod _q_ .
Instead, [5] computes normal multiplication by computing
the partial products 2 _[i]_ _x_ [ _i_ ] _· ω_ with D1, followed by
accumulation in D1. While this method leverages the
benefits of D1, it sacrifices DSP utilization in FPGA.
Applying this method in high-radix cases would lead to
significant consumption of LUTs and FFs, along with
potential frequency degradation due to complex routing.
Therefore, we choose to apply D1 representation in the
R2NTT/R2INTT, which involves modular multiplications
by power-of-2 constants, modular additions and modular



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


XING et al.: HIGH-RADIX/MIXED-RADIX NTT MULTIPLICATION ALGORITHM/ARCHITECTURE CO-DESIGN 3527


**Algorithm** **5:** High-radix/Mixed-radix INTT _RN_ with merged post-processing

**Input** **:** A vector _A_ of length _N_, modulus _q_, the inversion of a 2 _N_ -th primitive root of unity _ω_ 2 _[−]_ _N_ [1] [in] [Z] _[q]_ [,] [radix] _[R]_ [.]
**Output** **:** Output vector _a_ .



**1** _ωR_ _[−]_ [1] _[←]_ [(] _[ω]_ 2N _[−]_ [1][)][2N] _[/R]_ [;]

**2** _s ←⌊_ log( _N_ ) _/_ log( _R_ ) _⌋_ ;



**17** **for** _s ←⌊_ log( _N_ ) _/_ log( _R_ ) _⌋−_ 1 **to** 0 **do**

**18** _M_ _←_ _R_ _[s]_ [+1] ;



































|Col1|f s|Col3|Col4|
|---|---|---|---|
|||||
|**7**<br>**8**<br>**9**<br>**10**<br>**11**<br>**12**<br>**13**<br>**14**<br>**15**<br>**16**|||idx_ ←b ·_ ˆ_R_;<br>// unroll from line 8 to 16<br>**for** _r_1_ ←_0 **to** ˆ_R −_1 **do**<br>**for** _r_2_ ←_0 **to** _R_<br>ˆ<br>_R −_1 **do**<br>_Tr_1_· R_<br>ˆ<br>_R_ +_r_2_ ←_Norm_to_D1(_Aidx_+_r_1+_r_2_·R_);<br>_T ←_The last log ˆ_R_ substages of R2INTT(_T, R, q, ω−_1<br>_R_ );<br>// Algorithm 2 with line 1 having _s_ from<br>log ˆ_R −_1 to 0<br>**for** _r_1_ ←_0 **to** ˆ_R −_1** do**<br>**for** _r_2_ ←_0 **to** _R_<br>ˆ<br>_R −_1** do**<br>_Tr_1_· R_<br>ˆ<br>_R_ +_r_2_ ←_D1_to_Norm(_Tr_1_· R_<br>ˆ<br>_R_ +_r_2);<br>_Tr_1_· R_<br>ˆ<br>_R_ +_r_2_ ←A_idx+_r_1+_r_2_·_ ˆ<br>_R · ω−r_1_·_(2_·_bit-rev(_b_+_r_2)+1)<br>2_M_<br>_A_idx+_r_1+_r_2_·_ ˆ<br>_R ←Tr_1_· R_<br>ˆ<br>_R_ +_r_2 mod_ q_<br>// ModMul<br>**23**<br>idx_ ←b · N/Rs_ +_ g_;<br>// unroll from line 24 to 29<br>**24**<br>**for** _r ←_0 **to** _R −_1 **do**<br>**25**<br>_Tr ←_Norm_to_D1(_Aidx_+Δ_idx·r_);<br>**26**<br>_T ←_R2INTT(_T, R, q, ω−_1<br>_R_ )**for** _r ←_0 **to** _R −_1 **do**<br>**27**<br>_Tr ←_D1_to_Norm(_Tr_);<br>**28**<br>_Aidx_+Δ_idx·r ←Tr · ω−r·_(2_·_bit-rev(_b_)+1)<br>2_M_<br>mod_ q_<br>// ModMul<br>**29** _a ←A_;|
|**7**<br>**8**<br>**9**<br>**10**<br>**11**<br>**12**<br>**13**<br>**14**<br>**15**<br>**16**||||


**Algorithm** **6:** Existing memory mapping scheme







subtractions. For the ModMuls, which only involves modular multiplications by normal numbers, we use the normal
representation. This approach optimizes DSP resource usage in FPGAs while maintaining the advantages of D1 for
modular multiplications by powers of 2.


IV. REDUCED-COMPLEXITY CONFLICT-FREE
MEMORY MAPPING


In an in-place design, _R_ parallel data are read from _R_ banks,
processed, and then written back to the same addresses. Existing
designs require _R_ parallel address generators to compute the
bank indexes, which control the interconnection of the bank addresses and the data read/write. By using the method discussed
in Section II-C, the existing mapping algorithm can be summarized in Algorithm 6. In previous works, _R_ is small so it is not
a heavy task to compute _R_ bank indexes in parallel. However,
for larger _R_ (e.g. _R_ = 16), calculating and keeping _R_ parallel
bank indexes to select signals across the whole architecture will
degrade system efficiency in terms of resources and frequency.
Our mapping scheme addresses this issue by using only one
address generator as well as one select signal.
The proposed mapping scheme is come up from an observation. As shown in Fig. 1(a), data with original addresses are
partitioned into four banks. The bank indexes are indicated by
different colors. By a careful check on Fig. 1(a) and 1(d), one
could observe that the bank indexes in one particular cycle are



————— AddressGeneration —————
**for** _j ←_ 0 _, ...R −_ 1 **do**

log _R_ _[⌉][−]_ [1]

BankIndex _j_ _←_ [�] _[⌈]_ _i_ =0 [log] _[ N]_ OrigAddr _j_ [(log _R_ ) _·_

( _i_ + 1) : (log _R_ ) _i_ ] mod _R_ ;

—————-InterconnectBankOut————


Op0 _,_ 1 _,...R−_ 1 _←_ data from BankIndex0: _R−_ 1;
—————-InterconnectBankAddr———–
Addr with BankIndex0: _R−_ 1 _←_ OrigAddr0: _R−_ 1[log _N_ _−_ 1 : log _R_ ];
—————-InterconnectBankIn—————
Data with BankIndex0: _R−_ 1 _←_ Op with index 0 _,_ 1 _, ..., R −_ 1;


correlated. That is, the bank indexes of operands 1, 2 and 3
can be inferred when the bank index of operand 0 is known. In
single-radix cases, the data out of the banks can be arranged by
one-bit circular shifting, resulting in only _R_ possible cases of
arranging data from banks.
Fig. 4 depicts the proposed data mapping in a 64-point R4
design. Data from the four banks are reordered to four circular shifting groups, which are from {Bank0, Bank1, Bank2,
Bank3}, {Bank1, Bank2, Bank3, Bank0}, {Bank2, Bank3,
Bank0, Bank1} and {Bank3, Bank0, Bank1, Bank2}. The
output of the multiplexer is 4 parallel data from one group
of these choices, selected by the calculated bank index of
the first operand. After performing the main calculation, the



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


3528 IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025


Fig. 4. Conflict-free memory mapping for 64-point high-radix R4 NTT/INTT.


Fig. 5. Conflict-free memory mapping for 32-point mixed-radix (R4&R2) NTT/INTT. The modified part compared to Fig. 4 is highlighted in red color. The
butterflies are either fully applied for R4 stages or partially applied for the R2 stage.



four operands are reordered to the four corresponding reverse groups, which are {Operand0, Operand1, Operand2,
Operand3}, {Operand3, Operand0, Operand1, Operand2},
{Operand2, Operand3, Operand0, Operand1} and {Operand1,
Operand2 Operand3, Operand0}. Selected by the same bank
index, the output of the multiplexer is then fed into the banks.
In mixed-radix cases, the data arrangement is a little bit
different. Fig. 5 shows our data mapping in a 32-point R4&R2
design. There are totally 3 stages in one 32-point R4&R2
NTT or INTT. We apply a full R4 butterfly for the first two
stages and the first substage of the butterfly for the last stage
of NTT. For INTT, the stages are in reverse. It is worth noting that in the 2*R2 design, like [24], the two R2 butterflies
are parallel and separate so that their {Operand0, Operand1}
and {Operand2, Operand3} are fed into two R2 butterflies respectively. However, the two R2 in our R4 butterfly here for
the last stage is across to each other, so that the {Operand0,
Operand2} and {Operand1, Operand3} are fed into two R2
butterflies respectively. In conclusion, the required order for
the bank indexes of four operands has 4 possible groups again,
which is {Bank0, Bank2, Bank1, Bank3}, {Bank1, Bank3,
Bank2, Bank0}, {Bank2, Bank0, Bank3, Bank1} and {Bank3,
Bank1, Bank0, Bank2}. The corresponding writing orders for
each one are {Operand0, Operand2, Operand1, Operand3},
{Operand3, Operand0, Operand2, Operand1}, {Operand1,
Operand3, Operand0, Operand2} and {Operand2, Operand1,
Operand3, Operand0}.
To generalize, a new mapping scheme for single-radix and
mixed-radix is summarized in Algorithm 7. The bank indexes
and operand indexes are precomputed. The data, addresses and
operands are in _R_ possible orders respectively, waiting for the



mod _R_ ;
—————–InterconnectBankOut—————
Op0: _R−_ 1 _←_ data from BankIndexes0: _R−_ 1 _,_ iSelect;
—————–InterconnectBankAddr————–
Addr0: _R−_ 1 _←_ OrigAddr[log _N_ _−_ 1 : log _R_ ]

with OpIndexes0: _R−_ 1 _,_ iSelect
——————InterconnectBankIn—————–
Data0: _R−_ 1 _←_ Op with OpIndexes0: _R−_ 1 _,_ iSelect;


selection by the **iselect** signal which is the bank index of the
first operand calculated by one address generator. Only one
required group for each interconnection part is selected in each



**Algorithm** **7:** Proposed memory mapping scheme

——————– Precomputed ————————
// _R_ ˆ = 1 when it is single radix.
**for** _i ←_ 0 _, ...,_ _[R]_ _R_ ˆ _[−]_ [1] **[ do]**

**for** _j ←_ 0 _, ...,_ _R_ [ˆ] _−_ 1 **do**

**for** _k ←_ 0 _, ..., R −_ 1 **do**

BankIndexes _i_ + _j·_ _RR_ ˆ _[,k][ ←]_ _[i][·]_ [ ˆ] _[R]_ [+] _[j]_ [+] _[k]_ [mod] _[ R]_ [;]


**for** _i ←_ 0 _, ...,_ _[R]_ _R_ ˆ _[−]_ [1] **[ do]**

**for** _j ←_ 0 _, ...,_ _R_ [ˆ] _−_ 1 **do**

**for** _k ←_ 0 _, ..., R −_ 1 **do**

OpIndexes( _i·_ ˆ _R_ + _j_ + _k_ mod _R_ ) _,k_ _[←]_ _[i]_ [ +] _[ j][ ·]_ _[R]_ _R_ ˆ [;]


—————- AddressGeneration ——————




[log] log� _[ N]_ _R_ _[⌉][−]_ [1]



_⌈_ [log] log _[ N]_ _R_
iSelect _←_



OrigAddr0[(log _R_ ) _·_ ( _i_ + 1) : (log _R_ ) _i_ ]
_i_ =0



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


XING et al.: HIGH-RADIX/MIXED-RADIX NTT MULTIPLICATION ALGORITHM/ARCHITECTURE CO-DESIGN 3529


Fig. 6. An overall polynomial multiplication architecture based on high-radix/mixed-radix in-place NTT over fermat modulus. “ _−_ 1” denotes the conversion
from normal representation to D1 representation. “+1” denotes the conversion from D1 representation to normal representation.



selection. This scheme has lower complexity by minimizing address generators and select signals for interconnection modules
to one, enhancing resource efficiency and frequency in highradix/mixed-radix design.


V. HIGH-RADIX/MIXED-RADIX NTT
MULTIPLICATION ARCHITECTURE


_A._ _The_ _Overall_ _Architecture_


Fig. 6 depicts the overall architecture of the proposed design,
which is fit for the proposed algorithms. This architecture supports complete polynomial multiplication, where the process
consists of the first NTT, the second NTT, one PWM, and one
INTT, executed sequentially.
In each cycle, the control module provides the original addresses, denoted as **OrigAddr** . Specifically, the original addresses are _R_ indexes of parallel processing data of the sequence in Algorithm 4 for NTT and Algorithm 5 for INTT.
For the PWM procedure between two NTTs and one INTT, the
original addresses are provided by the first stage of INTT. The
**OrigAddr** 0 is fed into address generation to compute the signal
**iselect**, which is the key of our reduced-complexity memory
mapping scheme. The signal **iselect** is fed into three interconnection modules to determine the data selection and address
selection.
According to the indexes and addresses, _R_ parallel data are
derived from _R_ banks. In this design, the coefficients of two
polynomials are aligned one by one and stored in the lower
halves and upper halves of the same addresses respectively, thus
the bit-width of each data is twice the size of modulus.



TABLE II
DETAILED STATUS FOR WRITING TO/READING FROM BANK


State Signal To/From Bank Supported Procedure


11 All Input, PWM
Write 01 Lower Half NTT1, PWM, INTT
10 Upper Half NTT2


11 All PWM
Read 01 Lower Half NTT1, INTT, Output
10 Upper Half NTT2


TABLE III
COMPARISON OF SUPPORTED PARAMETERS AND OPERATIONS IN
STATE-OF-THE-ART DESIGNS AND OUR PROPOSED DESIGN


Work _q_ _R_ _N_ Supported Op.


[5] Fermat 2 256 (I)NTT/PWM

[21] tunable 2, 4 [M] scalable (I)NTT/PWM

[25] tunable 2 scalable (I)NTT/PWM

scalable (R2)

[17] tunable 2, 4 (I)NTT/PWM
limited (R4)

[24] fixed 2 512,1024 (I)NTT

[16] tunable 2, 4 1024 (I)NTT
**Ours** **Fermat** **2,4,8,16** [M] **scalable** **(I)NTT/PWM**


M The design supports the mixed-radix setting.


When performing PWM, the lower halves and upper halves
of data would be fed into the ModMul modules. The product
of them would be written as the lower halves of data into the
banks. When computing NTT or INTT, the lower halves (for



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


3530 IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025


TABLE IV
IMPLEMENTATION RESULTS OF POLYNOMIAL MULTIPLICATION (2 NTTS, 1 PWM AND 1 INTT) ON FPGA AND COMPARISONS


**LUT** **FF** **DSP** **BRAM** **Freq.** **Time**
**Work** **Device** **modulus** _q_ **BFU** **[a]** **Radix** **[b]** **Cycles**
**/ATP** **/ATP** **/ATP** **/ATP** **(MHz)** **(** _μ_ **s)**


_**N**_ **= 256**

[5] [c] Spartan-6 65537 (17-bit) 1*R2 2 404 _/_ 5 _._ 4 599 _/_ 8 _._ 0 0 _/_ 0 _._ 0 1 _/_ 13 _._ 3 287 3824 13 _._ 3


[21] Zynq-7 3329 (12-bit) 28*R2,1*R4 4 _,_ 2 9211 _/_ 8 _._ 6 9810 _/_ 9 _._ 1 60 _/_ 55 _._ 7 1 _/_ 0 _._ 9 265 246 0 _._ 9

[25] [d] Kintex-US+ 12289 (14-bit) 16*R2 2 24186 _/_ 41 _._ 2 14756 _/_ 25 _._ 1 48 _/_ 81 _._ 8 24 _/_ 40 _._ 9 200 341 1 _._ 7


1*R2 2 449 _/_ 5 _._ 3 271 _/_ 3 _._ 2 3 _/_ 35 _._ 2 3 _/_ 35 _._ 2 286 3354 11 _._ 7

[17] Virtex-7 13-bit 1*R4 4 1288 _/_ 4 _._ 1 888 _/_ 2 _._ 8 12 _/_ 37 _._ 9 4 _._ 5 _/_ 14 _._ 2 278 879 3 _._ 2

8*R2 2 6245 _/_ 10 _._ 8 1864 _/_ 3 _._ 2 24 _/_ 41 _._ 4 12 _/_ 20 _._ 7 256 442 1 _._ 7


1*R4 4 1690 _/_ 4 _._ 9 1289 _/_ 3 _._ 7 4 _/_ 11 _._ 6 0 _/_ 0 _._ 0 301 876 2 _._ 9
**Ours** Virtex-7 65537 (17-bit) 1*R8 8 _,_ 4 3596 _/_ 4 _._ 6 2888 _/_ 3 _._ 7 8 _/_ 10 _._ 3 0 _/_ 0 _._ 0 301 389 1 _._ 3

1*R16 16 8078 _/_ 5 _._ 8 6184 _/_ 4 _._ 4 16 _/_ 11 _._ 5 0 _/_ 0 _._ 0 274 197 0 _._ 7


_**N**_ **= 512**


[21] Zynq-7 12289 (14-bit) 32*R2,1*R4 4 _,_ 2 19103 _/_ 33 _._ 2 13677 _/_ 23 _._ 8 68 _/_ 118 _._ 3 1 _/_ 1 _._ 7 261 454 1 _._ 7

[24] [e] Zynq-7 12289 (14-bit) 2*R2 2 741 _/_ 12 _._ 1 330 _/_ 5 _._ 4 2 _/_ 32 _._ 7 5 _/_ 81 _._ 8 245 4010 16 _._ 4


1*R2 2 489 _/_ 13 _._ 1 245 _/_ 6 _._ 6 3 _/_ 80 _._ 4 3 _/_ 80 _._ 4 278 7450 26 _._ 8

[17] Virtex-7 14-bit
16*R2 2 28616 _/_ 91 _._ 1 4211 _/_ 13 _._ 4 48 _._ 0 _/_ 152 _._ 7 24 _/_ 76 _._ 4 154 490 3 _._ 2


1*R4 4 _,_ 2 1955 _/_ 13 _._ 6 1286 _/_ 8 _._ 9 4 _/_ 27 _._ 8 2 _/_ 13 _._ 9 301 2092 6 _._ 9
**Ours** Virtex-7 65537 (17-bit) 1*R8 8 3559 _/_ 8 _._ 2 2737 _/_ 6 _._ 3 8 _/_ 18 _._ 5 3 _._ 5 _/_ 8 _._ 1 301 697 2 _._ 3

1*R16 16 _,_ 2 8904 _/_ 13 _._ 1 6321 _/_ 9 _._ 3 16 _/_ 23 _._ 5 0 _/_ 0 _._ 0 274 402 1 _._ 5


_**N**_ **= 1024**


[21] Zynq-7 12289 (14-bit) 36*R2,1*R4 4 _,_ 2 23261 _/_ 76 _._ 6 14901 _/_ 49 _._ 1 76 _/_ 250 _._ 2 1 _/_ 3 _._ 3 257 846 3 _._ 3

[24] [e] Zynq-7 12289 (14-bit) 2*R2 2 847 _/_ 27 _._ 6 375 _/_ 12 _._ 2 2 _/_ 65 _._ 3 6 _/_ 195 _._ 8 244 7964 32 _._ 6




[16] [e] Virtex-7 14-bit



1*R4 4 1196 _/_ 18 _._ 5 969 _/_ 15 _._ 0 12 _/_ 186 _._ 0 3 _/_ 46 _._ 5 270 4186 15 _._ 5

2*R4 4 2953 _/_ 25 _._ 2 1875 _/_ 16 _._ 0 27 _/_ 230 _._ 9 5 _._ 5 _/_ 47 _._ 0 250 2138 8 _._ 6

1*R2 2 475 _/_ 27 _._ 2 307 _/_ 17 _._ 6 3 _/_ 171 _._ 7 1 _._ 5 _/_ 85 _._ 9 278 15915 57 _._ 2

8*R2 2 6300 _/_ 56 _._ 3 2124 _/_ 19 _._ 0 27 _/_ 241 _._ 1 10 _/_ 89 _._ 3 227 2027 8 _._ 9




[25] [d] Kintex-US+ 12289 (14-bit) 16*R2 2 22648 _/_ 132 _._ 3 15030 _/_ 87 _._ 8 48 _/_ 280 _._ 5 24 _/_ 140 _._ 2 200 1169 5 _._ 8


1*R4 4 1467 / 32.2 930 / 20.4 13 / 285.0 4.5 / 98.6 189 4143 21.9

[17] Virtex-7 14-bit
4*R4 4 8515 / 53.0 3618 / 22.5 49 / 305.1 12 / 74.7 172 1071 6.2


1*R4 4 1395 _/_ 19 _._ 2 1222 _/_ 16 _._ 8 4 _/_ 55 _._ 0 4 _/_ 55 _._ 0 301 4140 13 _._ 7
**Ours** Virtex-7 65537 (17-bit) 1*R8 8 _,_ 2 3463 _/_ 19 _._ 7 2665 _/_ 15 _._ 1 8 _/_ 45 _._ 5 7 _._ 5 _/_ 42 _._ 6 301 1712 5 _._ 7

1*R16 16 _,_ 4 9783 _/_ 25 _._ 6 6537 _/_ 17 _._ 1 16 _/_ 41 _._ 8 0 _/_ 0 _._ 0 274 716 2 _._ 6


a BFU: The style of butterfly unit for one NTT. For example, 2*R4 indicates two parallel radix-4 units in the NTT design.
b If two radix values are listed, this indicates mixed-radix. In our work, mixed-radix is computed by designing butterfly unit architecture of higher radix,
where the lower radix is computed by using part of the same architecture.
c The design supports only one NTT, one point-wise multiplication and one INTT. One more NTT is added to the cycles and time, assuming the given
cycles and time from the work is (2 + # _stages_ 1 [)] [NTT.] [The] [area] [is] [assumed] [to] [remain] [the] [same.]
d The work does not list cycles of this configuration ( _q_ and _N_ ). The cycles and time here is approximated by PWM cycles in a 16*R2 configuration
( _q_ = 8380417, _N_ = 256) times the ratio of NTT cycles between the two configurations.
e The design supports only one NTT/INTT. The cycles and time here is approximated by that of (3 + # _stages_ 1 [)] [NTT,] [while] [the] [area] [is] [assumed] [to]
remain the same.



the first NTT and the INTT) or the upper halves (for the second
NTT) are reordered by the interconnection module. For NTT,
the data are routed to the ModMul modules, followed by the _R_ point R2NTT module for further processing. For INTT, the data
are first sent to the _R_ -point R2INTT module, and then to the
ModMul modules for computation. The outputs pass through
another interconnection module before being written back to
the memory banks. The signal **isthe** _R_ [ˆ] **stage** indicates whether
the special _R_ [ˆ] stage is active, determining if the R2NTT and
R2INTT modules should be fully applied or used partially in
their specific substages.



Table II summarizes operations and support procedures for
different write states and read states.


VI. IMPLEMENTATION RESULTS AND COMPARISONS


The proposed architecture is designed using Verilog
HDL and implemented on the 28 _nm_ Xilinx Virtex-7 FPGA
(xc7vx690tffg1761-3). Vivado 2022.2 is used for synthesis
and implementation. Nine different settings are implemented,
with _N_ = 256 _,_ 512 _,_ 1024 and _R_ = 4 _,_ 8 _,_ 16. For cases where _N_
is not a power of _R_, the related mixed-radix design is applied.



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


XING et al.: HIGH-RADIX/MIXED-RADIX NTT MULTIPLICATION ALGORITHM/ARCHITECTURE CO-DESIGN 3531



Table III provides a general analysis, while Table IV presents
the detailed implementation results of our proposed polynomial
multiplication design compared to state-of-the-art designs. We
assume that a complete polynomial multiplication consists of 2
NTTs, 1 PWM and 1 INTT. However, some of the compared
designs, such as [5], [16], [24], do not support a complete polynomial multiplication. For these designs, we assume that the
INTT requires the same number of cycles as the NTT, and that
the PWM requires the same number of cycles as a single stage of
the NTT. We do not consider additional resource consumption
or potential frequency degradation, which are very likely to
occur due to increased data storage requirements and more
complex routing. We believe that this assumption is generous
and lenient for designs that do not fully support polynomial
multiplication.
Firstly we compare our work with [5], which uses the same
Fermat modulus _q_ = 65537. Ma et al. [5] propose an R2-NTT
polynomial multiplication design with one R2 butterfly for a
fixed degree _N_ = 256. Our R4/R8/R16 designs consume only
22 _._ 9% _/_ 10 _._ 2% _/_ 5 _._ 2% cycles of their work, primarily due to the
benefits of higher radix. Since Ma et al. [5] employ a modular
multiplier designed with shifting and accumulation using D1
representation, their design does not use DSPs but relies on a
relatively large number of LUTs and FFs. Our work achieves
around 50% better area-time product (ATP) in terms of FFs. Additionally, by employing LUT-based memory instead of BRAM
in cases where a large _R_ and a small _N_ lead to very small storage requirements per bank, our R8/R16 designs finally achieve
a slightly better ATP in terms of LUTs while eliminating all
BRAM usage.
Then we compare our work with [21] which features a mixedradix design. Duong-Ngoc and Lee [21] implement a fully
pipelined design without reordering buffers. Their NTT architecture consists of 4 sequences of R2 butterfly units in the initial
stages, followed by a R4 butterfly unit at the end, resulting
in a mixed-radix architecture combining R2 and R4 for each
degree. For the most similar configurations in _N_ = 512, the
proposed mixed-radix R4&R2 design uses 2 _._ 6 _×_ cycles more
than [21]. This difference is primarily due to two factors: their
design includes two NTTs in parallel, and they use a large
quantity of butterfly units to construct a pipeline across stages.
Additionally, they use only one BRAM because no temporary
storage is required. However, these advantages come at the
cost of significantly higher LUT, FF, and DSP usage. In contrast, our work efficiently reuses butterfly units, resulting in
59 _._ 0% _/_ 62 _._ 6% _/_ 76 _._ 5% less ATP in terms of LUT/FF/DSP. For
additional configurations, such as those with a higher radix like
R16, our design can achieve faster performance while using
fewer resources in every category compared to [21], demonstrating even greater efficiency gain, despite their modulus bitwidth being 3–5 bits smaller than ours.
Lastly we compare representative results from [16], [17],

[24], [25], which propose architectures with various numbers of
R2 or R4 butterfly units. Generally, as observed in [16] and [17],
R4 is more efficient than R2 for a single butterfly unit, but efficiency decreases with the number of butterfly units. Although
all the selected results in [16], [17], [24], [25] are on modulus



with smaller bit-width, our work generally outperforms them in
ATPs of DSP/BRAM while remaining similarly competitive in
those of LUT/FF.
Zhang et al. [24] propose a 2*R2 NTT design on a 14bit modulus 12289. For _N_ = 512, our R8 design achieves
43 _._ 4% _/_ 90 _._ 1% less ATP in terms of DSP/BRAM. For _N_ =
1024, our R8&R2 design achieves 30 _._ 3% _/_ 78 _._ 2% less ATP in
terms of DSP/BRAM. Chen et al. [16] propose NTT design with
various numbers of parallel R2 or R4 butterflies on a tunable
14-bit modulus and _N_ = 1024. Compared with their best configuration, i.e., 1*R4, our R8&R2 design achieves 75 _._ 6% _/_ 8 _._ 4%
less ATP in terms of DSP/BRAM but similar ATP in terms
of LUT/FF. Li et al. [25] propose an NTT-based polynomial
multiplication design with different numbers of parallel R2
butterflies on tunable modulus and scalable degree. The butterfly unit performs NTT, PWM, and INTT according to the
control signal. Their design with the best performance uses
16*R2 units. Due to their large numbers of parallel processing
elements, our 1*R16 design achieves more than 80% less ATP
across all categories for both _N_ = 256 and 1024. Mu et al.

[17] propose a scalable NTT-based polynomial multiplication
design with different numbers of parallel R2 or R4 butterflies
on tunable modulus and scalable degree. As 512 is not a power
of 4, Mu et al. [17] do not support R4 in _N_ = 512. Comparing
with their best results, our work achieves 70%-85% less ATP
in terms of DSP and over 90% less ATP in terms of BRAM for
_N_ = 256 _/_ 512 _/_ 1024. The above analysis demonstrates the great
potential of the Fermat modulus combined with our proposed
improvement methods.


VII. CONCLUSION AND FUTURE WORKS


In summary, a highly efficient polynomial multiplication
architecture based on high-radix and mixed-radix NTT over
Fermat modulus is proposed. The detailed derivation process for
high-radix and mixed-radix NTT with merged pre-processing
and INTT with merged post-processing is provided. To facilitate
PWM calculations and to leverage the complexity advantages of
both normal and D1 representations, the NTT/INTT processes
have been modularized into ModMuls and R2NTT/R2INTT
modules. To maintain efficiency across a broader range of
configurations, R2NTT/R2INTT is reused in the final stage of
mixed-radix cases. Additionally, the complexity of the memory
mapping scheme is reduced to improve frequency in high-radix
cases. In most configurations, our design reduces DSP ATP
by approximately 30%–85% and BRAM ATP by 70%–100%,
while remaining competitive in LUT and FF ATP. While a few
designs may show advantages in specific aspects, our approach
consistently demonstrates strong overall efficiency.
Looking ahead, our design can serve as a building block for
constructing efficient implementations within existing schemes
such as Hawk. The efficiency of FNT-based polynomial multiplication on alternative platforms—such as GPU or ASIC—
remains an area for further investigation. Additionally, exploring more FHE or PQC schemes that can support Fermat
moduli presents a challenging yet promising research opportunity. Moreover, the design and optimization of polynomial



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


3532 IEEE TRANSACTIONS ON COMPUTERS, VOL. 74, NO. 10, OCTOBER 2025



multiplication over a broader class of moduli—such as
Mersenne, pseudo-Mersenne/Fermat and even undiscovered
forms with more favorable arithmetic properties—remain open
research directions. It is anticipated that the strategic selection
and use of such moduli will lead to more elegant and computationally efficient cryptographic constructions.


REFERENCES


[1] Q. D. Truong, P. Duong-Ngoc, and H. Lee, “Hybrid number theoretic
transform architecture for homomorphic encryption,” _IEEE_ _Trans._ _Very_
_Large Scale Integr. (VLSI) Syst._, vol. 33, no. 7, pp. 2039–2043, Jul. 2025.

[2] Z. Ye et al., “PQNTRU: Acceleration of NTRU-based schemes via
customized post-quantum processor,” _IEEE_ _Trans._ _Comput._, vol. 74,
no. 5, pp. 1649–1662, May 2025.

[3] Z. Ye, R. Song, H. Zhang, D. Chen, R. C. Cheung, and K. Huang, “A
highly-efficient lattice-based post-quantum cryptography processor for
IoT applications,” _IACR_ _Trans._ _Cryptogr._ _Hardware_ _Embedded_ _Syst._,
vol. 2024, no. 2, pp. 130–153, 2024.

[4] A. Kim et al., “Exploring the advantages and challenges of Fermat
NTT in FHE acceleration,” in _Proc._ _Annu._ _Int._ _Cryptol._ _Conf._, Cham,
Switzerland: Springer, 2024, pp. 76–106.

[5] L. Ma, X. Wu, and G. Bai, “A low cost high performance polynomial
multiplier design for FPGA implementation,” in _Proc._ _IEEE_ _3rd_ _Int._
_Conf._ _Electron._ _Technol._ _(ICET)_, Piscataway, NJ, USA: IEEE Press,
2020, pp. 83–86.

[6] A. Abdulrahman, V. Hwang, M. J. Kannwischer, and A. Sprenkels,
“Faster kyber and dilithium on the cortex-m4,” in _Proc._ _Int._ _Conf._ _Appl._
_Cryptogr._ _Netw._ _Secur._, Cham, Switzerland: Springer, 2022, pp. 853–
871.

[7] L. Leibowitz, “A simplified binary arithmetic for the Fermat number
transform,” _IEEE Trans. Acoust., Speech, Signal Process._, vol. 24, no. 5,
pp. 356–359, Oct. 1976.

[8] L. Ducas, E. W. Postlethwaite, and W. van Woerden, “HAWK: Module
LIP makes lattice signatures fast, compact and simple,” in _Proc._ _28th_
_Int. Conf. Theory Appl. Cryptol. Inf. Secur. Adv. Cryptol. (ASIACRYPT)_,
Taipei, Taiwan, vol. 13794, Cham, Switzerland: Springer Nature, 2023,
p. 65.

[9] Y. Xing et al., “Low-complexity chromatic dispersion compensation
using high-radix Fermat number transform,” _J._ _Lightw._ _Technol._, vol.
42, no. 15, pp. 5190–5203, 2024.

[10] Z. Liu, S. Chen, J. Chen, Y. Li, and M. Tang, “Low complexity
equalization in coherent optical communication based on Fermat number
transform,” _Opt._ _Lett._, vol. 49, no. 14, pp. 3910–3913, 2024.

[11] S. Chen et al., “Fermat number transform based chromatic dispersion compensation and adaptive equalization algorithm,” 2024,
_arXiv:2405.04253_ .

[12] A. Daher, E. H. Baghious, N. El Khouja, E. Radoi, and G. Burel,
“Fast algorithm for optimal design of Fermat number transform based
block digital filters,” _Digit._ _Signal_ _Process._, vol. 113, Jun. 2021, Art.
no. 103029.

[13] W. Xu, Z. Zhang, X. You, and C. Zhang, “Reconfigurable and lowcomplexity accelerator for convolutional and generative networks over
finite fields,” _IEEE_ _Trans._ _Comput.-Aided_ _Des._ _Integr._ _Circuits_ _Syst._,
vol. 39, no. 12, pp. 4894–4907, Dec. 2020.

[14] Z. Baozhou, N. Ahmed, J. Peltenburg, K. Bertels, and Z. Al-Ars,
“Diminished-1 fermat number transform for integer convolutional neural
networks,” in _Proc._ _IEEE_ _4th_ _Int._ _Conf._ _Big_ _Data_ _Analytics_ _(ICBDA)_,
Piscataway, NJ, USA: IEEE Press, 2019, pp. 47–52.

[15] T. Toivonen and J. Heikkila, “Video filtering with Fermat number
theoretic transforms using residue number system,” _IEEE Trans. Circuits_
_Syst._ _Video_ _Technol._, vol. 16, no. 1, pp. 92–101, Jan. 2006.

[16] X. Chen, B. Yang, S. Yin, S. Wei, and L. Liu, “CFNTT: Scalable
radix-2/4 NTT multiplication architecture with an efficient conflict-free
memory mapping scheme,” _IACR Trans. Cryptogr. Hardware Embedded_
_Syst._, vol. 2022, no. 1, pp. 94–126, Nov. 2021.

[17] J. Mu et al., “Scalable and conflict-free NTT hardware accelerator design: Methodology, proof, and implementation,” _IEEE_ _Trans._ _Comput.-_
_Aided_ _Design_ _Integr._ _Circuits_ _Syst._, vol. 42, no. 5, pp. 1504–1517, May
2023.




[18] Y. Zhang et al., “Ultra high-speed polynomial multiplications for
lattice-based cryptography on FPGAs,” _IEEE_ _Trans._ _Emerg._ _Topics_
_Comput._ _Intell._, vol. 10, no. 4, pp. 1993–2005, Oct.–Dec. 2022.

[19] Z. Cheng, B. Zhang, and M. Pedram, “A high-performance, conflictfree memory-access architecture for modular polynomial multiplication,”
_IEEE_ _Trans._ _Comput.-Aided_ _Design_ _Integr._ _Circuits_ _Syst._, vol. 43, no. 2,
pp. 492–505, Feb. 2024.

[20] Y. Zhao, X. Liu, Y. Hu, and H. Xiao, “Design of an efficient
NTT/INTT architecture with low-complex memory mapping scheme,”
_IEEE_ _Trans._ _Circuits_ _Syst.,_ _II,_ _Exp._ _Briefs_, vol. 71, no. 1, pp. 400–404,
Jan. 2024.

[21] P. Duong-Ngoc and H. Lee, “Configurable mixed-radix number theoretic
transform architecture for lattice-based cryptography,” _IEEE_ _Access_,
vol. 10, pp. 12732–12741, 2022.

[22] G. Li, D. Chen, G. Mao, W. Dai, A. I. Sanka, and R. C. Cheung,
“Algorithm-hardware co-design of split-radix discrete Galois transformation for KyberKEM,” _IEEE_ _Trans._ _Emerg._ _Topics_ _Comput._, vol. 11,
no. 4, pp. 824–838, Oct.–Dec. 2023.

[23] W. Guo and S. Li, “Split-radix based compact hardware architecture
for crystals-kyber,” _IEEE_ _Trans._ _Comput._, vol. 73, no. 1, pp. 97–108,
Jan. 2024.

[24] N. Zhang, B. Yang, C. Chen, S. Yin, S. Wei, and L. Liu, “Highly
efficient architecture of NewHope-NIST on FPGA using low-complexity
NTT/INTT,” _IACR Trans. Cryptographic Hardware Embedded Syst._, vol.
2020, no. 2, pp. 49–72, Mar. 2020.

[25] B. Li, Y. Yan, Y. Wei, and H. Han, “Scalable and parallel optimization
of the number theoretic transform based on FPGA,” _IEEE_ _Trans._
_Very_ _Large_ _Scale_ _Integr._ _(VLSI)_ _Syst._, vol. 32, no. 2, pp. 291–304,
Feb. 2024.

[26] A. C. Mert, E. Karabulut, E. Öztürk, E. Sava¸s, and A. Aysu, “An
extensive study of flexible design methods for the number theoretic
transform,” _IEEE_ _Trans._ _Comput._, vol. 71, no. 11, pp. 2829–2843,
Nov. 2022.

[27] S. S. Roy, F. Vercauteren, N. Mentens, D. D. Chen, and I. Verbauwhede,
“Compact ring-lwe cryptoprocessor,” in _Proc._ _Int._ _Workshop_ _Cryptogr._
_Hardware_ _Embedded_ _Syst._, Berlin, Germany: Springer, 2014, pp. 371–
391.

[28] T. Pöppelmann, T. Oder, and T. Güneysu, “High-performance ideal
lattice-based cryptography on 8-bit atxmega microcontrollers,” in _Proc._
_Int. Conf. Cryptol. Inf. Secur. Latin Amer_ ., Cham, Switzerland: Springer,
2015, pp. 346–365.

[29] R. Agarwal and C. Burrus, “Fast convolution using Fermat number
transforms with applications to digital filtering,” _IEEE_ _Trans._ _Acoust.,_
_Speech,_ _Signal_ _Process._, vol. 22, no. 2, pp. 87–97, Apr. 1974.

[30] H.-F. Lo, M.-D. Shieh, and C.-M. Wu, “Design of an efficient FFT
processor for DAB system,” in _Proc._ _IEEE_ _Int._ _Symp._ _Circuits_ _Syst._
_(ISCAS)_ _(Cat._ _No._ _01CH37196)_, vol. 4, Piscataway, NJ, USA: IEEE
Press, 2001, pp. 654–657.

[31] D. D. Chen et al., “High-speed polynomial multiplication architecture
for ring-LWE and SHE cryptosystems,” _IEEE_ _Trans._ _Circuits_ _Syst._ _I,_
_Reg._ _Papers_, vol. 62, no. 1, pp. 157–166, Jan. 2015.

[32] U. Banerjee, T. S. Ukyab, and A. P. Chandrakasan, “Sapphire: A
configurable crypto-processor for post-quantum lattice-based protocols,”
2019, _arXiv:1910.07557_ .

[33] L. Johnson, “Conflict free memory addressing for dedicated FFT hardware,” _IEEE_ _Trans._ _Circuits_ _Syst._ _II,_ _Analog_ _Digit._ _Signal_ _Process._,
vol. 39, no. 5, pp. 312–316, May 1992.

[34] X. Chen, B. Yang, Y. Lu, S. Yin, S. Wei, and L. Liu, “Efficient access
scheme for multi-bank based NTT architecture through conflict graph,”
in _Proc._ _59th_ _ACM/IEEE_ _Des._ _Automat._ _Conf._, 2022, pp. 91–96.


**Yile** **Xing** (Student Member, IEEE) received the
B.Eng. degree from the School of Electronics and
Communication Engineering, Sun Yat-sen University, China, in 2021. She is currently working
toward the Ph.D. degree with the Department of
Electrical Engineering, City University of Hong
Kong. Her research interests include digital signal processing algorithm design and reconfigurable
computing with FPGA.



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


XING et al.: HIGH-RADIX/MIXED-RADIX NTT MULTIPLICATION ALGORITHM/ARCHITECTURE CO-DESIGN 3533



**Guangyan** **Li** received the B.Eng. degree from the
Department of Electrical Engineering, City University of Hong Kong, in 2020. He is currently working
toward the Ph.D. degree with the Department of
Electrical Engineering, City University of Hong
Kong. His research interests include reconfigurable
computing with FPGA, and postquantum cryptography algorithm design.


**Zewen** **Ye** (Student Member, IEEE) received the
bachelor’s degree in microelectronics science and
engineering from Zhejiang University, in 2020. He
is currently working toward the joint Ph.D. degree
with Zhejiang University and the City University of
Hong Kong, advised by Prof. Kejie Huang and Prof.
Ray C. C. Cheung. His research interests include
postquantum cryptography, hardware design, and
RISC-V.


**Ryan** **W.** **L.** **Luk** (Member, IEEE) received the
B.Eng. degree in electronic engineering from The
Hong Kong University of Science and Technology,
in 2021. Since 2022, he has been working toward
the M.Sc. degree in electrical engineering with the
City University of Hong Kong. Currently, he is a
Research Assistant supervised by Dr. Ray C. C.
Cheung with the Department of Electrical Engineering, City University of Hong Kong. His research
interests include computer arithmetic and modulomultiplier design.


**Donglong** **Chen** (Member, IEEE) received the
Ph.D. degree from the Department of Electronic Engineering, City University of Hong Kong, in 2015.
He was a Visiting Research Scholar of COSIC,
KU Leuven, Belgium, in 2013. After completing
his Ph.D. degree study, he spent four years with
the industry including Huawei Technology Company Ltd., and Tencent Technology Company Ltd.
Currently, he is an Associate Professor with the Faculty of Science and Technology, Beijing NormalHong Kong Baptist University Zhuhai, China. His
research interests include cryptographic engineering, software/hardware codesign for AI algorithms, and privacy computing.



**Hong** **Yan** (Life Fellow, IEEE) received the Ph.D.
degree from Yale University. He was a Professor
of imaging science with the University of Sydney,
and currently a Wong Chun Hong Professor of
data engineering and a Chair Professor of computer
engineering with the City University of Hong Kong.
His research interests include image processing and
computer vision, machine learning, and computational biology and medicine. He has over 600
journal and conference publications in these areas.
He received the 2016 Norbert Wiener Award from
the IEEE SMC Society for contributions to image and biomolecular pattern
recognition techniques. He is an IAPR Fellow, a Foreign Member of the
European Academy of Sciences and Arts, and a fellow of the US National
Academy of Inventors.


**Ray** **C.** **C.** **Cheung** (Senior Member, IEEE) received the B.Eng.(Hons.) and M.Phil. degrees in
computer engineering and computer science & engineering from The Chinese University of Hong
Kong (CUHK), in 1999 and 2001, respectively,
and the DIC and Ph.D. degrees in computing from
Imperial College London (IC), in 2007. Currently,
he is the Associate Provost (Digital Learning) with
the CityUHK, a Professor with the Department of
Electrical Engineering and Department of Computer
Science at CityUHK, and the CityUHK-EE Xilinx
Lab. He is the current Section Chairman of IEEE HK Section, the Former
Chairman of the IEEE Hong Kong Section CAS/COM Chapter, and an
Executive Committee Member of the IEEE Hong Kong Section Computer
Chapter. His research interests include cryptographic hardware designs and
design exploration of system-on-chip (SoC) designs, AIoT designs, and
embedded system designs.



Authorized licensed use limited to: International Institute of Information Technology Bangalore. Downloaded on January 18,2026 at 16:03:35 UTC from IEEE Xplore. Restrictions apply.


