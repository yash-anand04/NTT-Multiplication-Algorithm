// =============================================================================
// hier_n4k_top.v   (Phase E debug variant, L=8)
// Fourvariate (d=4) hierarchical NTT polynomial multiplier.  N = L^4 = 4096.
//
// Mirrors hier_n32k_top (d=3) but adds one more axis and one more cross-twiddle
// phase per direction.  Used as a fast L=8 sim variant before scaling to L=32
// (hier_n1M_top, N=10^6).
//
// Layout: flat index i = i0 + L*i1 + L^2*i2 + L^3*i3, L = 8.
//   bank(i0,i1,i2,i3) = (i0+i1+i2+i3) mod 8         (conflict-free)
//   pos (i0,i1,i2,i3) = i1 + L*i2 + L^2*i3          (per-bank addr in [0,512))
//   i0 contributes to bank only, not pos.
//
// Forward NTT (per polynomial):
//   STAGE 0:  pre-twist by psi^i, NTT along i3 axis (-> k3)
//   XTW1:     multiply by psi^(2*L^2*i2*k3)
//   STAGE 1:  NTT along i2 axis (-> k2)
//   XTW2:     multiply by psi^(2*L*i1*(L*k2+k3))
//   STAGE 2:  NTT along i1 axis (-> k1)
//   XTW3:     multiply by psi^(2*i0*(L^2*k1+L*k2+k3))
//   STAGE 3:  NTT along i0 axis (-> k0)
// PWM: spec_a * spec_b -> prod
// Inverse: reverse the chain (post-twist by psi^(-i) at the end).
//
// Storage: 4 banked_mem instances in BRAM mode (sync read).  At L=8 each
// memory is 8 banks * 512 entries * 17 bits = ~70 Kb per memory.  Total 4 mem
// banked storage fits in BRAM trivially.
//
// Pipeline taps (BRAM = +1 cycle vs Phase C):
//   d5  : mul-only paths (PWM, XTW phases, LOAD).
//   d8  : NTT-only paths (FWD_Lx, INV_Lx pure NTT phases).
//   d12 : NTT+mul paths  (FWD_L0 with pre-twist, INV_L0 with post-twist).
// =============================================================================

`ifndef _HIER_D4_L4_TOP_GUARD
`define _HIER_D4_L4_TOP_GUARD

