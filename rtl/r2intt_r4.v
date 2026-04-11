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
    parameter KSHIFT    = 4,   // ωR = 2^KSHIFT; so ω^{-1}R = 2^{B-KSHIFT}
    parameter KSHIFT_INV = 12  // = B - KSHIFT = 16 - 4 = 12 (right shift 4 = left shift 12)
)(
    input  [B:0] A0, A1, A2, A3,       // 4 inputs in D1 representation
    input        is_Rhat_stage,         // 1 = only use last substage (mixed-radix R^hat=2)
    output [B:0] a0, a1, a2, a3        // 4 outputs in D1 representation
);
    // --- Substage 0: top butterfly with twiddle ω^{-1}R on the difference ---
    // DIF: (A0+A1, (A0-A1)*ω) and (A2+A3, (A2-A3)*ω^2) etc.
    // For 4-point DIF-INTT using the structure from Alg2:
    // Step 0 (s=1 in Alg2, ω^{-1}_M = ω^{-1}_{2N}^{N/2}):
    //   T_top = (A0 + A1) * 2^{-1},   A0_new = T_top
    //   T_bot = (A0 - A1) * 2^{-1},   A1_new = T_bot * ω^{-1}R
    // Step 1 (s=0 in Alg2, ω^{-1}_M = ω^{-1}_{2N}^N = 1 since ω^N_{2N}=-1 mod q):
    //   a0 = (A0_new + A2_new)*2^{-1},  a1 = A0_new_new
    //   etc.

    // Substage 0 (s = log(R)-1 = 1 in Algorithm 2, runs first in DIF):
    wire [B:0] t0, t1, t2, t3;
    wire [B:0] sum02, diff02, sum13, diff13;
    wire [B:0] diff02_tw, diff13_tw;

    d1_add #(B) add02 (.in1(A0), .in2(A2), .out(sum02));
    d1_sub #(B) sub02 (.in1(A0), .in2(A2), .out(diff02));
    d1_add #(B) add13 (.in1(A1), .in2(A3), .out(sum13));
    d1_sub #(B) sub13 (.in1(A1), .in2(A3), .out(diff13));

    // Halve sum02 and sum13 (multiply by 2^{-1} = right shift 1 = left shift B-1)
    d1_mul_by_2k #(.B(B), .K(B-1)) half_sum02 (.in(sum02),  .out(t0));
    d1_mul_by_2k #(.B(B), .K(B-1)) half_sum13 (.in(sum13),  .out(t1));

    // diff * 2^{-1} * ω^{-1}R = diff * 2^{-1-KSHIFT} = right shift (1+KSHIFT) = left shift (B-1-KSHIFT)
    d1_mul_by_2k #(.B(B), .K(B-1-KSHIFT)) half_diff02_tw (.in(diff02), .out(t2));
    d1_mul_by_2k #(.B(B), .K(B-1-KSHIFT)) half_diff13_tw (.in(diff13), .out(t3));

    // Substage 1 (s=0, ω^{-1} = 1, halve again):
    wire [B:0] a0_full, a1_full, a2_full, a3_full;
    wire [B:0] sum_t01, diff_t01, sum_t23, diff_t23;

    d1_add #(B) add_t01 (.in1(t0), .in2(t1), .out(sum_t01));
    d1_sub #(B) sub_t01 (.in1(t0), .in2(t1), .out(diff_t01));
    d1_add #(B) add_t23 (.in1(t2), .in2(t3), .out(sum_t23));
    d1_sub #(B) sub_t23 (.in1(t2), .in2(t3), .out(diff_t23));

    d1_mul_by_2k #(.B(B), .K(B-1)) half_a0 (.in(sum_t01),  .out(a0_full));
    d1_mul_by_2k #(.B(B), .K(B-1)) half_a1 (.in(diff_t01), .out(a1_full));
    d1_mul_by_2k #(.B(B), .K(B-1)) half_a2 (.in(sum_t23),  .out(a2_full));
    d1_mul_by_2k #(.B(B), .K(B-1)) half_a3 (.in(diff_t23), .out(a3_full));

    // Output mux: when is_Rhat_stage, only the last substage (substage 1) is active
    // i.e., inputs (A0..A3) are already post-substage-0, just run substage 1
    wire [B:0] a0_hat, a1_hat, a2_hat, a3_hat;

    wire [B:0] s01, d01, s23, d23;
    d1_add #(B) hadd01 (.in1(A0), .in2(A1), .out(s01));
    d1_sub #(B) hsub01 (.in1(A0), .in2(A1), .out(d01));
    d1_add #(B) hadd23 (.in1(A2), .in2(A3), .out(s23));
    d1_sub #(B) hsub23 (.in1(A2), .in2(A3), .out(d23));
    d1_mul_by_2k #(.B(B), .K(B-1)) hh0 (.in(s01), .out(a0_hat));
    d1_mul_by_2k #(.B(B), .K(B-1)) hh1 (.in(d01), .out(a1_hat));
    d1_mul_by_2k #(.B(B), .K(B-1)) hh2 (.in(s23), .out(a2_hat));
    d1_mul_by_2k #(.B(B), .K(B-1)) hh3 (.in(d23), .out(a3_hat));

    assign a0 = is_Rhat_stage ? a0_hat : a0_full;
    assign a1 = is_Rhat_stage ? a1_hat : a1_full;
    assign a2 = is_Rhat_stage ? a2_hat : a2_full;
    assign a3 = is_Rhat_stage ? a3_hat : a3_full;
endmodule
