// =============================================================================
// ntt_top.v  —  NTT Polynomial Multiplier Top Level  (Fig. 6)
//
// Full pipeline:  LOAD → NTT1 → NTT2 → PWM → INTT → OUTPUT
//
// Architecture matches the paper (Xing et al. 2025, IEEE Trans. Computers):
//   - Single TIME-SHARED ModMul bank (R pipelined mod_mul_fermat instances)
//     reused for NTT twiddle, INTT twiddle, and PWM phases.
//   - 2-stage pipelined mod_mul_fermat (latency = 2 cycles, throughput = 1/cy)
//   - Write-back control signals delayed 2 cycles to match ModMul latency.
//
// Data paths:
//   NTT  :  Banks → modmul_ntt_in × twiddle → [ModMul] → R2NTT → Banks
//   INTT :  Banks → R2INTT → [ModMul × twiddle] → Banks
//   PWM  :  Banks → lower × upper → [ModMul] → Banks (lower half)
//   LOAD :  serial data_in_a / data_in_b → banks
//   OUTPUT: sequential read of lower half → data_out
// =============================================================================

`ifndef _NTT_TOP_GUARD
`define _NTT_TOP_GUARD

module ntt_top #(
    parameter B      = 16,
    parameter N      = 256,
    parameter R      = 4,
    parameter LOGN   = $clog2(N),       // 8
    parameter LOGR   = $clog2(R),       // 2
    parameter AWIDTH = LOGN - LOGR,     // 6  (bank address bits)
    parameter DWIDTH = 2 * (B + 1),     // 34 (lower+upper poly word)
    parameter WWIDTH = B + 1            // 17 (one coefficient)
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [WWIDTH-1:0] data_in_a,   // serial poly-a input
    input  wire [WWIDTH-1:0] data_in_b,   // serial poly-b input
    output wire [WWIDTH-1:0] data_out,    // serial output coefficients
    output wire              done
);

    // =========================================================================
    // CONTROL UNIT
    // =========================================================================
    wire [R*LOGN-1:0]  orig_addrs;
    wire [$clog2(2*N)-1:0] tw_step;
    wire               is_Rhat_stage;
    wire [1:0]         rd_sel, wr_sel;
    wire               ntt_mode, pwm_en;
    wire [R-1:0]       ctrl_bank_we;
    wire [2:0]         fsm_state;

    ctrl_unit #(
        .N(N), .R(R), .LOGN(LOGN), .LOGR(LOGR),
        .STAGES(LOGN/LOGR), .DEPTH(N/R), .AWIDTH(AWIDTH)
    ) u_ctrl (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .orig_addrs    (orig_addrs),
        .tw_step       (tw_step),
        .is_Rhat_stage (is_Rhat_stage),
        .rd_sel        (rd_sel),
        .wr_sel        (wr_sel),
        .ntt_mode      (ntt_mode),
        .pwm_en        (pwm_en),
        .bank_we       (ctrl_bank_we),
        .done          (done),
        .fsm_state     (fsm_state)
    );

    localparam ST_IDLE   = 3'd0,
               ST_LOAD   = 3'd1,
               ST_NTT1   = 3'd2,
               ST_NTT2   = 3'd3,
               ST_PWM    = 3'd4,
               ST_INTT   = 3'd5,
               ST_OUTPUT = 3'd6,
               ST_DONE   = 3'd7;

    localparam integer STAGES        = LOGN/LOGR;
    localparam integer R_POW_STAGES  = R ** STAGES;
    localparam integer RHAT          = (R_POW_STAGES != 0) ? (N / R_POW_STAGES) : 1;
    localparam integer R_OVER_RHAT   = (RHAT != 0) ? (R / RHAT) : 1;
    localparam integer SUPPORTS_RHAT = (RHAT > 1) && (R_OVER_RHAT == 2);
    localparam [WWIDTH-1:0] TW_ONE   = {{(WWIDTH-1){1'b0}}, 1'b1};

    function [LOGN-1:0] bit_reverse;
        input [LOGN-1:0] vin;
        input integer bits;
        integer bi;
        begin
            bit_reverse = {LOGN{1'b0}};
            for (bi = 0; bi < LOGN; bi = bi + 1)
                if (bi < bits)
                    bit_reverse[bits - 1 - bi] = vin[bi];
        end
    endfunction

    wire is_load   = (fsm_state == ST_LOAD);
    wire is_output = (fsm_state == ST_OUTPUT) || (fsm_state == ST_DONE);
    wire is_ntt    = (fsm_state == ST_NTT1) || (fsm_state == ST_NTT2);
    wire is_intt   = (fsm_state == ST_INTT);
    wire is_pwm    = (fsm_state == ST_PWM);


    // =========================================================================
    // TWIDDLE FACTOR ROM — outputs R parallel factors
    // =========================================================================
    localparam TW_BITS = $clog2(2*N);

    wire [R*WWIDTH-1:0]  tw_factors;
    wire [$clog2(2*N)-1:0] tw_step_inv = ((2 * N) - tw_step) % (2 * N);
    twiddle_rom #(.B(B), .N(N), .R(R)) u_twrom (
        .tw_step (tw_step),
        .tw_out  (tw_factors)
    );

    wire [R*WWIDTH-1:0] tw_factors_inv;
    twiddle_rom #(.B(B), .N(N), .R(R)) u_twrom_inv (
        .tw_step (tw_step_inv),
        .tw_out  (tw_factors_inv)
    );

    wire [LOGN-1:0] rhat_b = SUPPORTS_RHAT ? (orig_addrs[LOGN-1:0] / RHAT) : {LOGN{1'b0}};
    wire [TW_BITS-1:0] rhat_step0 = SUPPORTS_RHAT ?
        (((2 * bit_reverse(rhat_b, STAGES * LOGR)) + 1) % (2 * N)) : {TW_BITS{1'b0}};
    wire [TW_BITS-1:0] rhat_step1 = SUPPORTS_RHAT ?
        (((2 * bit_reverse(rhat_b + 1'b1, STAGES * LOGR)) + 1) % (2 * N)) : {TW_BITS{1'b0}};

    reg [R*TW_BITS-1:0] rhat_tw_idx_ntt;
    reg [R*TW_BITS-1:0] rhat_tw_idx_intt;
    integer tl;
    integer tr1;
    reg [TW_BITS-1:0] tbase;
    always @(*) begin
        for (tl = 0; tl < R; tl = tl + 1) begin
            tr1 = (R_OVER_RHAT != 0) ? (tl / R_OVER_RHAT) : 0;
            tbase = ((tl % R_OVER_RHAT) == 0) ? rhat_step0 : rhat_step1;
            rhat_tw_idx_ntt[tl*TW_BITS +: TW_BITS]  = (tr1 * tbase) % (2 * N);
            rhat_tw_idx_intt[tl*TW_BITS +: TW_BITS] = ((2 * N) - ((tr1 * tbase) % (2 * N))) % (2 * N);
        end
    end

    wire [R*WWIDTH-1:0] tw_rhat_pack;
    wire [R*WWIDTH-1:0] tw_rhat_pack_inv;
    genvar tg;
    generate
        for (tg = 0; tg < R; tg = tg + 1) begin : gen_tw_lookup_rhat
            twiddle_lookup #(.B(B), .N(N)) u_tw_lookup_ntt (
                .tw_idx (rhat_tw_idx_ntt[tg*TW_BITS +: TW_BITS]),
                .tw_val (tw_rhat_pack[tg*WWIDTH +: WWIDTH])
            );
            twiddle_lookup #(.B(B), .N(N)) u_tw_lookup_intt (
                .tw_idx (rhat_tw_idx_intt[tg*TW_BITS +: TW_BITS]),
                .tw_val (tw_rhat_pack_inv[tg*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    wire [R*WWIDTH-1:0] tw_factors_ntt_sel;
    wire [R*WWIDTH-1:0] tw_factors_intt_sel;
    // is_Rhat_stage_d1 aligns with registered orig_addrs/tw_step (1 cycle late).
    assign tw_factors_ntt_sel  = (is_Rhat_stage_d1 && SUPPORTS_RHAT) ? tw_rhat_pack     : tw_factors;
    assign tw_factors_intt_sel = (is_Rhat_stage_d1 && SUPPORTS_RHAT) ? tw_rhat_pack_inv : tw_factors_inv;

    // =========================================================================
    // ADDRESS GENERATOR  (used during NTT / INTT / PWM)
    // =========================================================================
    wire [LOGR-1:0]       iselect;
    wire [R*AWIDTH-1:0]   bank_addrs_raw;

    addr_gen #(.N(N), .R(R), .LOGN(LOGN), .LOGR(LOGR), .AWIDTH(AWIDTH)) u_addrgen (
        .orig_addr0 (orig_addrs[LOGN-1:0]),
        .orig_addrs (orig_addrs),
        .iselect    (iselect),
        .bank_addrs (bank_addrs_raw)
    );

    // =========================================================================
    // BANK WRITE ADDRESS for the current group
    // (declared early so the delay pipeline below can register it).
    // =========================================================================
    wire [R*AWIDTH-1:0]  ntt_waddr;
    interconnect_bank_addr #(.AWIDTH(AWIDTH), .R(R), .RHAT(RHAT)) u_icon_addr (
        .raw_addrs      (bank_addrs_raw),
        .iselect        (iselect),
        // is_Rhat_stage_d1 aligns with registered orig_addrs (1 cycle late).
        .is_Rhat_stage  (is_Rhat_stage_d1),
        .selected_addrs (ntt_waddr)
    );

    // =========================================================================
    // LOAD / OUTPUT sequential address counter
    // =========================================================================
    reg  [LOGN-1:0]  seq_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst)
            seq_cnt <= 0;
        else if (is_load || is_output)
            seq_cnt <= (seq_cnt == N-1) ? 0 : seq_cnt + 1;
        else
            seq_cnt <= 0;
    end

    wire [AWIDTH-1:0] seq_addr = seq_cnt[LOGN-1:LOGR];
    localparam integer FULL_GROUPS = LOGN / LOGR;
    localparam integer REM_BITS    = LOGN - (FULL_GROUPS * LOGR);
    reg  [LOGR-1:0]   seq_bank;
    reg  [LOGR-1:0]   seq_bank_rem;
    reg  [LOGR+3:0]   seq_bank_acc;
    integer sb_i;
    always @(*) begin
        seq_bank_rem = {LOGR{1'b0}};
        seq_bank_acc = {LOGR+4{1'b0}};
        for (sb_i = 0; sb_i < FULL_GROUPS; sb_i = sb_i + 1)
            seq_bank_acc = seq_bank_acc + seq_cnt[sb_i*LOGR +: LOGR];
        if (REM_BITS > 0) begin
            seq_bank_rem[REM_BITS-1:0] = seq_cnt[FULL_GROUPS*LOGR +: REM_BITS];
            seq_bank_acc = seq_bank_acc + seq_bank_rem;
        end
        seq_bank = seq_bank_acc[LOGR-1:0];
    end

    // =========================================================================
    // MEMORY BANKS
    // =========================================================================
    wire [R*DWIDTH-1:0]  bank_dout;
    wire [R*DWIDTH-1:0]  bank_din;
    wire [R*AWIDTH-1:0]  bank_waddr;
    wire [R-1:0]         bank_we;
    wire [R*AWIDTH-1:0]  bank_raddr;

    mem_banks #(
        .B(B), .N(N), .R(R), .DEPTH(N/R), .DWIDTH(DWIDTH), .AWIDTH(AWIDTH)
    ) u_membanks (
        .clk        (clk),
        .bank_we    (bank_we),
        .bank_waddr (bank_waddr),
        .bank_din   (bank_din),
        .bank_raddr (bank_raddr),
        .bank_dout  (bank_dout)
    );

    // =========================================================================
    // INTERCONNECT: BankOut → Operands  (current cycle's read mapping)
    // =========================================================================
    wire [R*DWIDTH-1:0]  operands_out;
    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R), .RHAT(RHAT)) u_icon_out (
        .bank_data_out (bank_dout),
        .iselect       (iselect),
        // is_Rhat_stage_d1 aligns with registered orig_addrs (1 cycle late).
        .is_Rhat_stage (is_Rhat_stage_d1),
        .operands_out  (operands_out)
    );

    // =========================================================================
    // EXTRACT LOWER / UPPER HALVES from operands
    // =========================================================================
    wire [R*WWIDTH-1:0]  op_lower, op_upper;
    genvar gi;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_op_extract
            assign op_lower[gi*WWIDTH +: WWIDTH] = operands_out[gi*DWIDTH +:         WWIDTH];
            assign op_upper[gi*WWIDTH +: WWIDTH] = operands_out[gi*DWIDTH + WWIDTH +: WWIDTH];
        end
    endgenerate

    // =========================================================================
    // INTT BUTTERFLY PATH (runs BEFORE the shared ModMul, combinational)
    // Paper Fig. 6 INTT path: Banks → Norm→D1 → R2INTT → D1→Norm → ModMul → Banks
    // =========================================================================
    wire [R*WWIDTH-1:0] intt_d1_in;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_intt_n2d1
            norm_to_d1 #(B) u_intt_n2d1 (
                .in  (op_lower[gi*WWIDTH +: WWIDTH]),
                .out (intt_d1_in[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    wire [R*WWIDTH-1:0] intt_d1_out;
    generate
        if (R == 4) begin : gen_r2intt_r4
            wire [WWIDTH-1:0] r2intt_out0, r2intt_out1, r2intt_out2, r2intt_out3;
            r2intt_r4 #(.B(B), .KSHIFT(8), .KSHIFT_INV(8)) u_r2intt (
                .A0 (intt_d1_in[0*WWIDTH +: WWIDTH]),
                .A1 (intt_d1_in[1*WWIDTH +: WWIDTH]),
                .A2 (intt_d1_in[2*WWIDTH +: WWIDTH]),
                .A3 (intt_d1_in[3*WWIDTH +: WWIDTH]),
                .is_Rhat_stage (is_Rhat_stage_d1),
                .a0 (r2intt_out0), .a1(r2intt_out1), .a2(r2intt_out2), .a3(r2intt_out3)
            );
            assign intt_d1_out = {r2intt_out3, r2intt_out2, r2intt_out1, r2intt_out0};
        end else if (R == 8) begin : gen_r2intt_r8
            r2intt_r8 #(.B(B), .N(N)) u_r2intt8 (
                .in_d1        (intt_d1_in),
                .is_Rhat_stage(is_Rhat_stage_d1),
                .out_d1       (intt_d1_out)
            );
        end else if (R == 16) begin : gen_r2intt_r16
            r2intt_r16 #(.B(B)) u_r2intt16 (
                .in_d1        (intt_d1_in),
                .is_Rhat_stage(is_Rhat_stage_d1),
                .out_d1       (intt_d1_out)
            );
        end else begin : gen_r2intt_generic
            r2intt_generic #(.B(B), .N(N), .R(R)) u_r2intt_g (
                .in_d1        (intt_d1_in),
                .is_Rhat_stage(is_Rhat_stage_d1),
                .out_d1       (intt_d1_out)
            );
        end
    endgenerate

    wire [R*WWIDTH-1:0] intt_norm;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_intt_d1n
            wire [WWIDTH-1:0] inn;
            d1_to_norm #(B) u_id1n (.in(intt_d1_out[gi*WWIDTH +: WWIDTH]), .out(inn));
            assign intt_norm[gi*WWIDTH +: WWIDTH] = inn;
        end
    endgenerate

    // =========================================================================
    // SHARED MODMUL BANK — time-shared for NTT, INTT, and PWM phases.
    // R pipelined mod_mul_fermat instances (2-stage), 1 DSP each = R DSPs total.
    //   NTT  : modmul_ntt_in  × tw_factors_ntt_sel
    //   INTT : intt_norm      × tw_factors_intt_sel
    //   PWM  : op_lower       × op_upper
    // =========================================================================
    // _d1 versions align with operands_out (now reflecting the group whose
    // orig_addrs was computed 1 cycle ago in ctrl_unit).
    wire [R*WWIDTH-1:0] modmul_ntt_in = (rd_sel_d1 == 2'b10) ? op_upper : op_lower;

    wire [R*WWIDTH-1:0] mm_in_a = pwm_en_d1   ? op_lower      :
                                   ntt_mode_d1 ? modmul_ntt_in :
                                                 intt_norm;
    wire [R*WWIDTH-1:0] mm_in_b = pwm_en_d1   ? op_upper            :
                                   ntt_mode_d1 ? tw_factors_ntt_sel  :
                                                 tw_factors_intt_sel;

    wire [R*WWIDTH-1:0] mm_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_modmul_shared
            mod_mul_fermat #(B) u_mm (
                .clk    (clk),
                .rst    (rst),
                .a      (mm_in_a[gi*WWIDTH +: WWIDTH]),
                .b      (mm_in_b[gi*WWIDTH +: WWIDTH]),
                .result (mm_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // 3-CYCLE WRITE-BACK DELAY PIPELINE
    // mod_mul_fermat is now 3-stage pipelined (input reg + multiply reg +
    // reduce reg) so write-back control signals are delayed 3 cycles.
    // For R=4 (N=256, 64 groups/stage) and R=8 (N=256, 32 groups/stage +
    // Rhat), one stall cycle between consecutive groups (PIPE_LATENCY=2 in
    // ctrl_unit) is enough to keep the in-bank write/read addresses disjoint.
    // =========================================================================
    // With registered orig_addrs in ctrl_unit, the data flow is 1 cycle late
    // relative to ctrl signals.  Input mux at cycle T+1 uses *_d1 versions of
    // ctrl signals (rd_sel, pwm_en, ntt_mode, is_Rhat_stage) to align with the
    // delayed orig_addrs/iselect/ntt_waddr.  Write-back at cycle T+4 uses *_d4
    // for raw ctrl signals (and *_d3 for the orig_addrs-derived waddr/iselect).
    reg [1:0]          rd_sel_d1;
    reg                pwm_en_d1;
    reg [1:0]          wr_sel_d1,        wr_sel_d2,        wr_sel_d3,        wr_sel_d4;
    reg                ntt_mode_d1,      ntt_mode_d2,      ntt_mode_d3,      ntt_mode_d4;
    reg [R-1:0]        bank_we_d1,       bank_we_d2,       bank_we_d3,       bank_we_d4;
    reg [R*AWIDTH-1:0] ntt_waddr_d1,     ntt_waddr_d2,     ntt_waddr_d3;
    reg [LOGR-1:0]     iselect_d1,       iselect_d2,       iselect_d3;
    reg                is_Rhat_stage_d1, is_Rhat_stage_d2, is_Rhat_stage_d3, is_Rhat_stage_d4;
    reg [R*DWIDTH-1:0] operands_out_d1,  operands_out_d2,  operands_out_d3;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_sel_d1        <= 2'b0;
            pwm_en_d1        <= 1'b0;
            wr_sel_d1        <= 2'b0;          wr_sel_d2        <= 2'b0;          wr_sel_d3        <= 2'b0;          wr_sel_d4        <= 2'b0;
            ntt_mode_d1      <= 1'b0;          ntt_mode_d2      <= 1'b0;          ntt_mode_d3      <= 1'b0;          ntt_mode_d4      <= 1'b0;
            bank_we_d1       <= {R{1'b0}};     bank_we_d2       <= {R{1'b0}};     bank_we_d3       <= {R{1'b0}};     bank_we_d4       <= {R{1'b0}};
            ntt_waddr_d1     <= {R*AWIDTH{1'b0}}; ntt_waddr_d2  <= {R*AWIDTH{1'b0}}; ntt_waddr_d3  <= {R*AWIDTH{1'b0}};
            iselect_d1       <= {LOGR{1'b0}};  iselect_d2       <= {LOGR{1'b0}};  iselect_d3       <= {LOGR{1'b0}};
            is_Rhat_stage_d1 <= 1'b0;          is_Rhat_stage_d2 <= 1'b0;          is_Rhat_stage_d3 <= 1'b0;          is_Rhat_stage_d4 <= 1'b0;
            operands_out_d1  <= {R*DWIDTH{1'b0}}; operands_out_d2 <= {R*DWIDTH{1'b0}}; operands_out_d3 <= {R*DWIDTH{1'b0}};
        end else begin
            rd_sel_d1        <= rd_sel;
            pwm_en_d1        <= pwm_en;
            wr_sel_d1        <= wr_sel;        wr_sel_d2        <= wr_sel_d1;     wr_sel_d3        <= wr_sel_d2;     wr_sel_d4        <= wr_sel_d3;
            ntt_mode_d1      <= ntt_mode;      ntt_mode_d2      <= ntt_mode_d1;   ntt_mode_d3      <= ntt_mode_d2;   ntt_mode_d4      <= ntt_mode_d3;
            bank_we_d1       <= ctrl_bank_we;  bank_we_d2       <= bank_we_d1;    bank_we_d3       <= bank_we_d2;    bank_we_d4       <= bank_we_d3;
            ntt_waddr_d1     <= ntt_waddr;     ntt_waddr_d2     <= ntt_waddr_d1;  ntt_waddr_d3     <= ntt_waddr_d2;
            iselect_d1       <= iselect;       iselect_d2       <= iselect_d1;    iselect_d3       <= iselect_d2;
            is_Rhat_stage_d1 <= is_Rhat_stage; is_Rhat_stage_d2 <= is_Rhat_stage_d1; is_Rhat_stage_d3 <= is_Rhat_stage_d2; is_Rhat_stage_d4 <= is_Rhat_stage_d3;
            operands_out_d1  <= operands_out;  operands_out_d2  <= operands_out_d1; operands_out_d3 <= operands_out_d2;
        end
    end

    // =========================================================================
    // NTT BUTTERFLY PATH (after the shared ModMul, on 2-cycle delayed mm_out)
    // Paper Fig. 6 NTT path: Banks → ModMul → Norm→D1 → R2NTT → D1→Norm → Banks
    // is_Rhat_stage_d3 aligns butterfly mode with the correct group's mm_out.
    // =========================================================================
    wire [R*WWIDTH-1:0] ntt_d1_in;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_ntod1
            wire [WWIDTH-1:0] nd;
            norm_to_d1 #(B) u_nd1 (.in(mm_out[gi*WWIDTH +: WWIDTH]), .out(nd));
            assign ntt_d1_in[gi*WWIDTH +: WWIDTH] = nd;
        end
    endgenerate

    // R2NTT operates on mm_out, which is the ModMul output for FSM cycle T's
    // group (4 cycles ago). is_Rhat_stage_d4 aligns the butterfly mode.
    wire [R*WWIDTH-1:0] ntt_result_d1;
    wire [R*WWIDTH-1:0] ntt_result;
    generate
        if (R == 4) begin : gen_r2ntt_r4
            wire [WWIDTH-1:0] r2ntt_out0, r2ntt_out1, r2ntt_out2, r2ntt_out3;
            r2ntt_r4 #(.B(B), .KSHIFT(8), .KNEG(1)) u_r2ntt (
                .a0 (ntt_d1_in[0*WWIDTH +: WWIDTH]),
                .a1 (ntt_d1_in[1*WWIDTH +: WWIDTH]),
                .a2 (ntt_d1_in[2*WWIDTH +: WWIDTH]),
                .a3 (ntt_d1_in[3*WWIDTH +: WWIDTH]),
                .is_Rhat_stage (is_Rhat_stage_d4),
                .A0 (r2ntt_out0), .A1(r2ntt_out1), .A2(r2ntt_out2), .A3(r2ntt_out3)
            );
            assign ntt_result_d1 = {r2ntt_out3, r2ntt_out2, r2ntt_out1, r2ntt_out0};
        end else if (R == 8) begin : gen_r2ntt_r8
            r2ntt_r8 #(.B(B), .N(N)) u_r2ntt8 (
                .in_d1        (ntt_d1_in),
                .is_Rhat_stage(is_Rhat_stage_d4),
                .out_d1       (ntt_result_d1)
            );
        end else if (R == 16) begin : gen_r2ntt_r16
            r2ntt_r16 #(.B(B)) u_r2ntt16 (
                .in_d1        (ntt_d1_in),
                .is_Rhat_stage(is_Rhat_stage_d4),
                .out_d1       (ntt_result_d1)
            );
        end else begin : gen_r2ntt_generic
            r2ntt_generic #(.B(B), .N(N), .R(R)) u_r2ntt_g (
                .in_d1        (ntt_d1_in),
                .is_Rhat_stage(is_Rhat_stage_d4),
                .out_d1       (ntt_result_d1)
            );
        end
    endgenerate

    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_ntt_d1n
            d1_to_norm #(B) u_ntt_d1n (
                .in  (ntt_result_d1[gi*WWIDTH +: WWIDTH]),
                .out (ntt_result[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // WRITE-DATA MUX (all control signals are 2-cycle delayed)
    //   NTT (ntt_mode_d3=1) : ntt_result (post-butterfly)
    //   INTT / PWM           : mm_out directly (no further butterfly)
    // =========================================================================
    wire [DWIDTH-1:0]    load_word = {data_in_b, data_in_a};

    // ntt_mode_d4/wr_sel_d4 align with FSM cycle T's group (4 cycles in pipeline:
    // 1 for registered orig_addrs + 3 for mod_mul_fermat).  operands_out_d3
    // captures the bank read at cycle T+1 (1 cycle after FSM issue) and
    // delivers it 3 cycles later at T+4 for write-back data preservation.
    wire [R*WWIDTH-1:0]  bfly_result = ntt_mode_d4 ? ntt_result : mm_out;

    wire [R*DWIDTH-1:0]  bfly_data_pre;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_bfly_pack
            wire [WWIDTH-1:0] rw    = bfly_result[gi*WWIDTH +: WWIDTH];
            wire [WWIDTH-1:0] cur_l = operands_out_d3[gi*DWIDTH +:         WWIDTH];
            wire [WWIDTH-1:0] cur_u = operands_out_d3[gi*DWIDTH + WWIDTH +: WWIDTH];
            assign bfly_data_pre[gi*DWIDTH +: DWIDTH] =
                (wr_sel_d4 == 2'b10) ? {rw,    cur_l} :   // update upper only
                (wr_sel_d4 == 2'b01) ? {cur_u, rw   } :   // update lower only
                                        operands_out_d3[gi*DWIDTH +: DWIDTH];
        end
    endgenerate

    // =========================================================================
    // INTERCONNECT: Operands → Banks  (pipelined write-back, uses delayed iselect)
    // =========================================================================
    wire [R*DWIDTH-1:0]  bfly_data_routed;

    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R), .RHAT(RHAT)) u_icon_in (
        .operands_in  (bfly_data_pre),
        // iselect_d3 captures iselect at T+1 (derived from registered orig_addrs)
        // and propagates 3 cycles to T+4.  is_Rhat_stage_d4 aligns with raw ctrl
        // (which is not on the registered-orig_addrs side).
        .iselect      (iselect_d3),
        .is_Rhat_stage(is_Rhat_stage_d4),
        .bank_data_in (bfly_data_routed)
    );

    // LOAD: only the active bank (seq_bank) gets the new word; all others get 0
    wire [R*DWIDTH-1:0]  load_data;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_pack
            assign load_data[gi*DWIDTH +: DWIDTH] =
                (seq_bank == gi[LOGR-1:0]) ? load_word : {DWIDTH{1'b0}};
        end
    endgenerate

    assign bank_din = is_load ? load_data : bfly_data_routed;

    // =========================================================================
    // BANK WRITE ADDRESS  (delayed 2 cycles for pipelined write-back)
    // =========================================================================
    wire [R*AWIDTH-1:0]  load_waddr;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_waddr
            assign load_waddr[gi*AWIDTH +: AWIDTH] = seq_addr;
        end
    endgenerate

    assign bank_waddr = is_load ? load_waddr : ntt_waddr_d3;

    // =========================================================================
    // BANK WRITE ENABLE  (delayed 2 cycles)
    // =========================================================================
    wire [R-1:0] load_we;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_we
            assign load_we[gi] = (seq_bank == gi[LOGR-1:0]);
        end
    endgenerate

    assign bank_we = is_load ? load_we : bank_we_d4;

    // =========================================================================
    // BANK READ ADDRESS  (current cycle — reads ahead of pipelined write-back)
    // =========================================================================
    wire [R*AWIDTH-1:0]  out_raddr;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_out_raddr
            assign out_raddr[gi*AWIDTH +: AWIDTH] = seq_addr;
        end
    endgenerate

    assign bank_raddr = is_output ? out_raddr : ntt_waddr;

    // =========================================================================
    // OUTPUT: serial read from bank seq_bank, lower WWIDTH bits
    // =========================================================================
    reg [WWIDTH-1:0] dout_r;
    always @(*) begin : gen_dout
        integer b;
        dout_r = {WWIDTH{1'b0}};
        for (b = 0; b < R; b = b + 1) begin
            if (seq_bank == b[LOGR-1:0])
                dout_r = bank_dout[b*DWIDTH +: WWIDTH];
        end
    end
    assign data_out = dout_r;

endmodule

`endif // _NTT_TOP_GUARD
