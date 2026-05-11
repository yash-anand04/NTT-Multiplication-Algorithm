// =============================================================================
// bivar_ntt_subntt8.v
// Natural-order 8-point NTT/INTT wrapper for Kim et al. row NTTs.
//
// Wraps r2ntt_r8 / r2intt_r8 (8-point shift-only cores, WEXP=12).
// r2ntt_r8 DIT produces bit-reversed output; wrapper reorders to natural
// frequency order on forward path.  r2intt_r8 DIF expects bit-reversed
// input; wrapper pre-permutes on inverse path.
// =============================================================================

`ifndef _BIVAR_NTT_SUBNTT8_GUARD
`define _BIVAR_NTT_SUBNTT8_GUARD

module bivar_ntt_subntt8 #(
    parameter B      = 16,
    parameter L      = 8,
    parameter WWIDTH = B + 1
)(
    input  wire                inverse,
    input  wire [L*WWIDTH-1:0] in_norm,
    output wire [L*WWIDTH-1:0] out_norm
);
    function integer bit_reverse3;
        input integer val;
        integer bi;
        begin
            bit_reverse3 = 0;
            for (bi = 0; bi < 3; bi = bi + 1)
                bit_reverse3 = (bit_reverse3 << 1) | ((val >> bi) & 1);
        end
    endfunction

    wire [L*WWIDTH-1:0] fwd_d1_in;
    wire [L*WWIDTH-1:0] inv_d1_in;
    wire [L*WWIDTH-1:0] fwd_d1_out;
    wire [L*WWIDTH-1:0] inv_d1_out;
    wire [L*WWIDTH-1:0] fwd_norm_raw;
    wire [L*WWIDTH-1:0] inv_norm_raw;

    genvar i;
    generate
        for (i = 0; i < L; i = i + 1) begin : gen_lane
            localparam integer BR = bit_reverse3(i);

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

    r2ntt_r8  #(.B(B), .N(256)) u_fwd (
        .in_d1         (fwd_d1_in),
        .is_Rhat_stage (1'b0),
        .out_d1        (fwd_d1_out)
    );

    r2intt_r8 #(.B(B), .N(256)) u_inv (
        .in_d1         (inv_d1_in),
        .is_Rhat_stage (1'b0),
        .out_d1        (inv_d1_out)
    );
endmodule

`endif // _BIVAR_NTT_SUBNTT8_GUARD
