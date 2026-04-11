// =============================================================================
// mod_mul_fermat.v
// Fermat Modular Multiplier: computes (a * b) mod (2^B + 1)
// Normal representation (not D1). Used in ModMuls and PWM stages.
//
// Fermat reduction formula:
//   Let p = a * b  (2B-bit product)
//   p_low  = p[B-1:0]
//   p_high = p[2B-1:B]
//   result = p_low - p_high  (mod 2^B + 1)
//   If result < 0, add 2^B + 1
//
// COMBINATIONAL implementation (no pipeline registers) for functional
// correctness in the single-butterfly, in-place NTT design.
// The ctrl_unit issues one butterfly group per cycle and results must be
// available in the same cycle for write-back.
// =============================================================================

module mod_mul_fermat #(
    parameter B = 16   // Fermat number Fn = 2^B + 1, q has B+1 bits
)(
    input  wire           clk,    // kept for interface compatibility
    input  wire           rst,    // kept for interface compatibility
    input  wire [B:0]     a,      // normal rep, range [0, 2^B]  (B+1 bits)
    input  wire [B:0]     b,      // normal rep, range [0, 2^B]  (B+1 bits)
    output wire [B:0]     result  // normal rep, range [0, 2^B]
);
    // Combinational multiply (need 2*(B+1) bits to hold full product of (B+1)*(B+1))
    wire [2*B+1:0] product = a * b;

    // Fermat reduction: result = p_low - p_high mod (2^B+1)
    wire [B:0] p_low  = product[B-1:0];          // lower B bits (zero-extended)
    wire [B:0] p_high = product[2*B-1:B];         // upper B bits

    wire [B+1:0] diff = {1'b0, p_low} - {1'b0, p_high};

    wire [B:0] diff_corrected = diff[B+1] ? (diff[B:0] + (1'b1 << B) + 1'b1) :
                                (diff[B:0] == ((1'b1 << B) + 1)) ? {(B+1){1'b0}} :
                                diff[B:0];

    assign result = diff_corrected;
endmodule
