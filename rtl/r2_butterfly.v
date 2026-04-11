// =============================================================================
// r2_butterfly.v
// Radix-2 DIT Butterfly Unit in D1 representation
// Computes: a_out = a + (2^k * b)
//           b_out = a - (2^k * b)
// all in D1 arithmetic, twiddle = 2^K (constant rotation)
// =============================================================================

module r2_butterfly #(
    parameter B = 16,   // Fermat number Fn = 2^B + 1
    parameter K = 0     // twiddle = 2^K (left circular shift by K bits)
)(
    input  [B:0] a,         // D1 rep
    input  [B:0] b,         // D1 rep
    output [B:0] a_out,     // D1 rep: a + 2^K*b
    output [B:0] b_out      // D1 rep: a - 2^K*b
);
    wire [B:0] tw_b;   // 2^K * b in D1

    generate
        if (K == 0) begin : gen_k0
            assign tw_b = b;  // 2^0 * b = b, circular shift by 0 is identity
        end else begin : gen_kn
            d1_mul_by_2k #(.B(B), .K(K)) twiddle_mul (
                .in  (b),
                .out (tw_b)
            );
        end
    endgenerate

    d1_add #(B) add_inst  (.in1(a), .in2(tw_b), .out(a_out));
    d1_sub #(B) sub_inst  (.in1(a), .in2(tw_b), .out(b_out));
endmodule
