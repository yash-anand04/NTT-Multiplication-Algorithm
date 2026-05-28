// =============================================================================
// hier_d5_L4_top.v
// Five-variate (d=5) hierarchical NTT polynomial multiplier.  L=4, N=L^5=1024.
//
// Extends hier_n4k_top.v (d=4) by adding one more axis and one more
// cross-twiddle phase per direction.
//
// Layout: flat index i = i0 + L*i1 + L^2*i2 + L^3*i3 + L^4*i4, L = 4.
//   bank(i0..i4) = (i0+i1+i2+i3+i4) mod 4         (conflict-free)
//   pos (i0..i4) = i1 + L*i2 + L^2*i3 + L^3*i4    (per-bank addr in [0,256))
//   i0 contributes to bank only, not pos.
//
// Forward NTT (per polynomial):
//   STAGE 0:  pre-twist by psi^i, NTT along i4 axis (-> k4)
//   XTW1:     multiply by psi^(2*L^3*i3*k4)
//   STAGE 1:  NTT along i3 axis (-> k3)
//   XTW2:     multiply by psi^(2*L^2*i2*(L*k3+k4))
//   STAGE 2:  NTT along i2 axis (-> k2)
//   XTW3:     multiply by psi^(2*L*i1*(L^2*k2+L*k3+k4))
//   STAGE 3:  NTT along i1 axis (-> k1)
//   XTW4:     multiply by psi^(2*i0*(L^3*k1+L^2*k2+L*k3+k4))
//   STAGE 4:  NTT along i0 axis (-> k0)
// PWM: spec_a * spec_b -> prod
// Inverse: reverse the chain (post-twist by psi^(-i) at the end).
//
// FSM: 32 states.  Pipeline taps d5/d8/d12.
// =============================================================================

`ifndef _HIER_D5_L8_TOP_GUARD
`define _HIER_D5_L8_TOP_GUARD

