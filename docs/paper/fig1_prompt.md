# Fig. 1 — architecture diagram generation prompt

Use this with an image/diagram generator. It specifies every block, label, and
connection so the output matches the paper's Section III. (For a guaranteed
clean, text-accurate vector figure, asking the model to emit **TikZ** or
**draw.io XML** from this same spec is more reliable than a raster image.)

---

## PROMPT

Create a clean, flat, black-and-white **academic block diagram** (vector style,
white background, thin black rectangles, sans-serif labels, no shadows, no 3D,
no color gradients) of an FPGA datapath for a hierarchical NTT polynomial
multiplier. Single-column figure aspect ratio (roughly 4:3, taller than wide is
fine). Lay it out in three horizontal tiers connected by arrows.

**TOP TIER — Banked memory (left to right, three labeled blocks):**
- Block 1 labeled "mem_A (operand A)"
- Block 2 labeled "mem_B (operand B)"
- Block 3 labeled "mem_scratch (in-place working buffer)"
- Each block is drawn as a horizontal strip subdivided into L=4 small equal
  cells labeled "bank 0", "bank 1", "bank 2", "bank 3".
- A small caption under this tier: "bank(i) = (sum of mixed-radix digits) mod L
  — conflict-free; no transpose buffer".

**MIDDLE TIER — Interconnect:**
- A single wide horizontal block labeled
  "L-wide barrel rotation (read/write crossbar), O(L)".
- Bidirectional vertical arrows connect every memory block above to this
  rotation block (data flows both ways: read up→down into datapath, write
  down→up back into memory).
- A small note to the side: "rotation amount = (sum of non-swept digits) mod L".

**BOTTOM TIER — Shared compute datapath (one row, three labeled blocks):**
- Block A labeled "shift-only L-point bidirectional sub-NTT (fwd/inv) —
  MULTIPLIER-FREE".
- Block B labeled "L modular multipliers (pre/post-twist, cross-twiddle,
  point-wise mult)" with a small tag "DSP = L".
- Block C labeled "twiddle ROM".
- Arrows: from the barrel-rotation block down into sub-NTT and into the
  multiplier array; from twiddle ROM into the multiplier array; outputs of
  sub-NTT and multipliers go back up into the barrel-rotation block (showing the
  in-place loop).

**RIGHT SIDE — Control (one tall block spanning the tiers):**
- A vertical block labeled "FSM + address generator (depth-d schedule)".
- Dashed control arrows from this block to the memory tier, the rotation block,
  and the datapath.

**CALLOUT / legend box (bottom):**
- "One datapath, time-multiplexed across all 6d-2 phases."
- "Interconnect width = L (independent of depth d and size N)."

Keep all text horizontal and legible, minimal clutter, generous spacing, and a
thin outer border. Do not invent extra blocks or labels beyond those listed.

---

## Caption to use in the paper (already wire \ref{fig:arch} where needed)

> Fig. 1. Shared-datapath architecture. Three banked memories (two operands, one
> in-place scratch) connect through an L-wide barrel-rotation crossbar to a
> single shift-only sub-NTT and an L-lane modular-multiplier array. The
> conflict-free bank map makes every axis single-cycle accessible, so axis
> switches are address remaps with no transpose buffer; the interconnect width is
> O(L), independent of d and N.
