# Rigorous Review and Evaluation of the Draft Paper

## Paper Under Review
**Title:** *A Measured Design-Space Exploration of Multivariate Fermat-Modulus NTT on FPGA: Fixed-Width Compute Scaling in Decomposition Depth*  
Draft reviewed against the reference paper *High-Radix/Mixed-Radix NTT Multiplication Algorithm/Architecture Co-Design Over Fermat Modulus* (IEEE TC 2025).

---

# Executive Summary

This draft is substantially stronger than a typical early-stage architecture paper draft. The work demonstrates:

- A clear experimental thesis.
- Strong architectural framing.
- Honest comparison methodology.
- A compelling empirical observation (constant-width compute scaling).
- Good awareness of prior art and contribution boundaries.
- Strong systems-level intuition.

The paper is particularly notable because it does **not** overclaim novelty. Instead, it reframes an existing multivariate Fermat-NTT methodology into a carefully measured architectural scaling study.

That positioning is actually a strength.

The central contribution is not algorithmic novelty, but the experimentally validated observation that:

> For fixed lane width L, the compute fabric remains approximately constant while decomposition depth d and transform size N increase.

This is a meaningful architectural insight.

The draft already reads significantly more mature than most workshop submissions and is approaching conference quality. However, several major issues remain before the work would be competitive at a strong FPGA/cryptographic hardware venue.

The largest weaknesses are:

1. The contribution boundary with Xing et al. is still dangerously close.
2. The architecture section needs more formalization and visual rigor.
3. The experimental methodology is incomplete.
4. The scaling argument is empirical but not theoretically generalized.
5. The evaluation lacks power/energy and throughput-normalized analysis.
6. The novelty claim currently risks being interpreted as "measurement-only replication."

Overall assessment:

| Category | Score |
|---|---|
| Technical Soundness | 8.5/10 |
| Experimental Rigor | 7/10 |
| Novelty | 5.5/10 |
| Clarity | 8/10 |
| Architectural Insight | 8.5/10 |
| Publication Readiness | 7/10 |

Projected venue suitability:

| Venue Tier | Likelihood |
|---|---|
| FPGA Workshop / Poster | Very High |
| Mid-tier FPGA/Crypto HW Conference | Moderate–High |
| FCCM/FPL short paper | Moderate |
| TRETS / TCAD / IEEE TC full paper | Low–Moderate without stronger novelty |
| Top cryptographic hardware venue (TCHES) | Low in current form |

---

# 1. Core Technical Assessment

## 1.1 What the Paper Actually Contributes

The paper's *real* contribution is:

> Demonstrating that hierarchical decomposition depth scales transform size without proportionally scaling compute fabric width.

This is fundamentally:

- an architectural scaling observation,
- enabled by:
  - transpose-free banking,
  - O(L) interconnect,
  - single shared datapath reuse.

This is distinct from Xing et al.

Xing et al. focus on:

- high-radix Fermat NTT design,
- D1 representation,
- merged pre/post processing,
- radix reuse,
- mixed-radix decomposition,
- modular multiplier optimization,
- ATP efficiency.

Your paper instead focuses on:

- decomposition-depth scaling behavior,
- datapath invariance,
- architectural asymptotics,
- memory/interconnect scaling,
- measured placed-and-routed characterization.

This distinction is valid.

However, it must be sharpened aggressively.

---

# 2. Strengths of the Draft

## 2.1 Excellent Contribution Honesty

One of the strongest qualities of the draft is intellectual honesty.

The paper repeatedly states:

- the algorithm is known,
- the banking concept is known,
- the work is empirical and architectural,
- the design loses to iterative approaches at small N.

This dramatically improves reviewer trust.

The paper avoids the classic weak-paper failure mode of:

> “We reinvented known architecture but claim novelty via minor rearrangement.”

Instead, the paper says:

> “Here is a measured architectural scaling phenomenon that prior work did not systematically characterize.”

That is a credible framing.

---

## 2.2 Strong Systems-Level Architectural Thesis

The strongest conceptual sentence in the paper is effectively:

> The datapath width is parameterized by L, not N.

That is a clean and meaningful architectural abstraction.

The paper successfully argues:

- increasing d increases schedule length,
- but not compute width,
- because:
  - all axis accesses remain conflict-free,
  - axis switches are address remaps,
  - no transpose buffers are needed,
  - interconnect remains O(L).

This is a real architectural insight.

---

## 2.3 The Banking Proposition is Strong

