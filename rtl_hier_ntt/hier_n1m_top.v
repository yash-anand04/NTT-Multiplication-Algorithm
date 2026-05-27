// =============================================================================
// hier_n1m_top.v   (Phase E production variant, L=32, d=4, N = L^4 ~ 10^6)
//
// Fourvariate hierarchical NTT polynomial multiplier.  N = 32^4 = 1,048,576.
// Adapted from hier_n4k_top.v (L=8 debug variant) with:
//   - L=32 (LOG_LANES=5, LOG_DEPTH=15)
//   - sub_ntt32_bidir instead of sub_ntt_simple
//   - URAM storage (per-bank 32K * 17 bits = 544 Kb fits in 2 URAMs)
//
// Layout: i = i0 + L*i1 + L^2*i2 + L^3*i3
//   bank(i0,i1,i2,i3) = (i0+i1+i2+i3) mod 32
//   pos (i0,i1,i2,i3) = i1 + L*i2 + L^2*i3   (15-bit per-bank addr)
// =============================================================================

`ifndef _HIER_N1M_TOP_GUARD
`define _HIER_N1M_TOP_GUARD

module hier_n1m_top #(
    parameter B       = 16,
    parameter L       = 32,
    parameter N       = L * L * L * L,        // 1,048,576
    parameter WWIDTH  = B + 1,
    parameter LOGN    = 20,                   // log2(N)
    parameter TW_BITS = LOGN + 1              // 21
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,
    input  wire [WWIDTH-1:0] data_in_a,
    input  wire [WWIDTH-1:0] data_in_b,
    output reg  [WWIDTH-1:0] data_out,
    output reg               data_out_valid,
    output reg               done,
    output reg  [31:0]       cycle_count
);

    // -------------------------------------------------------------------------
    // FSM states (26 states, 5 bits)
    // -------------------------------------------------------------------------
    localparam [4:0]
        ST_IDLE       = 5'd0,
        ST_LOAD       = 5'd1,
        ST_FWD_L0_A   = 5'd2,
        ST_FWD_XTW1_A = 5'd3,
        ST_FWD_L1_A   = 5'd4,
        ST_FWD_XTW2_A = 5'd5,
        ST_FWD_L2_A   = 5'd6,
        ST_FWD_XTW3_A = 5'd7,
        ST_FWD_L3_A   = 5'd8,
        ST_FWD_L0_B   = 5'd9,
        ST_FWD_XTW1_B = 5'd10,
        ST_FWD_L1_B   = 5'd11,
        ST_FWD_XTW2_B = 5'd12,
        ST_FWD_L2_B   = 5'd13,
        ST_FWD_XTW3_B = 5'd14,
        ST_FWD_L3_B   = 5'd15,
        ST_PWM        = 5'd16,
        ST_INV_L3     = 5'd17,
        ST_INV_XTW3   = 5'd18,
        ST_INV_L2     = 5'd19,
        ST_INV_XTW2   = 5'd20,
        ST_INV_L1     = 5'd21,
        ST_INV_XTW1   = 5'd22,
        ST_INV_L0     = 5'd23,
        ST_OUTPUT     = 5'd24,
        ST_DONE       = 5'd25;

    localparam integer SCAN_CYCLES = N / L;          // 32768
    localparam integer DRAIN       = 12;
    localparam integer SCAN_LEN    = SCAN_CYCLES + DRAIN;  // 32780

    reg [4:0]      state;
    reg [LOGN:0]   op_count;
    wire           issue_valid;

    // -------------------------------------------------------------------------
    // 12-stage delay pipeline
    // -------------------------------------------------------------------------
    reg [4:0]      state_d   [1:12];
    reg [LOGN:0]   opcnt_d   [1:12];
    reg            valid_d   [1:12];
    integer ds;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (ds = 1; ds <= 12; ds = ds + 1) begin
                state_d[ds] <= 5'd0;
                opcnt_d[ds] <= {(LOGN+1){1'b0}};
                valid_d[ds] <= 1'b0;
            end
        end else begin
            state_d[1] <= state;
            opcnt_d[1] <= op_count;
            valid_d[1] <= issue_valid;
            for (ds = 2; ds <= 12; ds = ds + 1) begin
                state_d[ds] <= state_d[ds-1];
                opcnt_d[ds] <= opcnt_d[ds-1];
                valid_d[ds] <= valid_d[ds-1];
            end
        end
    end

    assign issue_valid =
        (state == ST_LOAD)    ? (op_count < N) :
        (state == ST_OUTPUT)  ? (op_count < N) :
        (state == ST_IDLE)    ? 1'b0 :
        (state == ST_DONE)    ? 1'b0 :
                                (op_count < SCAN_CYCLES);

    // -------------------------------------------------------------------------
    // Banking parameters (L=32)
    // -------------------------------------------------------------------------
    localparam integer LANES     = L;           // 32
    localparam integer DEPTH     = L*L*L;       // 32,768 entries per bank
    localparam integer LOG_LANES = 5;
    localparam integer LOG_DEPTH = 15;

    // -------------------------------------------------------------------------
    // op_count decomposition for compute phases (each axis = 5 bits)
    // -------------------------------------------------------------------------
    wire [LOG_LANES-1:0] op_a = op_count[4:0];
    wire [LOG_LANES-1:0] op_b = op_count[9:5];
    wire [LOG_LANES-1:0] op_c = op_count[14:10];

    // LOAD/OUTPUT: 20-bit flat index
    wire [LOG_LANES-1:0] load_i0 = op_count[4:0];
    wire [LOG_LANES-1:0] load_i1 = op_count[9:5];
    wire [LOG_LANES-1:0] load_i2 = op_count[14:10];
    wire [LOG_LANES-1:0] load_i3 = op_count[19:15];
    wire [LOG_LANES-1:0] load_bank = (load_i0 + load_i1 + load_i2 + load_i3) & 5'h1f;
    reg  [LOG_LANES-1:0] load_bank_d1;
    always @(posedge clk) load_bank_d1 <= load_bank;
    wire [LOG_DEPTH-1:0] load_pos  = {load_i3, load_i2, load_i1};   // 5+5+5 = 15

    // Delayed LOAD writeback (d5 tap)
    wire [LOG_LANES-1:0] load_i0_d5 = opcnt_d[5][4:0];
    wire [LOG_LANES-1:0] load_i1_d5 = opcnt_d[5][9:5];
    wire [LOG_LANES-1:0] load_i2_d5 = opcnt_d[5][14:10];
    wire [LOG_LANES-1:0] load_i3_d5 = opcnt_d[5][19:15];
    wire [LOG_LANES-1:0] load_bank_d5 =
        (load_i0_d5 + load_i1_d5 + load_i2_d5 + load_i3_d5) & 5'h1f;
    wire [LOG_DEPTH-1:0] load_pos_d5  = {load_i3_d5, load_i2_d5, load_i1_d5};

    // -------------------------------------------------------------------------
    // Read-side rpos packs (same patterns as L=8 debug variant)
    //   axis_i3:    pos[k] = op_b + L*op_c + L^2*k         (15 bits = 5+5+5)
    //   axis_i2:    pos[k] = op_b + L*k    + L^2*op_c
    //   axis_i1:    pos[k] = k    + L*op_b + L^2*op_c
    //   broadcast:  pos[k] = op_a + L*op_b + L^2*op_c
    // -------------------------------------------------------------------------
    wire [LOG_LANES-1:0] rshift_op = (op_a + op_b + op_c) & 5'h1f;

    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i3_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i2_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i1_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_broadcast_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_zero_pack;
    genvar gk;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_rpos
            assign rpos_axis_i3_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {gk[4:0], op_c, op_b};
            assign rpos_axis_i2_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {op_c, gk[4:0], op_b};
            assign rpos_axis_i1_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {op_c, op_b, gk[4:0]};
            assign rpos_broadcast_pack[gk*LOG_DEPTH +: LOG_DEPTH] = {op_c, op_b, op_a};
            assign rpos_zero_pack    [gk*LOG_DEPTH +: LOG_DEPTH] = {LOG_DEPTH{1'b0}};
        end
    endgenerate

    // Write-side packs at d5, d8, d12
    wire [LANES*LOG_DEPTH-1:0] wpos_i3_d5,  wpos_i3_d8,  wpos_i3_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i2_d5,  wpos_i2_d8,  wpos_i2_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i1_d5,  wpos_i1_d8,  wpos_i1_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_bc_d5,  wpos_bc_d8,  wpos_bc_d12;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_wpos
            assign wpos_i3_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[4:0], opcnt_d[5][14:10], opcnt_d[5][9:5]};
            assign wpos_i2_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][14:10], gk[4:0], opcnt_d[5][9:5]};
            assign wpos_i1_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][14:10], opcnt_d[5][9:5], gk[4:0]};
            assign wpos_bc_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][14:10], opcnt_d[5][9:5], opcnt_d[5][4:0]};

            assign wpos_i3_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[4:0], opcnt_d[8][14:10], opcnt_d[8][9:5]};
            assign wpos_i2_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][14:10], gk[4:0], opcnt_d[8][9:5]};
            assign wpos_i1_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][14:10], opcnt_d[8][9:5], gk[4:0]};
            assign wpos_bc_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][14:10], opcnt_d[8][9:5], opcnt_d[8][4:0]};

            assign wpos_i3_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[4:0], opcnt_d[12][14:10], opcnt_d[12][9:5]};
            assign wpos_i2_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][14:10], gk[4:0], opcnt_d[12][9:5]};
            assign wpos_i1_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][14:10], opcnt_d[12][9:5], gk[4:0]};
            assign wpos_bc_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][14:10], opcnt_d[12][9:5], opcnt_d[12][4:0]};
        end
    endgenerate

    wire [LOG_LANES-1:0] wshift_d5  =
        (opcnt_d[5][4:0]  + opcnt_d[5][9:5]  + opcnt_d[5][14:10])  & 5'h1f;
    wire [LOG_LANES-1:0] wshift_d8  =
        (opcnt_d[8][4:0]  + opcnt_d[8][9:5]  + opcnt_d[8][14:10])  & 5'h1f;
    wire [LOG_LANES-1:0] wshift_d12 =
        (opcnt_d[12][4:0] + opcnt_d[12][9:5] + opcnt_d[12][14:10]) & 5'h1f;

    // -------------------------------------------------------------------------
    // Input data delay chain (for LOAD writeback at d5)
    // -------------------------------------------------------------------------
    reg [WWIDTH-1:0] in_a_d [1:5];
    reg [WWIDTH-1:0] in_b_d [1:5];
    integer dd;
    always @(posedge clk) begin
        in_a_d[1] <= data_in_a;
        in_b_d[1] <= data_in_b;
        for (dd = 2; dd <= 5; dd = dd + 1) begin
            in_a_d[dd] <= in_a_d[dd-1];
            in_b_d[dd] <= in_b_d[dd-1];
        end
    end

    // -------------------------------------------------------------------------
    // Mul array (32 lanes for L=32)
    // -------------------------------------------------------------------------
    reg  [L*WWIDTH-1:0]  mul_a_pack;
    reg  [L*WWIDTH-1:0]  mul_b_pack;
    wire [L*WWIDTH-1:0]  mul_out_pack;
    wire [L*WWIDTH-1:0]  tw_pack;
    wire [L*TW_BITS-1:0] tw_idx_pack;

    function [TW_BITS-1:0] inv_tw_idx;
        input [TW_BITS-1:0] idx;
        begin
            inv_tw_idx = (((2*N) - idx) % (2*N));
        end
    endfunction

    genvar tg;
    generate
        for (tg = 0; tg < L; tg = tg + 1) begin : gen_tw_lanes
            // d=4 twiddle formulas with REGISTERED=1 twiddle ROM (idx uses
            // CURRENT op_count / state; INV_L0 uses opcnt_d[7]/state_d[7]).
            wire [LOG_LANES-1:0] oa_d0 = op_a;
            wire [LOG_LANES-1:0] ob_d0 = op_b;
            wire [LOG_LANES-1:0] oc_d0 = op_c;

            wire [TW_BITS-1:0] tw_fwd_l0_idx =
                (oa_d0 + L*ob_d0 + L*L*oc_d0 + L*L*L*tg) % (2*N);
            wire [TW_BITS-1:0] tw_xtw1_idx =
                (2 * L * L * oc_d0 * tg) % (2*N);
            wire [TW_BITS-1:0] tw_xtw2_idx =
                (2 * L * tg * (L*ob_d0 + oc_d0)) % (2*N);
            wire [TW_BITS-1:0] tw_xtw3_idx =
                (2 * tg * (L*L*oa_d0 + L*ob_d0 + oc_d0)) % (2*N);

            wire [LOG_LANES-1:0] oa_d7 = opcnt_d[7][4:0];
            wire [LOG_LANES-1:0] ob_d7 = opcnt_d[7][9:5];
            wire [LOG_LANES-1:0] oc_d7 = opcnt_d[7][14:10];
            wire [TW_BITS-1:0] tw_inv_l0_idx_d7 = inv_tw_idx(
                (oa_d7 + L*ob_d7 + L*L*oc_d7 + L*L*L*tg) % (2*N));

            wire [TW_BITS-1:0] tw_inv_xtw1_idx = inv_tw_idx(tw_xtw1_idx);
            wire [TW_BITS-1:0] tw_inv_xtw2_idx = inv_tw_idx(tw_xtw2_idx);
            wire [TW_BITS-1:0] tw_inv_xtw3_idx = inv_tw_idx(tw_xtw3_idx);

            assign tw_idx_pack[tg*TW_BITS +: TW_BITS] =
                (state_d[7] == ST_INV_L0)                                        ? tw_inv_l0_idx_d7 :
                ((state == ST_FWD_L0_A) || (state == ST_FWD_L0_B))               ? tw_fwd_l0_idx :
                ((state == ST_FWD_XTW1_A) || (state == ST_FWD_XTW1_B))           ? tw_xtw1_idx :
                ((state == ST_FWD_XTW2_A) || (state == ST_FWD_XTW2_B))           ? tw_xtw2_idx :
                ((state == ST_FWD_XTW3_A) || (state == ST_FWD_XTW3_B))           ? tw_xtw3_idx :
                (state == ST_INV_XTW3)                                           ? tw_inv_xtw3_idx :
                (state == ST_INV_XTW2)                                           ? tw_inv_xtw2_idx :
                (state == ST_INV_XTW1)                                           ? tw_inv_xtw1_idx :
                {TW_BITS{1'b0}};

            twiddle_gen #(.B(B), .LOGN(LOGN), .REGISTERED(1)) u_tw (
                .clk(clk), .idx(tw_idx_pack[tg*TW_BITS +: TW_BITS]),
                .tw_out(tw_pack[tg*WWIDTH +: WWIDTH])
            );

            (* DONT_TOUCH = "true" *) reg [WWIDTH-1:0] mul_a_r;
            (* DONT_TOUCH = "true" *) reg [WWIDTH-1:0] mul_b_r;
            always @(posedge clk) begin
                mul_a_r <= mul_a_pack[tg*WWIDTH +: WWIDTH];
                mul_b_r <= mul_b_pack[tg*WWIDTH +: WWIDTH];
            end
            mod_mul_fermat #(.B(B), .PIPELINED(1)) u_mul (
                .clk(clk), .rst(rst),
                .a(mul_a_r), .b(mul_b_r),
                .result(mul_out_pack[tg*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Shared sub-NTT (sub_ntt32_bidir, 6-cycle latency same as Phase D)
    // -------------------------------------------------------------------------
    reg [L*WWIDTH-1:0] ntt_in_pack;
    reg [L*WWIDTH-1:0] ntt_in_reg;
    reg                ntt_start, ntt_start_d1;
    reg                ntt_inverse, ntt_inverse_d1;

    always @(posedge clk) begin
        ntt_in_reg     <= ntt_in_pack;
        ntt_start_d1   <= ntt_start;
        ntt_inverse_d1 <= ntt_inverse;
    end

    always @(*) begin
        ntt_start = 1'b0;
        ntt_inverse = 1'b0;
        case (state)
            ST_FWD_L0_A, ST_FWD_L0_B,
            ST_FWD_L1_A, ST_FWD_L1_B,
            ST_FWD_L2_A, ST_FWD_L2_B,
            ST_FWD_L3_A, ST_FWD_L3_B: ntt_start = issue_valid;
            ST_INV_L3, ST_INV_L2, ST_INV_L1, ST_INV_L0: begin
                ntt_start   = issue_valid;
                ntt_inverse = 1'b1;
            end
            default: ;
        endcase
    end

    wire [L*WWIDTH-1:0] ntt_out_pack;
    sub_ntt32_bidir #(.B(B)) u_subntt (
        .clk(clk), .rst(rst),
        .start(ntt_start_d1), .inverse(ntt_inverse_d1),
        .in_norm(ntt_in_reg), .out_norm(ntt_out_pack),
        .valid()
    );

    // =========================================================================
    // 4 banked memories (URAM-backed, 32 banks * 32K entries * 17 bits)
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
                     .LOG_LANES(LOG_LANES), .LOG_DEPTH(LOG_DEPTH), \
                     .READ_LATENCY(0), .STORAGE("uram")) u_``NM ( \
            .clk(clk), \
            .rshift(NM``_rshift), .rpos_pack(NM``_rpos), .rdata_pack(NM``_rdata), \
            .wshift(NM``_wshift), .wpos_pack(NM``_wpos), .wdata_pack(NM``_wdata), \
            .we_pack(NM``_we) \
        );

    `BMEM_DECL(mem_a)
    `BMEM_DECL(mem_b)
    `BMEM_DECL(mem_work)
    `BMEM_DECL(mem_trans)

    wire [LANES*WWIDTH-1:0] raw_a_rdata   = mem_a_rdata;
    wire [LANES*WWIDTH-1:0] raw_b_rdata   = mem_b_rdata;
    wire [LANES*WWIDTH-1:0] work_rdata    = mem_work_rdata;
    wire [LANES*WWIDTH-1:0] trans_rdata   = mem_trans_rdata;

    function [LANES*WWIDTH-1:0] broadcast17;
        input [WWIDTH-1:0] v;
        integer bi;
        begin
            broadcast17 = {LANES*WWIDTH{1'b0}};
            for (bi = 0; bi < LANES; bi = bi + 1)
                broadcast17[bi*WWIDTH +: WWIDTH] = v;
        end
    endfunction

    // ---- mem_a -------------------------------------------------------------
    always @(*) begin
        mem_a_rshift = 5'd0;
        mem_a_rpos   = rpos_zero_pack;
        mem_a_wshift = 5'd0;
        mem_a_wpos   = rpos_zero_pack;
        mem_a_wdata  = {LANES*WWIDTH{1'b0}};
        mem_a_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_L0_A: begin mem_a_rshift = rshift_op; mem_a_rpos = rpos_axis_i3_pack; end
            ST_PWM:      begin mem_a_rshift = rshift_op; mem_a_rpos = rpos_broadcast_pack; end
            ST_INV_L3:   begin mem_a_rshift = rshift_op; mem_a_rpos = rpos_broadcast_pack; end
            ST_OUTPUT: begin
                mem_a_rshift = 5'd0;
                mem_a_rpos[load_bank*LOG_DEPTH +: LOG_DEPTH] = load_pos;
            end
            default: ;
        endcase

        if (state_d[12] == ST_INV_L0 && valid_d[12]) begin
            mem_a_wshift = wshift_d12;
            mem_a_wpos   = wpos_i3_d12;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_FWD_L3_A && valid_d[8]) begin
            mem_a_wshift = wshift_d8;
            mem_a_wpos   = wpos_bc_d8;
            mem_a_wdata  = ntt_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_PWM && valid_d[5]) begin
            mem_a_wshift = wshift_d5;
            mem_a_wpos   = wpos_bc_d5;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_LOAD && valid_d[5]) begin
            mem_a_wpos[load_bank_d5*LOG_DEPTH +: LOG_DEPTH] = load_pos_d5;
            mem_a_wdata                                    = broadcast17(in_a_d[5]);
            mem_a_we[load_bank_d5]                         = 1'b1;
        end
    end

    // ---- mem_b -------------------------------------------------------------
    always @(*) begin
        mem_b_rshift = 5'd0;
        mem_b_rpos   = rpos_zero_pack;
        mem_b_wshift = 5'd0;
        mem_b_wpos   = rpos_zero_pack;
        mem_b_wdata  = {LANES*WWIDTH{1'b0}};
        mem_b_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_L0_B: begin mem_b_rshift = rshift_op; mem_b_rpos = rpos_axis_i3_pack; end
            ST_PWM:      begin mem_b_rshift = rshift_op; mem_b_rpos = rpos_broadcast_pack; end
            default: ;
        endcase

        if (state_d[8] == ST_FWD_L3_B && valid_d[8]) begin
            mem_b_wshift = wshift_d8;
            mem_b_wpos   = wpos_bc_d8;
            mem_b_wdata  = ntt_out_pack;
            mem_b_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_LOAD && valid_d[5]) begin
            mem_b_wpos[load_bank_d5*LOG_DEPTH +: LOG_DEPTH] = load_pos_d5;
            mem_b_wdata                                    = broadcast17(in_b_d[5]);
            mem_b_we[load_bank_d5]                         = 1'b1;
        end
    end

    // ---- mem_work ----------------------------------------------------------
    always @(*) begin
        mem_work_rshift = 5'd0;
        mem_work_rpos   = rpos_zero_pack;
        mem_work_wshift = 5'd0;
        mem_work_wpos   = rpos_zero_pack;
        mem_work_wdata  = {LANES*WWIDTH{1'b0}};
        mem_work_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_XTW1_A, ST_FWD_XTW1_B: begin
                mem_work_rshift = rshift_op; mem_work_rpos = rpos_axis_i3_pack;
            end
            ST_FWD_XTW2_A, ST_FWD_XTW2_B: begin
                mem_work_rshift = rshift_op; mem_work_rpos = rpos_axis_i1_pack;
            end
            ST_FWD_XTW3_A, ST_FWD_XTW3_B: begin
                mem_work_rshift = rshift_op; mem_work_rpos = rpos_broadcast_pack;
            end
            ST_INV_XTW3: begin
                mem_work_rshift = rshift_op; mem_work_rpos = rpos_broadcast_pack;
            end
            ST_INV_XTW2: begin
                mem_work_rshift = rshift_op; mem_work_rpos = rpos_axis_i1_pack;
            end
            ST_INV_XTW1: begin
                mem_work_rshift = rshift_op; mem_work_rpos = rpos_axis_i2_pack;
            end
            default: ;
        endcase

        if ((state_d[12] == ST_FWD_L0_A || state_d[12] == ST_FWD_L0_B)
            && valid_d[12]) begin
            mem_work_wshift = wshift_d12;
            mem_work_wpos   = wpos_i3_d12;
            mem_work_wdata  = ntt_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
        else if ((state_d[8] == ST_FWD_L1_A || state_d[8] == ST_FWD_L1_B)
                 && valid_d[8]) begin
            mem_work_wshift = wshift_d8;
            mem_work_wpos   = wpos_i2_d8;
            mem_work_wdata  = ntt_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
        else if ((state_d[8] == ST_FWD_L2_A || state_d[8] == ST_FWD_L2_B)
                 && valid_d[8]) begin
            mem_work_wshift = wshift_d8;
            mem_work_wpos   = wpos_i1_d8;
            mem_work_wdata  = ntt_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L3 && valid_d[8]) begin
            mem_work_wshift = wshift_d8;
            mem_work_wpos   = wpos_bc_d8;
            mem_work_wdata  = ntt_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L2 && valid_d[8]) begin
            mem_work_wshift = wshift_d8;
            mem_work_wpos   = wpos_i1_d8;
            mem_work_wdata  = ntt_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L1 && valid_d[8]) begin
            mem_work_wshift = wshift_d8;
            mem_work_wpos   = wpos_i2_d8;
            mem_work_wdata  = ntt_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
    end

    // ---- mem_trans ---------------------------------------------------------
    always @(*) begin
        mem_trans_rshift = 5'd0;
        mem_trans_rpos   = rpos_zero_pack;
        mem_trans_wshift = 5'd0;
        mem_trans_wpos   = rpos_zero_pack;
        mem_trans_wdata  = {LANES*WWIDTH{1'b0}};
        mem_trans_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_L1_A, ST_FWD_L1_B: begin
                mem_trans_rshift = rshift_op; mem_trans_rpos = rpos_axis_i2_pack;
            end
            ST_FWD_L2_A, ST_FWD_L2_B: begin
                mem_trans_rshift = rshift_op; mem_trans_rpos = rpos_axis_i1_pack;
            end
            ST_FWD_L3_A, ST_FWD_L3_B: begin
                mem_trans_rshift = rshift_op; mem_trans_rpos = rpos_broadcast_pack;
            end
            ST_INV_L2: begin
                mem_trans_rshift = rshift_op; mem_trans_rpos = rpos_axis_i1_pack;
            end
            ST_INV_L1: begin
                mem_trans_rshift = rshift_op; mem_trans_rpos = rpos_axis_i2_pack;
            end
            ST_INV_L0: begin
                mem_trans_rshift = rshift_op; mem_trans_rpos = rpos_axis_i3_pack;
            end
            default: ;
        endcase

        if ((state_d[5] == ST_FWD_XTW1_A || state_d[5] == ST_FWD_XTW1_B)
            && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_i3_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW2_A || state_d[5] == ST_FWD_XTW2_B)
                 && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_i1_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW3_A || state_d[5] == ST_FWD_XTW3_B)
                 && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_bc_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW3 && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_bc_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW2 && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_i1_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW1 && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_i2_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
    end

    // =========================================================================
    // Sub-NTT input pack and mul source pack
    // =========================================================================
    integer ci;
    always @(*) begin
        ntt_in_pack = {L*WWIDTH{1'b0}};
        if (state_d[5] == ST_FWD_L0_A || state_d[5] == ST_FWD_L0_B)
            ntt_in_pack = mul_out_pack;
        else begin
            case (state_d[1])
                ST_FWD_L1_A, ST_FWD_L1_B: ntt_in_pack = trans_rdata;
                ST_FWD_L2_A, ST_FWD_L2_B: ntt_in_pack = trans_rdata;
                ST_FWD_L3_A, ST_FWD_L3_B: ntt_in_pack = trans_rdata;
                ST_INV_L3:                ntt_in_pack = mem_a_rdata;
                ST_INV_L2:                ntt_in_pack = trans_rdata;
                ST_INV_L1:                ntt_in_pack = trans_rdata;
                ST_INV_L0:                ntt_in_pack = trans_rdata;
                default: ;
            endcase
        end
    end

    always @(*) begin
        mul_a_pack = {L*WWIDTH{1'b0}};
        mul_b_pack = {L*WWIDTH{1'b0}};
        if (state_d[8] == ST_INV_L0) begin
            mul_a_pack = ntt_out_pack;
            mul_b_pack = tw_pack;
        end else begin
            for (ci = 0; ci < L; ci = ci + 1) begin
                case (state_d[1])
                    ST_FWD_L0_A: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = raw_a_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack    [ci*WWIDTH +: WWIDTH];
                    end
                    ST_FWD_L0_B: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = raw_b_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack    [ci*WWIDTH +: WWIDTH];
                    end
                    ST_FWD_XTW1_A, ST_FWD_XTW1_B,
                    ST_FWD_XTW2_A, ST_FWD_XTW2_B,
                    ST_FWD_XTW3_A, ST_FWD_XTW3_B,
                    ST_INV_XTW1, ST_INV_XTW2, ST_INV_XTW3: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = work_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack   [ci*WWIDTH +: WWIDTH];
                    end
                    ST_PWM: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = mem_a_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = mem_b_rdata[ci*WWIDTH +: WWIDTH];
                    end
                    default: ;
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
            cycle_count    <= 32'd0;
            data_out       <= {WWIDTH{1'b0}};
            data_out_valid <= 1'b0;
            done           <= 1'b0;
        end else begin
            data_out_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    done        <= 1'b0;
                    op_count    <= {(LOGN+1){1'b0}};
                    cycle_count <= 32'd0;
                    if (start) state <= ST_LOAD;
                end

                ST_LOAD: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == N+11) begin
                        op_count <= {(LOGN+1){1'b0}};
                        state    <= ST_FWD_L0_A;
                    end else op_count <= op_count + 1;
                end

                ST_FWD_L0_A: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW1_A; end
                    else op_count <= op_count + 1; end
                ST_FWD_XTW1_A: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L1_A; end
                    else op_count <= op_count + 1; end
                ST_FWD_L1_A: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW2_A; end
                    else op_count <= op_count + 1; end
                ST_FWD_XTW2_A: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L2_A; end
                    else op_count <= op_count + 1; end
                ST_FWD_L2_A: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW3_A; end
                    else op_count <= op_count + 1; end
                ST_FWD_XTW3_A: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L3_A; end
                    else op_count <= op_count + 1; end
                ST_FWD_L3_A: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L0_B; end
                    else op_count <= op_count + 1; end

                ST_FWD_L0_B: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW1_B; end
                    else op_count <= op_count + 1; end
                ST_FWD_XTW1_B: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L1_B; end
                    else op_count <= op_count + 1; end
                ST_FWD_L1_B: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW2_B; end
                    else op_count <= op_count + 1; end
                ST_FWD_XTW2_B: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L2_B; end
                    else op_count <= op_count + 1; end
                ST_FWD_L2_B: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW3_B; end
                    else op_count <= op_count + 1; end
                ST_FWD_XTW3_B: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L3_B; end
                    else op_count <= op_count + 1; end
                ST_FWD_L3_B: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_PWM; end
                    else op_count <= op_count + 1; end

                ST_PWM: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L3; end
                    else op_count <= op_count + 1; end

                ST_INV_L3: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_XTW3; end
                    else op_count <= op_count + 1; end
                ST_INV_XTW3: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L2; end
                    else op_count <= op_count + 1; end
                ST_INV_L2: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_XTW2; end
                    else op_count <= op_count + 1; end
                ST_INV_XTW2: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L1; end
                    else op_count <= op_count + 1; end
                ST_INV_L1: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_XTW1; end
                    else op_count <= op_count + 1; end
                ST_INV_XTW1: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L0; end
                    else op_count <= op_count + 1; end
                ST_INV_L0: begin cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_OUTPUT; end
                    else op_count <= op_count + 1; end

                ST_OUTPUT: begin
                    cycle_count    <= cycle_count + 1;
                    data_out       <= mem_a_rdata[load_bank_d1*WWIDTH +: WWIDTH];
                    data_out_valid <= (op_count >= 1) && (op_count < N+1);
                    if (op_count == N+1) begin
                        op_count <= 0; state <= ST_DONE;
                    end else op_count <= op_count + 1;
                end

                ST_DONE: done <= 1'b1;
            endcase
        end
    end

endmodule

`endif // _HIER_N1M_TOP_GUARD
