// =============================================================================
// ntt_top.v  —  NTT Polynomial Multiplier Top Level  (Fig. 6)
//
// Full pipeline:  LOAD → NTT1 → NTT2 → PWM → INTT → OUTPUT
//
// Data-path:
//   LOAD  : serial data_in_a / data_in_b -> banks (simple sequential address)
//   NTT1  : lower half (poly a) through NTT butterfly
//   NTT2  : upper half (poly b) through NTT butterfly
//   PWM   : lower × upper -> lower half
//   INTT  : lower half through INTT butterfly
//   OUTPUT: sequential read of lower half -> data_out
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
    wire [$clog2(2*N)-1:0] tw_step;     // twiddle step = (2*bitrev(b)+1)*delta_idx
    wire               is_Rhat_stage;
    wire [1:0]         rd_sel, wr_sel;
    wire               ntt_mode, pwm_en;
    wire [R-1:0]       ctrl_bank_we;

    // Expose the FSM state so ntt_top can decode LOAD / OUTPUT
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

    wire is_load   = (fsm_state == ST_LOAD);
    wire is_output = (fsm_state == ST_OUTPUT) || (fsm_state == ST_DONE);
    wire is_ntt    = (fsm_state == ST_NTT1) || (fsm_state == ST_NTT2);
    wire is_intt   = (fsm_state == ST_INTT);
    wire is_pwm    = (fsm_state == ST_PWM);


    // =========================================================================
    // TWIDDLE FACTOR ROM — outputs R parallel factors
    // =========================================================================
    wire [R*WWIDTH-1:0]  tw_factors;  // R twiddle values: tw_factors[r] for element r
    wire [$clog2(2*N)-1:0] tw_step_inv = ((2 * N) - tw_step) % (2 * N);
    twiddle_rom #(.B(B), .N(N), .R(R)) u_twrom (
        .tw_step (tw_step),
        .tw_out  (tw_factors)
    );

    // INTT needs inverse twiddles (omega^{-k})
    wire [R*WWIDTH-1:0] tw_factors_inv;
    twiddle_rom #(.B(B), .N(N), .R(R)) u_twrom_inv (
        .tw_step (tw_step_inv),
        .tw_out  (tw_factors_inv)
    );

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
    // LOAD / OUTPUT sequential address counter
    // Each cycle during LOAD: address = load_cnt / R, bank = load_cnt % R
    // Each cycle during OUTPUT: same pattern, read-only
    // =========================================================================
    reg  [LOGN-1:0]  seq_cnt;   // counts 0..N-1 during LOAD and OUTPUT
    always @(posedge clk or posedge rst) begin
        if (rst)
            seq_cnt <= 0;
        else if (is_load || is_output)
            seq_cnt <= (seq_cnt == N-1) ? 0 : seq_cnt + 1;
        else
            seq_cnt <= 0;
    end

    wire [AWIDTH-1:0] seq_addr = seq_cnt[LOGN-1:LOGR];   // upper bits = row
    // Bank mapping must match addr_gen's conflict-free layout (sum of LOGR-bit groups mod R).
    reg  [LOGR-1:0]   seq_bank;
    reg  [LOGR+3:0]   seq_bank_acc;
    integer sb_i;
    always @(*) begin
        seq_bank_acc = {LOGR+4{1'b0}};
        for (sb_i = 0; sb_i < LOGN/LOGR; sb_i = sb_i + 1)
            seq_bank_acc = seq_bank_acc + seq_cnt[sb_i*LOGR +: LOGR];
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
    // INTERCONNECT: BankOut → Operands  (NTT/INTT/PWM)
    // =========================================================================
    wire [R*DWIDTH-1:0]  operands_out;
    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_icon_out (
        .bank_data_out (bank_dout),
        .iselect       (iselect),
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
    // NTT PATH:  Norm → ModMul (twiddle) → Norm→D1 → R2NTT → D1→Norm
    // rd_sel selects which polynomial half is read by NTT:
    //   2'b01 -> lower (NTT1), 2'b10 -> upper (NTT2)
    // =========================================================================
    wire [R*WWIDTH-1:0]  modmul_ntt_in = (rd_sel == 2'b10) ? op_upper : op_lower;

    wire [R*WWIDTH-1:0]  mm_ntt_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_modmul_ntt
            mod_mul_fermat #(B) u_mm (
                .clk    (clk),
                .rst    (rst),
                .a      (modmul_ntt_in[gi*WWIDTH +: WWIDTH]),
                .b      (tw_factors[gi*WWIDTH +: WWIDTH]),  // per-element twiddle
                .result (mm_ntt_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    wire [R*WWIDTH-1:0]  ntt_d1_in;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_ntod1
            wire [WWIDTH-1:0] nd;
            norm_to_d1 #(B) u_nd1 (.in(mm_ntt_out[gi*WWIDTH +: WWIDTH]), .out(nd));
            assign ntt_d1_in[gi*WWIDTH +: WWIDTH] = nd;
        end
    endgenerate

    wire [WWIDTH-1:0] r2ntt_out0, r2ntt_out1, r2ntt_out2, r2ntt_out3;
    r2ntt_r4 #(.B(B), .KSHIFT(8), .KNEG(1)) u_r2ntt (
        .a0 (ntt_d1_in[0*WWIDTH +: WWIDTH]),
        .a1 (ntt_d1_in[1*WWIDTH +: WWIDTH]),
        .a2 (ntt_d1_in[2*WWIDTH +: WWIDTH]),
        .a3 (ntt_d1_in[3*WWIDTH +: WWIDTH]),
        .is_Rhat_stage (is_Rhat_stage),
        .A0 (r2ntt_out0), .A1(r2ntt_out1), .A2(r2ntt_out2), .A3(r2ntt_out3)
    );

    // Convert NTT outputs back to normal representation before write-back.
    wire [R*WWIDTH-1:0] ntt_result_d1;
    wire [R*WWIDTH-1:0] ntt_result;
    assign ntt_result_d1 = {r2ntt_out3, r2ntt_out2, r2ntt_out1, r2ntt_out0};
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_ntt_d1n
            d1_to_norm #(B) u_ntt_d1n (
                .in  (ntt_result_d1[gi*WWIDTH +: WWIDTH]),
                .out (ntt_result[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // INTT PATH:  R2INTT → D1→Norm → ModMul (twiddle)
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

    wire [WWIDTH-1:0] r2intt_out0, r2intt_out1, r2intt_out2, r2intt_out3;
    r2intt_r4 #(.B(B), .KSHIFT(8), .KSHIFT_INV(8)) u_r2intt (
        .A0 (intt_d1_in[0*WWIDTH +: WWIDTH]),
        .A1 (intt_d1_in[1*WWIDTH +: WWIDTH]),
        .A2 (intt_d1_in[2*WWIDTH +: WWIDTH]),
        .A3 (intt_d1_in[3*WWIDTH +: WWIDTH]),
        .is_Rhat_stage (is_Rhat_stage),
        .a0 (r2intt_out0), .a1(r2intt_out1), .a2(r2intt_out2), .a3(r2intt_out3)
    );

    wire [R*WWIDTH-1:0] intt_d1_out;
    assign intt_d1_out = {r2intt_out3, r2intt_out2, r2intt_out1, r2intt_out0};

    wire [R*WWIDTH-1:0] intt_norm;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_intt_d1n
            wire [WWIDTH-1:0] inn;
            d1_to_norm #(B) u_id1n (.in(intt_d1_out[gi*WWIDTH +: WWIDTH]), .out(inn));
            assign intt_norm[gi*WWIDTH +: WWIDTH] = inn;
        end
    endgenerate

    wire [R*WWIDTH-1:0] mm_intt_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_modmul_intt
            mod_mul_fermat #(B) u_mm_intt (
                .clk    (clk),
                .rst    (rst),
                .a      (intt_norm[gi*WWIDTH +: WWIDTH]),
                .b      (tw_factors_inv[gi*WWIDTH +: WWIDTH]),
                .result (mm_intt_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // PWM PATH:  lower × upper → lower (normal representation)
    // =========================================================================
    wire [R*WWIDTH-1:0] pwm_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_pwm_mul
            mod_mul_fermat #(B) u_mm_pwm (
                .clk    (clk),
                .rst    (rst),
                .a      (op_lower[gi*WWIDTH +: WWIDTH]),
                .b      (op_upper[gi*WWIDTH +: WWIDTH]),
                .result (pwm_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // WRITE-DATA MUX
    //   LOAD   : pack data_in_a (lower) + data_in_b (upper) into one word
    //   NTT1   : NTT butterfly result → lower half
    //   NTT2   : NTT butterfly result → upper half
    //   INTT   : INTT+ModMul result   → lower half
    //   PWM    : PWM result            → lower half
    // =========================================================================
    wire [DWIDTH-1:0]    load_word = {data_in_b, data_in_a};

    // Butterfly result selection (shared across R elements)
    // NOTE: pwm_out and mm_intt_out are pipelined by 2 cycles (mod_mul_fermat);
    //       ntt_result is combinational (r2ntt adds only shift+add, no registers).
    //       For NTT stages: result is available immediately, no latency.
    //       For INTT and PWM: ModMul adds 2-cycle latency — controlled by stalls
    //       in ctrl_unit via PIPE_LATENCY. Since ctrl_unit doesn't currently stall,
    //       we use the combinational NTT result for NTT1/NTT2.
    wire [R*WWIDTH-1:0]  bfly_result = pwm_en    ? pwm_out :
                                        ntt_mode  ? ntt_result :
                                                    mm_intt_out;

    // Pack butterfly results into DWIDTH words (preserve the appropriate half)
    wire [R*DWIDTH-1:0]  bfly_data_pre;   // before bank-in interconnect routing
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_bfly_pack
            wire [WWIDTH-1:0] rw = bfly_result[gi*WWIDTH +: WWIDTH];
            wire [WWIDTH-1:0] cur_l = op_lower[gi*WWIDTH +: WWIDTH];
            wire [WWIDTH-1:0] cur_u = op_upper[gi*WWIDTH +: WWIDTH];
            // Preserve the non-target half to avoid corrupting the other polynomial.
            assign bfly_data_pre[gi*DWIDTH +: DWIDTH] =
                (wr_sel == 2'b10) ? {rw,    cur_l} :   // update upper only
                (wr_sel == 2'b01) ? {cur_u, rw   } :   // update lower only
                                    operands_out[gi*DWIDTH +: DWIDTH];
        end
    endgenerate

    // =========================================================================
    // INTERCONNECT: Operands → Banks  (NTT/INTT/PWM write-back)
    // BUG FIX: butterfly results must be inverse-circularly-shifted before
    // writing back, so operand[k] lands in bank[(iselect+k)%R].
    // =========================================================================
    wire [R*DWIDTH-1:0]  bfly_data_routed;

    // With combinational ModMul, iselect is valid for the same cycle's results.
    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R)) u_icon_in (
        .operands_in  (bfly_data_pre),
        .iselect      (iselect),
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

    // Final bank_din mux
    assign bank_din = is_load ? load_data : bfly_data_routed;

    // =========================================================================
    // BANK WRITE ADDRESS  (combinational path: no pipeline delay)
    // =========================================================================
    wire [R*AWIDTH-1:0]  ntt_waddr;
    interconnect_bank_addr #(.AWIDTH(AWIDTH), .R(R)) u_icon_addr (
        .raw_addrs      (bank_addrs_raw),
        .iselect        (iselect),
        .selected_addrs (ntt_waddr)
    );

    // During LOAD, all banks get seq_addr (only one is enabled via bank_we)
    wire [R*AWIDTH-1:0]  load_waddr;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_waddr
            assign load_waddr[gi*AWIDTH +: AWIDTH] = seq_addr;
        end
    endgenerate

    assign bank_waddr = is_load ? load_waddr : ntt_waddr;

    // =========================================================================
    // BANK WRITE ENABLE  (direct from ctrl_unit each cycle)
    // =========================================================================
    wire [R-1:0] load_we;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_we
            assign load_we[gi] = (seq_bank == gi[LOGR-1:0]);
        end
    endgenerate

    assign bank_we = is_load ? load_we : ctrl_bank_we;

    // =========================================================================
    // BANK READ ADDRESS
    //   NTT/INTT/PWM : from mapped addresses (Algorithm 7, InterconnectBankAddr)
    //   OUTPUT        : sequential scan, overriding bank_raddr
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
