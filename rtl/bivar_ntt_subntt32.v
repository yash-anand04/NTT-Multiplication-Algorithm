// =============================================================================
// bivar_ntt_subntt32.v
// Natural-order 32-point NTT/INTT wrapper for Kim et al. column NTTs.
//
// Wraps r2ntt_r32 (DIT, shift-only, WEXP=3) and r2intt_r32 (DIF, WEXP=3).
//
// Forward (inverse=0):
//   r2ntt_r32 is DIT: input natural, output bit-reversed.
//   Wrapper reorders output so out_norm is in natural frequency order.
//
// Inverse (inverse=1):
//   r2intt_r32 is DIF: expects bit-reversed frequency input to produce
//   natural time output. Wrapper pre-permutes in_norm to bit-reversed order
//   before feeding r2intt_r32. Output is in natural time order.
//
// Normalization: 5 DIF INTT stages each divide by 2, giving total 1/32.
// =============================================================================

`ifndef _BIVAR_NTT_SUBNTT32_GUARD
`define _BIVAR_NTT_SUBNTT32_GUARD

module bivar_ntt_subntt32 #(
    parameter B      = 16,
    parameter M      = 32,
    parameter WWIDTH = B + 1
)(
    input  wire                inverse,
    input  wire [M*WWIDTH-1:0] in_norm,
    output wire [M*WWIDTH-1:0] out_norm
);
    function integer bit_reverse5;
        input integer val;
        integer bi;
        begin
            bit_reverse5 = 0;
            for (bi = 0; bi < 5; bi = bi + 1)
                bit_reverse5 = (bit_reverse5 << 1) | ((val >> bi) & 1);
        end
    endfunction

    wire [M*WWIDTH-1:0] fwd_d1_in;
    wire [M*WWIDTH-1:0] inv_d1_in;
    wire [M*WWIDTH-1:0] fwd_d1_out;
    wire [M*WWIDTH-1:0] inv_d1_out;
    wire [M*WWIDTH-1:0] fwd_norm_raw;
    wire [M*WWIDTH-1:0] inv_norm_raw;

    genvar i;
    generate
        for (i = 0; i < M; i = i + 1) begin : gen_lane
            localparam integer BR = bit_reverse5(i);

            norm_to_d1 #(B) u_fwd_n2d (
                .in  (in_norm[i*WWIDTH +: WWIDTH]),
                .out (fwd_d1_in[i*WWIDTH +: WWIDTH])
            );

            // r2intt_r32 (DIF) expects bit-reversed input.
            norm_to_d1 #(B) u_inv_n2d (
                .in  (in_norm[BR*WWIDTH +: WWIDTH]),
                .out (inv_d1_in[i*WWIDTH +: WWIDTH])
            );

            d1_to_norm #(B) u_fwd_d2n (
                .in  (fwd_d1_out[i*WWIDTH +: WWIDTH]),
                .out (fwd_norm_raw[i*WWIDTH +: WWIDTH])
            );

            d1_to_norm #(B) u_inv_d2n (
                .in  (inv_d1_out[i*WWIDTH +: WWIDTH]),
                .out (inv_norm_raw[i*WWIDTH +: WWIDTH])
            );

            // r2ntt_r32 DIT: output lane i holds natural frequency bit_reverse5(i).
            // Reorder so out_norm[i] = frequency i.
            assign out_norm[i*WWIDTH +: WWIDTH] =
                inverse ? inv_norm_raw[i*WWIDTH +: WWIDTH]
                        : fwd_norm_raw[BR*WWIDTH +: WWIDTH];
        end
    endgenerate

    r2ntt_r32  #(.B(B)) u_fwd (.in_d1(fwd_d1_in), .out_d1(fwd_d1_out));
    r2intt_r32 #(.B(B)) u_inv (.in_d1(inv_d1_in), .out_d1(inv_d1_out));
endmodule

`endif // _BIVAR_NTT_SUBNTT32_GUARD
