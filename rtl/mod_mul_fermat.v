// =============================================================================
// mod_mul_fermat.v
// Fermat Modular Multiplier: computes (a * b) mod (2^B + 1)
//
// PARAMETERIZED: PIPELINED selects between two implementations.
//   PIPELINED = 1 (default): 3-stage pipelined, DSP48E1-friendly
//      - Stage 1: register inputs  (target A1/B1 DSP regs)
//      - Stage 2: register multiply (target DSP M register)
//      - Stage 3: register Fermat reduction result
//      - Latency = 3 clk cycles, throughput = 1 result/cycle.
//      - Used by ntt_top (matches paper's pipelined ModMul).
//   PIPELINED = 0: combinational (legacy)
//      - Used by bivar_ntt_top whose FSM expects same-cycle results.
//      - Documented future work: pipeline bivar's data path too.
// =============================================================================

module mod_mul_fermat #(
    parameter B         = 16,
    parameter PIPELINED = 1
)(
    input  wire           clk,
    input  wire           rst,
    input  wire [B:0]     a,
    input  wire [B:0]     b,
    output wire [B:0]     result
);
    generate
        if (PIPELINED == 0) begin : gen_comb
            // ---- Legacy combinational implementation ------------------------
            wire [2*B:0] product = a * b;
            wire [B:0]   p_low   = product[B-1:0];
            wire [B:0]   p_high  = product[2*B:B];
            wire [B+1:0] q_const = (1'b1 << B) + 1'b1;
            wire [B+1:0] t       = {1'b0, p_low} + q_const - {1'b0, p_high};
            wire [B+1:0] reduced = (t >= q_const) ? (t - q_const) : t;
            assign result = reduced[B:0];
        end else begin : gen_pipe
            // ---- 3-stage pipelined implementation ---------------------------
            (* USE_DSP = "yes" *) reg [B:0]   a_r;
            (* USE_DSP = "yes" *) reg [B:0]   b_r;
            (* USE_DSP = "yes" *) reg [2*B:0] product_r;
            reg [B:0] result_r;

            wire [B:0]   p_low   = product_r[B-1:0];
            wire [B:0]   p_high  = product_r[2*B:B];
            wire [B+1:0] q_const = (1'b1 << B) + 1'b1;
            wire [B+1:0] t       = {1'b0, p_low} + q_const - {1'b0, p_high};
            wire [B+1:0] reduced = (t >= q_const) ? (t - q_const) : t;

            always @(posedge clk) begin
                a_r       <= a;
                b_r       <= b;
                product_r <= a_r * b_r;
                result_r  <= reduced[B:0];
            end

            assign result = result_r;
        end
    endgenerate
endmodule
