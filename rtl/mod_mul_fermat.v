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
// For pipelined usage, a 2-stage pipeline is used (multiply, then reduce).
// =============================================================================

module mod_mul_fermat #(
    parameter B = 16   // Fermat number Fn = 2^B + 1, q has B+1 bits
)(
    input  wire           clk,
    input  wire           rst,
    input  wire [B:0]     a,          // normal rep, range [0, 2^B]  (B+1 bits)
    input  wire [B:0]     b,          // normal rep, range [0, 2^B]  (B+1 bits)
    output reg  [B:0]     result      // normal rep, range [0, 2^B]
);
    // Stage 1: multiply
    reg [2*B-1:0] product_r;
    always @(posedge clk or posedge rst) begin
        if (rst)
            product_r <= 0;
        else
            product_r <= a * b;
    end

    // Stage 2: Fermat reduction
    // p_low - p_high may be negative, so use signed-extended subtraction
    wire [B:0] p_low  = product_r[B-1:0];         // lower B bits
    wire [B:0] p_high = product_r[2*B-1:B];       // upper B bits (B bits wide)
    wire [B+1:0] diff  = {1'b0, p_low} - {1'b0, p_high};  // (B+2) bits, signed check via MSB

    always @(posedge clk or posedge rst) begin
        if (rst)
            result <= 0;
        else begin
            if (diff[B+1]) begin
                // diff is negative, add Fn = 2^B + 1
                result <= diff[B:0] + (1'b1 << B) + 1'b1;
            end else if (diff[B:0] == (1'b1 << B) + 1) begin
                // diff == 2^B+1 = Fn, reduce to 0
                result <= 0;
            end else begin
                result <= diff[B:0];
            end
        end
    end
endmodule
