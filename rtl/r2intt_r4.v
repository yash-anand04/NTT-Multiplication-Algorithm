// =============================================================================
// r2intt_r4.v
// Fixed 4-point DIF-INTT butterfly in D1 representation (R=4)
// For Fermat modulus q = F4 = 65537, B = 16
//
// DIF-INTT is the reverse of DIT-NTT: substages run in reverse order.
// Substage 0 (process top pair with ωR):
//   t0 = A0 + A1,            t1 = A0 - A1           (twiddle=1 after halving)
//   t2 = A2 + A3,            t3 = (A2 - A3)*ω^{-1}R
// But in D1 INTT (Algorithm 2), 2^{-1} mod q is incorporated:
//   For DIF INTT in D1, halving by 2 becomes a right circular shift (shift B-1 bits left = shift 1 right)
//
// The 4-point DIF-INTT (2 substages of R2 butterflies in D1):
// Substage 0 (ω^{-1}R = 2^{B-KSHIFT}):
//   t0 = A0 + A2,   t2 = (A0 - A2) * 2^{-1}   [halving: right shift 1]
//   t1 = A1 + A3,   t3 = (A1 - A3) * 2^{-1} * ω^{-1}R
// Substage 1 (ω = 1, halving again):
//   a0 = (t0 + t1)*2^{-1}, a1 = (t0 - t1)*2^{-1}
//   a2 = (t2 + t3)*2^{-1}, a3 = (t2 - t3)*2^{-1}
//
// Note: The paper's Algorithm 2 folds the N^{-1} scaling factor into each
// INTT stage (each butterfly divides by 2). For R=4, N/R=64-point INTT
// has log2(64)=6 stages, so the scaling is 2^{-log2(N)} = N^{-1}.
//
// KSHIFT_INV = B - KSHIFT (inverse shift for ω^{-1}R in D1 circular rotation).
// =============================================================================

module r2intt_r4 #(
    parameter B         = 16,  // Fermat Fn = 2^B + 1
    parameter KSHIFT    = 8,
    parameter KSHIFT_INV = 8
)(
    input  [B:0] A0, A1, A2, A3,       // 4 inputs in D1 representation
    input        is_Rhat_stage,         // 1 = only use last substage (mixed-radix R^hat=2)
    output [B:0] a0, a1, a2, a3        // 4 outputs in D1 representation
);
    // Inverse of r2ntt_r4:
    // t0 = (A0 + A1)/2
    // t1 = (A0 - A1)/2
    // t2 = (A2 + A3)/2
    // t3 = ((A2 - A3)/2) * ωR^{-1}
    // a0 = (t0 + t2)/2
    // a2 = (t0 - t2)/2
    // a1 = (t1 + t3)/2
    // a3 = (t1 - t3)/2

    wire [B:0] sum01, diff01, sum23, diff23;
    wire [B:0] t0, t1, t2;
    wire [B:0] half_diff23, t3;

    d1_add #(B) add01 (.in1(A0), .in2(A1), .out(sum01));
    d1_sub #(B) sub01 (.in1(A0), .in2(A1), .out(diff01));
    d1_add #(B) add23 (.in1(A2), .in2(A3), .out(sum23));
    d1_sub #(B) sub23 (.in1(A2), .in2(A3), .out(diff23));

    d1_mul_by_2k #(.B(B), .K(-1)) half01 (.in(sum01),  .out(t0));
    d1_mul_by_2k #(.B(B), .K(-1)) half11 (.in(diff01), .out(t1));
    d1_mul_by_2k #(.B(B), .K(-1)) half23 (.in(sum23),  .out(t2));
    d1_mul_by_2k #(.B(B), .K(-1)) halfd23 (.in(diff23), .out(half_diff23));
    d1_mul_by_2k #(.B(B), .K(KSHIFT_INV)) invw23 (.in(half_diff23), .out(t3));

    wire [B:0] sum02, diff02, sum13, diff13;
    wire [B:0] a0_full, a1_full, a2_full, a3_full;

    d1_add #(B) add02 (.in1(t0), .in2(t2), .out(sum02));
    d1_sub #(B) sub02 (.in1(t0), .in2(t2), .out(diff02));
    d1_add #(B) add13 (.in1(t1), .in2(t3), .out(sum13));
    d1_sub #(B) sub13 (.in1(t1), .in2(t3), .out(diff13));

    d1_mul_by_2k #(.B(B), .K(-1)) halfa0 (.in(sum02),  .out(a0_full));
    d1_mul_by_2k #(.B(B), .K(-1)) halfa2 (.in(diff02), .out(a2_full));
    d1_mul_by_2k #(.B(B), .K(-1)) halfa1 (.in(sum13),  .out(a1_full));
    d1_mul_by_2k #(.B(B), .K(-1)) halfa3 (.in(diff13), .out(a3_full));

    // Rhat mode is currently disabled at top-level control for N=256, R=4.
    assign a0 = a0_full;
    assign a1 = a1_full;
    assign a2 = a2_full;
    assign a3 = a3_full;
endmodule
