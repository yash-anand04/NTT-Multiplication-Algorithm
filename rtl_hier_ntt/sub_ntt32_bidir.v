// =============================================================================
// sub_ntt32_bidir.v
// Unified DIT 32-pt shift-only NTT/INTT.  Replaces sub_ntt32.v.
//
// Key idea: INTT = NTT-with-inverse-twiddles / N.  Both directions therefore
// share a single DIT pipeline; only the per-stage twiddle K/NEG values are
// runtime-muxed, and a 1/N circular shift is applied at the output when
// `inverse` is set.
//
// Same external contract as sub_ntt32:
//   - 1 input register + 5 DIT substage registers = 6-cycle latency
//   - Throughput 1 sub-NTT / cycle
//   - Natural-order I/O on both sides
//
// Versus the prior sub_ntt32 (~26 K LUT on U280 due to parallel fwd+inv
// pipelines and a heavy output mux), this version cuts the butterfly count
// from 160 to 80 and the pipeline register width in half.
// =============================================================================

`ifndef _SUB_NTT32_BIDIR_GUARD
`define _SUB_NTT32_BIDIR_GUARD

(* USE_DSP = "no" *)
module sub_ntt32_bidir #(
    parameter B      = 16,
    parameter WWIDTH = B + 1
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,
    input  wire                  inverse,
    input  wire [32*WWIDTH-1:0]  in_norm,
    output wire [32*WWIDTH-1:0]  out_norm,
    output wire                  valid
);
    localparam integer R    = 32;
    localparam integer WEXP = 19;

    // -------------------------------------------------------------------------
    // Helpers (copied unchanged from sub_ntt32)
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
        integer t; begin t = tw_mod(exp); tw_k = (t >= B) ? (t - B) : t; end
    endfunction
    function integer tw_neg;
        input integer exp;
        integer t; begin t = tw_mod(exp); tw_neg = (t >= B) ? 1 : 0; end
    endfunction
    function integer twinv_mod;
        input integer exp;
        begin twinv_mod = ((2 * B) - tw_mod(exp)) % (2 * B); end
    endfunction
    function integer twinv_k;
        input integer exp;
        integer t; begin t = twinv_mod(exp); twinv_k = (t >= B) ? (t - B) : t; end
    endfunction
    function integer twinv_neg;
        input integer exp;
        integer t; begin t = twinv_mod(exp); twinv_neg = (t >= B) ? 1 : 0; end
    endfunction

    function integer bitrev2;
        input integer v;
        begin bitrev2 = ((v & 1) << 1) | ((v >> 1) & 1); end
    endfunction
    function integer bitrev3;
        input integer v;
        begin bitrev3 = ((v & 1) << 2) | (((v >> 1) & 1) << 1) | ((v >> 2) & 1); end
    endfunction
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

    // -------------------------------------------------------------------------
    // Single input register (natural order, both fwd and inv)
    // -------------------------------------------------------------------------
    wire [B:0] d1_in [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_in_conv
            norm_to_d1 #(B) u_n2d (
                .in  (in_norm[i*WWIDTH +: WWIDTH]),
                .out (d1_in[i])
            );
        end
    endgenerate

    reg [B:0] reg0 [0:R-1];
    wire [B:0] s0 [0:R-1];
    wire [B:0] s1 [0:R-1];
    wire [B:0] s2 [0:R-1];
    wire [B:0] s3 [0:R-1];
    wire [B:0] s4 [0:R-1];
    reg [B:0] reg1 [0:R-1];
    reg [B:0] reg2 [0:R-1];
    reg [B:0] reg3 [0:R-1];
    reg [B:0] reg4 [0:R-1];
    reg [B:0] reg5 [0:R-1];

    // -------------------------------------------------------------------------
    // Per-stage inverse-mode pipe: each stage's butterfly inputs are taken
    // from the previous registered output, so the `inverse` flag must travel
    // alongside.  inv_pipe[s] indicates whether the issue currently AT stage s
    // is an inverse one.
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
    // Substage 0: delta=16, twiddle = 1 for all 16 groups  (E = 0 always)
    //   → fwd and inv K/NEG both zero, no actual mux needed; could use the
    //     plain r2_butterfly, but use bidir for uniformity.
    // -------------------------------------------------------------------------
    genvar g0;
    generate
        for (g0 = 0; g0 < 16; g0 = g0 + 1) begin : gen_s0
            r2_butterfly_bidir #(.B(B),
                .K_FWD(0), .NEG_FWD(0), .K_INV(0), .NEG_INV(0)) u_bf (
                .inverse(inv_pipe[0]),
                .a      (reg0[g0]),
                .b      (reg0[g0 + 16]),
                .a_out  (s0[g0]),
                .b_out  (s0[g0 + 16])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Substage 1: delta=8, 2 groups, E = bitrev1(b)*8
    // -------------------------------------------------------------------------
    genvar b1, j1;
    generate
        for (b1 = 0; b1 < 2; b1 = b1 + 1) begin : gen_s1_b
            for (j1 = 0; j1 < 8; j1 = j1 + 1) begin : gen_s1_g
                localparam integer IDX = b1 * 16 + j1;
                localparam integer E   = (b1 == 0) ? 0 : 8;
                r2_butterfly_bidir #(.B(B),
                    .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                    .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                    .inverse(inv_pipe[1]),
                    .a      (reg1[IDX]),
                    .b      (reg1[IDX + 8]),
                    .a_out  (s1[IDX]),
                    .b_out  (s1[IDX + 8])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Substage 2: delta=4, 4 groups, E = bitrev2(b)*4
    // -------------------------------------------------------------------------
    genvar b2, j2;
    generate
        for (b2 = 0; b2 < 4; b2 = b2 + 1) begin : gen_s2_b
            for (j2 = 0; j2 < 4; j2 = j2 + 1) begin : gen_s2_g
                localparam integer IDX = b2 * 8 + j2;
                localparam integer E   = bitrev2(b2) * 4;
                r2_butterfly_bidir #(.B(B),
                    .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                    .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                    .inverse(inv_pipe[2]),
                    .a      (reg2[IDX]),
                    .b      (reg2[IDX + 4]),
                    .a_out  (s2[IDX]),
                    .b_out  (s2[IDX + 4])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Substage 3: delta=2, 8 groups, E = bitrev3(b)*2
    // -------------------------------------------------------------------------
    genvar b3, j3;
    generate
        for (b3 = 0; b3 < 8; b3 = b3 + 1) begin : gen_s3_b
            for (j3 = 0; j3 < 2; j3 = j3 + 1) begin : gen_s3_g
                localparam integer IDX = b3 * 4 + j3;
                localparam integer E   = bitrev3(b3) * 2;
                r2_butterfly_bidir #(.B(B),
                    .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                    .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                    .inverse(inv_pipe[3]),
                    .a      (reg3[IDX]),
                    .b      (reg3[IDX + 2]),
                    .a_out  (s3[IDX]),
                    .b_out  (s3[IDX + 2])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Substage 4: delta=1, 16 groups, E = bitrev4(b)
    // -------------------------------------------------------------------------
    genvar b4;
    generate
        for (b4 = 0; b4 < 16; b4 = b4 + 1) begin : gen_s4
            localparam integer IDX = b4 * 2;
            localparam integer E   = bitrev4(b4);
            r2_butterfly_bidir #(.B(B),
                .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                .inverse(inv_pipe[4]),
                .a      (reg4[IDX]),
                .b      (reg4[IDX + 1]),
                .a_out  (s4[IDX]),
                .b_out  (s4[IDX + 1])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Pipeline registers
    // -------------------------------------------------------------------------
    integer ridx;
    always @(posedge clk) begin
        if (rst) begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                reg0[ridx] <= {WWIDTH{1'b0}};
                reg1[ridx] <= {WWIDTH{1'b0}};
                reg2[ridx] <= {WWIDTH{1'b0}};
                reg3[ridx] <= {WWIDTH{1'b0}};
                reg4[ridx] <= {WWIDTH{1'b0}};
                reg5[ridx] <= {WWIDTH{1'b0}};
            end
        end else begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                reg0[ridx] <= d1_in[ridx];
                reg1[ridx] <= s0[ridx];
                reg2[ridx] <= s1[ridx];
                reg3[ridx] <= s2[ridx];
                reg4[ridx] <= s3[ridx];
                reg5[ridx] <= s4[ridx];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output: bit-reverse permute (DIT-NR), apply 1/N scale when inverse.
    //
    //   1/N = 1/32 = 2^-5 mod q.  In F_4 with q=2^16+1, 2 has order 32, so
    //   2^-5 = 2^(32-5) = 2^27 = -2^11 mod q (since 2^16 = -1).
    //   d1_mul_by_2k only accepts |K| <= B, so use K=11 + d1_neg for the
    //   sign flip.
    // -------------------------------------------------------------------------
    wire [B:0] post_d1 [0:R-1];
    wire [B:0] scaled_d1 [0:R-1];
    genvar so;
    generate
        for (so = 0; so < R; so = so + 1) begin : gen_perm
            localparam integer BR = bit_reverse5(so);
            assign post_d1[so] = reg5[BR];
        end
    endgenerate

    // 1/N scaling, conditional on inverse:  out = -2^11 * post = 1/N * post
    genvar oi;
    generate
        for (oi = 0; oi < R; oi = oi + 1) begin : gen_scale
            wire [B:0] shifted_mag;
            wire [B:0] scaled_raw;
            d1_mul_by_2k #(.B(B), .K(11)) u_shift (
                .in  (post_d1[oi]),
                .out (shifted_mag)
            );
            d1_neg #(B) u_neg (
                .in  (shifted_mag),
                .out (scaled_raw)
            );
            assign scaled_d1[oi] = inv_pipe[5] ? scaled_raw : post_d1[oi];
        end
    endgenerate

    // d1 -> norm
    genvar oo;
    generate
        for (oo = 0; oo < R; oo = oo + 1) begin : gen_out_conv
            wire [B:0] norm_out;
            d1_to_norm #(B) u_d2n (.in(scaled_d1[oo]), .out(norm_out));
            assign out_norm[oo*WWIDTH +: WWIDTH] = norm_out;
        end
    endgenerate

endmodule

`endif // _SUB_NTT32_BIDIR_GUARD
