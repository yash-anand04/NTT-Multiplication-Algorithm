// =============================================================================
// d1_arith.v
// Diminished-1 (D1) Arithmetic Primitives for Fermat Modulus Fn = 2^b + 1
// Parameterized by B (b = bit width), so q = 2^B + 1
// =============================================================================

// ---- norm_to_d1 -------------------------------------------------------------
// Converts normal representation to D1: if in==0 => 2^b, else => in-1
module norm_to_d1 #(parameter B = 16) (
    input  [B:0] in,    // normal (B+1 bits, range 0..2^B)
    output [B:0] out    // D1    (B+1 bits, range 0..2^B; 2^B means zero)
);
    assign out = (in == {(B+1){1'b0}}) ? (1'b1 << B) : (in - 1'b1);
endmodule

// ---- d1_to_norm -------------------------------------------------------------
// Converts D1 representation to normal: if in==2^b => 0, else => in+1
module d1_to_norm #(parameter B = 16) (
    input  [B:0] in,
    output [B:0] out
);
    assign out = (in == (1'b1 << B)) ? {(B+1){1'b0}} : (in + 1'b1);
endmodule

// ---- d1_mul_by_2k -----------------------------------------------------------
// Multiplication by 2^k (k can be positive=left shift / negative=right shift)
// For Fermat, this is an invert-circular-shift on in[B-1:0].
// k is given as a 5-bit signed value (for B=16 max shift = 16 bits).
// If in == 2^B (i.e. D1 zero), output stays 2^B.
// Left shift by k positions (mod B): out[B-1:0] = {in[B-1-k:0], in[B-1:B-k]}
// Right shift by k positions (mod B): circular right shift
// NOTE: k must be in [-(B-1), B-1]; caller is responsible.
//
// For synthesizable constant-shift use: instantiate with a fixed K parameter.
module d1_mul_by_2k #(
    parameter B  = 16,   // bit width of Fermat number
    parameter K  = 1     // positive = left shift, negative not used here;
                         // for inverse (negative k) instantiate with K = B - |k|
)(
    input  [B:0] in,     // D1 representation
    output [B:0] out     // D1 representation after *2^K
);
    wire d1_zero = (in == (1'b1 << B));
    wire [B-1:0] shifted = {in[B-1-K:0], in[B-1:B-K]};  // invert circular left shift
    assign out = d1_zero ? in : {1'b0, shifted};
endmodule

// ---- d1_add -----------------------------------------------------------------
// Modular addition in D1 over Fermat Fn = 2^B + 1
// D1 zero is represented as 2^B
// Addition rule (from paper, Algorithm 3):
//   if in1 == 2^B: out = in2
//   elif in2 == 2^B: out = in1
//   else: t = in1 + in2; out = t[B-1:0] + ~t[B]  (Fermat reduction then -1)
module d1_add #(parameter B = 16) (
    input  [B:0] in1,
    input  [B:0] in2,
    output [B:0] out
);
    wire in1_zero = (in1 == (1'b1 << B));
    wire in2_zero = (in2 == (1'b1 << B));

    // Raw sum (B+2 bits to catch overflow)
    wire [B+1:0] raw_sum = {1'b0, in1} + {1'b0, in2};
    // Fermat reduction: t[B-1:0] + ~t[B] (add 1 if no overflow, subtract 1 if overflow)
    // In D1 sum = (a-1)+(b-1) = a+b-2, so result is (a+b-1)-1 = (a*b)-1 in normal, correct in D1
    wire [B:0] reduced = raw_sum[B-1:0] + (~raw_sum[B]);

    assign out = in1_zero ? in2 :
                 in2_zero ? in1 :
                            reduced;
endmodule

// ---- d1_sub -----------------------------------------------------------------
// Modular subtraction in D1: in1 - in2 = in1 + neg(in2)
module d1_neg #(parameter B = 16) (
    input  [B:0] in,
    output [B:0] out
);
    wire d1_zero = (in == (1'b1 << B));
    assign out = d1_zero ? in : {1'b0, ~in[B-1:0]};
endmodule

module d1_sub #(parameter B = 16) (
    input  [B:0] in1,
    input  [B:0] in2,
    output [B:0] out
);
    wire [B:0] neg_in2;
    d1_neg #(B) neg_inst (.in(in2), .out(neg_in2));
    d1_add #(B) add_inst (.in1(in1), .in2(neg_in2), .out(out));
endmodule
