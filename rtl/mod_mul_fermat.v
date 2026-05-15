// =============================================================================
// mod_mul_fermat.v
// Fermat Modular Multiplier: computes (a * b) mod (2^B + 1)
//
// 3-STAGE PIPELINED (matches paper, gives Vivado room to retime into DSP48E1):
//   Stage 1: register inputs                -> packs into DSP48E1 A1/B1 regs
//   Stage 2: register the (B+1)x(B+1) mul    -> packs into DSP48E1 M register
//   Stage 3: register the Fermat-reduced out -> sits in fabric (P-reg or LUT FF)
//
// Latency    = 3 clock cycles (issue at T, result valid at T+3).
// Throughput = 1 result per cycle.
//
// (* USE_DSP = "yes" *) on each register requests DSP48E1 mapping.
// With three explicit pipeline stages, Vivado retiming will balance the
// path b_cnt -> orig_addrs -> bank_dout -> mm_in_a -> A1 across two cycles
// (the previously-monolithic 20+ ns combinational chain).
// =============================================================================

module mod_mul_fermat #(
    parameter B = 16   // Fermat number Fn = 2^B + 1, q has B+1 bits
)(
    input  wire           clk,
    input  wire           rst,
    input  wire [B:0]     a,       // normal rep, range [0, 2^B]  (B+1 bits)
    input  wire [B:0]     b,       // normal rep, range [0, 2^B]  (B+1 bits)
    output reg  [B:0]     result   // normal rep, range [0, 2^B], latency = 3 cycles
);

    // ---- Stage 1: register inputs (target A1/B1 inside DSP48E1) ------------
    (* USE_DSP = "yes" *) reg [B:0] a_r;
    (* USE_DSP = "yes" *) reg [B:0] b_r;
    always @(posedge clk) begin
        a_r <= a;
        b_r <= b;
    end

    // ---- Stage 2: register the raw multiply (target M register) -----------
    (* USE_DSP = "yes" *) reg [2*B:0] product_r;
    always @(posedge clk) begin
        product_r <= a_r * b_r;
    end

    // ---- Stage 3: Fermat reduction and register result --------------------
    // result = (p_low - p_high) mod (2^B + 1)
    // Robust normalization in one step: t = p_low + q - p_high, 1 <= t <= 2q-2.
    wire [B:0]   p_low   = product_r[B-1:0];
    wire [B:0]   p_high  = product_r[2*B:B];
    wire [B+1:0] q_const = (1'b1 << B) + 1'b1;
    wire [B+1:0] t       = {1'b0, p_low} + q_const - {1'b0, p_high};
    wire [B+1:0] reduced = (t >= q_const) ? (t - q_const) : t;

    always @(posedge clk) begin
        result <= reduced[B:0];
    end
endmodule