module hier_d5_L8_top #(
    parameter B       = 16,
    parameter L       = 8,
    parameter N       = L * L * L * L * L,    // 1024
    parameter WWIDTH  = B + 1,
    parameter LOGN    = 15,                   // $clog2(N)
    parameter TW_BITS = LOGN + 1              // 11: psi has order 2N = 2048
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
    // FSM states (32 states, 5 bits)
    // -------------------------------------------------------------------------
    localparam [4:0]
        ST_IDLE       = 5'd0,
        ST_LOAD       = 5'd1,
        // --- A forward chain (9 phases) ---
        ST_FWD_L0_A   = 5'd2,    // pre-twist + NTT along i4
        ST_FWD_XTW1_A = 5'd3,
        ST_FWD_L1_A   = 5'd4,    // NTT along i3
        ST_FWD_XTW2_A = 5'd5,
        ST_FWD_L2_A   = 5'd6,    // NTT along i2
        ST_FWD_XTW3_A = 5'd7,
        ST_FWD_L3_A   = 5'd8,    // NTT along i1
        ST_FWD_XTW4_A = 5'd9,
        ST_FWD_L4_A   = 5'd10,   // NTT along i0 -> spec_a
        // --- B forward chain (9 phases) ---
        ST_FWD_L0_B   = 5'd11,
        ST_FWD_XTW1_B = 5'd12,
        ST_FWD_L1_B   = 5'd13,
        ST_FWD_XTW2_B = 5'd14,
        ST_FWD_L2_B   = 5'd15,
        ST_FWD_XTW3_B = 5'd16,
        ST_FWD_L3_B   = 5'd17,
        ST_FWD_XTW4_B = 5'd18,
        ST_FWD_L4_B   = 5'd19,
        // --- pointwise ---
        ST_PWM        = 5'd20,
        // --- inverse chain (9 phases) ---
        ST_INV_L4     = 5'd21,   // INTT along k0 -> i0
        ST_INV_XTW4   = 5'd22,
        ST_INV_L3     = 5'd23,   // INTT along k1 -> i1
        ST_INV_XTW3   = 5'd24,
        ST_INV_L2     = 5'd25,   // INTT along k2 -> i2
        ST_INV_XTW2   = 5'd26,
        ST_INV_L1     = 5'd27,   // INTT along k3 -> i3
        ST_INV_XTW1   = 5'd28,
        ST_INV_L0     = 5'd29,   // INTT along k4 + post-twist
        ST_OUTPUT     = 5'd30,
        ST_DONE       = 5'd31;

    localparam integer SCAN_CYCLES = N / L;       // 256 issues per compute phase
    localparam integer DRAIN       = 12;
    localparam integer SCAN_LEN    = SCAN_CYCLES + DRAIN;  // 268 cycles per phase

    reg [4:0]      state;
    reg [LOGN:0]   op_count;
    wire           issue_valid;

    // -------------------------------------------------------------------------
    // 12-stage delay pipeline.  Taps: d5, d8, d12.
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
    // Banking parameters (L=4)
    // -------------------------------------------------------------------------
    localparam integer LANES     = L;          // 4
    localparam integer DEPTH     = L*L*L*L;    // 256 entries per bank
    localparam integer LOG_LANES = 3;
    localparam integer LOG_DEPTH = 12;

    // -------------------------------------------------------------------------
    // op_count decomposition during compute phases (op_count in [0, L^4)):
    //   op_a = op_count[2:0]
    //   op_b = op_count[5:3]
    //   op_c = op_count[8:6]
    //   op_d = op_count[11:9]
    // These four are the four non-lane axes for any phase.
    // -------------------------------------------------------------------------
    wire [LOG_LANES-1:0] op_a = op_count[2:0];
    wire [LOG_LANES-1:0] op_b = op_count[5:3];
    wire [LOG_LANES-1:0] op_c = op_count[8:6];
    wire [LOG_LANES-1:0] op_d = op_count[11:9];

    // During LOAD/OUTPUT: op_count = i0 + L*i1 + L^2*i2 + L^3*i3 + L^4*i4 (10-bit)
    wire [LOG_LANES-1:0] load_i0 = op_count[2:0];
    wire [LOG_LANES-1:0] load_i1 = op_count[5:3];
    wire [LOG_LANES-1:0] load_i2 = op_count[8:6];
    wire [LOG_LANES-1:0] load_i3 = op_count[11:9];
    wire [LOG_LANES-1:0] load_i4 = op_count[14:12];
    wire [LOG_LANES-1:0] load_bank =
        (load_i0 + load_i1 + load_i2 + load_i3 + load_i4) & 3'h7;
    reg  [LOG_LANES-1:0] load_bank_d1;
    always @(posedge clk) load_bank_d1 <= load_bank;
    // pos = i1 + L*i2 + L^2*i3 + L^3*i4 -> {i4, i3, i2, i1}
    wire [LOG_DEPTH-1:0] load_pos  = {load_i4, load_i3, load_i2, load_i1};

    // Delayed LOAD writeback (write tap d5)
    wire [LOG_LANES-1:0] load_i0_d5 = opcnt_d[5][2:0];
    wire [LOG_LANES-1:0] load_i1_d5 = opcnt_d[5][5:3];
    wire [LOG_LANES-1:0] load_i2_d5 = opcnt_d[5][8:6];
    wire [LOG_LANES-1:0] load_i3_d5 = opcnt_d[5][11:9];
    wire [LOG_LANES-1:0] load_i4_d5 = opcnt_d[5][14:12];
    wire [LOG_LANES-1:0] load_bank_d5 =
        (load_i0_d5 + load_i1_d5 + load_i2_d5 + load_i3_d5 + load_i4_d5) & 3'h7;
    wire [LOG_DEPTH-1:0] load_pos_d5  =
        {load_i4_d5, load_i3_d5, load_i2_d5, load_i1_d5};

    // -------------------------------------------------------------------------
    // Read-side rpos packs.  Pattern depends on which axis is "lane".
    //   axis_i4 (lane=i4): pos[k] = op_b + L*op_c + L^2*op_d + L^3*k
    //                              = {k, op_d, op_c, op_b}    (i0=op_a, i1=op_b, i2=op_c, i3=op_d, i4=k)
    //   axis_i3 (lane=i3): pos[k] = op_b + L*op_c + L^2*k    + L^3*op_d
    //                              = {op_d, k, op_c, op_b}    (i0=op_a, i1=op_b, i2=op_c, i3=k, i4=op_d)
    //   axis_i2 (lane=i2): pos[k] = op_b + L*k    + L^2*op_c + L^3*op_d
    //                              = {op_d, op_c, k, op_b}    (i0=op_a, i1=op_b, i2=k, i3=op_c, i4=op_d)
    //   axis_i1 (lane=i1): pos[k] = k    + L*op_b + L^2*op_c + L^3*op_d
    //                              = {op_d, op_c, op_b, k}    (i0=op_a, i1=k, i2=op_b, i3=op_c, i4=op_d)
    //   broadcast (lane=i0):
    //     pos[k]=op_a+L*op_b+L^2*op_c+L^3*op_d   (k -> bank only)
    //                              = {op_d, op_c, op_b, op_a} (i0=k, i1=op_a, i2=op_b, i3=op_c, i4=op_d)
    //
    // rshift = (op_a + op_b + op_c + op_d) mod L for all NTT/XTW phases.
    // bank[k] = (rshift + k) mod L.
    // -------------------------------------------------------------------------
    wire [LOG_LANES-1:0] rshift_op = (op_a + op_b + op_c + op_d) & 3'h7;

    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i4_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i3_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i2_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i1_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_broadcast_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_zero_pack;
    genvar gk;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_rpos
            assign rpos_axis_i4_pack [gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[2:0], op_d, op_c, op_b};
            assign rpos_axis_i3_pack [gk*LOG_DEPTH +: LOG_DEPTH] =
                {op_d, gk[2:0], op_c, op_b};
            assign rpos_axis_i2_pack [gk*LOG_DEPTH +: LOG_DEPTH] =
                {op_d, op_c, gk[2:0], op_b};
            assign rpos_axis_i1_pack [gk*LOG_DEPTH +: LOG_DEPTH] =
                {op_d, op_c, op_b, gk[2:0]};
            assign rpos_broadcast_pack[gk*LOG_DEPTH +: LOG_DEPTH] =
                {op_d, op_c, op_b, op_a};
            assign rpos_zero_pack    [gk*LOG_DEPTH +: LOG_DEPTH] = {LOG_DEPTH{1'b0}};
        end
    endgenerate

    // Write-side: same patterns at delayed taps (d5, d8, d12)
    wire [LANES*LOG_DEPTH-1:0] wpos_i4_d5,  wpos_i4_d8,  wpos_i4_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i3_d5,  wpos_i3_d8,  wpos_i3_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i2_d5,  wpos_i2_d8,  wpos_i2_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i1_d5,  wpos_i1_d8,  wpos_i1_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_bc_d5,  wpos_bc_d8,  wpos_bc_d12;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_wpos
            // tap 5
            assign wpos_i4_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[2:0], opcnt_d[5][11:9], opcnt_d[5][8:6], opcnt_d[5][5:3]};
            assign wpos_i3_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][11:9], gk[2:0], opcnt_d[5][8:6], opcnt_d[5][5:3]};
            assign wpos_i2_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][11:9], opcnt_d[5][8:6], gk[2:0], opcnt_d[5][5:3]};
            assign wpos_i1_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][11:9], opcnt_d[5][8:6], opcnt_d[5][5:3], gk[2:0]};
            assign wpos_bc_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][11:9], opcnt_d[5][8:6], opcnt_d[5][5:3], opcnt_d[5][2:0]};
            // tap 8
            assign wpos_i4_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[2:0], opcnt_d[8][11:9], opcnt_d[8][8:6], opcnt_d[8][5:3]};
            assign wpos_i3_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][11:9], gk[2:0], opcnt_d[8][8:6], opcnt_d[8][5:3]};
            assign wpos_i2_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][11:9], opcnt_d[8][8:6], gk[2:0], opcnt_d[8][5:3]};
            assign wpos_i1_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][11:9], opcnt_d[8][8:6], opcnt_d[8][5:3], gk[2:0]};
            assign wpos_bc_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][11:9], opcnt_d[8][8:6], opcnt_d[8][5:3], opcnt_d[8][2:0]};
            // tap 12
            assign wpos_i4_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[2:0], opcnt_d[12][11:9], opcnt_d[12][8:6], opcnt_d[12][5:3]};
            assign wpos_i3_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][11:9], gk[2:0], opcnt_d[12][8:6], opcnt_d[12][5:3]};
            assign wpos_i2_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][11:9], opcnt_d[12][8:6], gk[2:0], opcnt_d[12][5:3]};
            assign wpos_i1_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][11:9], opcnt_d[12][8:6], opcnt_d[12][5:3], gk[2:0]};
            assign wpos_bc_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][11:9], opcnt_d[12][8:6], opcnt_d[12][5:3], opcnt_d[12][2:0]};
        end
    endgenerate

    wire [LOG_LANES-1:0] wshift_d5  =
        (opcnt_d[5][2:0]  + opcnt_d[5][5:3]  + opcnt_d[5][8:6]  + opcnt_d[5][11:9])  & 3'h7;
    wire [LOG_LANES-1:0] wshift_d8  =
        (opcnt_d[8][2:0]  + opcnt_d[8][5:3]  + opcnt_d[8][8:6]  + opcnt_d[8][11:9])  & 3'h7;
    wire [LOG_LANES-1:0] wshift_d12 =
        (opcnt_d[12][2:0] + opcnt_d[12][5:3] + opcnt_d[12][8:6] + opcnt_d[12][11:9]) & 3'h7;

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
    // Mul array (4 lanes for L=4)
    // -------------------------------------------------------------------------
    reg  [L*WWIDTH-1:0]  mul_a_pack;
    reg  [L*WWIDTH-1:0]  mul_b_pack;
    wire [L*WWIDTH-1:0]  mul_out_pack;
    wire [L*WWIDTH-1:0]  tw_pack;
    wire [L*TW_BITS-1:0] tw_idx_pack;

    // -------------------------------------------------------------------------
    // Per-lane twiddle indices.  d=5 formulas (from fivvar_ntt_model.py):
    //   FWD_L0 pre-twist:    psi^(i0 + L*i1 + L^2*i2 + L^3*i3 + L^4*i4)
    //                          at lane=i4
    //                          = psi^(op_a + L*op_b + L^2*op_c + L^3*op_d + L^4*tg)
    //   FWD_XTW1 (lane=k4):  psi^(2*L^3 * i3 * k4) = psi^(2L^3 * op_d * tg)
    //   FWD_XTW2 (lane=i2):  psi^(2*L^2 * i2 * (L*k3 + k4))
    //                          = psi^(2*L^2 * tg * (L*op_c + op_d))
    //                          where op_a=i0, op_b=i1, op_c=k3, op_d=k4
    //   FWD_XTW3 (lane=i1):  psi^(2*L * i1 * (L^2*k2 + L*k3 + k4))
    //                          = psi^(2*L * tg * (L^2*op_b + L*op_c + op_d))
    //                          where op_a=i0, op_b=k2, op_c=k3, op_d=k4
    //   FWD_XTW4 (lane=i0):  psi^(2 * i0 * (L^3*k1 + L^2*k2 + L*k3 + k4))
    //                          = psi^(2 * tg * (L^3*op_a + L^2*op_b + L*op_c + op_d))
    //                          where op_a=k1, op_b=k2, op_c=k3, op_d=k4
    //   INV_L0 post-twist:   inv of FWD_L0 idx, at d7 tap.
    //   INV_XTW1/2/3/4:      inverses of the corresponding FWD formulas.
    // -------------------------------------------------------------------------
    function [TW_BITS-1:0] inv_tw_idx;
        input [TW_BITS-1:0] idx;
        begin
            inv_tw_idx = (((2*N) - idx) % (2*N));
        end
    endfunction

    genvar tg;
    generate
        for (tg = 0; tg < L; tg = tg + 1) begin : gen_tw_lanes
            wire [LOG_LANES-1:0] oa_d0 = op_a;
            wire [LOG_LANES-1:0] ob_d0 = op_b;
            wire [LOG_LANES-1:0] oc_d0 = op_c;
            wire [LOG_LANES-1:0] od_d0 = op_d;

            // FWD_L0 pre-twist: psi^(i0 + L*i1 + L^2*i2 + L^3*i3 + L^4*i4),
            //   lane=i4
            wire [TW_BITS-1:0] tw_fwd_l0_idx =
                (oa_d0 + L*ob_d0 + L*L*oc_d0 + L*L*L*od_d0 + L*L*L*L*tg) % (2*N);

            // FWD_XTW1: psi^(2 * L^3 * i3 * k4), lane=k4, op_d=i3
            wire [TW_BITS-1:0] tw_xtw1_idx =
                (2 * L*L*L * od_d0 * tg) % (2*N);

            // FWD_XTW2: psi^(2 * L^2 * i2 * (L*k3 + k4)), lane=i2,
            //          op_c=k3, op_d=k4
            wire [TW_BITS-1:0] tw_xtw2_idx =
                (2 * L*L * tg * (L*oc_d0 + od_d0)) % (2*N);

            // FWD_XTW3: psi^(2 * L * i1 * (L^2*k2 + L*k3 + k4)), lane=i1,
            //          op_b=k2, op_c=k3, op_d=k4
            wire [TW_BITS-1:0] tw_xtw3_idx =
                (2 * L * tg * (L*L*ob_d0 + L*oc_d0 + od_d0)) % (2*N);

            // FWD_XTW4: psi^(2 * i0 * (L^3*k1 + L^2*k2 + L*k3 + k4)), lane=i0,
            //          op_a=k1, op_b=k2, op_c=k3, op_d=k4
            wire [TW_BITS-1:0] tw_xtw4_idx =
                (2 * tg * (L*L*L*oa_d0 + L*L*ob_d0 + L*oc_d0 + od_d0)) % (2*N);

            // INV_L0 post-twist: mul fires 8 cycles after NTT issue.  With
            // REGISTERED=1 twiddle, idx tap shifts d8 -> d7.
            wire [LOG_LANES-1:0] oa_d7 = opcnt_d[7][2:0];
            wire [LOG_LANES-1:0] ob_d7 = opcnt_d[7][5:3];
            wire [LOG_LANES-1:0] oc_d7 = opcnt_d[7][8:6];
            wire [LOG_LANES-1:0] od_d7 = opcnt_d[7][11:9];
            wire [TW_BITS-1:0] tw_inv_l0_idx_d7 = inv_tw_idx(
                (oa_d7 + L*ob_d7 + L*L*oc_d7 + L*L*L*od_d7 + L*L*L*L*tg) % (2*N));

            // INV_XTW{1,2,3,4}: same iteration as the corresponding FWD phase,
            // just inverse exponent.
            wire [TW_BITS-1:0] tw_inv_xtw1_idx = inv_tw_idx(tw_xtw1_idx);
            wire [TW_BITS-1:0] tw_inv_xtw2_idx = inv_tw_idx(tw_xtw2_idx);
            wire [TW_BITS-1:0] tw_inv_xtw3_idx = inv_tw_idx(tw_xtw3_idx);
            wire [TW_BITS-1:0] tw_inv_xtw4_idx = inv_tw_idx(tw_xtw4_idx);

            assign tw_idx_pack[tg*TW_BITS +: TW_BITS] =
                (state_d[7] == ST_INV_L0)                                          ? tw_inv_l0_idx_d7 :
                ((state == ST_FWD_L0_A)   || (state == ST_FWD_L0_B))               ? tw_fwd_l0_idx :
                ((state == ST_FWD_XTW1_A) || (state == ST_FWD_XTW1_B))             ? tw_xtw1_idx :
                ((state == ST_FWD_XTW2_A) || (state == ST_FWD_XTW2_B))             ? tw_xtw2_idx :
                ((state == ST_FWD_XTW3_A) || (state == ST_FWD_XTW3_B))             ? tw_xtw3_idx :
                ((state == ST_FWD_XTW4_A) || (state == ST_FWD_XTW4_B))             ? tw_xtw4_idx :
                (state == ST_INV_XTW4)                                             ? tw_inv_xtw4_idx :
                (state == ST_INV_XTW3)                                             ? tw_inv_xtw3_idx :
                (state == ST_INV_XTW2)                                             ? tw_inv_xtw2_idx :
                (state == ST_INV_XTW1)                                             ? tw_inv_xtw1_idx :
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
    // Shared sub-NTT.  Uses sub_ntt8_bidir (L=4, 6-cycle latency via padding).
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

    // ntt_start uses state_d[1]/valid_d[1] instead of current state, so the
    // start signal aligns with when the data actually reaches the sub-NTT's
    // first register stage.  Using `state` directly causes the LAST issue
    // (K=SCAN_CYCLES-1) of each phase to drop start before its data enters
    // the sub-NTT, which silently flips the NTT direction (FWD vs INV mode)
    // for that iteration via the inv_pipe gating in sub_ntt{4,8,16,32}_bidir.
    // For FWD_L0_*, the data comes via the multiplier (5-cycle latency from
    // read), so we use state_d[5] gated by valid_d[5].
    always @(*) begin
        ntt_start = 1'b0;
        ntt_inverse = 1'b0;
        if ((state_d[5] == ST_FWD_L0_A || state_d[5] == ST_FWD_L0_B) && valid_d[5])
            ntt_start = 1'b1;
        else case (state_d[1])
            ST_FWD_L1_A, ST_FWD_L1_B,
            ST_FWD_L2_A, ST_FWD_L2_B,
            ST_FWD_L3_A, ST_FWD_L3_B,
            ST_FWD_L4_A, ST_FWD_L4_B: ntt_start = valid_d[1];
            ST_INV_L4, ST_INV_L3, ST_INV_L2, ST_INV_L1, ST_INV_L0: begin
                ntt_start   = valid_d[1];
                ntt_inverse = 1'b1;
            end
            default: ;
        endcase
    end

    wire [L*WWIDTH-1:0] ntt_out_pack;
    sub_ntt8_bidir #(.B(B)) u_subntt (
        .clk(clk), .rst(rst),
        .start(ntt_start_d1), .inverse(ntt_inverse_d1),
        .in_norm(ntt_in_reg), .out_norm(ntt_out_pack),
        .valid()
    );

    // =========================================================================
    // 3 banked memories (BRAM-backed): mem_a, mem_b, mem_scratch
    // (mem_work + mem_trans consolidated into mem_scratch as in Phase E.1)
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
                     .READ_LATENCY(0), .STORAGE("bram")) u_``NM ( \
            .clk(clk), \
            .rshift(NM``_rshift), .rpos_pack(NM``_rpos), .rdata_pack(NM``_rdata), \
            .wshift(NM``_wshift), .wpos_pack(NM``_wpos), .wdata_pack(NM``_wdata), \
            .we_pack(NM``_we) \
        );

    `BMEM_DECL(mem_a)
    `BMEM_DECL(mem_b)
    `BMEM_DECL(mem_scratch)

    wire [LANES*WWIDTH-1:0] raw_a_rdata   = mem_a_rdata;
    wire [LANES*WWIDTH-1:0] raw_b_rdata   = mem_b_rdata;
    wire [LANES*WWIDTH-1:0] scratch_rdata = mem_scratch_rdata;

    function [LANES*WWIDTH-1:0] broadcastN;
        input [WWIDTH-1:0] v;
        integer bi;
        begin
            broadcastN = {LANES*WWIDTH{1'b0}};
            for (bi = 0; bi < LANES; bi = bi + 1)
                broadcastN[bi*WWIDTH +: WWIDTH] = v;
        end
    endfunction

    // =========================================================================
    // Phase plan (a chain shown; b chain identical pattern; scratch alternates
    // role of mem_work/mem_trans like Phase E.1):
    //   LOAD       : write mem_a, mem_b
    //   FWD_L0_A   : read mem_a (axis_i4), mul+NTT     -> mem_scratch (i4 d12)
    //   FWD_XTW1_A : read mem_scratch (axis_i4), mul   -> mem_scratch (i4 d5)
    //   FWD_L1_A   : read mem_scratch (axis_i3), NTT   -> mem_scratch (i3 d8)
    //   FWD_XTW2_A : read mem_scratch (axis_i2), mul   -> mem_scratch (i2 d5)
    //   FWD_L2_A   : read mem_scratch (axis_i2), NTT   -> mem_scratch (i2 d8)
    //   FWD_XTW3_A : read mem_scratch (axis_i1), mul   -> mem_scratch (i1 d5)
    //   FWD_L3_A   : read mem_scratch (axis_i1), NTT   -> mem_scratch (i1 d8)
    //   FWD_XTW4_A : read mem_scratch (broadcast), mul -> mem_scratch (bc d5)
    //   FWD_L4_A   : read mem_scratch (broadcast), NTT -> mem_a (bc d8)
    //   ... B chain identical with mem_b
    //   PWM        : read mem_a + mem_b (bc), mul      -> mem_a (bc d5)
    //   INV_L4     : read mem_a (bc), NTT              -> mem_scratch (bc d8)
    //   INV_XTW4   : read mem_scratch (bc), mul        -> mem_scratch (bc d5)
    //   INV_L3     : read mem_scratch (axis_i1), NTT   -> mem_scratch (i1 d8)
    //   INV_XTW3   : read mem_scratch (axis_i1), mul   -> mem_scratch (i1 d5)
    //   INV_L2     : read mem_scratch (axis_i2), NTT   -> mem_scratch (i2 d8)
    //   INV_XTW2   : read mem_scratch (axis_i2), mul   -> mem_scratch (i2 d5)
    //   INV_L1     : read mem_scratch (axis_i3), NTT   -> mem_scratch (i3 d8)
    //   INV_XTW1   : read mem_scratch (axis_i3), mul   -> mem_scratch (i3 d5)
    //   INV_L0     : read mem_scratch (axis_i4), NTT+mul -> mem_a (i4 d12)
    //   OUTPUT     : read mem_a
    // =========================================================================

    // ---- mem_a -------------------------------------------------------------
    always @(*) begin
        mem_a_rshift = 2'd0;
        mem_a_rpos   = rpos_zero_pack;
        mem_a_wshift = 2'd0;
        mem_a_wpos   = rpos_zero_pack;
        mem_a_wdata  = {LANES*WWIDTH{1'b0}};
        mem_a_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_L0_A: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_axis_i4_pack;
            end
            ST_PWM: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_broadcast_pack;
            end
            ST_INV_L4: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_broadcast_pack;
            end
            ST_OUTPUT: begin
                mem_a_rshift = 2'd0;
                mem_a_rpos[load_bank*LOG_DEPTH +: LOG_DEPTH] = load_pos;
            end
            default: ;
        endcase

        // INV_L0 final write -> mem_a (d12 = mul+NTT tap, axis_i4 pos)
        if (state_d[12] == ST_INV_L0 && valid_d[12]) begin
            mem_a_wshift = wshift_d12;
            mem_a_wpos   = wpos_i4_d12;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // FWD_L4_A final NTT -> mem_a (spec_a) (d8 = NTT tap, broadcast pos)
        else if (state_d[8] == ST_FWD_L4_A && valid_d[8]) begin
            mem_a_wshift = wshift_d8;
            mem_a_wpos   = wpos_bc_d8;
            mem_a_wdata  = ntt_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // PWM write -> mem_a (prod)
        else if (state_d[5] == ST_PWM && valid_d[5]) begin
            mem_a_wshift = wshift_d5;
            mem_a_wpos   = wpos_bc_d5;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // LOAD: single-cell write via load_bank_d5
        else if (state_d[5] == ST_LOAD && valid_d[5]) begin
            mem_a_wpos[load_bank_d5*LOG_DEPTH +: LOG_DEPTH] = load_pos_d5;
            mem_a_wdata                                    = broadcastN(in_a_d[5]);
            mem_a_we[load_bank_d5]                         = 1'b1;
        end
    end

    // ---- mem_b -------------------------------------------------------------
    always @(*) begin
        mem_b_rshift = 2'd0;
        mem_b_rpos   = rpos_zero_pack;
        mem_b_wshift = 2'd0;
        mem_b_wpos   = rpos_zero_pack;
        mem_b_wdata  = {LANES*WWIDTH{1'b0}};
        mem_b_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_L0_B: begin
                mem_b_rshift = rshift_op;
                mem_b_rpos   = rpos_axis_i4_pack;
            end
            ST_PWM: begin
                mem_b_rshift = rshift_op;
                mem_b_rpos   = rpos_broadcast_pack;
            end
            default: ;
        endcase

        if (state_d[8] == ST_FWD_L4_B && valid_d[8]) begin
            mem_b_wshift = wshift_d8;
            mem_b_wpos   = wpos_bc_d8;
            mem_b_wdata  = ntt_out_pack;
            mem_b_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_LOAD && valid_d[5]) begin
            mem_b_wpos[load_bank_d5*LOG_DEPTH +: LOG_DEPTH] = load_pos_d5;
            mem_b_wdata                                    = broadcastN(in_b_d[5]);
            mem_b_we[load_bank_d5]                         = 1'b1;
        end
    end

    // ---- mem_scratch (consolidates work + trans) --------------------------
    always @(*) begin
        mem_scratch_rshift = 2'd0;
        mem_scratch_rpos   = rpos_zero_pack;
        mem_scratch_wshift = 2'd0;
        mem_scratch_wpos   = rpos_zero_pack;
        mem_scratch_wdata  = {LANES*WWIDTH{1'b0}};
        mem_scratch_we     = {LANES{1'b0}};

        // ---- Read side (one phase active at a time) ----
        case (state)
            // XTW1: read axis_i4 (just-written from FWD_L0)
            ST_FWD_XTW1_A, ST_FWD_XTW1_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i4_pack;
            end
            // FWD_L1 sweeps i3 -> need axis_i3 layout
            ST_FWD_L1_A, ST_FWD_L1_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i3_pack;
            end
            // XTW2 lane=i2 -> axis_i2 (so the i2 axis sweeps through k)
            ST_FWD_XTW2_A, ST_FWD_XTW2_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i2_pack;
            end
            ST_FWD_L2_A, ST_FWD_L2_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i2_pack;
            end
            ST_FWD_XTW3_A, ST_FWD_XTW3_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_FWD_L3_A, ST_FWD_L3_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_FWD_XTW4_A, ST_FWD_XTW4_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_broadcast_pack;
            end
            ST_FWD_L4_A, ST_FWD_L4_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_broadcast_pack;
            end
            // INV chain (reverse): INV_L4 writes bc; XTW4 reads bc
            ST_INV_XTW4: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_broadcast_pack;
            end
            // INV_L3 sweeps k1 (lane=i1), data was broadcast -> need axis_i1
            ST_INV_L3: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_INV_XTW3: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_INV_L2: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i2_pack;
            end
            ST_INV_XTW2: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i2_pack;
            end
            ST_INV_L1: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i3_pack;
            end
            ST_INV_XTW1: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i3_pack;
            end
            ST_INV_L0: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i4_pack;
            end
            default: ;
        endcase

        // ---- Write side (mutually exclusive across taps and states) ----
        // d12 tap: only FWD_L0 (mul-then-NTT)
        if ((state_d[12] == ST_FWD_L0_A || state_d[12] == ST_FWD_L0_B)
            && valid_d[12]) begin
            mem_scratch_wshift = wshift_d12;
            mem_scratch_wpos   = wpos_i4_d12;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        // d8 tap: NTT-output phases
        // FWD_L1 writes axis_i3, FWD_L2 writes axis_i2, FWD_L3 writes axis_i1
        else if ((state_d[8] == ST_FWD_L1_A || state_d[8] == ST_FWD_L1_B)
                 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i3_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[8] == ST_FWD_L2_A || state_d[8] == ST_FWD_L2_B)
                 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i2_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[8] == ST_FWD_L3_A || state_d[8] == ST_FWD_L3_B)
                 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i1_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L4 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_bc_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L3 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i1_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L2 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i2_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L1 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i3_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        // d5 tap: mul-only XTW phases
        else if ((state_d[5] == ST_FWD_XTW1_A || state_d[5] == ST_FWD_XTW1_B)
                 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i4_d5;   // i4 layout (read was axis_i4)
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW2_A || state_d[5] == ST_FWD_XTW2_B)
                 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i2_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW3_A || state_d[5] == ST_FWD_XTW3_B)
                 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i1_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW4_A || state_d[5] == ST_FWD_XTW4_B)
                 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_bc_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW4 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_bc_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW3 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i1_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW2 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i2_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW1 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i3_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
    end

    // =========================================================================
    // Sub-NTT input pack and mul source pack (consumer-side muxes)
    // =========================================================================
    integer ci;

    always @(*) begin
        ntt_in_pack = {L*WWIDTH{1'b0}};
        if (state_d[5] == ST_FWD_L0_A || state_d[5] == ST_FWD_L0_B)
            ntt_in_pack = mul_out_pack;
        else begin
            case (state_d[1])
                ST_FWD_L1_A, ST_FWD_L1_B,
                ST_FWD_L2_A, ST_FWD_L2_B,
                ST_FWD_L3_A, ST_FWD_L3_B,
                ST_FWD_L4_A, ST_FWD_L4_B,
                ST_INV_L3, ST_INV_L2, ST_INV_L1, ST_INV_L0:
                    ntt_in_pack = scratch_rdata;
                ST_INV_L4:
                    ntt_in_pack = mem_a_rdata;
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
                    ST_FWD_XTW4_A, ST_FWD_XTW4_B,
                    ST_INV_XTW1, ST_INV_XTW2, ST_INV_XTW3, ST_INV_XTW4: begin
                        mul_a_pack[ci*WWIDTH +: WWIDTH] = scratch_rdata[ci*WWIDTH +: WWIDTH];
                        mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack     [ci*WWIDTH +: WWIDTH];
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

                // A forward chain
                ST_FWD_L0_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW1_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW1_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L1_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L1_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW2_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW2_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L2_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L2_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW3_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW3_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L3_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L3_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW4_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW4_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L4_A; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L4_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L0_B; end
                    else op_count <= op_count + 1;
                end

                // B forward chain
                ST_FWD_L0_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW1_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW1_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L1_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L1_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW2_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW2_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L2_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L2_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW3_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW3_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L3_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L3_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_XTW4_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_XTW4_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_FWD_L4_B; end
                    else op_count <= op_count + 1;
                end
                ST_FWD_L4_B: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_PWM; end
                    else op_count <= op_count + 1;
                end

                ST_PWM: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L4; end
                    else op_count <= op_count + 1;
                end

                // Inverse chain
                ST_INV_L4: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_XTW4; end
                    else op_count <= op_count + 1;
                end
                ST_INV_XTW4: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L3; end
                    else op_count <= op_count + 1;
                end
                ST_INV_L3: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_XTW3; end
                    else op_count <= op_count + 1;
                end
                ST_INV_XTW3: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L2; end
                    else op_count <= op_count + 1;
                end
                ST_INV_L2: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_XTW2; end
                    else op_count <= op_count + 1;
                end
                ST_INV_XTW2: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L1; end
                    else op_count <= op_count + 1;
                end
                ST_INV_L1: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_XTW1; end
                    else op_count <= op_count + 1;
                end
                ST_INV_XTW1: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L0; end
                    else op_count <= op_count + 1;
                end
                ST_INV_L0: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_OUTPUT; end
                    else op_count <= op_count + 1;
                end

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

`endif // _HIER_D5_L8_TOP_GUARD
