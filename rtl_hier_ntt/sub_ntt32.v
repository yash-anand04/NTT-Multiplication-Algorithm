// =============================================================================
// sub_ntt32.v   (Phase B.1)
// Pipelined 32-point shift-only NTT/INTT over Fermat modulus q = 2^B + 1.
//
//   - Forward path (inverse=0): DIT, natural-order I/O. Internally feeds
//     in_norm through 5 DIT substages, then re-orders bit-rev -> natural.
//   - Inverse path (inverse=1): DIF, natural-order I/O. Internally
//     pre-permutes in_norm bit-reversed, runs 5 DIF substages.
//
// Throughput: 1 sub-NTT / cycle.
// Latency:    6 cycles between `start` rising and `valid` rising
//             (1 input register + 5 substage registers).  The input register
//             is kept to shorten the longest combinational path
//             in_norm -> norm_to_d1 -> butterfly -> register, easing Fmax
//             closure on U280 above 350 MHz.
//
// Shift-only: all twiddles are powers of 2 (mod sign), so each butterfly
// is built from d1_mul_by_2k + d1_add + d1_sub. ZERO DSPs required.
// =============================================================================

`ifndef _SUB_NTT32_GUARD
`define _SUB_NTT32_GUARD

(* USE_DSP = "no" *)
module sub_ntt32 #(
    parameter B      = 16,
    parameter WWIDTH = B + 1
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,        // asserted same cycle as in_norm
    input  wire                  inverse,
    input  wire [32*WWIDTH-1:0]  in_norm,
    output wire [32*WWIDTH-1:0]  out_norm,
    output wire                  valid
);
    localparam integer R = 32;

    // -------------------------------------------------------------------------
    // bit_reverse5: 5-bit bit reversal
    // -------------------------------------------------------------------------
    function integer bit_reverse5;
        input integer val;
        integer bi;
        begin
            bit_reverse5 = 0;
            for (bi = 0; bi < 5; bi = bi + 1)
                bit_reverse5 = (bit_reverse5 << 1) | ((val >> bi) & 1);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Twiddle helpers shared with r2ntt_r32 / r2intt_r32
    //   omega_32 = 2^WEXP, WEXP = 19 mod 2B
    // -------------------------------------------------------------------------
    localparam integer WEXP = 19;

    function integer tw_mod;
        input integer exp;
        integer t;
        begin
            t = (WEXP * exp) % (2 * B);
            if (t < 0) t = t + (2 * B);
            tw_mod = t;
        end
    endfunction
    function integer tw_k;
        input integer exp;
        integer t;
        begin t = tw_mod(exp); tw_k = (t >= B) ? (t - B) : t; end
    endfunction
    function integer tw_neg;
        input integer exp;
        integer t;
        begin t = tw_mod(exp); tw_neg = (t >= B) ? 1 : 0; end
    endfunction
    function integer twinv_mod;
        input integer exp;
        begin twinv_mod = ((2 * B) - tw_mod(exp)) % (2 * B); end
    endfunction
    function integer twinv_k;
        input integer exp;
        integer t;
        begin t = twinv_mod(exp); twinv_k = (t >= B) ? (t - B) : t; end
    endfunction
    function integer twinv_neg;
        input integer exp;
        integer t;
        begin t = twinv_mod(exp); twinv_neg = (t >= B) ? 1 : 0; end
    endfunction

    // -------------------------------------------------------------------------
    // Per-lane norm_to_d1 (combinational, on inputs)
    //
    // Forward path uses natural order; inverse path uses bit-reversed order.
    // -------------------------------------------------------------------------
    wire [B:0] fwd_d1 [0:R-1];
    wire [B:0] inv_d1 [0:R-1];

    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_in_conv
            localparam integer BR = bit_reverse5(i);
            norm_to_d1 #(B) u_fwd_n2d (
                .in  (in_norm[i*WWIDTH +: WWIDTH]),
                .out (fwd_d1[i])
            );
            norm_to_d1 #(B) u_inv_n2d (
                .in  (in_norm[BR*WWIDTH +: WWIDTH]),
                .out (inv_d1[i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // FORWARD DIT pipeline (5 substages, registered after each)
    //
    //   stage layout:
    //     fwd_reg[0] = registered fwd_d1 (input sample)
    //     fwd_reg[1] = after substage s=0  (delta=16, twiddle=1)
    //     fwd_reg[2] = after substage s=1  (delta=8)
    //     fwd_reg[3] = after substage s=2  (delta=4)
    //     fwd_reg[4] = after substage s=3  (delta=2)
    //     fwd_reg[5] = after substage s=4  (delta=1, bit-reversed)
    // -------------------------------------------------------------------------
    reg  [B:0] fwd_reg0 [0:R-1];
    reg  [B:0] fwd_reg1 [0:R-1];
    reg  [B:0] fwd_reg2 [0:R-1];
    reg  [B:0] fwd_reg3 [0:R-1];
    reg  [B:0] fwd_reg4 [0:R-1];
    wire [B:0] fwd_s0  [0:R-1];
    wire [B:0] fwd_s1  [0:R-1];
    wire [B:0] fwd_s2  [0:R-1];
    wire [B:0] fwd_s3  [0:R-1];
    wire [B:0] fwd_s4  [0:R-1];

    // Substage 0: delta=16, twiddle = 1 for all 16 groups
    genvar g0;
    generate
        for (g0 = 0; g0 < 16; g0 = g0 + 1) begin : gen_fwd_s0
            r2_butterfly #(.B(B), .K(0), .NEG(0)) u_bf (
                .a     (fwd_reg0[g0]),
                .b     (fwd_reg0[g0 + 16]),
                .a_out (fwd_s0[g0]),
                .b_out (fwd_s0[g0 + 16])
            );
        end
    endgenerate

    // Substage 1: delta=8, 2 groups, E = bit_reverse_small(b,1)*8
    genvar b1, j1;
    generate
        for (b1 = 0; b1 < 2; b1 = b1 + 1) begin : gen_fwd_s1_b
            for (j1 = 0; j1 < 8; j1 = j1 + 1) begin : gen_fwd_s1_g
                localparam integer IDX = b1 * 16 + j1;
                localparam integer E   = (b1 == 0) ? 0 : 8;   // bitrev1(b1)*8
                r2_butterfly #(.B(B), .K(tw_k(E)), .NEG(tw_neg(E))) u_bf (
                    .a     (fwd_reg1[IDX]),
                    .b     (fwd_reg1[IDX + 8]),
                    .a_out (fwd_s1[IDX]),
                    .b_out (fwd_s1[IDX + 8])
                );
            end
        end
    endgenerate

    // Substage 2: delta=4, 4 groups, E = bitrev2(b)*4
    function integer bitrev2;
        input integer v;
        begin bitrev2 = ((v & 1) << 1) | ((v >> 1) & 1); end
    endfunction
    genvar b2, j2;
    generate
        for (b2 = 0; b2 < 4; b2 = b2 + 1) begin : gen_fwd_s2_b
            for (j2 = 0; j2 < 4; j2 = j2 + 1) begin : gen_fwd_s2_g
                localparam integer IDX = b2 * 8 + j2;
                localparam integer E   = bitrev2(b2) * 4;
                r2_butterfly #(.B(B), .K(tw_k(E)), .NEG(tw_neg(E))) u_bf (
                    .a     (fwd_reg2[IDX]),
                    .b     (fwd_reg2[IDX + 4]),
                    .a_out (fwd_s2[IDX]),
                    .b_out (fwd_s2[IDX + 4])
                );
            end
        end
    endgenerate

    // Substage 3: delta=2, 8 groups, E = bitrev3(b)*2
    function integer bitrev3;
        input integer v;
        begin bitrev3 = ((v & 1) << 2) | ((v >> 1) & 1) << 1 | ((v >> 2) & 1); end
    endfunction
    genvar b3, j3;
    generate
        for (b3 = 0; b3 < 8; b3 = b3 + 1) begin : gen_fwd_s3_b
            for (j3 = 0; j3 < 2; j3 = j3 + 1) begin : gen_fwd_s3_g
                localparam integer IDX = b3 * 4 + j3;
                localparam integer E   = bitrev3(b3) * 2;
                r2_butterfly #(.B(B), .K(tw_k(E)), .NEG(tw_neg(E))) u_bf (
                    .a     (fwd_reg3[IDX]),
                    .b     (fwd_reg3[IDX + 2]),
                    .a_out (fwd_s3[IDX]),
                    .b_out (fwd_s3[IDX + 2])
                );
            end
        end
    endgenerate

    // Substage 4: delta=1, 16 groups, E = bitrev4(b)
    function integer bitrev4;
        input integer v;
        integer bi, r;
        begin
            r = 0;
            for (bi = 0; bi < 4; bi = bi + 1)
                r = (r << 1) | ((v >> bi) & 1);
            bitrev4 = r;
        end
    endfunction
    genvar b4;
    generate
        for (b4 = 0; b4 < 16; b4 = b4 + 1) begin : gen_fwd_s4
            localparam integer IDX = b4 * 2;
            localparam integer E   = bitrev4(b4);
            r2_butterfly #(.B(B), .K(tw_k(E)), .NEG(tw_neg(E))) u_bf (
                .a     (fwd_reg4[IDX]),
                .b     (fwd_reg4[IDX + 1]),
                .a_out (fwd_s4[IDX]),
                .b_out (fwd_s4[IDX + 1])
            );
        end
    endgenerate

    // Pipeline registers for forward path
    reg  [B:0] fwd_reg5 [0:R-1];
    integer ridx;
    always @(posedge clk) begin
        if (rst) begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                fwd_reg0[ridx] <= {WWIDTH{1'b0}};
                fwd_reg1[ridx] <= {WWIDTH{1'b0}};
                fwd_reg2[ridx] <= {WWIDTH{1'b0}};
                fwd_reg3[ridx] <= {WWIDTH{1'b0}};
                fwd_reg4[ridx] <= {WWIDTH{1'b0}};
                fwd_reg5[ridx] <= {WWIDTH{1'b0}};
            end
        end else begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                fwd_reg0[ridx] <= fwd_d1[ridx];
                fwd_reg1[ridx] <= fwd_s0[ridx];
                fwd_reg2[ridx] <= fwd_s1[ridx];
                fwd_reg3[ridx] <= fwd_s2[ridx];
                fwd_reg4[ridx] <= fwd_s3[ridx];
                fwd_reg5[ridx] <= fwd_s4[ridx];
            end
        end
    end

    // -------------------------------------------------------------------------
    // INVERSE DIF pipeline (5 substages, registered after each)
    //   DIF order: s=0 has delta=1, s=4 has delta=16.
    //   Input is pre-bit-reversed (via inv_d1[i] = norm_to_d1(in_norm[bitrev5(i)])).
    // -------------------------------------------------------------------------
    reg  [B:0] inv_reg0 [0:R-1];
    reg  [B:0] inv_reg1 [0:R-1];
    reg  [B:0] inv_reg2 [0:R-1];
    reg  [B:0] inv_reg3 [0:R-1];
    reg  [B:0] inv_reg4 [0:R-1];
    reg  [B:0] inv_reg5 [0:R-1];
    wire [B:0] inv_s0  [0:R-1];
    wire [B:0] inv_s1  [0:R-1];
    wire [B:0] inv_s2  [0:R-1];
    wire [B:0] inv_s3  [0:R-1];
    wire [B:0] inv_s4  [0:R-1];

    // DIF substage 0: delta=1, 16 groups, E = bitrev4(b)
    genvar ib0;
    generate
        for (ib0 = 0; ib0 < 16; ib0 = ib0 + 1) begin : gen_inv_s0
            localparam integer IDX = ib0 * 2;
            localparam integer E   = bitrev4(ib0);
            r2intt_butterfly_pow2 #(.B(B), .K(twinv_k(E)), .NEG(twinv_neg(E))) u_bf (
                .a     (inv_reg0[IDX]),
                .b     (inv_reg0[IDX + 1]),
                .a_out (inv_s0[IDX]),
                .b_out (inv_s0[IDX + 1])
            );
        end
    endgenerate

    // DIF substage 1: delta=2, 8 groups, E = bitrev3(b)*2
    genvar ib1, ij1;
    generate
        for (ib1 = 0; ib1 < 8; ib1 = ib1 + 1) begin : gen_inv_s1_b
            for (ij1 = 0; ij1 < 2; ij1 = ij1 + 1) begin : gen_inv_s1_g
                localparam integer IDX = ib1 * 4 + ij1;
                localparam integer E   = bitrev3(ib1) * 2;
                r2intt_butterfly_pow2 #(.B(B), .K(twinv_k(E)), .NEG(twinv_neg(E))) u_bf (
                    .a     (inv_reg1[IDX]),
                    .b     (inv_reg1[IDX + 2]),
                    .a_out (inv_s1[IDX]),
                    .b_out (inv_s1[IDX + 2])
                );
            end
        end
    endgenerate

    // DIF substage 2: delta=4, 4 groups, E = bitrev2(b)*4
    genvar ib2, ij2;
    generate
        for (ib2 = 0; ib2 < 4; ib2 = ib2 + 1) begin : gen_inv_s2_b
            for (ij2 = 0; ij2 < 4; ij2 = ij2 + 1) begin : gen_inv_s2_g
                localparam integer IDX = ib2 * 8 + ij2;
                localparam integer E   = bitrev2(ib2) * 4;
                r2intt_butterfly_pow2 #(.B(B), .K(twinv_k(E)), .NEG(twinv_neg(E))) u_bf (
                    .a     (inv_reg2[IDX]),
                    .b     (inv_reg2[IDX + 4]),
                    .a_out (inv_s2[IDX]),
                    .b_out (inv_s2[IDX + 4])
                );
            end
        end
    endgenerate

    // DIF substage 3: delta=8, 2 groups, E = bitrev1(b)*8
    genvar ib3, ij3;
    generate
        for (ib3 = 0; ib3 < 2; ib3 = ib3 + 1) begin : gen_inv_s3_b
            for (ij3 = 0; ij3 < 8; ij3 = ij3 + 1) begin : gen_inv_s3_g
                localparam integer IDX = ib3 * 16 + ij3;
                localparam integer E   = (ib3 == 0) ? 0 : 8;
                r2intt_butterfly_pow2 #(.B(B), .K(twinv_k(E)), .NEG(twinv_neg(E))) u_bf (
                    .a     (inv_reg3[IDX]),
                    .b     (inv_reg3[IDX + 8]),
                    .a_out (inv_s3[IDX]),
                    .b_out (inv_s3[IDX + 8])
                );
            end
        end
    endgenerate

    // DIF substage 4: delta=16, twiddle=1
    genvar ig4;
    generate
        for (ig4 = 0; ig4 < 16; ig4 = ig4 + 1) begin : gen_inv_s4
            r2intt_butterfly_pow2 #(.B(B), .K(0), .NEG(0)) u_bf (
                .a     (inv_reg4[ig4]),
                .b     (inv_reg4[ig4 + 16]),
                .a_out (inv_s4[ig4]),
                .b_out (inv_s4[ig4 + 16])
            );
        end
    endgenerate

    integer iidx;
    always @(posedge clk) begin
        if (rst) begin
            for (iidx = 0; iidx < R; iidx = iidx + 1) begin
                inv_reg0[iidx] <= {WWIDTH{1'b0}};
                inv_reg1[iidx] <= {WWIDTH{1'b0}};
                inv_reg2[iidx] <= {WWIDTH{1'b0}};
                inv_reg3[iidx] <= {WWIDTH{1'b0}};
                inv_reg4[iidx] <= {WWIDTH{1'b0}};
                inv_reg5[iidx] <= {WWIDTH{1'b0}};
            end
        end else begin
            for (iidx = 0; iidx < R; iidx = iidx + 1) begin
                inv_reg0[iidx] <= inv_d1[iidx];
                inv_reg1[iidx] <= inv_s0[iidx];
                inv_reg2[iidx] <= inv_s1[iidx];
                inv_reg3[iidx] <= inv_s2[iidx];
                inv_reg4[iidx] <= inv_s3[iidx];
                inv_reg5[iidx] <= inv_s4[iidx];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Valid + inverse-select shift register
    //
    // Data pipeline depth = 1 input register (fwd_reg0/inv_reg0) + 5 substage
    // registers (fwd_reg1..5 / inv_reg1..5) = 6 register stages = 6 cycles
    // latency from `start` to `valid`.  valid_pipe and inv_pipe must match.
    // -------------------------------------------------------------------------
    reg [5:0] valid_pipe;
    reg [5:0] inv_pipe;
    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= 6'b0;
            inv_pipe   <= 6'b0;
        end else begin
            valid_pipe <= {valid_pipe[4:0], start};
            inv_pipe   <= {inv_pipe[4:0],   inverse & start};
        end
    end
    assign valid = valid_pipe[5];

    // -------------------------------------------------------------------------
    // Output stage: select forward vs inverse, convert d1->norm, undo
    // forward bit-reversal so out_norm[i] = naturally-indexed frequency i.
    // -------------------------------------------------------------------------
    wire [B:0] sel [0:R-1];
    genvar so;
    generate
        for (so = 0; so < R; so = so + 1) begin : gen_sel
            localparam integer BR = bit_reverse5(so);
            // Forward path: fwd_reg5 holds bit-reversed natural-frequency order;
            //   we read fwd_reg5[BR(so)] to deliver out_norm[so] in natural order.
            // Inverse path: inv_reg5 is already in natural time order.
            assign sel[so] = inv_pipe[5] ? inv_reg5[so] : fwd_reg5[BR];
        end
    endgenerate

    genvar oi;
    generate
        for (oi = 0; oi < R; oi = oi + 1) begin : gen_out_conv
            wire [B:0] norm_out;
            d1_to_norm #(B) u_d2n (.in(sel[oi]), .out(norm_out));
            assign out_norm[oi*WWIDTH +: WWIDTH] = norm_out;
        end
    endgenerate

endmodule

`endif // _SUB_NTT32_GUARD
