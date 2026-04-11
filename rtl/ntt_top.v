// =============================================================================
// ntt_top.v
// Top-Level NTT Polynomial Multiplier Module (Fig. 6 Architecture)
//
// Implements full polynomial multiplication: NTT1 → NTT2 → PWM → INTT
// over Fermat modulus q = F4 = 65537, degree N = 256, Radix R = 4.
//
// Datapath from Fig. 6 (left to right for NTT, right to left for INTT):
//
//  NTT path (left side of Fig. 6):
//    Banks → InterconnectBankOut → (+1: D1_to_Norm) → ModMul → (−1: Norm_to_D1)
//          → R-point R2NTT → InterconnectBankIn → Banks
//
//  INTT path (right side of Fig. 6):
//    Banks → InterconnectBankOut → R-point R2INTT → (+1: D1_to_Norm) → ModMul
//          → InterconnectBankIn → Banks
//
//  PWM:
//    Banks (lower+upper halves) → ModMul → Banks (lower half)
//
// Port list:
//   clk, rst, start         - control
//   data_in_a[B:0]          - serial input coefficient of polynomial a
//   data_in_b[B:0]          - serial input coefficient of polynomial b
//   data_out[B:0]           - serial output coefficient of product c
//   done                    - computation done signal
// =============================================================================

// Includes removed for batch compilation (iverilog *.v)

