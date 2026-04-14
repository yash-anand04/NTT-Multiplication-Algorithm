# NTT Timing Optimization Analysis Report

## Summary
**Baseline (Table.xlsx):** WNS = -20.038 ns  
**After Optimization (Table_new.xlsx):** WNS = -20.594 ns  
**Result:** **DEGRADATION by 0.556 ns** ❌

---

## Key Findings

### 1. Critical Path Shift
The optimization strategy **backfired**:

| Metric | Baseline | Optimized |
|--------|----------|-----------|
| **Worst Slack** | -20.0381 ns | -20.5936 ns |
| **Primary Startpoint** | `u_ctrl/b_cnt_reg[0]/C` (1003 paths) | `u_ctrl/delta_idx_reg[2]_replica_2/C` (1244 paths) |
| **Total Paths Analyzed** | 1537 | 1500 |

**What happened:**
- The `max_fanout = 32` directives on `state`, `b_cnt`, `g_cnt`, and `delta_idx` caused Vivado to replicate registers
- Vivado created `delta_idx_reg[2]_replica_2` to distribute fanout
- **The routing to this replica became the new bottleneck** (1244 paths now originate from it)
- New critical path is **0.556 ns worse** than the original

### 2. Why Register Replication Failed

When you specify `(* max_fanout = 32 *)` on LOGN-bit registers with 100+ loads:
1. Vivado replicates the register to meet the constraint
2. But it doesn't automatically optimize **routing to the replicas**
3. The physical location of replicas vs. loads can create **longer routes** than the original fanout
4. In Kintex-7 with high congestion, this routing penalty > fanout reduction benefit

---

## Root Cause Analysis

### Original Path (Baseline)
```
b_cnt_reg[0] --fanout-to-100+-loads--> BRAM write addresses
    Delay: ~20 ns (fanout + routing + interconnect logic)
```

### New Path (Optimized)
```
delta_idx_reg[2]_replica_2 --1244-paths-with-suboptimal-routing--> BRAM addresses  
    Delay: ~20.6 ns (replica routing worse than expected)
```

### Why Delta_idx Became Bottleneck
In `ctrl_unit.v` address generation:
```verilog
stride_all = (delta_idx << LOGR);      // CAN'T AVOID - all R addresses need this
base_block = b_cnt * stride_all;        // Still uses delta_idx indirectly
for (r_idx = 0; r_idx < R; r_idx = r_idx + 1) begin
    orig_addrs[r_idx*LOGN +: LOGN] = 
        base_block + g_cnt + (delta_idx * r_idx);  // Loops use delta_idx R times
end
```
Every address computation depends on `delta_idx` - even though we cached arithmetic, the register itself is **always on the critical path**.

---

## Why Previous Optimizations Didn't Help

| Change | Intended Effect | Actual Result |
|--------|-----------------|---------------|
| `max_fanout = 32` on delta_idx, b_cnt, state, g_cnt | Reduce fanout congestion | **Increased routing delay** through replicas |
| `stride_all` caching | Eliminate multiply chain | **Not evaluated** by tool with new routing |
| Modulo simplification (`j[LOGR-1:0] - iselect`) | Remove modulo operator | Works but **not the bottleneck** |


---

## Recommended Next Steps

### Option 1: Revert Fanout Directives (Lowest Risk)
Remove `max_fanout = 32` annotations and let Vivado use natural fanout buffering:
```verilog
// REMOVE these lines:
(* max_fanout = 32 *) reg [LOGN-1:0] delta_idx;
(* max_fanout = 32 *) reg [LOGN-1:0] b_cnt;
// etc.
```
**Expected Result:** Revert to baseline -20.038 ns (recover lost 0.556 ns)

---

### Option 2: Increase max_fanout Threshold
If you want to keep fanout directives, use larger thresholds to reduce replication:
```verilog
(* max_fanout = 64 *)   // Up from 32
(* max_fanout = 96 *)   // Even more conservative
```
**Rationale:** Fewer replicas = fewer routing penalties  
**Risk:** May not help if fanout is the non-dominant delay component

---

### Option 3: Pipeline the Critical Path (Most Aggressive)
Insert a register stage between control FSM and address generation:
```verilog
// Stage 1: Capture control outputs
always @(posedge clk) begin
    delta_idx_pipe   <= delta_idx;
    b_cnt_pipe       <= b_cnt;
    g_cnt_pipe       <= g_cnt;
    stage_cnt_pipe   <= stage_cnt;
end

// Stage 2: Compute addresses from pipelined values
always @(*) begin
    stride_all = (delta_idx_pipe << LOGR);
    base_block = b_cnt_pipe * stride_all;
    ...
end
```
**Expected Result:** Reduce WNS significantly (2-3 ns per pipe stage)  
**Trade-off:** +1 cycle latency throughout computation  
**Feasibility:** Medium (require stall logic updates in ntt_top)

---

### Option 4: Hybrid - Selective Pipelining
Only pipeline the high-fanout `delta_idx` register:
```verilog
always @(posedge clk) begin
    delta_idx_pipe <= delta_idx;  // Just this one
end
```
Then update address logic to use `delta_idx_pipe` in combinational block.

**Expected Result:** 1-2 ns improvement with minimal latency impact  
**Risk:** Functional timing constraints (verify with simulation)

---

## Immediate Recommendation

**Do NOT run another Vivado iteration until deciding on strategy.**

The current RTL changes (fanout directives, arithmetic caching, modulo simplification) are **making things worse**. 

1. **Best first action:** Revert fanout directives to recover baseline -20.038 ns
2. **Then evaluate:** Whether -20 ns is acceptable for your use case
3. **If more optimization needed:** Try Option 3 (pipelining) separately at new iteration

---

## Data Summary Table

```
Baseline Paths (Top 3):
  Start: u_ctrl/b_cnt_reg[0]/C        → End: BRAM WADR   | Slack: -20.04 ns
  Start: u_ctrl/FSM_seq_state[1]/C    → End: BRAM WADR   | Slack: ~-19.80 ns (402 paths)
  
Optimized Paths (Top 3):
  Start: delta_idx_reg[2]_replica_2/C → End: BRAM WADR   | Slack: -20.59 ns ⚠
  Start: state_reg[1]_rep__0/C         → End: BRAM WADR   | Slack: ~-20.50 ns (141 paths)
```

---

## Next Steps

1. **Decision Required:** Which optimization approach (1-4 above)?
2. **If choosing Option 1 (revert):** I'll remove fanout directives
3. **If choosing Option 3 (pipeline):** I'll add pipeline stage and update FSM stall logic
4. **Run new Vivado iteration** and share updated Table_opt.xlsx for comparison

**What would you prefer?**
