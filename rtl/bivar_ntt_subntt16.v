// =============================================================================
// bivar_ntt_subntt16.v
// Natural-order 16-point NTT/INTT wrapper for bivar column NTTs (N=128, M=16).
//
// Wraps r2ntt_r16 / r2intt_r16 (16-point shift-only cores, WEXP=6).
// Column root: omega_16 = psi_{128}^{16} = 3^{4096} = 2^6 = 64 mod 65537.
// r2ntt_r16 DIT produces bit-reversed output; wrapper reorders to natural
// frequency order on forward path.  r2intt_r16 DIF expects bit-reversed
// input; wrapper pre-permutes on inverse path.
// =============================================================================

`ifndef _BIVAR_NTT_SUBNTT16_GUARD
`define _BIVAR_NTT_SUBNTT16_GUARD

module bivar_ntt_subntt16 #(
    parameter B      = 16,
    parameter M      = 16,
    parameter WWIDTH = B + 1
)(
    input  wire                inverse,
    input  wire [M*WWIDTH-1:0] in_norm,
    output wire [M*WWIDTH-1:0] out_norm
);
    function integer bit_reverse4;
        input integer val;
        integer bi;
        begin
            bit_reverse4 = 0;
            for (bi = 0; bi < 4; bi = bi + 1)
                bit_reverse4 = (bit_reverse4 << 1) | ((val >> bi) & 1);
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
            localparam integer BR = bit_reverse4(i);

            norm_to_d1 #(B) u_fwd_n2d (
                .in  (in_norm[i*WWIDTH +: WWIDTH]),
                .out (fwd_d1_in[i*WWIDTH +: WWIDTH])
            );

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

            assign out_norm[i*WWIDTH +: WWIDTH] =
                inverse ? inv_norm_raw[i*WWIDTH +: WWIDTH]
                        : fwd_norm_raw[BR*WWIDTH +: WWIDTH];
        end
    endgenerate

    r2ntt_r16  #(.B(B)) u_fwd (
        .in_d1         (fwd_d1_in),
        .is_Rhat_stage (1'b0),
        .out_d1        (fwd_d1_out)
    );

    r2intt_r16 #(.B(B)) u_inv (
        .in_d1         (inv_d1_in),
        .is_Rhat_stage (1'b0),
        .out_d1        (inv_d1_out)
    );
endmodule

`endif // _BIVAR_NTT_SUBNTT16_GUARD