The proof in Section III-B is concise and correct.

This is one of the most convincing parts of the paper.

Specifically:

\[
 b(i)=\left(\sum_{j=0}^{d-1} i_j\right) \bmod L
\]

followed by the uniqueness proof across an axis sweep is elegant.

This proposition is doing enormous work in the paper.

It justifies:

- conflict-free access,
- no transpose,
- O(L) interconnect,
- in-place operation,
- depth independence.

This proposition should be elevated visually and conceptually.

Right now it is buried.

Recommendation:

- Turn it into a highlighted theorem box.
- Add an example tensor visualization.
- Add one worked example with L=4, d=3.

---

## 2.4 Good Empirical Framing

The paper does not just present isolated points.

It presents:

- the entire admissible design grid.
- complete placed-and-routed results.
- exact cycle model.
- LUT/DSP scaling trends.
- lane-width sweep.
- comparison against prior work.

This makes the work feel scientifically grounded.

---

## 2.5 Excellent Comparative Honesty

The comparison section is refreshingly honest.

Most FPGA papers try to obscure weak comparisons.

This draft explicitly states:

> Xing et al. is better on ATP.

This dramatically improves credibility.

The paper instead reframes the contribution around:

- minimum absolute footprint,
- scaling characterization,
- full valid-depth exploration.

This is the correct move.

---

# 3. Major Weaknesses

# 3.1 Novelty Risk: Too Close to Xing et al.

This is the single largest issue.

A skeptical reviewer may say:

> “This is merely a parameter sweep of Xing et al.”

And currently the draft does not completely defeat that criticism.

The paper needs a sharper statement of:

- what architecture was independently designed,
- what is inherited,
- what is newly synthesized,
- what is newly proven,
- what is newly measured.

Right now the paper says:

> “We make no claim to a new algorithm.”

Good.

But that alone is not enough.

You must explain:

## What is NEW architecturally?

Possible candidates:

### A. Full decomposition-depth scaling study

This is currently the strongest novelty.

Emphasize:

- prior work only explored shallow configurations,
- your work explores the entire Fermat-valid grid,
- the scaling law itself was previously unknown.

---

### B. Shared single datapath interpretation

You should explicitly argue:

> Existing papers optimize throughput.

while:

> This paper studies width-invariant compute scaling.

This is a different design objective.

That distinction needs to appear in the introduction.

---

### C. Architectural asymptotics

You should formalize:

| Quantity | Scaling |
|---|---|
| Compute width | O(L) |
| Interconnect | O(L) |
| FSM state | O(d) |
| Memory | O(N) |
| Runtime | O(dN/L) |

Right now these claims are scattered.

Formal asymptotic analysis would strengthen novelty.

---

# 3.2 Architecture Figure is Not Yet Strong Enough

The architecture figure concept is excellent.

But the draft currently lacks:

- detailed lane annotations,
- bank access example,
- rotation visualization,
- scheduling illustration.

The architecture figure should be the centerpiece of the paper.

Currently it is too generic.

The figure should explicitly communicate:

- no transpose,
- in-place operation,
- shared datapath reuse,
- conflict-free axis sweep.

A reviewer should understand the key insight from the figure alone.

---

# 3.3 Theoretical Depth Scaling Needs Formalization

The empirical scaling claim is convincing.

But the paper stops short of giving a generalized analytical model.

Currently:

- the paper shows measurements,
- then verbally explains why they happen.

This should become more rigorous.

For example:

## Suggested theorem-style argument

For fixed lane width L:

- sub-NTT width is constant,
- multiplier count is constant,
- rotation network width is constant,
- banking permutation remains local,
- therefore compute logic is asymptotically independent of d.

Then explicitly identify which components scale with d:

- FSM,
- address counters,
- schedule ROM.

This would elevate the paper from:

> “interesting measurements”

to:

> “architectural scaling analysis.”

---

# 3.4 Missing Energy / Power Evaluation

This is a serious weakness.

Modern FPGA architecture papers almost always include:

- power,
- energy/op,
- energy-delay product,
- throughput/W.

Without power analysis, reviewers may interpret:

- constant LUTs

as:

- hidden routing activity,
- high dynamic switching,
- poor energy scaling.

At minimum include:

| Metric | Why Needed |
|---|---|
| Dynamic power | datapath scaling validation |
| Total power | FPGA relevance |
| Energy per multiplication | architectural efficiency |
| Energy-delay product | compare against iterative designs |

Even Vivado-estimated power is better than nothing.

