# RTL Implementation Quick Reference & Developer Notes

## Parameter Cheat Sheet

### Core Configuration
```verilog
// Fermat parameters (fixed)
parameter B = 16;              // q = 2^16 + 1 = 65537
parameter N = 256;             // Polynomial degree
parameter LOGN = $clog2(N);    // 8 bits

// Configurable radix
parameter R = 4;               // or 8, 16
parameter LOGR = $clog2(R);    // 2, 3, or 4 bits
parameter AWIDTH = LOGN - LOGR;// 6, 5, or 4 bits (bank address bits)

// Derived
parameter STAGES = LOGN/LOGR;  // 4, 3, 2 for R=4,8,16
parameter RHAT = N / R^STAGES; // Mixed-radix factor
parameter DEPTH = N/R;         // Entries per bank: 64, 32, 16
parameter DWIDTH = 2*(B+1);    // Data width: 34 bits (dual poly coefficients)
parameter WWIDTH = B+1;        // Word width: 17 bits
```

### Timing/Area Knobs
```verilog
// In ntt_top.v
parameter PAPER_AREA_MODE = 0;        // 0=perf, 1=area
parameter MODMUL_PIPELINED = 0;       // 0=comb, 1=registered output, 2=registered product+output
parameter MEM_SYNC_READ = 0;          // 0=async, 1=sync (BRAM-style with latency)
parameter PIPE_LATENCY = (R >= 16) ? 3 : 1;

// Derived
parameter WRITEBACK_DELAY = 2 + MEM_SYNC_READ + MODMUL_PIPELINED;
```

---

## Datapath Walkthrough

### LOAD Phase (256 cycles)
```
data_in_a / data_in_b (serial) 
  ↓
load_cnt (0→255)
  ↓
Simple sequential address: mem[load_cnt] = {data_in_b, data_in_a}
  ↓
Banks loaded with dual coefficients
```

### NTT1 Phase (STAGES iterations)
```
For each stage s = 0 to STAGES-1:
  1. Control unit computes: b_cnt (0→R^s-1), g_cnt (0→delta_idx-1)
  2. Generate R original addresses via address mapping
  3. iSelect = sum of orig_addr[0] groups mod R
  4. Bank addresses = orig_addr[LOGN-1:LOGR] (all same)
  5. Read from banks via interconnect_bank_out (circular shift by iSelect)
  6. Butterfly computation (4-point, 8-point, or 16-point)
  7. Modular multiply by power-of-2 twiddle factors
  8. Write back via interconnect_bank_in (inverse permutation)
```

### PWM Phase (N/R cycles)
```
For each element 0→N/R-1:
  Lower = product of coefficients from NTT1(a) × NTT1(b)
  Upper = product of coefficients from NTT2(b) × NTT1(b)
  
  result = ModMul(Lower, Upper)  // Fermat reduction
  Write lower half with result
```

### INTT Phase (similar to NTT1)
```
Inverse butterflies using ω^{-k} twiddles
Halving operation: divide by 2 each stage (right-inverse circular shift)
Final scaling: N^{-1} = 256^{-1} mod 65537 merged into last stage
```

### OUTPUT Phase (256 cycles)
```
Sequential readout of lower half coefficients
Output via data_out
```

---

## Memory Mapping Algorithm (Conflict-Free Access)

### Single-Radix (R=4)
```
iSelect = sum(OrigAddr[0][1:0], OrigAddr[0][3:2], ...) mod 4
Bank k gets address: OrigAddr[7:2]
Operand lane j reads from bank[(iSelect + j) mod 4]
Operand lane j writes to bank[(iSelect - j + 4) mod 4]  // inverse
```

### Mixed-Radix (Example: R=8, N=256, STAGES=3, RHAT=4)
```
iSelect = sum(OrigAddr[0] groups) mod 8
When is_Rhat_stage=1 (last stage, RHAT mode):
  // Special permutation for 8→4 reduction
  map_mixed(k) = (k mod 2) * 4 + floor(k/2)
  Lane j reads from bank[(iSelect + map_mixed(j)) mod 8]
```

---

## D1 Representation

### Conversion
```verilog
norm_to_d1(x):    x == 0 ? 2^16 : x - 1
d1_to_norm(x):    x == 2^16 ? 0 : x + 1
```

### Arithmetic (All in D1)
```
d1_add(a, b):
  if a == 2^16: return b         // D1 zero
  if b == 2^16: return a
  sum = a + b
  return (sum[15:0] + (1 - sum[16]))  // Fermat reduction - 1

d1_mul_by_2k(x, k):
  if x == 2^16: return x  // D1 zero preserved
  bits = x[15:0]
  shifted = circular_shift(bits, k)
  return shifted

d1_sub(a, b):
  return d1_add(a, d1_neg(b))

d1_neg(x):
  if x == 2^16: return x
  return ~x & 0xFFFF
```