module hier_d4_L4_top #(
    parameter B       = 16,
    parameter L       = 4,
    parameter N       = L * L * L * L,        // 4096
    parameter WWIDTH  = B + 1,
    parameter LOGN    = 8,                   // $clog2(N)
    parameter TW_BITS = LOGN + 1              // 13: psi has order 2N = 8192
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
        // --- A forward chain (7 phases) ---
        ST_FWD_L0_A   = 5'd2,    // pre-twist + NTT along i3
        ST_FWD_XTW1_A = 5'd3,
        ST_FWD_L1_A   = 5'd4,    // NTT along i2
        ST_FWD_XTW2_A = 5'd5,
        ST_FWD_L2_A   = 5'd6,    // NTT along i1
        ST_FWD_XTW3_A = 5'd7,
        ST_FWD_L3_A   = 5'd8,    // NTT along i0 -> spec_a
        // --- B forward chain (7 phases) ---
        ST_FWD_L0_B   = 5'd9,
        ST_FWD_XTW1_B = 5'd10,
        ST_FWD_L1_B   = 5'd11,
        ST_FWD_XTW2_B = 5'd12,
        ST_FWD_L2_B   = 5'd13,
        ST_FWD_XTW3_B = 5'd14,
        ST_FWD_L3_B   = 5'd15,
        // --- pointwise ---
        ST_PWM        = 5'd16,
        // --- inverse chain (7 phases) ---
        ST_INV_L3     = 5'd17,   // INTT along k0 -> i0
        ST_INV_XTW3   = 5'd18,
        ST_INV_L2     = 5'd19,   // INTT along k1 -> i1
        ST_INV_XTW2   = 5'd20,
        ST_INV_L1     = 5'd21,   // INTT along k2 -> i2
        ST_INV_XTW1   = 5'd22,
        ST_INV_L0     = 5'd23,   // INTT along k3 + post-twist
        ST_OUTPUT     = 5'd24,
        ST_DONE       = 5'd25;

    localparam integer SCAN_CYCLES = N / L;       // 512 issues per compute phase
    localparam integer DRAIN       = 12;
    localparam integer SCAN_LEN    = SCAN_CYCLES + DRAIN;  // 524 cycles per phase

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
    // Banking parameters (L=8)
    // -------------------------------------------------------------------------
    localparam integer LANES     = L;       // 8
    localparam integer DEPTH     = L*L*L;   // 512 entries per bank
    localparam integer LOG_LANES = 2;
    localparam integer LOG_DEPTH = 6;

    // -------------------------------------------------------------------------
    // op_count decomposition.  During compute phases (op_count in [0, L^3)):
    //   op_a = op_count[1:0]   = "lowest" iteration index
    //   op_b = op_count[3:2]
    //   op_c = op_count[5:4]
    // Their interpretation as (i0,i1,i2,i3) depends on which axis the current
    // FSM phase is sweeping.  Convention: the bank-only axis (i0 for NTT_i1/i2/i3
    // phases) maps to op_a.  Pos-axes map to op_b, op_c.
    // -------------------------------------------------------------------------
    wire [LOG_LANES-1:0] op_a = op_count[1:0];
    wire [LOG_LANES-1:0] op_b = op_count[3:2];
    wire [LOG_LANES-1:0] op_c = op_count[5:4];

    // During LOAD/OUTPUT: op_count = i0 + L*i1 + L^2*i2 + L^3*i3 (full 12-bit)
    wire [LOG_LANES-1:0] load_i0 = op_count[1:0];
    wire [LOG_LANES-1:0] load_i1 = op_count[3:2];
    wire [LOG_LANES-1:0] load_i2 = op_count[5:4];
    wire [LOG_LANES-1:0] load_i3 = op_count[7:6];
    wire [LOG_LANES-1:0] load_bank = (load_i0 + load_i1 + load_i2 + load_i3) & 2'h3;
    reg  [LOG_LANES-1:0] load_bank_d1;
    always @(posedge clk) load_bank_d1 <= load_bank;
    wire [LOG_DEPTH-1:0] load_pos  = {load_i3, load_i2, load_i1};   // i1 + L*i2 + L^2*i3

    // Delayed LOAD writeback (write tap d5)
    wire [LOG_LANES-1:0] load_i0_d5 = opcnt_d[5][1:0];
    wire [LOG_LANES-1:0] load_i1_d5 = opcnt_d[5][3:2];
    wire [LOG_LANES-1:0] load_i2_d5 = opcnt_d[5][5:4];
    wire [LOG_LANES-1:0] load_i3_d5 = opcnt_d[5][7:6];
    wire [LOG_LANES-1:0] load_bank_d5 =
        (load_i0_d5 + load_i1_d5 + load_i2_d5 + load_i3_d5) & 2'h3;
    wire [LOG_DEPTH-1:0] load_pos_d5  = {load_i3_d5, load_i2_d5, load_i1_d5};

    // -------------------------------------------------------------------------
    // Read-side rpos packs.  Pattern depends on which axis is "lane".
    //   axis_i3 (lane=i3):       pos[k] = op_b + L*op_c + L^2*k
    //   axis_i2 (lane=i2):       pos[k] = op_b + L*k    + L^2*op_c
    //   axis_i1 (lane=i1):       pos[k] = k    + L*op_b + L^2*op_c
    //   broadcast/axis_i0:       pos[k] = op_a + L*op_b + L^2*op_c   (k -> bank only)
    //
    // rshift = (op_a + op_b + op_c) mod L for all NTT/XTW phases.
    // bank[k] = (rshift + k) mod L.
    // -------------------------------------------------------------------------
    wire [LOG_LANES-1:0] rshift_op = (op_a + op_b + op_c) & 2'h3;

    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i3_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i2_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i1_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_broadcast_pack;
    wire [LANES*LOG_DEPTH-1:0] rpos_zero_pack;
    genvar gk;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_rpos
            assign rpos_axis_i3_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {gk[1:0], op_c, op_b};
            assign rpos_axis_i2_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {op_c, gk[1:0], op_b};
            assign rpos_axis_i1_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {op_c, op_b, gk[1:0]};
            assign rpos_broadcast_pack[gk*LOG_DEPTH +: LOG_DEPTH] = {op_c, op_b, op_a};
            assign rpos_zero_pack    [gk*LOG_DEPTH +: LOG_DEPTH] = {LOG_DEPTH{1'b0}};
        end
    endgenerate

    // Write-side: same patterns at delayed taps
    wire [LANES*LOG_DEPTH-1:0] wpos_i3_d5,  wpos_i3_d8,  wpos_i3_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i2_d5,  wpos_i2_d8,  wpos_i2_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i1_d5,  wpos_i1_d8,  wpos_i1_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_bc_d5,  wpos_bc_d8,  wpos_bc_d12;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_wpos
            // tap 5
            assign wpos_i3_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[1:0], opcnt_d[5][5:4], opcnt_d[5][3:2]};
            assign wpos_i2_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][5:4], gk[1:0], opcnt_d[5][3:2]};
            assign wpos_i1_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][5:4], opcnt_d[5][3:2], gk[1:0]};
            assign wpos_bc_d5 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[5][5:4], opcnt_d[5][3:2], opcnt_d[5][1:0]};
            // tap 8
            assign wpos_i3_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[1:0], opcnt_d[8][5:4], opcnt_d[8][3:2]};
            assign wpos_i2_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][5:4], gk[1:0], opcnt_d[8][3:2]};
            assign wpos_i1_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][5:4], opcnt_d[8][3:2], gk[1:0]};
            assign wpos_bc_d8 [gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[8][5:4], opcnt_d[8][3:2], opcnt_d[8][1:0]};
            // tap 12
            assign wpos_i3_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {gk[1:0], opcnt_d[12][5:4], opcnt_d[12][3:2]};
            assign wpos_i2_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][5:4], gk[1:0], opcnt_d[12][3:2]};
            assign wpos_i1_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][5:4], opcnt_d[12][3:2], gk[1:0]};
            assign wpos_bc_d12[gk*LOG_DEPTH +: LOG_DEPTH] =
                {opcnt_d[12][5:4], opcnt_d[12][3:2], opcnt_d[12][1:0]};
        end
    endgenerate

    wire [LOG_LANES-1:0] wshift_d5  =
        (opcnt_d[5][1:0]  + opcnt_d[5][3:2]  + opcnt_d[5][5:4])  & 2'h3;
    wire [LOG_LANES-1:0] wshift_d8  =
        (opcnt_d[8][1:0]  + opcnt_d[8][3:2]  + opcnt_d[8][5:4])  & 2'h3;
    wire [LOG_LANES-1:0] wshift_d12 =
        (opcnt_d[12][1:0] + opcnt_d[12][3:2] + opcnt_d[12][5:4]) & 2'h3;

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
    // Mul array (8 lanes for L=8)
    // -------------------------------------------------------------------------
    reg  [L*WWIDTH-1:0]  mul_a_pack;
    reg  [L*WWIDTH-1:0]  mul_b_pack;
    wire [L*WWIDTH-1:0]  mul_out_pack;
    wire [L*WWIDTH-1:0]  tw_pack;
    wire [L*TW_BITS-1:0] tw_idx_pack;

    // -------------------------------------------------------------------------
    // Per-lane twiddle indices.  d=4 formulas (from fourvar_ntt_model.py):
    //   FWD_L0 pre-twist:       psi^(i0 + L*i1 + L^2*i2 + L^3*i3) at lane=i3
    //                             = psi^(op_a + L*op_b + L^2*op_c + L^3*tg)
    //   FWD_XTW1 (lane=k3=tg):  psi^(2*L^2 * i2 * k3) = psi^(2L^2 * op_c * tg)
    //   FWD_XTW2 (lane=i1=tg):  psi^(2*L * i1 * (L*k2+k3))
    //                             = psi^(2L * tg * (L*op_b + op_c))
    //   FWD_XTW3 (lane=i0=tg):  psi^(2 * i0 * (L^2*k1+L*k2+k3))
    //                             = psi^(2 * tg * (L^2*op_a + L*op_b + op_c))
    //   INV_L0 post-twist:      inv of FWD_L0 idx, but mul fires 8 cycles AFTER
    //                            NTT issue -> use opcnt_d[7] (REGISTERED twiddle
    //                            adds 1 cycle, so tap-shift d8 -> d7).
    //   INV_XTW1/2/3: inverses of the corresponding FWD formulas.
    //
    // Twiddle ROMs are REGISTERED=1 (1-cycle BRAM read).  Idx uses CURRENT
    // op_count / state for most phases; INV_L0 uses opcnt_d[7]/state_d[7].
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

            // FWD_L0: pre-twist by psi^(i0 + L*i1 + L^2*i2 + L^3*i3), lane=i3
            wire [TW_BITS-1:0] tw_fwd_l0_idx =
                (oa_d0 + L*ob_d0 + L*L*oc_d0 + L*L*L*tg) % (2*N);

            // FWD_XTW1: psi^(2 * L^2 * i2 * k3), lane=k3, op_c=i2
            wire [TW_BITS-1:0] tw_xtw1_idx =
                (2 * L * L * oc_d0 * tg) % (2*N);

            // FWD_XTW2: psi^(2 * L * i1 * (L*k2+k3)), lane=i1, op_b=k2, op_c=k3
            wire [TW_BITS-1:0] tw_xtw2_idx =
                (2 * L * tg * (L*ob_d0 + oc_d0)) % (2*N);

            // FWD_XTW3: psi^(2 * i0 * (L^2*k1 + L*k2 + k3)), lane=i0,
            //          op_a=k1, op_b=k2, op_c=k3
            wire [TW_BITS-1:0] tw_xtw3_idx =
                (2 * tg * (L*L*oa_d0 + L*ob_d0 + oc_d0)) % (2*N);

            // INV_L0 post-twist: mul fires 8 cycles after NTT issue.  With
            // REGISTERED=1 twiddle, idx tap shifts d8 -> d7.
            wire [LOG_LANES-1:0] oa_d7 = opcnt_d[7][1:0];
            wire [LOG_LANES-1:0] ob_d7 = opcnt_d[7][3:2];
            wire [LOG_LANES-1:0] oc_d7 = opcnt_d[7][5:4];
            wire [TW_BITS-1:0] tw_inv_l0_idx_d7 = inv_tw_idx(
                (oa_d7 + L*ob_d7 + L*L*oc_d7 + L*L*L*tg) % (2*N));

            // INV_XTW1: inv(FWD_XTW1) at lane=k3=tg (same iteration as FWD)
            wire [TW_BITS-1:0] tw_inv_xtw1_idx = inv_tw_idx(tw_xtw1_idx);

            // INV_XTW2: inverse iterates with different (lane, op) mapping in
            // d=3 (lane was reassigned).  For d=4 the inverse iteration matches
            // the forward iteration (lane=i1 in both FWD_XTW2 and INV_XTW2),
            // so the formula is just the inverse of FWD_XTW2.
            wire [TW_BITS-1:0] tw_inv_xtw2_idx = inv_tw_idx(tw_xtw2_idx);

            // INV_XTW3: lane=i0 (just-promoted from k0).  After INV_L3 the data
            // is at broadcast pos with (op_a, op_b, op_c) = (k1, k2, k3).
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
    // Shared sub-NTT.  Uses sub_ntt_simple (L=8 module, bidirectional, 6-cycle
    // latency identical to sub_ntt32 — pipeline taps stay d5/d8/d12).
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

    // ntt_start uses state_d[1]/valid_d[1] (and state_d[5]/valid_d[5] for the
    // FWD_L0 mul-driven path) so start aligns with when the data actually
    // reaches the sub-NTT's first register stage.  Using current `state`
    // causes the LAST issue (K=SCAN_CYCLES-1) of each phase to drop start
    // before its data enters the sub-NTT, silently flipping the NTT direction
    // (FWD vs INV) via the inv_pipe gating in sub_ntt*_bidir.  See §17.6 fix.
    always @(*) begin
        ntt_start = 1'b0;
        ntt_inverse = 1'b0;
        if ((state_d[5] == ST_FWD_L0_A || state_d[5] == ST_FWD_L0_B) && valid_d[5])
            ntt_start = 1'b1;
        else case (state_d[1])
            ST_FWD_L1_A, ST_FWD_L1_B,
            ST_FWD_L2_A, ST_FWD_L2_B,
            ST_FWD_L3_A, ST_FWD_L3_B: ntt_start = valid_d[1];
            ST_INV_L3, ST_INV_L2, ST_INV_L1, ST_INV_L0: begin
                ntt_start   = valid_d[1];
                ntt_inverse = 1'b1;
            end
            default: ;
        endcase
    end

    wire [L*WWIDTH-1:0] ntt_out_pack;
    sub_ntt4_bidir #(.B(B)) u_subntt (
        .clk(clk), .rst(rst),
        .start(ntt_start_d1), .inverse(ntt_inverse_d1),
        .in_norm(ntt_in_reg), .out_norm(ntt_out_pack),
        .valid()
    );

    // =========================================================================
    // 4 banked memories (BRAM-backed, 8 banks * 512 entries * 17 bits)
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
    // Note: mem_work + mem_trans consolidated into mem_scratch (Phase E.1
    // optimisation).  Each scratch-using phase reads from mem_scratch and
    // writes back in-place (read pattern == write pattern within a phase).
    // Cross-phase R/W race is avoided by the existing 12-cycle drain: phase X
    // last write commits at SCAN_CYCLES+11 (d12 tap); phase X+1 first read at
    // SCAN_LEN = SCAN_CYCLES+12.  Saves 256 URAMs vs the 4-mem layout.

    wire [LANES*WWIDTH-1:0] raw_a_rdata   = mem_a_rdata;
    wire [LANES*WWIDTH-1:0] raw_b_rdata   = mem_b_rdata;
    wire [LANES*WWIDTH-1:0] scratch_rdata = mem_scratch_rdata;

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
    // Phase plan (a chain shown; b chain identical with mem_a -> mem_b for the
    // initial LOAD/L0 read; intermediate work/trans alternate the same way):
    //   LOAD       : mem_a (write single cell), mem_b (write single cell)
    //   FWD_L0_A   : read mem_a (axis_i3), mul+NTT -> write mem_work (axis_i3 d12)
    //   FWD_XTW1_A : read mem_work (axis_i3), mul -> write mem_trans (axis_i3 d5)
    //   FWD_L1_A   : read mem_trans (axis_i2), NTT -> write mem_work (axis_i2 d8)
    //   FWD_XTW2_A : read mem_work (axis_i1), mul -> write mem_trans (axis_i1 d5)
    //   FWD_L2_A   : read mem_trans (axis_i1), NTT -> write mem_work (axis_i1 d8)
    //   FWD_XTW3_A : read mem_work (broadcast), mul -> write mem_trans (bc d5)
    //   FWD_L3_A   : read mem_trans (broadcast), NTT -> write mem_a (bc d8) [spec_a]
    //   ... B chain identical with mem_b in place of mem_a
    //   PWM        : read mem_a + mem_b (bc), mul -> write mem_a (bc d5) [prod]
    //   INV_L3     : read mem_a (bc), NTT -> write mem_work (bc d8)
    //   INV_XTW3   : read mem_work (bc), mul -> write mem_trans (bc d5)
    //   INV_L2     : read mem_trans (axis_i1), NTT -> write mem_work (axis_i1 d8)
    //   INV_XTW2   : read mem_work (axis_i1), mul -> write mem_trans (axis_i1 d5)
    //   INV_L1     : read mem_trans (axis_i2), NTT -> write mem_work (axis_i2 d8)
    //   INV_XTW1   : read mem_work (axis_i2), mul -> write mem_trans (axis_i2 d5)
    //   INV_L0     : read mem_trans (axis_i3), NTT+mul -> write mem_a (axis_i3 d12)
    //   OUTPUT     : read mem_a, single cell out
    // =========================================================================

    // ---- mem_a -------------------------------------------------------------
    always @(*) begin
        mem_a_rshift = 3'd0;
        mem_a_rpos   = rpos_zero_pack;
        mem_a_wshift = 3'd0;
        mem_a_wpos   = rpos_zero_pack;
        mem_a_wdata  = {LANES*WWIDTH{1'b0}};
        mem_a_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_L0_A: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_axis_i3_pack;
            end
            ST_PWM: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_broadcast_pack;
            end
            ST_INV_L3: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_broadcast_pack;
            end
            ST_OUTPUT: begin
                mem_a_rshift = 3'd0;
                mem_a_rpos[load_bank*LOG_DEPTH +: LOG_DEPTH] = load_pos;
            end
            default: ;
        endcase

        // INV_L0 final write -> mem_a (result)  (d12 = mul+NTT tap)
        if (state_d[12] == ST_INV_L0 && valid_d[12]) begin
            mem_a_wshift = wshift_d12;
            mem_a_wpos   = wpos_i3_d12;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // FWD_L3_A final NTT -> mem_a (spec_a)  (d8 = NTT tap, broadcast pos)
        else if (state_d[8] == ST_FWD_L3_A && valid_d[8]) begin
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
            mem_a_wdata                                    = broadcast17(in_a_d[5]);
            mem_a_we[load_bank_d5]                         = 1'b1;
        end
    end

    // ---- mem_b -------------------------------------------------------------
    always @(*) begin
        mem_b_rshift = 3'd0;
        mem_b_rpos   = rpos_zero_pack;
        mem_b_wshift = 3'd0;
        mem_b_wpos   = rpos_zero_pack;
        mem_b_wdata  = {LANES*WWIDTH{1'b0}};
        mem_b_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_L0_B: begin
                mem_b_rshift = rshift_op;
                mem_b_rpos   = rpos_axis_i3_pack;
            end
            ST_PWM: begin
                mem_b_rshift = rshift_op;
                mem_b_rpos   = rpos_broadcast_pack;
            end
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

    // ---- mem_scratch (consolidates mem_work + mem_trans) ------------------
    // Reads cover all NTT-input and XTW-input phases.
    // Writes cover all NTT-output and XTW-output phases (mutually exclusive
    // with reads at any given cycle; verified that for every (state, tap)
    // combination only one branch fires).
    always @(*) begin
        mem_scratch_rshift = 3'd0;
        mem_scratch_rpos   = rpos_zero_pack;
        mem_scratch_wshift = 3'd0;
        mem_scratch_wpos   = rpos_zero_pack;
        mem_scratch_wdata  = {LANES*WWIDTH{1'b0}};
        mem_scratch_we     = {LANES{1'b0}};

        // ---- Read side (one phase active at a time) ----
        case (state)
            // XTW phases (previously mem_work reads, axis = next-NTT's axis)
            ST_FWD_XTW1_A, ST_FWD_XTW1_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i3_pack;
            end
            ST_FWD_XTW2_A, ST_FWD_XTW2_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_FWD_XTW3_A, ST_FWD_XTW3_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_broadcast_pack;
            end
            ST_INV_XTW3: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_broadcast_pack;
            end
            ST_INV_XTW2: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_INV_XTW1: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i2_pack;
            end
            // NTT phases (previously mem_trans reads)
            ST_FWD_L1_A, ST_FWD_L1_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i2_pack;
            end
            ST_FWD_L2_A, ST_FWD_L2_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_FWD_L3_A, ST_FWD_L3_B: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_broadcast_pack;
            end
            ST_INV_L2: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i1_pack;
            end
            ST_INV_L1: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i2_pack;
            end
            ST_INV_L0: begin
                mem_scratch_rshift = rshift_op;
                mem_scratch_rpos   = rpos_axis_i3_pack;
            end
            default: ;
        endcase

        // ---- Write side (mutually exclusive across taps and states) ----
        // d12 tap: only FWD_L0 (mul-then-NTT)
        if ((state_d[12] == ST_FWD_L0_A || state_d[12] == ST_FWD_L0_B)
            && valid_d[12]) begin
            mem_scratch_wshift = wshift_d12;
            mem_scratch_wpos   = wpos_i3_d12;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        // d8 tap: NTT-output phases (FWD_L1/L2, INV_L3/L2/L1)
        else if ((state_d[8] == ST_FWD_L1_A || state_d[8] == ST_FWD_L1_B)
                 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i2_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[8] == ST_FWD_L2_A || state_d[8] == ST_FWD_L2_B)
                 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i1_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L3 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_bc_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L2 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i1_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L1 && valid_d[8]) begin
            mem_scratch_wshift = wshift_d8;
            mem_scratch_wpos   = wpos_i2_d8;
            mem_scratch_wdata  = ntt_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        // d5 tap: mul-only XTW phases
        else if ((state_d[5] == ST_FWD_XTW1_A || state_d[5] == ST_FWD_XTW1_B)
                 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i3_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW2_A || state_d[5] == ST_FWD_XTW2_B)
                 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i1_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW3_A || state_d[5] == ST_FWD_XTW3_B)
                 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_bc_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW3 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_bc_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW2 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i1_d5;
            mem_scratch_wdata  = mul_out_pack;
            mem_scratch_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW1 && valid_d[5]) begin
            mem_scratch_wshift = wshift_d5;
            mem_scratch_wpos   = wpos_i2_d5;
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
                ST_INV_L2, ST_INV_L1, ST_INV_L0:
                    ntt_in_pack = scratch_rdata;
                ST_INV_L3:
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
                    ST_INV_XTW1, ST_INV_XTW2, ST_INV_XTW3: begin
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
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_PWM; end
                    else op_count <= op_count + 1;
                end

                ST_PWM: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_INV_L3; end
                    else op_count <= op_count + 1;
                end

                // Inverse chain
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

`endif // _HIER_D4_L4_TOP_GUARD