---

# 3.5 Throughput Framing is Weak

The draft focuses heavily on area.

But modern FPGA papers also expect:

- throughput,
- throughput per LUT,
- throughput per DSP,
- GOPS/W,
- coefficient/s.

You already have cycle counts and Fmax.

Add:

\[
\text{Throughput} = \frac{N}{\text{latency}}
\]

for each configuration.

Then normalize.

---

# 3.6 The Cycle Model is Good But Underexploited

Equation (2) is actually one of the stronger technical components.

But it is treated almost casually.

You should emphasize:

- exactness,
- no fitted parameters,
- predictive capability.

Add:

- a measured-vs-predicted plot,
- residual error plot,
- percent error.

This strengthens scientific rigor significantly.

---

# 3.7 The Discussion Section Needs More Vision

The discussion is technically sound.

But it lacks a broader research framing.

You should discuss:

## A. Why fixed-width scaling matters

For example:

- resource-constrained FPGA deployments,
- multi-channel FHE pipelines,
- composable accelerators,
- spatial multiplexing.

---

## B. Why decomposition depth is an important knob

Right now this is implied.

But it should be explicit:

- throughput-area tradeoff,
- memory-compute decoupling,
- architectural scalability.

---

## C. ASIC implications

A reviewer may wonder:

> “Would this matter more on ASIC?”

You should answer that.

Potentially yes.

Especially:

- routing complexity,
- local interconnect,
- SRAM banking.

---

# 4. Section-by-Section Evaluation

# 4.1 Title

Current title:

> A Measured Design-Space Exploration of Multivariate Fermat-Modulus NTT on FPGA: Fixed-Width Compute Scaling in Decomposition Depth

This is actually good.

Strengths:

- accurately scoped,
- not overclaiming,
- emphasizes empirical contribution.

Possible improvement:

> Fixed-Width Compute Scaling in Hierarchical Fermat-NTT Architectures

This is more concise and emphasizes the main insight.

---

# 4.2 Abstract

The abstract is strong.

Especially good:

- immediate statement of known algorithmic basis,
- clear empirical claim,
- quantified scaling result,
- honest comparison.

Weakness:

The architectural novelty is still somewhat implicit.

Recommendation:

Explicitly state:

> “We identify and experimentally validate a width-invariant architectural regime.”

---

# 4.3 Introduction

Strong overall.

Good structure:

1. NTT importance.
2. Fermat modulus.
3. Multivariate factorization.
4. Missing hardware scaling characterization.
5. Contributions.

However:

The introduction still undersells the architectural idea.

You should introduce earlier:

> “The decomposition depth changes schedule length but not datapath width.”

That should become the paper's conceptual hook.

---

# 4.4 Background

Technically solid.

But it is slightly too condensed.

Potential reviewer issue:

- multidimensional decomposition may feel abrupt.

Recommendation:

Add:

- one explicit tensor example,
- one mapping example,
- one decomposition visualization.

---

# 4.5 Architecture Section

This is the most important section.

Currently:

- conceptually strong,
- visually underdeveloped.

Needs:

- more diagrams,
- lane examples,
- scheduling illustration,
- rotation examples,
- timing diagram.

The propositions are good.

But the section needs stronger pedagogical flow.

---

# 4.6 Methodology

Good but incomplete.

Missing:

- synthesis settings,
- routing directives,
- BRAM inference policy,
- DSP packing details,
- floorplanning policy,
- whether retiming enabled,
- whether out-of-context synthesis used.

Reviewers often care.

---

# 4.7 Results Section

Strongest section overall.

Especially:

- complete grid,
- exact cycle model,
- isolated L=4 analysis,
- width sweep.

The paper does a good job of:

- avoiding cherry-picking.

That is rare and valuable.

---

# 4.8 Comparison Section

Very good.

The honesty helps enormously.

One issue:

The ATP discussion needs clearer normalization language.

Because:

- different moduli,
- different FPGA families,
- different pipeline assumptions.

A reviewer may object.

Recommendation:

Add explicit caveat table.

---

# 4.9 Conclusion

Good and appropriately scoped.

But slightly too modest.

You should more strongly emphasize:

> the identification of a width-invariant architectural scaling regime.

That is the real contribution.

---

# 5. Comparison Against Xing et al.

This section is critical.

## What Xing et al. already contribute

Xing et al. already provide:

- high-radix/mixed-radix FNT,
- merged preprocessing,
- D1 optimization,
- modularized datapath,
- conflict-free mapping,
- radix reuse,
- architectural implementation.

