// =============================================================================
// sub_ntt16_bidir.v
// Bidirectional 16-pt shift-only NTT/INTT over F₄ = 65537.
// omega_16 = 2^2 = 4 (primitive 16th root).
// 4 DIT substages, 8 butterflies per stage = 32 butterflies total.
// 5-cycle latency (1 input reg + 4 substage regs).
// =============================================================================

`ifndef _SUB_NTT16_BIDIR_GUARD
`define _SUB_NTT16_BIDIR_GUARD

(* USE_DSP = "no" *)
module sub_ntt16_bidir #(
    parameter B      = 16,
    parameter WWIDTH = B + 1
)(
    input  wire                  clk, rst, start, inverse,
    input  wire [16*WWIDTH-1:0]  in_norm,
    output wire [16*WWIDTH-1:0]  out_norm,
    output wire                  valid
);
    localparam integer R    = 16;
    // omega_16 = 3^((q-1)/16) mod q = 2^6 = 64 (canonical, matches Python).
    // (Previously used 2^2 = 4; valid primitive 16th root but wrong convention.)
    localparam integer WEXP = 6;

    function integer bit_reverse4;
        input integer val;
        integer bi, r;
        begin
            r = 0;
            for (bi = 0; bi < 4; bi = bi + 1)
                r = (r << 1) | ((val >> bi) & 1);
            bit_reverse4 = r;
        end
    endfunction
    function integer bitrev2;
        input integer v;
        begin bitrev2 = ((v & 1) << 1) | ((v >> 1) & 1); end
    endfunction
    function integer bitrev3;
        input integer v;
        begin bitrev3 = ((v & 1) << 2) | (((v >> 1) & 1) << 1) | ((v >> 2) & 1); end
    endfunction
    function integer tw_mod;
        input integer exp;
        integer t;
        begin t = (WEXP * exp) % (2*B); if (t < 0) t = t + (2*B); tw_mod = t; end
    endfunction
    function integer tw_k;
        input integer exp;
        integer t; begin t = tw_mod(exp); tw_k = (t >= B) ? (t - B) : t; end
    endfunction
    function integer tw_neg;
        input integer exp;
        integer t; begin t = tw_mod(exp); tw_neg = (t >= B) ? 1 : 0; end
    endfunction
    function integer twinv_mod;
        input integer exp;
        begin twinv_mod = ((2*B) - tw_mod(exp)) % (2*B); end
    endfunction
    function integer twinv_k;
        input integer exp;
        integer t; begin t = twinv_mod(exp); twinv_k = (t >= B) ? (t - B) : t; end
    endfunction
    function integer twinv_neg;
        input integer exp;
        integer t; begin t = twinv_mod(exp); twinv_neg = (t >= B) ? 1 : 0; end
    endfunction

    wire [B:0] d1_in [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_in_conv
            norm_to_d1 #(B) u_n2d (.in(in_norm[i*WWIDTH +: WWIDTH]), .out(d1_in[i]));
        end
    endgenerate

    reg [B:0] reg0 [0:R-1];
    wire [B:0] s0 [0:R-1], s1 [0:R-1], s2 [0:R-1], s3 [0:R-1];
    reg [B:0] reg1 [0:R-1], reg2 [0:R-1], reg3 [0:R-1], reg4 [0:R-1];

    // Padded to 6-stage pipe to match sub_ntt32_bidir's latency
    reg [5:0] valid_pipe, inv_pipe;
    always @(posedge clk) begin
        if (rst) begin valid_pipe <= 6'b0; inv_pipe <= 6'b0; end
        else begin
            valid_pipe <= {valid_pipe[4:0], start};
            inv_pipe   <= {inv_pipe[4:0],   inverse & start};
        end
    end
    assign valid = valid_pipe[5];

    // Substage 0: delta=8, 8 butterflies, E=0
    genvar g0;
    generate
        for (g0 = 0; g0 < 8; g0 = g0 + 1) begin : gen_s0
            r2_butterfly_bidir #(.B(B),
                .K_FWD(0), .NEG_FWD(0), .K_INV(0), .NEG_INV(0)) u_bf (
                .inverse(inv_pipe[0]),
                .a(reg0[g0]), .b(reg0[g0 + 8]),
                .a_out(s0[g0]), .b_out(s0[g0 + 8])
            );
        end
    endgenerate

    // Substage 1: delta=4, 2 groups of 4, E = bitrev1(b)*4
    genvar b1, j1;
    generate
        for (b1 = 0; b1 < 2; b1 = b1 + 1) begin : gen_s1_b
            for (j1 = 0; j1 < 4; j1 = j1 + 1) begin : gen_s1_g
                localparam integer IDX = b1 * 8 + j1;
                localparam integer E   = (b1 == 0) ? 0 : 4;
                r2_butterfly_bidir #(.B(B),
                    .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                    .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                    .inverse(inv_pipe[1]),
                    .a(reg1[IDX]), .b(reg1[IDX + 4]),
                    .a_out(s1[IDX]), .b_out(s1[IDX + 4])
                );
            end
        end
    endgenerate

    // Substage 2: delta=2, 4 groups of 2, E = bitrev2(b)*2
    genvar b2, j2;
    generate
        for (b2 = 0; b2 < 4; b2 = b2 + 1) begin : gen_s2_b
            for (j2 = 0; j2 < 2; j2 = j2 + 1) begin : gen_s2_g
                localparam integer IDX = b2 * 4 + j2;
                localparam integer E   = bitrev2(b2) * 2;
                r2_butterfly_bidir #(.B(B),
                    .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                    .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                    .inverse(inv_pipe[2]),
                    .a(reg2[IDX]), .b(reg2[IDX + 2]),
                    .a_out(s2[IDX]), .b_out(s2[IDX + 2])
                );
            end
        end
    endgenerate

    // Substage 3: delta=1, 8 groups, E = bitrev3(b)
    genvar b3;
    generate
        for (b3 = 0; b3 < 8; b3 = b3 + 1) begin : gen_s3
            localparam integer IDX = b3 * 2;
            localparam integer E   = bitrev3(b3);
            r2_butterfly_bidir #(.B(B),
                .K_FWD(tw_k(E)), .NEG_FWD(tw_neg(E)),
                .K_INV(twinv_k(E)), .NEG_INV(twinv_neg(E))) u_bf (
                .inverse(inv_pipe[3]),
                .a(reg3[IDX]), .b(reg3[IDX + 1]),
                .a_out(s3[IDX]), .b_out(s3[IDX + 1])
            );
        end
    endgenerate

    integer ridx;
    always @(posedge clk) begin
        if (rst) begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                reg0[ridx] <= {WWIDTH{1'b0}};
                reg1[ridx] <= {WWIDTH{1'b0}};
                reg2[ridx] <= {WWIDTH{1'b0}};
                reg3[ridx] <= {WWIDTH{1'b0}};
                reg4[ridx] <= {WWIDTH{1'b0}};
            end
        end else begin
            for (ridx = 0; ridx < R; ridx = ridx + 1) begin
                reg0[ridx] <= d1_in[ridx];
                reg1[ridx] <= s0[ridx];
                reg2[ridx] <= s1[ridx];
                reg3[ridx] <= s2[ridx];
                reg4[ridx] <= s3[ridx];
            end
        end
    end

    // 1/16 = 2^-4 = 2^28 = -2^12. K=12, NEG=1.
    // Then 1 stage of padding to match sub_ntt32_bidir's 6-cycle latency.
    wire [B:0] post_d1 [0:R-1];
    wire [B:0] scaled_d1 [0:R-1];
    genvar so;
    generate
        for (so = 0; so < R; so = so + 1) begin : gen_perm
            localparam integer BR = bit_reverse4(so);
            assign post_d1[so] = reg4[BR];
        end
    endgenerate

    genvar oi;
    generate
        for (oi = 0; oi < R; oi = oi + 1) begin : gen_scale
            wire [B:0] shifted_mag;
            wire [B:0] scaled_raw;
            d1_mul_by_2k #(.B(B), .K(12)) u_shift (.in(post_d1[oi]), .out(shifted_mag));
            d1_neg #(B) u_neg (.in(shifted_mag), .out(scaled_raw));
            assign scaled_d1[oi] = inv_pipe[4] ? scaled_raw : post_d1[oi];
        end
    endgenerate

    reg [B:0] pad1 [0:R-1];
    integer padidx;
    always @(posedge clk) begin
        if (rst) begin
            for (padidx = 0; padidx < R; padidx = padidx + 1)
                pad1[padidx] <= {WWIDTH{1'b0}};
        end else begin
            for (padidx = 0; padidx < R; padidx = padidx + 1)
                pad1[padidx] <= scaled_d1[padidx];
        end
    end

    genvar oo;
    generate
        for (oo = 0; oo < R; oo = oo + 1) begin : gen_out_conv
            wire [B:0] norm_out;
            d1_to_norm #(B) u_d2n (.in(pad1[oo]), .out(norm_out));
            assign out_norm[oo*WWIDTH +: WWIDTH] = norm_out;
        end
    endgenerate

endmodule

`endif // _SUB_NTT16_BIDIR_GUARD
