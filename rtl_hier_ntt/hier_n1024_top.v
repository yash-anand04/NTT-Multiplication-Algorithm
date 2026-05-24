// =============================================================================
// hier_n1024_top.v   (Phase C, banked-storage revision)
// Hierarchical d=2 NTT polynomial multiplier:  N = L * M = 32 * 32 = 1024.
//
// Storage refactor (from register-array v1):
//   Each of the 8 working arrays (raw_a, raw_b, work, trans, spec_a, spec_b,
//   prod, result) is now a 32-bank × 32-entry × 17-bit conflict-free banked
//   memory mapped to distributed RAM (RAM32X1S).  The lane<->bank crossbar
//   is a cyclic rotation by `op_count` mod 32 — the FSM's natural shift
//   parameter for both row and column scans.
//
//   Banking formula:  bank(outer, inner) = (outer + inner) mod 32,
//                     position(outer, inner) = inner.
//   With L = M = 32 and op_count playing the role of either outer or inner
//   depending on phase, the cyclic shift gives the same crossbar permutation
//   for every phase's read AND write side.  See banked_mem.v.
//
// All other architectural choices unchanged from the v1 register-array build:
//   - Sub-NTTs are the existing combinational bivar_ntt_subntt32 (DIT fwd /
//     DIF inv, shift-only).
//   - Mul lanes use combinational mod_mul_fermat (PIPELINED=0).
//   - twiddle_gen runs in REGISTERED=0 (combinational) mode.
// =============================================================================

`ifndef _HIER_N1024_TOP_GUARD
`define _HIER_N1024_TOP_GUARD

