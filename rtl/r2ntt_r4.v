// =============================================================================
// r2ntt_r4.v
// Fixed 4-point DIT-NTT butterfly in D1 representation (R=4)
// For Fermat modulus q = F4 = 65537, B = 16
// ωR = ω_{2N}^{2N/R} = ω_{2N}^{2N/4} = ω_{2N}^{N/2} = power of 2
//
// For q=65537 (B=16), R=4:   ωR = 2^4 = 16 (for N=256)
//
// The 4-point DIT-NTT (2 substages of R2 butterflies in D1):
// Substage 0 (ω = 1):
//   t0 = a0 + a2,  t2 = a0 - a2
//   t1 = a1 + a3,  t3 = a1 - a3
// Substage 1 (ω = ωR, ω^2 = ωR^2, ...):
//   A0 = t0 + t1,    A1 = t0 - t1
//   A2 = t2 + ωR*t3, A3 = t2 - ωR*t3
//
// The module is parameterized with KSHIFT = shift amount for ωR.
// Caller sets is_Rhat_stage to use only the first substage (for mixed-radix R^hat=2).
// =============================================================================

module r2ntt_r4 #(
    parameter B      = 16,  // Fermat Fn = 2^B + 1
    parameter KSHIFT = 4    // ωR = 2^KSHIFT (e.g., ω_{512}^{128} = 2^4 for N=256, R=4)
)(
    input  [B:0] a0, a1, a2, a3,       // 4 inputs in D1 representation
    input        is_Rhat_stage,         // 1 = only run substage 0 (mixed-radix R^hat=2)
    output [B:0] A0, A1, A2, A3        // 4 outputs in D1 representation
);
    // --- Substage 0: butterfly with twiddle = 1 (shift 0) --------------------
    wire [B:0] t0, t1, t2, t3;

    r2_butterfly #(.B(B), .K(0)) bf0 (.a(a0), .b(a2), .a_out(t0), .b_out(t2));
    r2_butterfly #(.B(B), .K(0)) bf1 (.a(a1), .b(a3), .a_out(t1), .b_out(t3));

    // --- Substage 1: butterfly with twiddle = ωR = 2^KSHIFT ------------------
    wire [B:0] A0_full, A1_full, A2_full, A3_full;

    r2_butterfly #(.B(B), .K(0))      bf2 (.a(t0), .b(t1), .a_out(A0_full), .b_out(A1_full));
    r2_butterfly #(.B(B), .K(KSHIFT)) bf3 (.a(t2), .b(t3), .a_out(A2_full), .b_out(A3_full));

    // Output mux: when is_Rhat_stage, only substage 0 is used (R^hat=2 case)
    assign A0 = is_Rhat_stage ? t0 : A0_full;
    assign A1 = is_Rhat_stage ? t1 : A1_full;
    assign A2 = is_Rhat_stage ? t2 : A2_full;
    assign A3 = is_Rhat_stage ? t3 : A3_full;
endmodule
