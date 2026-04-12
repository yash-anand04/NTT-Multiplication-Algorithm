// =============================================================================
// r2intt_butterfly_pow2.v
// Radix-2 DIF INTT butterfly in D1 representation with power-of-2 twiddle.
// Computes:
//   a_out = (a + b) / 2
//   b_out = (a - b) / 2 * twiddle
// where twiddle = (+/-)2^K in D1.
// =============================================================================

`ifndef _R2INTT_BUTTERFLY_POW2_GUARD
`define _R2INTT_BUTTERFLY_POW2_GUARD

module r2intt_butterfly_pow2 #(
    parameter B = 16,
    parameter integer K = 0,
    parameter NEG = 0
)(
    input  wire [B:0] a,
    input  wire [B:0] b,
    output wire [B:0] a_out,
    output wire [B:0] b_out
);
    wire [B:0] sum_raw, diff_raw;
    wire [B:0] sum_half, diff_half;
    wire [B:0] diff_tw_mag;

    d1_add #(B) u_add (.in1(a), .in2(b), .out(sum_raw));
    d1_sub #(B) u_sub (.in1(a), .in2(b), .out(diff_raw));

    d1_mul_by_2k #(.B(B), .K(-1)) u_half_sum  (.in(sum_raw),  .out(sum_half));
    d1_mul_by_2k #(.B(B), .K(-1)) u_half_diff (.in(diff_raw), .out(diff_half));

    d1_mul_by_2k #(.B(B), .K(K)) u_tw_mul (.in(diff_half), .out(diff_tw_mag));

    assign a_out = sum_half;

    generate
        if (NEG) begin : gen_neg
            d1_neg #(B) u_neg (.in(diff_tw_mag), .out(b_out));
        end else begin : gen_pos
            assign b_out = diff_tw_mag;
        end
    endgenerate
endmodule

`endif // _R2INTT_BUTTERFLY_POW2_GUARD