module hier_n1024_top #(
    parameter B       = 16,
    parameter L       = 32,
    parameter M       = 32,
    parameter N       = L * M,            // 1024
    parameter WWIDTH  = B + 1,
    parameter LOGN    = $clog2(N),        // 10
    parameter TW_BITS = LOGN + 1          // 11
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,
    input  wire [WWIDTH-1:0] data_in_a,
    input  wire [WWIDTH-1:0] data_in_b,
    output reg  [WWIDTH-1:0] data_out,
    output reg               data_out_valid,
    output reg               done,
    output reg  [15:0]       cycle_count
);

    // ---- FSM ---------------------------------------------------------------
    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_LOAD      = 4'd1,
        ST_FWD_ROW_A = 4'd2,
        ST_FWD_XTW_A = 4'd3,
        ST_FWD_COL_A = 4'd4,
        ST_FWD_ROW_B = 4'd5,
        ST_FWD_XTW_B = 4'd6,
        ST_FWD_COL_B = 4'd7,
        ST_PWM       = 4'd8,
        ST_INV_COL   = 4'd9,
        ST_INV_XTW   = 4'd10,
        ST_INV_ROW   = 4'd11,
        ST_OUTPUT    = 4'd12,
        ST_DONE      = 4'd13;

    reg [3:0]      state;
    reg [LOGN:0]   op_count;             // up to N-1 = 1023

    // -------------------------------------------------------------------------
    // 3-cycle pipeline delay registers (match PIPELINED=1 mod_mul_fermat).
    // The write side of every memory uses *_d3 signals so the write address
    // realigns with the mul output 3 cycles after the read/issue.
    // -------------------------------------------------------------------------
    // 9-stage delay pipeline.  Three "tap" points are used by different
    // write paths to align with each pipeline's natural latency:
    //   d3 : mul-only phases (FWD_XTW, PWM, INV_XTW, LOAD streaming)
    //   d6 : NTT-only phases (FWD_COL, INV_COL)
    //   d9 : NTT+mul phases  (FWD_ROW, INV_ROW)
    reg [3:0]      state_d1,    state_d2,    state_d3,    state_d4,    state_d5,
                   state_d6,    state_d7,    state_d8,    state_d9,    state_d10,
                   state_d11,   state_d12;
    reg [LOGN:0]   op_count_d1, op_count_d2, op_count_d3, op_count_d4, op_count_d5,
                   op_count_d6, op_count_d7, op_count_d8, op_count_d9, op_count_d10,
                   op_count_d11, op_count_d12;
    reg            valid_d1,    valid_d2,    valid_d3,    valid_d4,    valid_d5,
                   valid_d6,    valid_d7,    valid_d8,    valid_d9,    valid_d10,
                   valid_d11,   valid_d12;
    wire           issue_valid;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            {state_d1, state_d2, state_d3, state_d4, state_d5,
             state_d6, state_d7, state_d8, state_d9, state_d10,
             state_d11, state_d12} <= {12{4'd0}};
            {op_count_d1, op_count_d2, op_count_d3, op_count_d4, op_count_d5,
             op_count_d6, op_count_d7, op_count_d8, op_count_d9, op_count_d10,
             op_count_d11, op_count_d12} <= {12*(LOGN+1){1'b0}};
            {valid_d1, valid_d2, valid_d3, valid_d4, valid_d5,
             valid_d6, valid_d7, valid_d8, valid_d9, valid_d10,
             valid_d11, valid_d12} <= 12'b0;
        end else begin
            state_d1<=state;       state_d2<=state_d1;     state_d3<=state_d2;
            state_d4<=state_d3;    state_d5<=state_d4;     state_d6<=state_d5;
            state_d7<=state_d6;    state_d8<=state_d7;     state_d9<=state_d8;
            state_d10<=state_d9;   state_d11<=state_d10;   state_d12<=state_d11;
            op_count_d1<=op_count;     op_count_d2<=op_count_d1;  op_count_d3<=op_count_d2;
            op_count_d4<=op_count_d3;  op_count_d5<=op_count_d4;  op_count_d6<=op_count_d5;
            op_count_d7<=op_count_d6;  op_count_d8<=op_count_d7;  op_count_d9<=op_count_d8;
            op_count_d10<=op_count_d9; op_count_d11<=op_count_d10; op_count_d12<=op_count_d11;
            valid_d1<=issue_valid; valid_d2<=valid_d1;  valid_d3<=valid_d2;
            valid_d4<=valid_d3;    valid_d5<=valid_d4;  valid_d6<=valid_d5;
            valid_d7<=valid_d6;    valid_d8<=valid_d7;  valid_d9<=valid_d8;
            valid_d10<=valid_d9;   valid_d11<=valid_d10; valid_d12<=valid_d11;
        end
    end

    // issue_valid: 1 during the M (or N for LOAD/OUTPUT) "real" cycles of a
    // phase; 0 during the 3 trailing drain cycles.
    assign issue_valid =
        (state == ST_LOAD)    ? (op_count < N) :
        (state == ST_OUTPUT)  ? (op_count < N) :
        (state == ST_IDLE)    ? 1'b0 :
        (state == ST_DONE)    ? 1'b0 :
                                (op_count < M);

    // Banking parameters
    localparam integer LANES     = L;     // 32
    localparam integer DEPTH     = M;     // 32
    localparam integer LOG_LANES = 5;
    localparam integer LOG_DEPTH = 5;

    // ---- Common derived signals --------------------------------------------
    // Bottom 5 bits of op_count at each pipeline tap
    wire [LOG_LANES-1:0] op5      = op_count[LOG_LANES-1:0];
    wire [LOG_LANES-1:0] op5_d4   = op_count_d4[LOG_LANES-1:0];
    wire [LOG_LANES-1:0] op5_d7   = op_count_d7[LOG_LANES-1:0];
    wire [LOG_LANES-1:0] op5_d11  = op_count_d11[LOG_LANES-1:0];

    // LOAD / OUTPUT single-cell bank/position (current and 4-delayed for d4 tap)
    wire [LOG_LANES-1:0] load_bank;
    wire [LOG_DEPTH-1:0] load_pos = op_count[LOG_DEPTH-1:0];
    assign load_bank = (op_count[LOG_LANES-1:0] + op_count[LOGN-1:LOG_LANES]) & {LOG_LANES{1'b1}};

    wire [LOG_LANES-1:0] load_bank_d4;
    wire [LOG_DEPTH-1:0] load_pos_d4 = op_count_d4[LOG_DEPTH-1:0];
    assign load_bank_d4 = (op_count_d4[LOG_LANES-1:0] + op_count_d4[LOGN-1:LOG_LANES]) & {LOG_LANES{1'b1}};

    // Per-lane position vectors
    wire [LANES*LOG_DEPTH-1:0] pos_lane_id_pack;
    wire [LANES*LOG_DEPTH-1:0] pos_const_d4_pack;   // pos[k] = op5_d4
    wire [LANES*LOG_DEPTH-1:0] pos_const_d7_pack;   // pos[k] = op5_d7
    wire [LANES*LOG_DEPTH-1:0] pos_const_d11_pack;  // pos[k] = op5_d11
    wire [LANES*LOG_DEPTH-1:0] pos_zero_pack;
    // Read-side rshift/rpos drivers still use op5 (cycle-T issue value);
    // pos_const_pack is the legacy alias kept for the read side.
    wire [LANES*LOG_DEPTH-1:0] pos_const_pack;
    genvar gk;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_pos
            assign pos_lane_id_pack  [gk*LOG_DEPTH +: LOG_DEPTH] = gk[LOG_DEPTH-1:0];
            assign pos_const_pack    [gk*LOG_DEPTH +: LOG_DEPTH] = op5;
            assign pos_const_d4_pack [gk*LOG_DEPTH +: LOG_DEPTH] = op5_d4;
            assign pos_const_d7_pack [gk*LOG_DEPTH +: LOG_DEPTH] = op5_d7;
            assign pos_const_d11_pack[gk*LOG_DEPTH +: LOG_DEPTH] = op5_d11;
            assign pos_zero_pack     [gk*LOG_DEPTH +: LOG_DEPTH] = {LOG_DEPTH{1'b0}};
        end
    endgenerate

    // ---- 3-cycle delay registers for LOAD data ----
    // Pipelined sub_ntt32's output is already registered (6-cycle latency
    // from start to valid), so no extra ntt_col_out delay is needed.
    reg [WWIDTH-1:0] data_in_a_d1, data_in_a_d2, data_in_a_d3, data_in_a_d4;
    reg [WWIDTH-1:0] data_in_b_d1, data_in_b_d2, data_in_b_d3, data_in_b_d4;
    always @(posedge clk) begin
        data_in_a_d1 <= data_in_a;
        data_in_a_d2 <= data_in_a_d1;
        data_in_a_d3 <= data_in_a_d2;
        data_in_a_d4 <= data_in_a_d3;
        data_in_b_d1 <= data_in_b;
        data_in_b_d2 <= data_in_b_d1;
        data_in_b_d3 <= data_in_b_d2;
        data_in_b_d4 <= data_in_b_d3;
    end

    // ---- Sub-NTT and mul plumbing (unchanged from v1) ----------------------
    reg  [L*WWIDTH-1:0]      mul_a_pack;
    reg  [L*WWIDTH-1:0]      mul_b_pack;
    wire [L*WWIDTH-1:0]      mul_out_pack;
    wire [L*WWIDTH-1:0]      tw_pack;
    wire [L*TW_BITS-1:0]     tw_idx_pack;

    // Shared sub-NTT input pack (row and col phases are mutually exclusive
    // through the FSM, so one sub_ntt32 instance serves both).
    reg  [L*WWIDTH-1:0]      ntt_in_pack;

    // Sub-NTT control: pipelined sub_ntt32 (6-cycle latency, start/valid).
    // ROW path: used by FWD_ROW (input = mul_out, sampled at state_d4=FWD_ROW)
    //           and INV_ROW (input = trans_rdata, sampled at state=INV_ROW).
    // COL path: used by FWD_COL_A/B and INV_COL (input = trans/prod rdata).
    wire ntt_row_start =
        ((state_d4 == ST_FWD_ROW_A || state_d4 == ST_FWD_ROW_B) && valid_d4) ||
        ((state    == ST_INV_ROW)                               && issue_valid);
    wire ntt_row_inverse = (state == ST_INV_ROW);

    wire ntt_col_start =
        ((state == ST_FWD_COL_A) || (state == ST_FWD_COL_B) ||
         (state == ST_INV_COL)) && issue_valid;
    wire ntt_col_inverse = (state == ST_INV_COL);

    wire inverse_subntt_row = ntt_row_inverse;   // legacy alias kept for grep
    wire inverse_subntt_col = ntt_col_inverse;

    function [TW_BITS-1:0] inv_tw_idx;
        input [TW_BITS-1:0] idx;
        begin
            inv_tw_idx = ((2*N) - idx) % (2*N);
        end
    endfunction

    genvar tg;
    generate
        for (tg = 0; tg < L; tg = tg + 1) begin : gen_tw_lanes
            wire [TW_BITS-1:0] lane_tw_fwd_row    =  (tg * M + op_count) % (2*N);
            wire [TW_BITS-1:0] lane_tw_cross      = (2 * op_count * tg) % (2*N);
            wire [TW_BITS-1:0] lane_tw_inv_cross  = inv_tw_idx((2 * tg * op_count) % (2*N));
            // For INV_ROW the mul fires 6 cycles AFTER the issue (when sub_ntt32
            // valid goes high).  The twiddle for that issue uses op_count_d7.
            wire [TW_BITS-1:0] lane_tw_inv_row_d7 = inv_tw_idx((tg * M + op_count_d7) % (2*N));

            assign tw_idx_pack[tg*TW_BITS +: TW_BITS] =
                (state_d7 == ST_INV_ROW)                             ? lane_tw_inv_row_d7 :
                ((state == ST_FWD_ROW_A) || (state == ST_FWD_ROW_B)) ? lane_tw_fwd_row    :
                ((state == ST_FWD_XTW_A) || (state == ST_FWD_XTW_B)) ? lane_tw_cross      :
                (state == ST_INV_XTW)                                ? lane_tw_inv_cross  :
                {TW_BITS{1'b0}};

            twiddle_gen #(.B(B), .LOGN(LOGN), .REGISTERED(0)) u_tw (
                .clk    (clk),
                .idx    (tw_idx_pack[tg*TW_BITS +: TW_BITS]),
                .tw_out (tw_pack[tg*WWIDTH +: WWIDTH])
            );

            // Register mul inputs to break the long combinational path:
            //   op_count -> bank addressing -> LUTRAM read -> crossbar
            //                -> state mux -> mod_mul a_r/b_r register input.
            // Adds +1 cycle to all mul-using paths.  d3->d4, d10->d11.
            //
            // DONT_TOUCH forces Vivado to keep these registers external; without
            // it, Vivado packs them into the DSP's input register and the
            // critical path stays op_count -> DSP_A_pin -> DSP_mul -> product_r.
            (* DONT_TOUCH = "true" *) reg [WWIDTH-1:0] mul_a_r;
            (* DONT_TOUCH = "true" *) reg [WWIDTH-1:0] mul_b_r;
            always @(posedge clk) begin
                mul_a_r <= mul_a_pack[tg*WWIDTH +: WWIDTH];
                mul_b_r <= mul_b_pack[tg*WWIDTH +: WWIDTH];
            end
            mod_mul_fermat #(.B(B), .PIPELINED(1)) u_mul (
                .clk    (clk),
                .rst    (rst),
                .a      (mul_a_r),
                .b      (mul_b_r),
                .result (mul_out_pack[tg*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // Register the shared sub-NTT input to break the long path
    //   op_count -> bank addressing -> LUTRAM -> crossbar -> sub-NTT input.
    // This adds +1 cycle to all NTT-using phase latencies.
    reg [L*WWIDTH-1:0] ntt_in_reg;
    reg                ntt_start_d1, ntt_inverse_d1;
    wire               ntt_start   = ntt_row_start   | ntt_col_start;
    wire               ntt_inverse = ntt_row_inverse | ntt_col_inverse;
    always @(posedge clk) begin
        ntt_in_reg      <= ntt_in_pack;
        ntt_start_d1    <= ntt_start;
        ntt_inverse_d1  <= ntt_inverse;
    end

    wire [L*WWIDTH-1:0] ntt_out_pack;
    wire                ntt_valid;
    sub_ntt32_bidir #(.B(B)) u_subntt (
        .clk      (clk),
        .rst      (rst),
        .start    (ntt_start_d1),
        .inverse  (ntt_inverse_d1),
        .in_norm  (ntt_in_reg),
        .out_norm (ntt_out_pack),
        .valid    (ntt_valid)
    );

    // Legacy aliases — write logic and mul_a_pack INV_ROW path consume these.
    wire [L*WWIDTH-1:0] ntt_row_out_pack = ntt_out_pack;
    wire [M*WWIDTH-1:0] ntt_col_out_pack = ntt_out_pack;

    // =========================================================================
    // 8 banked memories with per-state control logic
    // =========================================================================
    `define BMEM_DECL(NM) \
        wire [LANES*WWIDTH-1:0]    NM``_rdata; \
        reg  [LOG_LANES-1:0]       NM``_rshift; \
        reg  [LANES*LOG_DEPTH-1:0] NM``_rpos; \
        reg  [LOG_LANES-1:0]       NM``_wshift; \
        reg  [LANES*LOG_DEPTH-1:0] NM``_wpos; \
        reg  [LANES*WWIDTH-1:0]    NM``_wdata; \
        reg  [LANES-1:0]           NM``_we; \
        banked_mem #(.WWIDTH(WWIDTH), .LANES(LANES), .DEPTH(DEPTH), \
                     .READ_LATENCY(0)) u_``NM ( \
            .clk(clk), \
            .rshift(NM``_rshift), .rpos_pack(NM``_rpos), .rdata_pack(NM``_rdata), \
            .wshift(NM``_wshift), .wpos_pack(NM``_wpos), .wdata_pack(NM``_wdata), \
            .we_pack(NM``_we) \
        );

    // Consolidated 4-memory layout (in-place reuse):
    //   mem_a  : raw_a (LOAD..FWD_ROW_A) -> spec_a (FWD_COL_A..PWM)
    //                                   -> prod   (PWM..INV_COL)
    //                                   -> result (INV_ROW..OUTPUT)
    //   mem_b  : raw_b (LOAD..FWD_ROW_B) -> spec_b (FWD_COL_B..PWM)
    //   mem_work : work (FWD_ROW outputs / INV_COL outputs)
    //   mem_trans: trans (FWD_XTW outputs / INV_XTW outputs)
    //
    // The logical-array aliases used below (raw_a_rdata etc.) are wires that
    // mirror the underlying physical memory's rdata.  No additional storage.
    `BMEM_DECL(mem_a)
    `BMEM_DECL(mem_b)
    `BMEM_DECL(mem_work)
    `BMEM_DECL(mem_trans)

    // Logical aliases: name what each physical memory holds during each phase
    // so the rest of the code stays readable.
    wire [LANES*WWIDTH-1:0] raw_a_rdata    = mem_a_rdata;
    wire [LANES*WWIDTH-1:0] raw_b_rdata    = mem_b_rdata;
    wire [LANES*WWIDTH-1:0] work_rdata     = mem_work_rdata;
    wire [LANES*WWIDTH-1:0] trans_rdata    = mem_trans_rdata;
    wire [LANES*WWIDTH-1:0] spec_a_rdata   = mem_a_rdata;
    wire [LANES*WWIDTH-1:0] spec_b_rdata   = mem_b_rdata;
    wire [LANES*WWIDTH-1:0] prod_rdata     = mem_a_rdata;
    wire [LANES*WWIDTH-1:0] result_rdata   = mem_a_rdata;

    // -------------------------------------------------------------------------
    // Helper: a 32-wide "broadcast" packing for write data from a single scalar
    // -------------------------------------------------------------------------
    function [LANES*WWIDTH-1:0] broadcast17;
        input [WWIDTH-1:0] v;
        integer bi;
        begin
            broadcast17 = {LANES*WWIDTH{1'b0}};
            for (bi = 0; bi < LANES; bi = bi + 1)
                broadcast17[bi*WWIDTH +: WWIDTH] = v;
        end
    endfunction

    // =========================================================================
    // PER-MEMORY DRIVER LOGIC
    //
    // Each of the 8 banked_mem instances has:
    //   * READ side  (combinational, used by the current FSM phase)
    //   * WRITE side (gated by state matching this memory's writer)
    //
    // Convention: when a memory is not read in this state, rshift=0, rpos=0
    // (no consumer cares).  When not written, we=0.
    // =========================================================================

    // ---- mem_a -------------------------------------------------------------
    // Write delays (matching the natural pipeline of each phase's data path):
    //   LOAD:        d3 (data_in_a_d4)
    //   FWD_COL_A:   d6 (ntt_col_out_pack -- sub_ntt32 valid at issue+6)
    //   PWM:         d3 (mul_out_pack    -- mul valid at issue+3)
    //   INV_ROW:     d9 (mul_out_pack    -- mul of NTT'd at issue+6, mul+3)
    always @(*) begin
        mem_a_rshift = {LOG_LANES{1'b0}};
        mem_a_rpos   = pos_zero_pack;
        mem_a_wshift = {LOG_LANES{1'b0}};
        mem_a_wpos   = pos_zero_pack;
        mem_a_wdata  = {LANES*WWIDTH{1'b0}};
        mem_a_we     = {LANES{1'b0}};
        // ---- Read side ----
        case (state)
            ST_FWD_ROW_A,
            ST_PWM: begin
                mem_a_rshift = op5;
                mem_a_rpos   = pos_const_pack;
            end
            ST_INV_COL: begin
                mem_a_rshift = op5;
                mem_a_rpos   = pos_lane_id_pack;
            end
            ST_OUTPUT: begin
                mem_a_rshift                                = {LOG_LANES{1'b0}};
                mem_a_rpos[load_bank*LOG_DEPTH +: LOG_DEPTH] = load_pos;
            end
            default: ;
        endcase
        // ---- Write side: layered priority by pipeline tap (highest first) ----
        // d9 tap (INV_ROW)
        if (state_d11 == ST_INV_ROW && valid_d11) begin
            mem_a_wshift = op5_d11;
            mem_a_wpos   = pos_const_d11_pack;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // d6 tap (FWD_COL_A) -- mutually exclusive with d9 (different phases)
        else if (state_d7 == ST_FWD_COL_A && valid_d7) begin
            mem_a_wshift = op5_d7;
            mem_a_wpos   = pos_lane_id_pack;
            mem_a_wdata  = ntt_col_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // d3 tap (LOAD or PWM)
        else if (state_d4 == ST_LOAD && valid_d4) begin
            mem_a_wpos[load_bank_d4*LOG_DEPTH +: LOG_DEPTH] = load_pos_d4;
            mem_a_wdata                                     = broadcast17(data_in_a_d4);
            mem_a_we[load_bank_d4]                          = 1'b1;
        end
        else if (state_d4 == ST_PWM && valid_d4) begin
            mem_a_wshift = op5_d4;
            mem_a_wpos   = pos_const_d4_pack;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
    end

    // ---- mem_b -------------------------------------------------------------
    // Write delays: LOAD (d3), FWD_COL_B (d6).
    always @(*) begin
        mem_b_rshift = {LOG_LANES{1'b0}};
        mem_b_rpos   = pos_zero_pack;
        mem_b_wshift = {LOG_LANES{1'b0}};
        mem_b_wpos   = pos_zero_pack;
        mem_b_wdata  = {LANES*WWIDTH{1'b0}};
        mem_b_we     = {LANES{1'b0}};
        case (state)
            ST_FWD_ROW_B,
            ST_PWM: begin
                mem_b_rshift = op5;
                mem_b_rpos   = pos_const_pack;
            end
            default: ;
        endcase
        if (state_d7 == ST_FWD_COL_B && valid_d7) begin
            mem_b_wshift = op5_d7;
            mem_b_wpos   = pos_lane_id_pack;
            mem_b_wdata  = ntt_col_out_pack;
            mem_b_we     = {LANES{1'b1}};
        end
        else if (state_d4 == ST_LOAD && valid_d4) begin
            mem_b_wpos[load_bank_d4*LOG_DEPTH +: LOG_DEPTH] = load_pos_d4;
            mem_b_wdata                                     = broadcast17(data_in_b_d4);
            mem_b_we[load_bank_d4]                          = 1'b1;
        end
    end

    // ---- mem_work ----------------------------------------------------------
    // Write delays: FWD_ROW_A/B (d9), INV_COL (d6).
    always @(*) begin
        mem_work_rshift = {LOG_LANES{1'b0}};
        mem_work_rpos   = pos_zero_pack;
        mem_work_wshift = {LOG_LANES{1'b0}};
        mem_work_wpos   = pos_zero_pack;
        mem_work_wdata  = {LANES*WWIDTH{1'b0}};
        mem_work_we     = {LANES{1'b0}};
        case (state)
            ST_FWD_XTW_A,
            ST_FWD_XTW_B: begin
                mem_work_rshift = op5;
                mem_work_rpos   = pos_lane_id_pack;
            end
            ST_INV_XTW: begin
                mem_work_rshift = op5;
                mem_work_rpos   = pos_const_pack;
            end
            default: ;
        endcase
        if ((state_d11 == ST_FWD_ROW_A || state_d11 == ST_FWD_ROW_B) && valid_d11) begin
            mem_work_wshift = op5_d11;
            mem_work_wpos   = pos_lane_id_pack;
            mem_work_wdata  = ntt_row_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
        else if (state_d7 == ST_INV_COL && valid_d7) begin
            mem_work_wshift = op5_d7;
            mem_work_wpos   = pos_lane_id_pack;
            mem_work_wdata  = ntt_col_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
    end

    // ---- mem_trans ---------------------------------------------------------
    // Write delays: FWD_XTW_A/B (d3), INV_XTW (d3).
    always @(*) begin
        mem_trans_rshift = {LOG_LANES{1'b0}};
        mem_trans_rpos   = pos_zero_pack;
        mem_trans_wshift = {LOG_LANES{1'b0}};
        mem_trans_wpos   = pos_zero_pack;
        mem_trans_wdata  = {LANES*WWIDTH{1'b0}};
        mem_trans_we     = {LANES{1'b0}};
        case (state)
            ST_FWD_COL_A,
            ST_FWD_COL_B,
            ST_INV_ROW: begin
                mem_trans_rshift = op5;
                mem_trans_rpos   = pos_lane_id_pack;
            end
            default: ;
        endcase
        if ((state_d4 == ST_FWD_XTW_A || state_d4 == ST_FWD_XTW_B) && valid_d4) begin
            mem_trans_wshift = op5_d4;
            mem_trans_wpos   = pos_const_d4_pack;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if (state_d4 == ST_INV_XTW && valid_d4) begin
            mem_trans_wshift = op5_d4;
            mem_trans_wpos   = pos_lane_id_pack;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
    end


    // =========================================================================
    // Sub-NTT / multiplier input packing  (consumer-side)
    // =========================================================================
    integer ci;

    // Shared ntt_in source — row and col phases are mutually exclusive:
    //  ROW path:
    //    - FWD_ROW writes (state_d4 == FWD_ROW): input = registered mul_out.
    //    - INV_ROW reads  (state    == INV_ROW): input = current trans_rdata.
    //  COL path:
    //    - FWD_COL_A/B (state == FWD_COL_*): input = current trans_rdata.
    //    - INV_COL     (state == INV_COL):   input = current prod_rdata.
    always @(*) begin
        ntt_in_pack = {L*WWIDTH{1'b0}};
        if (state_d4 == ST_FWD_ROW_A || state_d4 == ST_FWD_ROW_B)
            ntt_in_pack = mul_out_pack;
        else begin
            case (state)
                ST_INV_ROW,
                ST_FWD_COL_A,
                ST_FWD_COL_B: ntt_in_pack = trans_rdata;
                ST_INV_COL:   ntt_in_pack = prod_rdata;
                default: ;
            endcase
        end
    end

    always @(*) begin
        mul_a_pack = {L*WWIDTH{1'b0}};
        mul_b_pack = {L*WWIDTH{1'b0}};
        // INV_ROW path: mul samples sub-NTT output 6 cycles after issue.
        // This branch has priority over the per-state mux below.
        if (state_d7 == ST_INV_ROW) begin
            mul_a_pack = ntt_row_out_pack;
            mul_b_pack = tw_pack;
        end else begin
            for (ci = 0; ci < L; ci = ci + 1) begin
                case (state)
                    ST_FWD_ROW_A: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = raw_a_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack    [ci*WWIDTH +: WWIDTH];
                    end
                    ST_FWD_ROW_B: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = raw_b_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack    [ci*WWIDTH +: WWIDTH];
                    end
                    ST_FWD_XTW_A,
                    ST_FWD_XTW_B: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = work_rdata [ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack    [ci*WWIDTH +: WWIDTH];
                    end
                    ST_PWM: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = spec_a_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = spec_b_rdata[ci*WWIDTH +: WWIDTH];
                    end
                    ST_INV_XTW: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = work_rdata [ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack    [ci*WWIDTH +: WWIDTH];
                    end
                    default: begin end
                endcase
            end
        end
    end

    // =========================================================================
    // Main state machine
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= ST_IDLE;
            op_count       <= {(LOGN+1){1'b0}};
            cycle_count    <= 16'd0;
            data_out       <= {WWIDTH{1'b0}};
            data_out_valid <= 1'b0;
            done           <= 1'b0;
        end else begin
            data_out_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    done        <= 1'b0;
                    op_count    <= {(LOGN+1){1'b0}};
                    cycle_count <= 16'd0;
                    if (start) state <= ST_LOAD;
                end

                ST_LOAD: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == N+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_FWD_ROW_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_ROW_A: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_FWD_XTW_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_XTW_A: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_FWD_COL_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_COL_A: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_FWD_ROW_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_ROW_B: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_FWD_XTW_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_XTW_B: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_FWD_COL_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_COL_B: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_PWM;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_PWM: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_INV_COL;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_INV_COL: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_INV_XTW;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_INV_XTW: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_INV_ROW;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_INV_ROW: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M+10) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_OUTPUT;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_OUTPUT: begin
                    cycle_count    <= cycle_count + 1'b1;
                    data_out       <= result_rdata[load_bank*WWIDTH +: WWIDTH];
                    data_out_valid <= (op_count < N);
                    if (op_count == N-1) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_DONE;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_DONE: begin
                    done <= 1'b1;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`endif // _HIER_N1024_TOP_GUARD
