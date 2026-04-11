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
    // Full product of two (B+1)-bit operands has up to (2B+1) significant bits.
    // Keep indices [2B:0] so the top meaningful bit at position 2B is preserved.
    wire [2*B:0] product = a * b;

    // Fermat reduction: result = p_low - p_high mod (2^B+1)
    wire [B:0] p_low  = product[B-1:0];          // lower B bits (zero-extended)
    wire [B:0] p_high = product[2*B:B];          // floor(product / 2^B), includes bit[2B]

    // Robustly compute (p_low - p_high) mod (2^B + 1) in one normalization step:
    // t = p_low + q - p_high, where q = 2^B + 1 and 1 <= t <= 2q-2.
    // Then reduce once: if t >= q -> t-q else t.
    wire [B+1:0] q_const = (1'b1 << B) + 1'b1;
    wire [B+1:0] t = {1'b0, p_low} + q_const - {1'b0, p_high};
    wire [B+1:0] reduced = (t >= q_const) ? (t - q_const) : t;

    assign result = reduced[B:0];
endmodule
