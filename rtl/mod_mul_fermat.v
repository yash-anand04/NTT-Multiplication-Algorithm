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
// Default is combinational for current throughput/latency behavior.
// Optional 1-stage/2-stage pipelining can be enabled for Fmax tuning.
// =============================================================================

module mod_mul_fermat #(
    parameter B = 16,         // Fermat number Fn = 2^B + 1, q has B+1 bits
    parameter PIPE_STAGES = 0 // 0=comb, 1=output-registered, 2=product+output registered
)(
    input  wire           clk,    // kept for interface compatibility
    input  wire           rst,    // kept for interface compatibility
    input  wire [B:0]     a,      // normal rep, range [0, 2^B]  (B+1 bits)
    input  wire [B:0]     b,      // normal rep, range [0, 2^B]  (B+1 bits)
    output wire [B:0]     result  // normal rep, range [0, 2^B]
);
    // Full product of two (B+1)-bit operands has up to (2B+1) significant bits.
    // Keep indices [2B:0] so the top meaningful bit at position 2B is preserved.
    wire [2*B:0] product_comb = a * b;
    // Fermat reduction: result = p_low - p_high mod (2^B+1)
    wire [B:0] p_low_comb  = product_comb[B-1:0];
    wire [B:0] p_high_comb = product_comb[2*B:B];

    // Robustly compute (p_low - p_high) mod (2^B + 1) in one normalization step:
    // t = p_low + q - p_high, where q = 2^B + 1 and 1 <= t <= 2q-2.
    // Then reduce once: if t >= q -> t-q else t.
    wire [B+1:0] q_const = (1'b1 << B) + 1'b1;
    wire [B+1:0] t_comb = {1'b0, p_low_comb} + q_const - {1'b0, p_high_comb};
    wire [B+1:0] reduced_comb = (t_comb >= q_const) ? (t_comb - q_const) : t_comb;
    wire [B:0] result_comb = reduced_comb[B:0];

    generate
        if (PIPE_STAGES == 0) begin : gen_comb
            assign result = result_comb;
        end else if (PIPE_STAGES == 1) begin : gen_pipe1
            reg [B:0] result_q;
            always @(posedge clk or posedge rst) begin
                if (rst)
                    result_q <= {(B+1){1'b0}};
                else
                    result_q <= result_comb;
            end
            assign result = result_q;
        end else begin : gen_pipe2
            reg [2*B:0] product_q;
            reg [B:0] result_q;

            wire [B:0] p_low_q  = product_q[B-1:0];
            wire [B:0] p_high_q = product_q[2*B:B];
            wire [B+1:0] t_q = {1'b0, p_low_q} + q_const - {1'b0, p_high_q};
            wire [B+1:0] reduced_q = (t_q >= q_const) ? (t_q - q_const) : t_q;
            wire [B:0] result_pipe2 = reduced_q[B:0];

            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    product_q <= {(2*B+1){1'b0}};
                    result_q <= {(B+1){1'b0}};
                end else begin
                    product_q <= product_comb;
                    result_q <= result_pipe2;
                end
            end
            assign result = result_q;
        end
    endgenerate
endmodule
