// =============================================================================
// r2intt_r8.v
// Fixed 8-point DIF-INTT butterfly in D1 representation.
// - Substage order follows Algorithm 2 (delta: 1 -> 2 -> 4).
// - Mixed-radix mode reuses the last 2 substages (RHAT=4 case).
// =============================================================================

module r2intt_r8 #(
    parameter B = 16,
    parameter N = 256
)(
    input  wire [8*(B+1)-1:0] in_d1,
    input  wire               is_Rhat_stage,
    output wire [8*(B+1)-1:0] out_d1
);
    localparam integer R      = 8;
    localparam integer WWIDTH = B + 1;
    // For N=256, q=65537 and the project twiddle root: omega_8 = 2^12.
    localparam integer WEXP   = 12;

    function integer bit_reverse_small;
        input integer val;
        input integer bits;
        integer bi;
        begin
            bit_reverse_small = 0;
            for (bi = 0; bi < bits; bi = bi + 1)
                bit_reverse_small = (bit_reverse_small << 1) | ((val >> bi) & 1);
        end
    endfunction

    function integer tw_mod;
        input integer exp;
        integer t;
        begin
            t = (WEXP * exp) % (2 * B);
            if (t < 0)
                t = t + (2 * B);
            tw_mod = t;
        end
    endfunction

    function integer twinv_mod;
        input integer exp;
        begin
            twinv_mod = ((2 * B) - tw_mod(exp)) % (2 * B);
        end
    endfunction

    function integer twinv_k;
        input integer exp;
        integer t;
        begin
            t = twinv_mod(exp);
            twinv_k = (t >= B) ? (t - B) : t;
        end
    endfunction

    function integer twinv_neg;
        input integer exp;
        integer t;
        begin
            t = twinv_mod(exp);
            twinv_neg = (t >= B) ? 1 : 0;
        end
    endfunction

    wire [B:0] x        [0:R-1];
    wire [B:0] s0_full  [0:R-1];
    wire [B:0] s1_full  [0:R-1];
    wire [B:0] s2_full  [0:R-1];
    wire [B:0] s1_rhat  [0:R-1];
    wire [B:0] s2_rhat  [0:R-1];

    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_unpack
            assign x[i] = in_d1[i*WWIDTH +: WWIDTH];
        end
    endgenerate

    // Full INTT substage s=2, delta=1, exponent = bitrev2(b).
    genvar b0;
    generate
        for (b0 = 0; b0 < 4; b0 = b0 + 1) begin : gen_full_s0
            localparam integer IDX0 = b0 * 2;
            localparam integer E0   = bit_reverse_small(b0, 2);
            localparam integer K0   = twinv_k(E0);
            localparam integer N0   = twinv_neg(E0);
            r2intt_butterfly_pow2 #(.B(B), .K(K0), .NEG(N0)) u_bf (
                .a     (x[IDX0]),
                .b     (x[IDX0 + 1]),
                .a_out (s0_full[IDX0]),
                .b_out (s0_full[IDX0 + 1])
            );
        end
    endgenerate

    // Full INTT substage s=1, delta=2, exponent = bitrev1(b)*2.
    genvar b1, g1;
    generate
        for (b1 = 0; b1 < 2; b1 = b1 + 1) begin : gen_full_s1_b
            for (g1 = 0; g1 < 2; g1 = g1 + 1) begin : gen_full_s1_g
                localparam integer IDX1 = b1 * 4 + g1;
                localparam integer E1   = bit_reverse_small(b1, 1) * 2;
                localparam integer K1   = twinv_k(E1);
                localparam integer N1   = twinv_neg(E1);
                r2intt_butterfly_pow2 #(.B(B), .K(K1), .NEG(N1)) u_bf (
                    .a     (s0_full[IDX1]),
                    .b     (s0_full[IDX1 + 2]),
                    .a_out (s1_full[IDX1]),
                    .b_out (s1_full[IDX1 + 2])
                );
            end
        end
    endgenerate

    // Full INTT substage s=0, delta=4, twiddle = 1.
    genvar g2;
    generate
        for (g2 = 0; g2 < 4; g2 = g2 + 1) begin : gen_full_s2
            r2intt_butterfly_pow2 #(.B(B), .K(0), .NEG(0)) u_bf (
                .a     (s1_full[g2]),
                .b     (s1_full[g2 + 4]),
                .a_out (s2_full[g2]),
                .b_out (s2_full[g2 + 4])
            );
        end
    endgenerate

    // Mixed-radix reuse: last 2 substages only (s=1 then s=0).
    generate
        for (b1 = 0; b1 < 2; b1 = b1 + 1) begin : gen_rhat_s1_b
            for (g1 = 0; g1 < 2; g1 = g1 + 1) begin : gen_rhat_s1_g
                localparam integer IDX1R = b1 * 4 + g1;
                localparam integer E1R   = bit_reverse_small(b1, 1) * 2;
                localparam integer K1R   = twinv_k(E1R);
                localparam integer N1R   = twinv_neg(E1R);
                r2intt_butterfly_pow2 #(.B(B), .K(K1R), .NEG(N1R)) u_bf (
                    .a     (x[IDX1R]),
                    .b     (x[IDX1R + 2]),
                    .a_out (s1_rhat[IDX1R]),
                    .b_out (s1_rhat[IDX1R + 2])
                );
            end
        end
    endgenerate

    generate
        for (g2 = 0; g2 < 4; g2 = g2 + 1) begin : gen_rhat_s2
            r2intt_butterfly_pow2 #(.B(B), .K(0), .NEG(0)) u_bf (
                .a     (s1_rhat[g2]),
                .b     (s1_rhat[g2 + 4]),
                .a_out (s2_rhat[g2]),
                .b_out (s2_rhat[g2 + 4])
            );
        end
    endgenerate

    generate
        for (i = 0; i < R; i = i + 1) begin : gen_pack
            assign out_d1[i*WWIDTH +: WWIDTH] = is_Rhat_stage ? s2_rhat[i] : s2_full[i];
        end
    endgenerate
endmodule
