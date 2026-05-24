// =============================================================================
// hier_n32k_top.v   (Phase D)
// Trivariate hierarchical NTT polynomial multiplier.  N = L^3 = 32^3 = 32768.
//
// Layout: flat index i = i1 + L*i2 + L^2*i3, L = 32.
//   bank(i1, i2, i3) = (i1 + i2 + i3) mod 32           (conflict-free)
//   pos (i1, i2, i3) = i2 + L*i3                       (per-bank addr in [0,1024))
//
// Forward NTT (per polynomial):
//   STAGE 0:  pre-twist by psi^i,  32-pt NTT along i3 axis
//   XTW1:     multiply by  psi^(2*L*i2*k3)
//   STAGE 1:  32-pt NTT along i2 axis
//   XTW2:     multiply by  psi^(2*i1*(L*k2 + k3))
//   STAGE 2:  32-pt NTT along i1 axis
// PWM: spec_a * spec_b -> prod
// Inverse: reverse the chain with inv twiddles and INTTs (each INTT divides by L,
// three INTTs total divide by L^3 = N).  Post-twist by psi^(-i).
//
// Storage: 4 banked_mem instances in BRAM mode (sync read).
//   mem_a : raw_a -> intermediate chain -> spec_a -> prod -> intermediate -> result
//   mem_b : raw_b -> intermediate chain -> spec_b
//   mem_work, mem_trans : ping-pong scratch.
//
// Per-memory: 32 banks * 1024 entries * 17 bits = 1 RAMB18E2 per bank
//             = 32 RAMB18E2 per memory.  Total: 128 RAMB18E2.
//
// Pipeline taps (BRAM = +1 cycle vs Phase C):
//   d5  : mul-only paths (PWM, XTW phases, LOAD).
//   d8  : NTT-only paths (FWD_Lx, INV_Lx pure NTT phases).
//   d12 : NTT+mul paths  (FWD_L0 with pre-twist, INV_L0 with post-twist).
// =============================================================================

`ifndef _HIER_N32K_TOP_GUARD
`define _HIER_N32K_TOP_GUARD

