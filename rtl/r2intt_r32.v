// =============================================================================
// r2intt_r32.v
// Fixed 32-point DIF-INTT in D1 representation (Kim et al. column INTT).
// omega_32 = psi^16 = -8 = 2^19 mod 65537  (WEXP=19).
// r2intt_butterfly_pow2 divides by 2 per stage; 5 stages give 1/32 scaling.
// Input is natural order, output is natural order (DIF + bit-rev correction).
// =============================================================================

`ifndef _R2INTT_R32_GUARD
`define _R2INTT_R32_GUARD

module r2intt_r32 #(
    parameter B = 16
)(
    input  wire [32*(B+1)-1:0] in_d1,
    output wire [32*(B+1)-1:0] out_d1
);
    localparam integer R      = 32;
    localparam integer WWIDTH = B + 1;
    localparam integer WEXP   = 19; // omega_32 = psi^16 = -8 = 2^19 mod 65537

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

    wire [B:0] x  [0:R-1];
    wire [B:0] s0 [0:R-1];
    wire [B:0] s1 [0:R-1];
    wire [B:0] s2 [0:R-1];
    wire [B:0] s3 [0:R-1];
    wire [B:0] s4 [0:R-1];

    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_unpack
            assign x[i] = in_d1[i*WWIDTH +: WWIDTH];
        end
    endgenerate

    // DIF substage s=0 (first): delta=1, 16 groups, E=bitrev4(b).
    genvar b0;
    generate
        for (b0 = 0; b0 < 16; b0 = b0 + 1) begin : gen_s0
            localparam integer IDX0 = b0 * 2;
            localparam integer E0   = bit_reverse_small(b0, 4);
            localparam integer K0   = twinv_k(E0);
            localparam integer N0   = twinv_neg(E0);
            r2intt_butterfly_pow2 #(.B(B), .K(K0), .NEG(N0)) u_bf (
                .a     (x[IDX0]),
                .b     (x[IDX0 + 1]),
                .a_out (s0[IDX0]),
                .b_out (s0[IDX0 + 1])
            );
        end
    endgenerate

    // DIF substage s=1: delta=2, 8 groups, E=bitrev3(b)*2.
    genvar b1, g1;
    generate
        for (b1 = 0; b1 < 8; b1 = b1 + 1) begin : gen_s1_b
            for (g1 = 0; g1 < 2; g1 = g1 + 1) begin : gen_s1_g
                localparam integer IDX1 = b1 * 4 + g1;
                localparam integer E1   = bit_reverse_small(b1, 3) * 2;
                localparam integer K1   = twinv_k(E1);
                localparam integer N1   = twinv_neg(E1);
                r2intt_butterfly_pow2 #(.B(B), .K(K1), .NEG(N1)) u_bf (
                    .a     (s0[IDX1]),
                    .b     (s0[IDX1 + 2]),
                    .a_out (s1[IDX1]),
                    .b_out (s1[IDX1 + 2])
                );
            end
        end
    endgenerate

    // DIF substage s=2: delta=4, 4 groups, E=bitrev2(b)*4.
    genvar b2, g2;
    generate
        for (b2 = 0; b2 < 4; b2 = b2 + 1) begin : gen_s2_b
            for (g2 = 0; g2 < 4; g2 = g2 + 1) begin : gen_s2_g
                localparam integer IDX2 = b2 * 8 + g2;
                localparam integer E2   = bit_reverse_small(b2, 2) * 4;
                localparam integer K2   = twinv_k(E2);
                localparam integer N2   = twinv_neg(E2);
                r2intt_butterfly_pow2 #(.B(B), .K(K2), .NEG(N2)) u_bf (
                    .a     (s1[IDX2]),
                    .b     (s1[IDX2 + 4]),
                    .a_out (s2[IDX2]),
                    .b_out (s2[IDX2 + 4])
                );
            end
        end
    endgenerate

    // DIF substage s=3: delta=8, 2 groups, E=bitrev1(b)*8.
    genvar b3, g3;
    generate
        for (b3 = 0; b3 < 2; b3 = b3 + 1) begin : gen_s3_b
            for (g3 = 0; g3 < 8; g3 = g3 + 1) begin : gen_s3_g
                localparam integer IDX3 = b3 * 16 + g3;
                localparam integer E3   = bit_reverse_small(b3, 1) * 8;
                localparam integer K3   = twinv_k(E3);
                localparam integer N3   = twinv_neg(E3);
                r2intt_butterfly_pow2 #(.B(B), .K(K3), .NEG(N3)) u_bf (
                    .a     (s2[IDX3]),
                    .b     (s2[IDX3 + 8]),
                    .a_out (s3[IDX3]),
                    .b_out (s3[IDX3 + 8])
                );
            end
        end
    endgenerate

    // DIF substage s=4 (last): delta=16, 1 group, twiddle=1.
    genvar g4;
    generate
        for (g4 = 0; g4 < 16; g4 = g4 + 1) begin : gen_s4
            r2intt_butterfly_pow2 #(.B(B), .K(0), .NEG(0)) u_bf (
                .a     (s3[g4]),
                .b     (s3[g4 + 16]),
                .a_out (s4[g4]),
                .b_out (s4[g4 + 16])
            );
        end
    endgenerate

    generate
        for (i = 0; i < R; i = i + 1) begin : gen_pack
            assign out_d1[i*WWIDTH +: WWIDTH] = s4[i];
        end
    endgenerate
endmodule

`endif // _R2INTT_R32_GUARD