Therefore your paper cannot claim:

- high-radix Fermat NTT architecture,
- conflict-free banking novelty,
- mixed-radix decomposition novelty,
- shared butterfly reuse novelty.

---

## What your draft DOES contribute

Your work instead contributes:

### A. Full-depth design-space exploration

This is genuinely new.

Xing explores:

- a few practical points.

You explore:

- the entire admissible depth range.

That matters.

---

### B. Width-invariant compute interpretation

This is arguably the strongest novelty.

Xing optimize throughput.

Your paper identifies:

- an architectural scaling law.

---

### C. Empirical asymptotic characterization

Your work studies:

- how resource classes scale differently.

That is not the focus of Xing.

---

### D. Architectural abstraction

Your paper reframes the design as:

- a single reusable datapath,
- parameterized by lane width only.

This is a more systems-oriented interpretation.

---

# 6. Publication Risk Assessment

## Likely Reviewer Criticisms

### Reviewer 1

> “Interesting characterization study.”

Probably positive.

---

### Reviewer 2

> “Insufficient novelty over Xing et al.”

Very likely.

Must be addressed.

---

### Reviewer 3

> “No power evaluation.”

Likely.

---

### Reviewer 4

> “Architectural insight is interesting but underformalized.”

Also likely.

---

# 7. What Would Make This Paper Stronger

# HIGH PRIORITY

## 1. Add formal scaling analysis

This is the biggest upgrade possible.

---

## 2. Add power/energy evaluation

Mandatory for stronger venues.

---

## 3. Sharpen novelty framing

Must clearly separate from Xing.

---

## 4. Improve architecture figure dramatically

The figure should visually teach:

- no transpose,
- O(L) interconnect,
- shared datapath.

---

## 5. Add measured-vs-modeled cycle plot

This significantly improves rigor.

---

# MEDIUM PRIORITY

## 6. Add ASIC discussion

---

## 7. Add routing/interconnect discussion

Especially:

- wirelength,
- congestion,
- timing closure trends.

---

## 8. Add memory efficiency analysis

Current BRAM discussion is good.

Could be extended.

---

# LOW PRIORITY

## 9. Add floorplan visualizations

Could be very compelling.

---

## 10. Add utilization heatmaps

Optional but visually strong.

---

# 8. Suggested Reframing

The paper should explicitly frame itself as:

> an architectural scaling study.

NOT:

> a new NTT architecture.

This distinction is essential.

Suggested revised positioning:

> “This work investigates an underexplored architectural regime in hierarchical Fermat-NTT accelerators: whether decomposition depth scales transform size without scaling compute width. Using a complete placed-and-routed exploration across all Fermat-valid configurations, we show that the compute datapath remains approximately invariant with depth, enabled by conflict-free transpose-free banking and an O(L) interconnect.”

That framing is strong and defensible.

---

# 9. Overall Verdict

## Overall Technical Quality

High.

The work is:

- technically coherent,
- experimentally grounded,
- intellectually honest,
- architecturally meaningful.

---

## Main Weakness

Novelty separation from Xing et al.

Without sharper framing, some reviewers may interpret the paper as:

> “parameter sweep + replication.”

The paper must instead establish:

> “architectural scaling characterization.”

as the central contribution.

---

## Final Recommendation

### In current form

Strong workshop / poster / short-paper candidate.

### With:

- formal scaling analysis,
- power evaluation,
- stronger novelty framing,
- improved architecture visuals,
- cycle-model validation plots,

it could become a credible full conference paper.

---

# Final Scores

| Criterion | Score |
|---|---|
| Technical correctness | 8.5/10 |
| Experimental quality | 7.5/10 |
| Clarity | 8/10 |
| Novelty | 5.5/10 |
| Architectural insight | 8.5/10 |
| Reproducibility | 8/10 |
| Publication readiness | 7/10 |

---

# Bottom-Line Assessment

This draft is considerably better than a typical early FPGA architecture paper because it:

- identifies a genuine architectural phenomenon,
- measures it rigorously,
- avoids exaggerated claims,
- presents complete placed-and-routed evidence,
- openly acknowledges where prior work is superior.

The work's success depends almost entirely on whether reviewers accept the framing:

> “architectural scaling characterization”

as a sufficient contribution distinct from Xing et al.

If the novelty framing is sharpened and the scaling theory formalized, the paper has a realistic path to publication in a respectable FPGA or hardware-acceleration venue.