module hier_n32k_top #(
    parameter B       = 16,
    parameter L       = 32,
    parameter N       = L * L * L,        // 32768
    parameter WWIDTH  = B + 1,
    parameter LOGN    = 15,               // $clog2(N)
    parameter TW_BITS = LOGN + 1          // 16: psi has order 2N = 65536
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
    // FSM states
    // -------------------------------------------------------------------------
    localparam [4:0]
        ST_IDLE       = 5'd0,
        ST_LOAD       = 5'd1,
        // -- A polynomial forward chain --
        ST_FWD_L0_A   = 5'd2,    // pre-twist + NTT along i3
        ST_FWD_XTW1_A = 5'd3,    // cross-twiddle 1
        ST_FWD_L1_A   = 5'd4,    // NTT along i2
        ST_FWD_XTW2_A = 5'd5,    // cross-twiddle 2
        ST_FWD_L2_A   = 5'd6,    // NTT along i1 -> spec_a
        // -- B polynomial forward chain --
        ST_FWD_L0_B   = 5'd7,
        ST_FWD_XTW1_B = 5'd8,
        ST_FWD_L1_B   = 5'd9,
        ST_FWD_XTW2_B = 5'd10,
        ST_FWD_L2_B   = 5'd11,
        // -- pointwise multiply --
        ST_PWM        = 5'd12,
        // -- inverse chain --
        ST_INV_L2     = 5'd13,   // INTT along k1
        ST_INV_XTW2   = 5'd14,
        ST_INV_L1     = 5'd15,
        ST_INV_XTW1   = 5'd16,
        ST_INV_L0     = 5'd17,   // INTT along k3 + post-twist
        ST_OUTPUT     = 5'd18,
        ST_DONE       = 5'd19;

    localparam integer SCAN_CYCLES = N / L;       // 1024 issues per compute phase
    localparam integer DRAIN       = 12;          // worst tap is d12
    localparam integer SCAN_LEN    = SCAN_CYCLES + DRAIN;   // 1036 cycles per phase

    reg [4:0]      state;
    reg [LOGN:0]   op_count;                // 0..max(N-1, SCAN_LEN-1)
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
    // Banking parameters
    // -------------------------------------------------------------------------
    localparam integer LANES     = L;     // 32
    localparam integer DEPTH     = L * L; // 1024 entries per bank
    localparam integer LOG_LANES = 5;
    localparam integer LOG_DEPTH = 10;

    // -------------------------------------------------------------------------
    // op_count decomposition.  During compute phases:
    //   op_low  = op_count[4:0]   = "scan inner" index
    //   op_high = op_count[9:5]   = "scan outer" index
    // Their interpretation as (i1, i2, i3) depends on which axis the current
    // FSM phase is sweeping (NTT lane axis = i_axis, other two = op_low/op_high).
    // -------------------------------------------------------------------------
    wire [LOG_LANES-1:0] op_low  = op_count[4:0];
    wire [LOG_LANES-1:0] op_high = op_count[9:5];

    // During LOAD/OUTPUT: op_count = i1 + L*i2 + L^2*i3  (full 15-bit flat index)
    wire [LOG_LANES-1:0] load_i1 = op_count[4:0];
    wire [LOG_LANES-1:0] load_i2 = op_count[9:5];
    wire [LOG_LANES-1:0] load_i3 = op_count[14:10];
    wire [LOG_LANES-1:0] load_bank = (load_i1 + load_i2 + load_i3) & 5'h1f;
    // 1-cycle-delayed load_bank for OUTPUT's BRAM-read alignment (Phase D bug 1).
    reg  [LOG_LANES-1:0] load_bank_d1;
    always @(posedge clk) load_bank_d1 <= load_bank;
    wire [LOG_DEPTH-1:0] load_pos  = {load_i3, load_i2};   // i2 + L*i3

    // Delayed LOAD writeback (write tap d5 for LOAD phase mul/data path)
    wire [LOG_LANES-1:0] load_i1_d5 = opcnt_d[5][4:0];
    wire [LOG_LANES-1:0] load_i2_d5 = opcnt_d[5][9:5];
    wire [LOG_LANES-1:0] load_i3_d5 = opcnt_d[5][14:10];
    wire [LOG_LANES-1:0] load_bank_d5 = (load_i1_d5 + load_i2_d5 + load_i3_d5) & 5'h1f;
    wire [LOG_DEPTH-1:0] load_pos_d5  = {load_i3_d5, load_i2_d5};

    // -------------------------------------------------------------------------
    // Per-state read-side rshift / rpos.
    // The bank shift formula is always rshift = (op_low + op_high) mod 32 for
    // axis-aligned scans (the lane axis contributes itself to the bank).
    // The position pattern depends on which axis is being scanned:
    //   axis = i3 (FWD_L0, INV_L0):     rpos[k] = op_high + L*k
    //   axis = i2 (FWD_L1, INV_L1):     rpos[k] = k       + L*op_high
    //   axis = i1 (FWD_L2, INV_L2):     rpos[k] = op_low  + L*op_high   (broadcast)
    //   XTW phases: same as the producer NTT's output layout (broadcast pos)
    // -------------------------------------------------------------------------
    // Pre-compute per-lane rpos packs for each pattern.
    wire [LOG_LANES-1:0] rshift_op = (op_low + op_high) & 5'h1f;

    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i3_pack;     // pos[k] = {k, op_high}  (i3=k, i2=op_high)
    wire [LANES*LOG_DEPTH-1:0] rpos_axis_i2_pack;     // pos[k] = {op_high, k}  (i3=op_high, i2=k)
    wire [LANES*LOG_DEPTH-1:0] rpos_broadcast_pack;   // pos[k] = {op_high, op_low}
    wire [LANES*LOG_DEPTH-1:0] rpos_zero_pack;
    genvar gk;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_rpos
            assign rpos_axis_i3_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {gk[4:0], op_high};
            assign rpos_axis_i2_pack [gk*LOG_DEPTH +: LOG_DEPTH] = {op_high, gk[4:0]};
            assign rpos_broadcast_pack[gk*LOG_DEPTH +: LOG_DEPTH] = {op_high, op_low};
            assign rpos_zero_pack    [gk*LOG_DEPTH +: LOG_DEPTH] = {LOG_DEPTH{1'b0}};
        end
    endgenerate

    // Write-side: each compute phase writes the same axis layout as its read.
    // For the writeback at delay tap T, op_high_dT and op_low_dT replace the
    // unregistered versions.  Build per-tap write-pos packs.
    function [LOG_LANES-1:0] olo;
        input [3:0] tap;
        olo = opcnt_d[tap][4:0];
    endfunction
    function [LOG_LANES-1:0] ohi;
        input [3:0] tap;
        ohi = opcnt_d[tap][9:5];
    endfunction

    // wpos packs for each (tap, axis-pattern) combination.  We need taps d5,
    // d8, d12 and patterns {axis_i3, axis_i2, broadcast}.
    wire [LANES*LOG_DEPTH-1:0] wpos_i3_d5,  wpos_i3_d8,  wpos_i3_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_i2_d5,  wpos_i2_d8,  wpos_i2_d12;
    wire [LANES*LOG_DEPTH-1:0] wpos_bc_d5,  wpos_bc_d8,  wpos_bc_d12;
    generate
        for (gk = 0; gk < LANES; gk = gk + 1) begin : g_wpos
            assign wpos_i3_d5 [gk*LOG_DEPTH +: LOG_DEPTH] = {gk[4:0], opcnt_d[5][9:5]};
            assign wpos_i3_d8 [gk*LOG_DEPTH +: LOG_DEPTH] = {gk[4:0], opcnt_d[8][9:5]};
            assign wpos_i3_d12[gk*LOG_DEPTH +: LOG_DEPTH] = {gk[4:0], opcnt_d[12][9:5]};
            assign wpos_i2_d5 [gk*LOG_DEPTH +: LOG_DEPTH] = {opcnt_d[5][9:5],  gk[4:0]};
            assign wpos_i2_d8 [gk*LOG_DEPTH +: LOG_DEPTH] = {opcnt_d[8][9:5],  gk[4:0]};
            assign wpos_i2_d12[gk*LOG_DEPTH +: LOG_DEPTH] = {opcnt_d[12][9:5], gk[4:0]};
            assign wpos_bc_d5 [gk*LOG_DEPTH +: LOG_DEPTH] = {opcnt_d[5][9:5],  opcnt_d[5][4:0]};
            assign wpos_bc_d8 [gk*LOG_DEPTH +: LOG_DEPTH] = {opcnt_d[8][9:5],  opcnt_d[8][4:0]};
            assign wpos_bc_d12[gk*LOG_DEPTH +: LOG_DEPTH] = {opcnt_d[12][9:5], opcnt_d[12][4:0]};
        end
    endgenerate

    wire [LOG_LANES-1:0] wshift_d5  = (opcnt_d[5][4:0]  + opcnt_d[5][9:5])  & 5'h1f;
    wire [LOG_LANES-1:0] wshift_d8  = (opcnt_d[8][4:0]  + opcnt_d[8][9:5])  & 5'h1f;
    wire [LOG_LANES-1:0] wshift_d12 = (opcnt_d[12][4:0] + opcnt_d[12][9:5]) & 5'h1f;

    // -------------------------------------------------------------------------
    // Input-data delay chain (for LOAD)
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
    // Mul array (32 lanes, pipelined mod_mul_fermat + external mul_a_r/mul_b_r)
    // -------------------------------------------------------------------------
    reg  [L*WWIDTH-1:0]  mul_a_pack;
    reg  [L*WWIDTH-1:0]  mul_b_pack;
    wire [L*WWIDTH-1:0]  mul_out_pack;
    wire [L*WWIDTH-1:0]  tw_pack;
    wire [L*TW_BITS-1:0] tw_idx_pack;

    // -------------------------------------------------------------------------
    // Per-lane twiddle indices.  Twiddle exponents derived from the d=3
    // algorithm.  All exponents are mod 2N = 65536; psi has order 2N.
    //   FWD_L0 / INV_L0 pre/post-twist: psi^( op_low + L*op_high + L^2*tg )
    //   XTW1   : psi^( 2*L * op_high * tg )            (i2=op_high, k3=tg)
    //   XTW2   : psi^( 2 * op_low * (L*tg + op_high) ) (i1=op_low, k2=tg, k3=op_high)
    //   INV_XTW1, INV_XTW2: inverses of the above
    // The INV_L0 inverse pre/post-twist uses a delayed op_count tap (mul fires
    // after the sub-NTT) -- handled via opcnt_d[7].
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
            // Twiddle ROMs are now BRAM-backed with REGISTERED=1 (1-cycle read
            // latency), paralleling the data BRAM.  The idx therefore uses the
            // CURRENT op_count / state (the registered ROM output then arrives
            // at the same d1 cycle as the BRAM data, matching mul_a timing).
            wire [LOG_LANES-1:0] olo_d0 = op_count[4:0];
            wire [LOG_LANES-1:0] ohi_d0 = op_count[9:5];
            wire [TW_BITS-1:0] tw_fwd_l0_idx   =
                (olo_d0 + L*ohi_d0 + L*L*tg) % (2*N);
            wire [TW_BITS-1:0] tw_xtw1_idx     =
                (2 * L * ohi_d0 * tg) % (2*N);
            wire [TW_BITS-1:0] tw_xtw2_idx     =
                (2 * olo_d0 * (L*tg + ohi_d0)) % (2*N);

            // INV_L0 mul fires 8 cycles AFTER NTT issue; with the +1 ROM stage
            // we shift the idx tap from d8 to d7 (ROM output arrives at d8).
            wire [LOG_LANES-1:0] olo_d7 = opcnt_d[7][4:0];
            wire [LOG_LANES-1:0] ohi_d7 = opcnt_d[7][9:5];
            wire [TW_BITS-1:0] tw_inv_l0_idx_d7 = inv_tw_idx(
                (olo_d7 + L*ohi_d7 + L*L*tg) % (2*N));

            wire [TW_BITS-1:0] tw_inv_xtw1_idx = inv_tw_idx(tw_xtw1_idx);
            // INV_XTW2 has DIFFERENT (op_low, op_high, lane) -> (k2, k3, i1)
            // mapping vs FWD_XTW2's (i1, k3, k2).  Element at (i1, k2, k3) needs
            // psi^(-2*i1*(L*k2+k3)) = psi^(-2*tg*(L*olo+ohi)) for the inverse iteration.
            wire [TW_BITS-1:0] tw_inv_xtw2_idx =
                inv_tw_idx((2 * tg * (L*olo_d0 + ohi_d0)) % (2*N));

            assign tw_idx_pack[tg*TW_BITS +: TW_BITS] =
                (state_d[7] == ST_INV_L0)                                        ? tw_inv_l0_idx_d7 :
                ((state == ST_FWD_L0_A) || (state == ST_FWD_L0_B))               ? tw_fwd_l0_idx :
                ((state == ST_FWD_XTW1_A) || (state == ST_FWD_XTW1_B))           ? tw_xtw1_idx :
                ((state == ST_FWD_XTW2_A) || (state == ST_FWD_XTW2_B))           ? tw_xtw2_idx :
                (state == ST_INV_XTW2)                                           ? tw_inv_xtw2_idx :
                (state == ST_INV_XTW1)                                           ? tw_inv_xtw1_idx :
                {TW_BITS{1'b0}};

            twiddle_gen #(.B(B), .LOGN(LOGN), .REGISTERED(1)) u_tw (
                .clk(clk), .idx(tw_idx_pack[tg*TW_BITS +: TW_BITS]),
                .tw_out(tw_pack[tg*WWIDTH +: WWIDTH])
            );

            // External mul input registers with DONT_TOUCH (same as Phase C step 12)
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
    // Shared sub-NTT (same pattern as Phase C A2 consolidation).
    // Start gated by valid_d* + state_d* matching the phases that need it.
    // -------------------------------------------------------------------------
    reg  [L*WWIDTH-1:0] ntt_in_pack;
    reg  [L*WWIDTH-1:0] ntt_in_reg;
    reg                 ntt_start_d1, ntt_inverse_d1;

    // ntt_start: high when the sub-NTT input is valid (1 cycle after the issue
    // for read-driven inputs, 5 cycles after the issue for mul-driven inputs).
    // For Phase D:
    //   FWD_L0_*  : mul-driven (pre-twist*data),  start at state_d[5]
    //   FWD_L1_*  : read-driven (trans_rdata),    start at state_d[1] (BRAM +1)
    //   FWD_L2_*  : read-driven (trans_rdata),    start at state_d[1]
    //   INV_L2    : read-driven,                  start at state_d[1]
    //   INV_L1    : read-driven,                  start at state_d[1]
    //   INV_L0    : read-driven,                  start at state_d[1]
    wire ntt_start =
        ((state_d[5] == ST_FWD_L0_A || state_d[5] == ST_FWD_L0_B) && valid_d[5]) ||
        ((state_d[1] == ST_FWD_L1_A || state_d[1] == ST_FWD_L1_B ||
          state_d[1] == ST_FWD_L2_A || state_d[1] == ST_FWD_L2_B ||
          state_d[1] == ST_INV_L0   ||
          state_d[1] == ST_INV_L1   ||
          state_d[1] == ST_INV_L2) && valid_d[1]);

    wire ntt_inverse =
        (state_d[1] == ST_INV_L0) ||
        (state_d[1] == ST_INV_L1) ||
        (state_d[1] == ST_INV_L2);

    always @(posedge clk) begin
        ntt_in_reg     <= ntt_in_pack;
        ntt_start_d1   <= ntt_start;
        ntt_inverse_d1 <= ntt_inverse;
    end

    wire [L*WWIDTH-1:0] ntt_out_pack;
    sub_ntt32_bidir #(.B(B)) u_subntt (
        .clk(clk), .rst(rst),
        .start(ntt_start_d1), .inverse(ntt_inverse_d1),
        .in_norm(ntt_in_reg), .out_norm(ntt_out_pack),
        .valid()
    );

    // =========================================================================
    // 4 banked memories (BRAM-backed, 32 banks * 1024 entries * 17 bits)
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
    `BMEM_DECL(mem_work)
    `BMEM_DECL(mem_trans)

    // Logical aliases (the same physical mem holds different things across phases)
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

    // =========================================================================
    // PER-MEMORY DRIVER LOGIC
    //
    // Forward A chain:
    //   LOAD       : mem_a (write single cell), mem_b (write single cell)
    //   FWD_L0_A   : read mem_a, mul out -> write mem_work (NTT writes at d12)
    //   FWD_XTW1_A : read mem_work, mul out -> write mem_trans (d5)
    //   FWD_L1_A   : read mem_trans, NTT out -> write mem_work (d8)
    //   FWD_XTW2_A : read mem_work, mul out -> write mem_trans (d5)
    //   FWD_L2_A   : read mem_trans, NTT out -> write mem_a (d8)  [in-place spec_a]
    //   ... B chain identical with mem_b in place of mem_a
    //   PWM        : read mem_a + mem_b, mul out -> write mem_a (d5)  [prod = mem_a]
    //   INV_L2     : read mem_a, NTT out -> write mem_work (d8)
    //   INV_XTW2   : read mem_work, mul out -> write mem_trans (d5)
    //   INV_L1     : read mem_trans, NTT out -> write mem_work (d8)
    //   INV_XTW1   : read mem_work, mul out -> write mem_trans (d5)
    //   INV_L0     : read mem_trans, NTT+mul out -> write mem_a (d12) [result]
    //   OUTPUT     : read mem_a, single cell out
    // =========================================================================

    // ---- mem_a -------------------------------------------------------------
    always @(*) begin
        mem_a_rshift = 5'd0;
        mem_a_rpos   = rpos_zero_pack;
        mem_a_wshift = 5'd0;
        mem_a_wpos   = rpos_zero_pack;
        mem_a_wdata  = {LANES*WWIDTH{1'b0}};
        mem_a_we     = {LANES{1'b0}};

        // ---- Read side ----
        case (state)
            ST_FWD_L0_A: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_axis_i3_pack;     // axis = i3
            end
            ST_PWM: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_broadcast_pack;   // single-cell broadcast (spec_a layout)
            end
            ST_INV_L2: begin
                mem_a_rshift = rshift_op;
                mem_a_rpos   = rpos_broadcast_pack;   // spec_a/prod stored with axis_i1 layout
            end
            ST_OUTPUT: begin
                mem_a_rshift = 5'd0;
                mem_a_rpos[load_bank*LOG_DEPTH +: LOG_DEPTH] = load_pos;
            end
            default: ;
        endcase

        // ---- Write side (priority by tap) ----
        // d12: INV_L0 final write -> mem_a (result)
        if (state_d[12] == ST_INV_L0 && valid_d[12]) begin
            mem_a_wshift = wshift_d12;
            mem_a_wpos   = wpos_i3_d12;   // INV_L0 lane axis = i3 -> result indexed by i3
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // d8: FWD_L2_A final NTT -> mem_a (spec_a)
        else if (state_d[8] == ST_FWD_L2_A && valid_d[8]) begin
            mem_a_wshift = wshift_d8;
            mem_a_wpos   = wpos_bc_d8;     // i1-axis NTT output has broadcast pos
            mem_a_wdata  = ntt_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // d5: PWM write -> mem_a (prod)
        else if (state_d[5] == ST_PWM && valid_d[5]) begin
            mem_a_wshift = wshift_d5;
            mem_a_wpos   = wpos_bc_d5;
            mem_a_wdata  = mul_out_pack;
            mem_a_we     = {LANES{1'b1}};
        end
        // d5: LOAD write -> mem_a (single cell, broadcast data via load_bank_d5)
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

        if (state_d[8] == ST_FWD_L2_B && valid_d[8]) begin
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
    // Roles by phase:
    //   read in FWD_XTW1_A/B (consumes FWD_L0 output) - axis i3 layout
    //   read in FWD_XTW2_A/B (consumes FWD_L1 output) - axis i2 layout
    //   read in INV_XTW2 (consumes INV_L2 output)      - broadcast pos (k1 NTT out)
    //   read in INV_XTW1 (consumes INV_L1 output)      - axis i2 layout
    //   write from FWD_L0_A/B (d12 NTT+mul output)     - axis i3 layout
    //   write from FWD_L1_A/B (d8 NTT output)          - axis i2 layout
    //   write from INV_L2     (d8 NTT output)          - broadcast layout
    //   write from INV_L1     (d8 NTT output)          - axis i2 layout
    always @(*) begin
        mem_work_rshift = 5'd0;
        mem_work_rpos   = rpos_zero_pack;
        mem_work_wshift = 5'd0;
        mem_work_wpos   = rpos_zero_pack;
        mem_work_wdata  = {LANES*WWIDTH{1'b0}};
        mem_work_we     = {LANES{1'b0}};

        case (state)
            ST_FWD_XTW1_A, ST_FWD_XTW1_B: begin
                mem_work_rshift = rshift_op;
                mem_work_rpos   = rpos_axis_i3_pack;
            end
            ST_FWD_XTW2_A, ST_FWD_XTW2_B: begin
                mem_work_rshift = rshift_op;
                mem_work_rpos   = rpos_axis_i2_pack;
            end
            ST_INV_XTW2: begin
                mem_work_rshift = rshift_op;
                mem_work_rpos   = rpos_broadcast_pack;
            end
            ST_INV_XTW1: begin
                mem_work_rshift = rshift_op;
                mem_work_rpos   = rpos_axis_i2_pack;
            end
            default: ;
        endcase

        if ((state_d[12] == ST_FWD_L0_A || state_d[12] == ST_FWD_L0_B) && valid_d[12]) begin
            mem_work_wshift = wshift_d12;
            mem_work_wpos   = wpos_i3_d12;
            mem_work_wdata  = ntt_out_pack;   // Bug 3 fix: FWD_L0 = mul then NTT
            mem_work_we     = {LANES{1'b1}};
        end
        else if ((state_d[8] == ST_FWD_L1_A || state_d[8] == ST_FWD_L1_B) && valid_d[8]) begin
            mem_work_wshift = wshift_d8;
            mem_work_wpos   = wpos_i2_d8;
            mem_work_wdata  = ntt_out_pack;
            mem_work_we     = {LANES{1'b1}};
        end
        else if (state_d[8] == ST_INV_L2 && valid_d[8]) begin
            mem_work_wshift = wshift_d8;
            mem_work_wpos   = wpos_bc_d8;
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
                mem_trans_rshift = rshift_op;
                mem_trans_rpos   = rpos_axis_i2_pack;
            end
            ST_FWD_L2_A, ST_FWD_L2_B: begin
                mem_trans_rshift = rshift_op;
                mem_trans_rpos   = rpos_broadcast_pack;
            end
            ST_INV_L1: begin
                mem_trans_rshift = rshift_op;
                mem_trans_rpos   = rpos_axis_i2_pack;
            end
            ST_INV_L0: begin
                mem_trans_rshift = rshift_op;
                mem_trans_rpos   = rpos_axis_i3_pack;
            end
            default: ;
        endcase

        if ((state_d[5] == ST_FWD_XTW1_A || state_d[5] == ST_FWD_XTW1_B) && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_i3_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if ((state_d[5] == ST_FWD_XTW2_A || state_d[5] == ST_FWD_XTW2_B) && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_i2_d5;
            mem_trans_wdata  = mul_out_pack;
            mem_trans_we     = {LANES{1'b1}};
        end
        else if (state_d[5] == ST_INV_XTW2 && valid_d[5]) begin
            mem_trans_wshift = wshift_d5;
            mem_trans_wpos   = wpos_bc_d5;
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
    // Sub-NTT input pack and mul source pack (consumer-side muxes)
    // =========================================================================
    integer ci;

    // ntt_in source.  For BRAM-driven inputs, rdata is available state_d[1].
    // For mul-driven (FWD_L0), the mul_out is available at state_d[5].
    always @(*) begin
        ntt_in_pack = {L*WWIDTH{1'b0}};
        if (state_d[5] == ST_FWD_L0_A || state_d[5] == ST_FWD_L0_B)
            ntt_in_pack = mul_out_pack;
        else begin
            case (state_d[1])
                ST_FWD_L1_A, ST_FWD_L1_B:
                    ntt_in_pack = trans_rdata;
                ST_FWD_L2_A, ST_FWD_L2_B:
                    ntt_in_pack = trans_rdata;
                ST_INV_L2:
                    ntt_in_pack = mem_a_rdata;
                ST_INV_L1:
                    ntt_in_pack = trans_rdata;   // Bug 5 fix: was work_rdata
                ST_INV_L0:
                    ntt_in_pack = trans_rdata;
                default: ;
            endcase
        end
    end

    // mul_a / mul_b pack.  Each phase muxes the appropriate source.
    //   FWD_L0 : a = raw, b = tw_pack (pre-twist)
    //   FWD_XTW1 : a = work_rdata,  b = tw_pack
    //   FWD_XTW2 : a = work_rdata,  b = tw_pack
    //   PWM      : a = mem_a_rdata, b = mem_b_rdata
    //   INV_XTW2 : a = work_rdata,  b = tw_pack
    //   INV_XTW1 : a = work_rdata,  b = tw_pack
    //   INV_L0   : a = ntt_out_pack, b = tw_pack  (post-twist, mul fires at state_d[8])
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
                    ST_INV_XTW1, ST_INV_XTW2: begin
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

    // tw for INV_XTW1/2 uses the work_rdata source; XTW reads from mem_work
    // (above) and mem_trans (also above).  The XTW reads above use mem_work
    // and mem_trans respectively -- need to add the inverse XTW read paths.
    // Actually re-check: INV_XTW2 reads INV_L2 output (in mem_work).  Add
    // mem_work read driver for INV_XTW2 -- already present.
    // INV_XTW1 reads INV_L1 output (in mem_work too).  Also present.

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

                // Compute phases - all have length SCAN_LEN - 1
                ST_FWD_L0_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin
                        op_count <= 0; state <= ST_FWD_XTW1_A;
                    end else op_count <= op_count + 1;
                end
                ST_FWD_XTW1_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin
                        op_count <= 0; state <= ST_FWD_L1_A;
                    end else op_count <= op_count + 1;
                end
                ST_FWD_L1_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin
                        op_count <= 0; state <= ST_FWD_XTW2_A;
                    end else op_count <= op_count + 1;
                end
                ST_FWD_XTW2_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin
                        op_count <= 0; state <= ST_FWD_L2_A;
                    end else op_count <= op_count + 1;
                end
                ST_FWD_L2_A: begin
                    cycle_count <= cycle_count + 1;
                    if (op_count == SCAN_LEN-1) begin
                        op_count <= 0; state <= ST_FWD_L0_B;
                    end else op_count <= op_count + 1;
                end
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
                    if (op_count == SCAN_LEN-1) begin op_count <= 0; state <= ST_PWM; end
                    else op_count <= op_count + 1;
                end
                ST_PWM: begin
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
                    // mem_a sync read has +1 cycle latency; data_out then registers
                    // one more cycle.  Total OUTPUT phase length = N + 2.
                    data_out       <= mem_a_rdata[load_bank_d1*WWIDTH +: WWIDTH];
                    data_out_valid <= (op_count >= 1) && (op_count < N+1);
                    if (op_count == N+1) begin
                        op_count <= 0; state <= ST_DONE;
                    end else op_count <= op_count + 1;
                end

                ST_DONE: done <= 1'b1;
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`endif // _HIER_N32K_TOP_GUARD