### Twiddle Multiplication
```
In D1:  omega^k = 2^k (power-of-2)
Multiply: b × 2^k = d1_mul_by_2k(b, k) = circular shift + adjust
No actual multiplier needed! (key FPGA savings)
```

---

## Critical Control Signals

### FSM States
```verilog
ST_IDLE   = 0  // Waiting for start
ST_LOAD   = 1  // Serial load phase
ST_NTT1   = 2  // First NTT transform
ST_NTT2   = 3  // Second NTT transform (for poly b)
ST_PWM    = 4  // Point-wise multiply
ST_INTT   = 5  // Inverse NTT
ST_OUTPUT = 6  // Serial output
ST_DONE   = 7  // Complete
```

### Key Outputs from ctrl_unit
```verilog
orig_addrs[R*LOGN-1:0]     // R original addresses (read/write pattern)
tw_step[$clog2(2*N)-1:0]   // Twiddle exponent
is_Rhat_stage              // Mixed-radix special stage marker
rd_sel[1:0]                // Which half to read: 00=none, 01=lower, 10=upper, 11=both
wr_sel[1:0]                // Which half to write
ntt_mode                   // 1=NTT (forward), 0=INTT (inverse)
pwm_en                     // Point-wise multiply enable
bank_we[R-1:0]             // Per-bank write enables
fsm_state[2:0]             // Current state (exposed)
done                       // Computation finished
```

---

## Common Debugging Points

### Functional Issues
1. **Coefficient mismatch:** Check D1 conversion (norm_to_d1, d1_to_norm)
2. **Twiddle error:** Verify twiddle_rom power-of-2 computation
3. **Memory corruption:** Check interconnect bank routing (iSelect calculation)
4. **Zero handling:** D1 zero is 2^16, not 0 in D1 domain

### Timing Issues
1. **Critical path:** Control → address → BRAM write is longest
2. **RAW conflicts:** Stall logic must insert cycles when reading/writing same address
3. **Interconnect delay:** Long routing paths from ctrl_unit to interconnect

### Test Failures
1. **Check golden model:** `scripts/golden_model.py` uses correct Fermat reduction
2. **Verify test vectors:** Random/impulse/identity have specific semantics
3. **Compare stage outputs:** Use `tb_r8_ntt1_ntt2_compare.v` to isolate stages

---

## Performance Tuning

### For Higher Frequency (Timing)
```verilog
// Register control outputs
wire [R*LOGN-1:0] orig_addrs_q;
always @(posedge clk) orig_addrs_q <= orig_addrs;

// Use PIPE_LATENCY=3 for R≥16
// Increase MEM_SYNC_READ if memory is bottleneck
```

### For Lower Area
```verilog
// Set PAPER_AREA_MODE=1 (uses sync BRAM read, pipelined ModMul)
// Reuse R2 butterfly units for high-radix (shares logic)
// Remove unused radix cores (ifdef R4, R8, R16)
```

### For Lower Power
```verilog
// Disable unused twiddle ROM parallel outputs
// Clock-gate banks that aren't accessed
// Reduce PIPE_LATENCY for reduced register count
```

---

## Integration Checklist

- [ ] Set `N` and `R` parameters in ntt_top.v
- [ ] Verify D1 arithmetic tests pass: `iverilog ... tb_d1_arith.v`
- [ ] Run ModMul unit test: `tb_mod_mul.v`
- [ ] Generate golden model: `python scripts/golden_model.py`
- [ ] Compile testbench: `iverilog -g2009 -I../rtl testbenches/tb_ntt_capture.v ../rtl/*.v`
- [ ] Simulate: `vvp a.out | tee sim.log`
- [ ] Parse output: Extract OUTPUT[i] values
- [ ] Compare to expected_out.hex: All 256 coefficients should match
- [ ] Run regression matrix for all (R, test_type) combinations
- [ ] Synthesize with Vivado: `vivado -mode batch -source synth/synth_ntt.tcl`
- [ ] Check timing report: Target WNS > -18 ns

---

## Quick Start: Adding New Radix Support

Example: Add R=32 support

1. **Create r2ntt_r32.v** with 5 substage loops (2^5 = 32)
   - Twiddle root: ω_32 = 2^? (compute from paper Table I)
   - Generate all 32×substage×twiddle combinations

2. **Add to ntt_top.v:**
   ```verilog
   else if (R == 32) begin
     r2ntt_r32 u_r2ntt (...)
     r2intt_r32 u_r2intt (...)
   end
   ```

3. **Update ctrl_unit.v** PIPE_LATENCY (likely 4 for R=32)

4. **Test:**
   ```powershell
   python run_regression_matrix.py  # auto-detects R=32
   ```

---

## References
- Paper: IEEE TC Vol. 74, No. 10, October 2025 (in docs/paper_text.txt)
- Test harness: sim/run_regression_matrix.py
- Golden model: scripts/golden_model.py
- Architecture diagram: docs/Architecture.png

---

**Last Updated:** May 6, 2026  
**Status:** All tests PASS ✓
