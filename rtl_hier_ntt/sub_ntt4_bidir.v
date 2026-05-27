// =============================================================================
// sub_ntt4_bidir.v
// Bidirectional 4-pt shift-only NTT/INTT over F₄ = 65537.
// omega_4 = 2^8 = 256 (primitive 4th root).  Inverse: omega_4^-1 = -256.
// 2 DIT substages, 2 butterflies per stage = 4 butterflies total.
// 3-cycle latency (1 input reg + 2 substage regs).
// =============================================================================

`ifndef _SUB_NTT4_BIDIR_GUARD
`define _SUB_NTT4_BIDIR_GUARD

(* USE_DSP = "no" *)
module sub_ntt4_bidir #(
    parameter B      = 16,
    parameter WWIDTH = B + 1
)(
    input  wire                 clk, rst, start, inverse,
    input  wire [4*WWIDTH-1:0]  in_norm,
    output wire [4*WWIDTH-1:0]  out_norm,
    output wire                 valid
);
    localparam integer R    = 4;
    // omega_4 must match Python golden's 3^((q-1)/4) = 2^24 mod q = -256.
    // (Previously used 2^8 = 256, which is a valid primitive 4th root but
    // not the canonical generator-derived one; round-trip worked but did
    // not match the outer hier's cross-twiddle convention.)
    localparam integer WEXP = 24;

    function integer bit_reverse2;
        input integer val;
        begin bit_reverse2 = ((val & 1) << 1) | ((val >> 1) & 1); end
    endfunction
    function integer tw_mod;
        input integer exp;
        integer t;
        begin t = (WEXP * exp) % (2*B); if (t < 0) t = t + (2*B); tw_mod = t; end
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
        begin twinv_mod = ((2*B) - tw_mod(exp)) % (2*B); end
    endfunction
    function integer twinv_k;
        input integer exp;
        integer t; begin t = twinv_mod(exp); twinv_k = (t >= B) ? (t - B) : t; end
    endfunction
    function integer twinv_neg;
        input integer exp;
        integer t; begin t = twinv_mod(exp); twinv_neg = (t >= B) ? 1 : 0; end
    endfunction

    // Input D1 conversion
    wire [B:0] d1_in [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_in_conv
            norm_to_d1 #(B) u_n2d (.in(in_norm[i*WWIDTH +: WWIDTH]), .out(d1_in[i]));
        end
    endgenerate

    reg [B:0] reg0 [0:R-1];
    wire [B:0] s0 [0:R-1];
    wire [B:0] s1 [0:R-1];
    reg [B:0] reg1 [0:R-1];
    reg [B:0] reg2 [0:R-1];

    // valid + inverse-mode pipe — padded to 6 stages so the latency
    // matches sub_ntt32_bidir (lets the same hier d5/d8/d12 taps work
    // across all L values).
    reg [5:0] valid_pipe;
    reg [5:0] inv_pipe;
    always @(posedge clk) begin
        if (rst) begin valid_pipe <= 6'b0; inv_pipe <= 6'b0; end
        else begin
            valid_pipe <= {valid_pipe[4:0], start};
            inv_pipe   <= {inv_pipe[4:0],   inverse & start};
        end
    end
    assign valid = valid_pipe[5];

    // Substage 0: delta=2, twiddle = 1 for both butterflies (E = 0)
    genvar g0;
    generate
        for (g0 = 0; g0 < 2; g0 = g0 + 1) begin : gen_s0
            r2_butterfly_bidir #(.B(B),
                .K_FWD(0), .NEG_FWD(0), .K_INV(0), .NEG_INV(0)) u_bf (
                .inverse(inv_pipe[0]),
                .a(reg0[g0]), .b(reg0[g0 + 2]),
                .a_out(s0[g0]), .b_out(s0[g0 + 2])
            );
        end
    endgenerate

    // Substage 1: delta=1, 2 groups, E = bitrev1(b)
    genvar b1;
    generate
        for (b1 = 0; b1 < 2; b1 = b1 + 1) begin : gen_s1
            localparam integer IDX = b1 * 2;
            localparam integer E   = b1;   // bit_reverse_small(b, 1) for 1-bit = b
            r2_butterfly_bidir #(.B(B),
                .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                .inverse(inv_pipe[1]),
                .a(reg1[IDX]), .b(reg1[IDX + 1]),
                .a_out(s1[IDX]), .b_out(s1[IDX + 1])
            );
        end
    endgenerate

    integer ridx;
    always @(posedge clk) begin
        if (rst) begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                reg0[ridx] <= {WWIDTH{1'b0}};
                reg1[ridx] <= {WWIDTH{1'b0}};
                reg2[ridx] <= {WWIDTH{1'b0}};
            end
        end else begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                reg0[ridx] <= d1_in[ridx];
                reg1[ridx] <= s0[ridx];
                reg2[ridx] <= s1[ridx];
            end
        end
    end

    // Output: bit-reverse permute + 1/L scale when inverse.
    // 1/4 = 2^-2 mod q = 2^30 = -2^14 mod q (since 2^16=-1). K=14, NEG=1.
    // Then 3 stages of output-pipeline padding to match 6-cycle latency.
    wire [B:0] post_d1 [0:R-1];
    wire [B:0] scaled_d1 [0:R-1];
    genvar so;
    generate
        for (so = 0; so < R; so = so + 1) begin : gen_perm
            localparam integer BR = bit_reverse2(so);
            assign post_d1[so] = reg2[BR];
        end
    endgenerate

    genvar oi;
    generate
        for (oi = 0; oi < R; oi = oi + 1) begin : gen_scale
            wire [B:0] shifted_mag;
            wire [B:0] scaled_raw;
            d1_mul_by_2k #(.B(B), .K(14)) u_shift (.in(post_d1[oi]), .out(shifted_mag));
            d1_neg #(B) u_neg (.in(shifted_mag), .out(scaled_raw));
            assign scaled_d1[oi] = inv_pipe[2] ? scaled_raw : post_d1[oi];
        end
    endgenerate

    // 3-stage padding to match sub_ntt32_bidir's 6-cycle latency
    reg [B:0] pad1 [0:R-1];
    reg [B:0] pad2 [0:R-1];
    reg [B:0] pad3 [0:R-1];
    integer padidx;
    always @(posedge clk) begin
        if (rst) begin
            for (padidx = 0; padidx < R; padidx = padidx + 1) begin
                pad1[padidx] <= {WWIDTH{1'b0}};
                pad2[padidx] <= {WWIDTH{1'b0}};
                pad3[padidx] <= {WWIDTH{1'b0}};
            end
        end else begin
            for (padidx = 0; padidx < R; padidx = padidx + 1) begin
                pad1[padidx] <= scaled_d1[padidx];
                pad2[padidx] <= pad1[padidx];
                pad3[padidx] <= pad2[padidx];
            end
        end
    end

    genvar oo;
    generate
        for (oo = 0; oo < R; oo = oo + 1) begin : gen_out_conv
            wire [B:0] norm_out;
            d1_to_norm #(B) u_d2n (.in(pad3[oo]), .out(norm_out));
            assign out_norm[oo*WWIDTH +: WWIDTH] = norm_out;
        end
    endgenerate

endmodule

`endif // _SUB_NTT4_BIDIR_GUARD
