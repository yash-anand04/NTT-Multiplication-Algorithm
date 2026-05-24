// =============================================================================
// r2_butterfly_bidir.v
// Bidirectional DIT radix-2 butterfly in D1 representation.
//   inverse = 0 (NTT):  a_out = a + (NEG_FWD ? -1 : 1) * 2^K_FWD * b
//                       b_out = a - (NEG_FWD ? -1 : 1) * 2^K_FWD * b
//   inverse = 1 (INTT): a_out = a + (NEG_INV ? -1 : 1) * 2^K_INV * b
//                       b_out = a - (NEG_INV ? -1 : 1) * 2^K_INV * b
// INTT = NTT with inverse twiddles; caller applies 1/N at the output.
// Both K_FWD/K_INV shifts are constant-wired; only the 17-bit 2:1 mux is real
// logic per butterfly.
// =============================================================================

`ifndef _R2_BUTTERFLY_BIDIR_GUARD
`define _R2_BUTTERFLY_BIDIR_GUARD

module r2_butterfly_bidir #(
    parameter B       = 16,
    parameter K_FWD   = 0,
    parameter NEG_FWD = 0,
    parameter K_INV   = 0,
    parameter NEG_INV = 0
)(
    input  wire        inverse,
    input  wire [B:0]  a,
    input  wire [B:0]  b,
    output wire [B:0]  a_out,
    output wire [B:0]  b_out
);
    wire [B:0] b_fwd_mag, b_inv_mag;   // 2^K * b (unsigned)
    wire [B:0] b_fwd, b_inv;           // signed twiddled b
    wire [B:0] tw_b;                   // selected twiddled b

    // ----- Forward path -----------------------------------------------------
    generate
        if (K_FWD == 0) begin : gen_kf0
            assign b_fwd_mag = b;
        end else begin : gen_kfn
            d1_mul_by_2k #(.B(B), .K(K_FWD)) u_fwd_shift (.in(b), .out(b_fwd_mag));
        end
        if (NEG_FWD) begin : gen_neg_f
            d1_neg #(B) u_fwd_neg (.in(b_fwd_mag), .out(b_fwd));
        end else begin : gen_pos_f
            assign b_fwd = b_fwd_mag;
        end
    endgenerate

    // ----- Inverse path -----------------------------------------------------
    generate
        if (K_INV == 0) begin : gen_ki0
            assign b_inv_mag = b;
        end else begin : gen_kin
            d1_mul_by_2k #(.B(B), .K(K_INV)) u_inv_shift (.in(b), .out(b_inv_mag));
        end
        if (NEG_INV) begin : gen_neg_i
            d1_neg #(B) u_inv_neg (.in(b_inv_mag), .out(b_inv));
        end else begin : gen_pos_i
            assign b_inv = b_inv_mag;
        end
    endgenerate

    // ----- Runtime mux + add/sub --------------------------------------------
    assign tw_b = inverse ? b_inv : b_fwd;
    d1_add #(B) u_add (.in1(a), .in2(tw_b), .out(a_out));
    d1_sub #(B) u_sub (.in1(a), .in2(tw_b), .out(b_out));
endmodule

`endif // _R2_BUTTERFLY_BIDIR_GUARD
