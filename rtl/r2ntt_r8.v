// =============================================================================
// r2ntt_r8.v
// Fixed 8-point DIT-NTT butterfly in D1 representation.
// - Substage order follows Algorithm 1 (delta: 4 -> 2 -> 1).
// - Mixed-radix mode reuses the first 2 substages (RHAT=4 case).
// =============================================================================

module r2ntt_r8 #(
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

    function integer tw_k;
        input integer exp;
        integer t;
        begin
            t = tw_mod(exp);
            tw_k = (t >= B) ? (t - B) : t;
        end
    endfunction

    function integer tw_neg;
        input integer exp;
        integer t;
        begin
            t = tw_mod(exp);
            tw_neg = (t >= B) ? 1 : 0;
        end
    endfunction

    wire [B:0] x  [0:R-1];
    wire [B:0] s0 [0:R-1];
    wire [B:0] s1 [0:R-1];
    wire [B:0] s2 [0:R-1];

    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_unpack
            assign x[i] = in_d1[i*WWIDTH +: WWIDTH];
        end
    endgenerate

    // Substage s=0, delta=4, all twiddles = 1.
    genvar g0;
    generate
        for (g0 = 0; g0 < 4; g0 = g0 + 1) begin : gen_s0
            r2_butterfly #(.B(B), .K(0), .NEG(0)) u_bf (
                .a     (x[g0]),
                .b     (x[g0 + 4]),
                .a_out (s0[g0]),
                .b_out (s0[g0 + 4])
            );
        end
    endgenerate

    // Substage s=1, delta=2, exponent = bitrev1(b)*2.
    genvar b1, g1;
    generate
        for (b1 = 0; b1 < 2; b1 = b1 + 1) begin : gen_s1_b
            for (g1 = 0; g1 < 2; g1 = g1 + 1) begin : gen_s1_g
                localparam integer IDX1 = b1 * 4 + g1;
                localparam integer E1   = bit_reverse_small(b1, 1) * 2;
                localparam integer K1   = tw_k(E1);
                localparam integer N1   = tw_neg(E1);
                r2_butterfly #(.B(B), .K(K1), .NEG(N1)) u_bf (
                    .a     (s0[IDX1]),
                    .b     (s0[IDX1 + 2]),
                    .a_out (s1[IDX1]),
                    .b_out (s1[IDX1 + 2])
                );
            end
        end
    endgenerate

    // Substage s=2, delta=1, exponent = bitrev2(b).
    genvar b2;
    generate
        for (b2 = 0; b2 < 4; b2 = b2 + 1) begin : gen_s2
            localparam integer IDX2 = b2 * 2;
            localparam integer E2   = bit_reverse_small(b2, 2);
            localparam integer K2   = tw_k(E2);
            localparam integer N2   = tw_neg(E2);
            r2_butterfly #(.B(B), .K(K2), .NEG(N2)) u_bf (
                .a     (s1[IDX2]),
                .b     (s1[IDX2 + 1]),
                .a_out (s2[IDX2]),
                .b_out (s2[IDX2 + 1])
            );
        end
    endgenerate

    generate
        for (i = 0; i < R; i = i + 1) begin : gen_pack
            assign out_d1[i*WWIDTH +: WWIDTH] = is_Rhat_stage ? s1[i] : s2[i];
        end
    endgenerate
endmodule