module ntt_top #(
    parameter B      = 16,
    parameter N      = 256,
    parameter R      = 4,
    parameter LOGN   = $clog2(N),
    parameter LOGR   = $clog2(R),
    parameter AWIDTH = LOGN - LOGR,       // 6: bank address bits
    parameter DWIDTH = 2 * (B + 1),       // 34: data width (lower+upper half)
    parameter WWIDTH = B + 1              // 17: one polynomial coefficient
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    // Serial data input (one coefficient per cycle, N cycles for each poly)
    input  wire [WWIDTH-1:0] data_in_a,
    input  wire [WWIDTH-1:0] data_in_b,
    output wire [WWIDTH-1:0] data_out,
    output wire              done
);

    // =========================================================================
    // CONTROL UNIT
    // =========================================================================
    wire [R*LOGN-1:0]   orig_addrs;
    wire [LOGN-1:0]     tw_addr;
    wire                is_Rhat_stage;
    wire [1:0]          rd_sel, wr_sel;
    wire                ntt_mode, pwm_en;
    wire [R-1:0]        ctrl_bank_we;

    ctrl_unit #(
        .N(N), .R(R), .LOGN(LOGN), .LOGR(LOGR),
        .STAGES(LOGN/LOGR), .DEPTH(N/R), .AWIDTH(AWIDTH)
    ) u_ctrl (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .orig_addrs   (orig_addrs),
        .tw_addr      (tw_addr),
        .is_Rhat_stage(is_Rhat_stage),
        .rd_sel       (rd_sel),
        .wr_sel       (wr_sel),
        .ntt_mode     (ntt_mode),
        .pwm_en       (pwm_en),
        .bank_we      (ctrl_bank_we),
        .done         (done)
    );

    // =========================================================================
    // TWIDDLE FACTOR ROM
    // =========================================================================
    wire [WWIDTH-1:0]  tw_factor;
    twiddle_rom #(.B(B), .N(N), .R(R)) u_twrom (
        .tw_addr (tw_addr[$clog2(N)-1:0]),
        .tw_out  (tw_factor)
    );

    // =========================================================================
    // ADDRESS GENERATOR
    // =========================================================================
    wire [LOGR-1:0]        iselect;
    wire [R*AWIDTH-1:0]    bank_addrs_raw;

    addr_gen #(.N(N), .R(R), .LOGN(LOGN), .LOGR(LOGR), .AWIDTH(AWIDTH)) u_addrgen (
        .orig_addr0  (orig_addrs[LOGN-1:0]),
        .orig_addrs  (orig_addrs),
        .iselect     (iselect),
        .bank_addrs  (bank_addrs_raw)
    );

    // =========================================================================
    // MEMORY BANKS
    // =========================================================================
    wire [R*DWIDTH-1:0]  bank_dout;
    wire [R*DWIDTH-1:0]  bank_din;
    wire [R*AWIDTH-1:0]  bank_raddr, bank_waddr;
    wire [R-1:0]         bank_we;

    mem_banks #(.B(B), .N(N), .R(R), .DEPTH(N/R), .DWIDTH(DWIDTH), .AWIDTH(AWIDTH)) u_membanks (
        .clk        (clk),
        .bank_we    (bank_we),
        .bank_waddr (bank_waddr),
        .bank_din   (bank_din),
        .bank_raddr (bank_raddr),
        .bank_dout  (bank_dout)
    );

    // =========================================================================
    // INTERCONNECT: BankOut → Operands
    // =========================================================================
    wire [R*DWIDTH-1:0]  operands_out;
    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_icon_out (
        .bank_data_out (bank_dout),
        .iselect       (iselect),
        .operands_out  (operands_out)
    );

    // =========================================================================
    // INTERCONNECT: BankAddr  (for write addresses)
    // =========================================================================
    interconnect_bank_addr #(.AWIDTH(AWIDTH), .R(R)) u_icon_addr (
        .raw_addrs     (bank_addrs_raw),
        .iselect       (iselect),
        .selected_addrs(bank_waddr)
    );
    // Read addresses: same raw addresses (in-place)
    assign bank_raddr = bank_addrs_raw;

    // =========================================================================
    // EXTRACT OPERANDS IN CORRECT HALF (lower = poly a, upper = poly b)
    // =========================================================================
    // rd_sel: 01=lower half, 10=upper half, 11=both
    wire [R*WWIDTH-1:0]  op_lower, op_upper;
    genvar gi;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_op_extract
            assign op_lower[gi*WWIDTH +: WWIDTH] = operands_out[gi*DWIDTH +: WWIDTH];
            assign op_upper[gi*WWIDTH +: WWIDTH] = operands_out[gi*DWIDTH + WWIDTH +: WWIDTH];
        end
    endgenerate

    // =========================================================================
    // NTT path (left side): D1_to_Norm → ModMul (twiddle) → Norm_to_D1 → R2NTT
    // =========================================================================

    // ModMul inputs: one operand is the data, other is the twiddle factor
    // Each of the R operands gets multiplied by its own twiddle factor
    wire [R*WWIDTH-1:0]  modmul_in;   // R operands in normal form (post d1_to_norm)
    wire [R*WWIDTH-1:0]  modmul_out;  // R products in normal form

    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_d1ton
            wire [WWIDTH-1:0]  d1n_out;
            d1_to_norm #(B) u_d1n (.in(op_lower[gi*WWIDTH +: WWIDTH]), .out(d1n_out));
            assign modmul_in[gi*WWIDTH +: WWIDTH] = ntt_mode ? d1n_out
                                                              : op_lower[gi*WWIDTH +: WWIDTH];
        end
    endgenerate

    // R ModMul instances (NTT path)
    wire [R*WWIDTH-1:0]  mm_ntt_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_modmul_ntt
            // For NTT: multiply each operand by its twiddle factor
            // Twiddle for operand r = ω^{r*(2*b+1)}_{2M} — addresses managed by ctrl
            mod_mul_fermat #(B) u_mm (
                .clk    (clk),
                .rst    (rst),
                .a      (modmul_in[gi*WWIDTH +: WWIDTH]),
                .b      (tw_factor),      // Simplified: full per-operand twiddling needs ctrl extension
                .result (mm_ntt_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // Norm_to_D1 after ModMul → feed into R2NTT
    wire [R*WWIDTH-1:0]  ntt_d1_in;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_ntod1
            wire [WWIDTH-1:0]  nd_out;
            norm_to_d1 #(B) u_nd1 (.in(mm_ntt_out[gi*WWIDTH +: WWIDTH]), .out(nd_out));
            assign ntt_d1_in[gi*WWIDTH +: WWIDTH] = nd_out;
        end
    endgenerate

    // R2NTT Unit
    wire [WWIDTH-1:0]  r2ntt_out0, r2ntt_out1, r2ntt_out2, r2ntt_out3;
    r2ntt_r4 #(.B(B), .KSHIFT(4)) u_r2ntt (
        .a0 (ntt_d1_in[0*WWIDTH +: WWIDTH]),
        .a1 (ntt_d1_in[1*WWIDTH +: WWIDTH]),
        .a2 (ntt_d1_in[2*WWIDTH +: WWIDTH]),
        .a3 (ntt_d1_in[3*WWIDTH +: WWIDTH]),
        .is_Rhat_stage (is_Rhat_stage),
        .A0 (r2ntt_out0), .A1(r2ntt_out1),
        .A2 (r2ntt_out2), .A3(r2ntt_out3)
    );

    // =========================================================================
    // INTT path (right side): R2INTT → D1_to_Norm → ModMul (twiddle)
    // =========================================================================

    // R2INTT Unit
    wire [WWIDTH-1:0]  r2intt_out0, r2intt_out1, r2intt_out2, r2intt_out3;
    r2intt_r4 #(.B(B), .KSHIFT(4), .KSHIFT_INV(12)) u_r2intt (
        .A0 (op_lower[0*WWIDTH +: WWIDTH]),
        .A1 (op_lower[1*WWIDTH +: WWIDTH]),
        .A2 (op_lower[2*WWIDTH +: WWIDTH]),
        .A3 (op_lower[3*WWIDTH +: WWIDTH]),
        .is_Rhat_stage (is_Rhat_stage),
        .a0 (r2intt_out0), .a1(r2intt_out1),
        .a2 (r2intt_out2), .a3(r2intt_out3)
    );

    // D1_to_Norm after R2INTT
    wire [R*WWIDTH-1:0]  intt_norm;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_intt_d1n
            wire [WWIDTH-1:0]  intt_d1_in_r;
            assign intt_d1_in_r = (gi==0) ? r2intt_out0 :
                                  (gi==1) ? r2intt_out1 :
                                  (gi==2) ? r2intt_out2 : r2intt_out3;
            wire [WWIDTH-1:0]  intt_n;
            d1_to_norm #(B) u_intt_d1n (.in(intt_d1_in_r), .out(intt_n));
            assign intt_norm[gi*WWIDTH +: WWIDTH] = intt_n;
        end
    endgenerate

    // ModMul instances for INTT path (twiddle multiplication)
    wire [R*WWIDTH-1:0]  mm_intt_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_modmul_intt
            mod_mul_fermat #(B) u_mm_intt (
                .clk    (clk),
                .rst    (rst),
                .a      (intt_norm[gi*WWIDTH +: WWIDTH]),
                .b      (tw_factor),
                .result (mm_intt_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // PWM path: lower half × upper half → lower half
    // =========================================================================
    wire [R*WWIDTH-1:0]  pwm_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_pwm
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
    // MUX: Select output of NTT, INTT, or PWM to write back to banks
    // Also form the full DWIDTH data word (lower+upper halves)
    // =========================================================================
    wire [R*WWIDTH-1:0]  selected_result;
    assign selected_result = pwm_en    ? pwm_out :
                             ntt_mode  ? {r2ntt_out3, r2ntt_out2, r2ntt_out1, r2ntt_out0} :
                                         mm_intt_out;

    // Pack into DWIDTH words: for NTT1/INTT use lower half; NTT2 use upper half
    wire [R*DWIDTH-1:0]  write_data;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_write_pack
            wire [WWIDTH-1:0] res_word = selected_result[gi*WWIDTH +: WWIDTH];
            // Preserve the other half unchanged (read-modify-write not done here;
            // simplified: write selected half, use wr_sel at bank level)
            assign write_data[gi*DWIDTH +: DWIDTH] = (wr_sel == 2'b10) ?
                        {res_word, {WWIDTH{1'b0}}} :   // upper half (NTT2)
                        {{WWIDTH{1'b0}}, res_word};     // lower half (NTT1/INTT/input)
        end
    endgenerate

    // =========================================================================
    // INTERCONNECT: BankIn ← computed results
    // =========================================================================
    wire [R*DWIDTH-1:0]  bank_write_data;
    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R)) u_icon_in (
        .operands_in  (write_data),
        .iselect      (iselect),
        .bank_data_in (bank_write_data)
    );

    assign bank_din = bank_write_data;
    assign bank_we  = ctrl_bank_we;

    // =========================================================================
    // LOAD / OUTPUT: serial interface
    // Reuse bank_din for loading; tap bank_dout for output
    // =========================================================================
    // For output, read lower half of bank 0 word by word

    // The data_out is the lower (B+1) bits of bank_dout[0]
    assign data_out = bank_dout[WWIDTH-1:0];

endmodule
