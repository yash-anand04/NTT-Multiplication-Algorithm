// =============================================================================
// sub_ntt_simple.v   (Phase D debug helper, L=8 ONLY, hardcoded matrix)
// 8-pt NTT/INTT with 6-cycle pipelined start/valid interface.
// omega_8 = 4096, inv_8 = 57345.  Twiddle matrix written out explicitly.
// =============================================================================

`ifndef _SUB_NTT_SIMPLE_GUARD
`define _SUB_NTT_SIMPLE_GUARD

module sub_ntt_simple #(
    parameter integer B      = 16,
    parameter integer L      = 8,
    parameter integer WWIDTH = B + 1
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    input  wire                   inverse,
    input  wire [L*WWIDTH-1:0]    in_norm,
    output wire [L*WWIDTH-1:0]    out_norm,
    output wire                   valid
);
    localparam integer Q     = 32'd65537;
    localparam integer INV_L = 32'd57345;

    // -- DFT matrix W[j][k] = omega^((j*k) mod 8), omega=4096 --
    //   omega^0=1, ^1=4096, ^2=65281, ^3=16, ^4=65536, ^5=61441, ^6=256, ^7=65521
    //   For inverse: W_inv[j][k] = inv_omega^((j*k) mod 8) where inv_omega=65521=omega^7
    //                            = omega^((7*j*k) mod 8)

    // ---- Input register ----
    reg [L*WWIDTH-1:0] in_reg;
    reg                start_reg;
    reg                inverse_reg;
    always @(posedge clk) begin
        in_reg      <= in_norm;
        start_reg   <= start;
        inverse_reg <= inverse;
    end

    // Slice helpers
    wire [WWIDTH-1:0] x [0:7];
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_x
            assign x[gi] = in_reg[gi*WWIDTH +: WWIDTH];
        end
    endgenerate

    // omega^k table (forward) and  omega^(7k mod 8) (inverse)
    wire [WWIDTH-1:0] w_fwd [0:7];
    wire [WWIDTH-1:0] w_inv [0:7];
    assign w_fwd[0] = 17'd1;
    assign w_fwd[1] = 17'd4096;
    assign w_fwd[2] = 17'd65281;
    assign w_fwd[3] = 17'd16;
    assign w_fwd[4] = 17'd65536;
    assign w_fwd[5] = 17'd61441;
    assign w_fwd[6] = 17'd256;
    assign w_fwd[7] = 17'd65521;
    // w_inv[k] = w_fwd[7k mod 8]
    assign w_inv[0] = w_fwd[0];   // 0
    assign w_inv[1] = w_fwd[7];   // 7
    assign w_inv[2] = w_fwd[6];   // 14 % 8 = 6
    assign w_inv[3] = w_fwd[5];   // 21 % 8 = 5
    assign w_inv[4] = w_fwd[4];   // 28 % 8 = 4
    assign w_inv[5] = w_fwd[3];   // 35 % 8 = 3
    assign w_inv[6] = w_fwd[2];   // 42 % 8 = 2
    assign w_inv[7] = w_fwd[1];   // 49 % 8 = 1

    // For each output j, compute sum_k x[k] * W[j][k] where W[j][k] = w_fwd[(j*k) mod 8]
    // Since L=8, (j*k) mod 8 is in [0,7], so we use w_fwd indexed by that.
    // We need integer mul + mod q reduction.  Use a function for clarity.
    function automatic [WWIDTH-1:0] mul_mod_q;
        input [WWIDTH-1:0] a, b;
        reg [33:0] prod;
        begin
            prod = a * b;
            // Reduce mod 65537 = 2^16+1.  prod up to (65536)^2 < 2^32, fits in 34 bits.
            // Decompose prod = low + 2^16 * high.  low - high mod q.
            mul_mod_q = (prod[15:0] + prod[33:16] * 65535) % Q;
        end
    endfunction

    wire [WWIDTH-1:0] o_fwd [0:7];
    wire [WWIDTH-1:0] o_inv [0:7];
    genvar gj;
    generate
        for (gj = 0; gj < 8; gj = gj + 1) begin : g_dft
            // out[j] = sum_{k=0..7} x[k] * w_fwd[(j*k) mod 8]
            wire [33:0] term_f0 = x[0] * w_fwd[(gj*0) % 8];
            wire [33:0] term_f1 = x[1] * w_fwd[(gj*1) % 8];
            wire [33:0] term_f2 = x[2] * w_fwd[(gj*2) % 8];
            wire [33:0] term_f3 = x[3] * w_fwd[(gj*3) % 8];
            wire [33:0] term_f4 = x[4] * w_fwd[(gj*4) % 8];
            wire [33:0] term_f5 = x[5] * w_fwd[(gj*5) % 8];
            wire [33:0] term_f6 = x[6] * w_fwd[(gj*6) % 8];
            wire [33:0] term_f7 = x[7] * w_fwd[(gj*7) % 8];
            wire [37:0] sum_f = term_f0 + term_f1 + term_f2 + term_f3 +
                                term_f4 + term_f5 + term_f6 + term_f7;
            assign o_fwd[gj] = (sum_f % Q);

            wire [33:0] term_i0 = x[0] * w_inv[(gj*0) % 8];
            wire [33:0] term_i1 = x[1] * w_inv[(gj*1) % 8];
            wire [33:0] term_i2 = x[2] * w_inv[(gj*2) % 8];
            wire [33:0] term_i3 = x[3] * w_inv[(gj*3) % 8];
            wire [33:0] term_i4 = x[4] * w_inv[(gj*4) % 8];
            wire [33:0] term_i5 = x[5] * w_inv[(gj*5) % 8];
            wire [33:0] term_i6 = x[6] * w_inv[(gj*6) % 8];
            wire [33:0] term_i7 = x[7] * w_inv[(gj*7) % 8];
            wire [37:0] sum_i_raw = term_i0 + term_i1 + term_i2 + term_i3 +
                                    term_i4 + term_i5 + term_i6 + term_i7;
            wire [37:0] sum_i_q   = sum_i_raw % Q;
            wire [54:0] sum_i_scaled = sum_i_q * INV_L;
            assign o_inv[gj] = (sum_i_scaled % Q);
        end
    endgenerate

    // Pack to bus and select fwd/inv
    wire [L*WWIDTH-1:0] dft_sel;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_pack
            assign dft_sel[gi*WWIDTH +: WWIDTH] = inverse_reg ? o_inv[gi] : o_fwd[gi];
        end
    endgenerate

    // Pipeline registers: 5 bubble stages for total LATENCY = 6 cycles
    reg [L*WWIDTH-1:0] s1, s2, s3, s4, s5;
    reg                v1, v2, v3, v4, v5;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s1<=0; s2<=0; s3<=0; s4<=0; s5<=0;
            v1<=0; v2<=0; v3<=0; v4<=0; v5<=0;
        end else begin
            s1 <= dft_sel; s2 <= s1; s3 <= s2; s4 <= s3; s5 <= s4;
            v1 <= start_reg; v2 <= v1; v3 <= v2; v4 <= v3; v5 <= v4;
        end
    end
    assign out_norm = s5;
    assign valid    = v5;

endmodule

`endif
