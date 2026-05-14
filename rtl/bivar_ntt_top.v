// =============================================================================
// bivar_ntt_top.v
// Kim et al. (2024) Bivariate NTT Polynomial Multiplier.
//
// Computes C(X) = A(X)*B(X) mod (X^N+1) over Z/(2^B+1)Z.
//
// Implements the algebraic embedding X2 = X1^(L) with L=N/M:
//   Basis: {X1^i1 * X2^i2 | i1 in [0,L), i2 in [0,M)}  L*M = N
//   Index: natural polynomial index i = i1*M + i2 (row-major)
//
// Parameters (q=65537, L=8 fixed by Fermat prime structure):
//   L = 8   (row/X1 dimension, shift-only 8-pt NTT via r2ntt_r8,   WEXP=12)
//   M = N/8 (col/X2 dimension, shift-only M-pt NTT; WEXP depends on N)
//     N=64  → M=8,  col uses r2ntt_r8   WEXP=12
//     N=128 → M=16, col uses r2ntt_r16  WEXP=6
//     N=256 → M=32, col uses r2ntt_r32  WEXP=19 (default)
//
// Hardware savings: row and col butterflies are shift-only (no DSP multiplier).
// mod_mul_fermat only for: pre-twist, cross-twiddle, PWM, un-twist.
//
// Pipeline: LOAD -> FWD_ROW_A -> FWD_XTW_A -> FWD_COL_A ->
//                   FWD_ROW_B -> FWD_XTW_B -> FWD_COL_B ->
//                   PWM -> INV_COL -> INV_XTW -> INV_ROW -> OUTPUT
// =============================================================================

`ifndef _BIVAR_NTT_TOP_GUARD
`define _BIVAR_NTT_TOP_GUARD

module bivar_ntt_top #(
    parameter B       = 16,
    parameter L       = 8,
    parameter M       = 32,
    parameter N       = L * M,    // derived; override only if tools require it
    parameter WWIDTH  = B + 1,
    parameter TW_BITS = $clog2(2*N)
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,
    input  wire [WWIDTH-1:0] data_in_a,
    input  wire [WWIDTH-1:0] data_in_b,
    output reg  [WWIDTH-1:0] data_out,
    output reg               data_out_valid,
    output reg               done,
    output reg  [15:0]       cycle_count
);
    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_LOAD      = 4'd1,
        ST_FWD_ROW_A = 4'd2,
        ST_FWD_XTW_A = 4'd3,
        ST_FWD_COL_A = 4'd4,
        ST_FWD_ROW_B = 4'd5,
        ST_FWD_XTW_B = 4'd6,
        ST_FWD_COL_B = 4'd7,
        ST_PWM       = 4'd8,
        ST_INV_COL   = 4'd9,
        ST_INV_XTW   = 4'd10,
        ST_INV_ROW   = 4'd11,
        ST_OUTPUT    = 4'd12,
        ST_DONE      = 4'd13;

    reg [3:0] state;
    reg [7:0] op_count;

    // Memory arrays: all N=256 entries.
    // Addressing: raw_a[i1*M + i2] = a[i1*M + i2] (row-major index).
    reg [WWIDTH-1:0] raw_a  [0:N-1];
    reg [WWIDTH-1:0] raw_b  [0:N-1];
    // work[i2*L + j1]: post-row-NTT data, indexed by (i2, j1).
    reg [WWIDTH-1:0] work   [0:N-1];
    // trans[j1*M + i2]: post-cross-twiddle, indexed by (j1, i2).
    reg [WWIDTH-1:0] trans  [0:N-1];
    reg [WWIDTH-1:0] spec_a [0:N-1];
    reg [WWIDTH-1:0] spec_b [0:N-1];
    // prod[j1*M + j2]: pointwise product in frequency domain.
    reg [WWIDTH-1:0] prod   [0:N-1];
    // result[i1*M + i2]: output coefficients in row-major index order.
    reg [WWIDTH-1:0] result [0:N-1];

    // L=8 twiddle and multiplier lanes.
    reg  [L*WWIDTH-1:0]  mul_a_pack;
    reg  [L*WWIDTH-1:0]  mul_b_pack;
    wire [L*WWIDTH-1:0]  mul_out_pack;
    wire [L*WWIDTH-1:0]  tw_pack;
    wire [L*TW_BITS-1:0] tw_idx_pack;

    // 8-pt row NTT I/O.
    reg  [L*WWIDTH-1:0] ntt8_in_pack;
    wire [L*WWIDTH-1:0] ntt8_out_pack;

    // M-pt col NTT I/O.
    reg  [M*WWIDTH-1:0] nttM_in_pack;
    wire [M*WWIDTH-1:0] nttM_out_pack;

    wire inverse_subntt8 = (state == ST_INV_ROW);
    wire inverse_subnttM = (state == ST_INV_COL);

    function [TW_BITS-1:0] inv_tw_idx;
        input [TW_BITS-1:0] idx;
        begin
            inv_tw_idx = ((2*N) - idx) % (2*N);
        end
    endfunction

    // Twiddle index generation per lane (ci = i1 or j1 depending on state).
    genvar tg;
    generate
        for (tg = 0; tg < L; tg = tg + 1) begin : gen_tw_lanes
            // Pre-twist (FWD_ROW): psi^{i1*M + i2} = psi^{tg*M + op_count}
            wire [TW_BITS-1:0] lane_tw_fwd_row  = (tg * M + op_count) % (2*N);
            // Cross-twiddle (FWD_XTW): psi^{2*i2*j1} = psi^{2*op_count*tg}
            wire [TW_BITS-1:0] lane_tw_cross    = (2 * op_count * tg) % (2*N);
            // Inverse cross-twiddle (INV_XTW): psi^{-(2*j1*i2)} = psi^{-(2*tg*op_count)}
            wire [TW_BITS-1:0] lane_tw_inv_cross = inv_tw_idx((2 * tg * op_count) % (2*N));
            // Un-twist (INV_ROW): psi^{-(i1*M + i2)} = psi^{-(tg*M + op_count)}
            wire [TW_BITS-1:0] lane_tw_inv_row   = inv_tw_idx((tg * M + op_count) % (2*N));

            assign tw_idx_pack[tg*TW_BITS +: TW_BITS] =
                ((state == ST_FWD_ROW_A) || (state == ST_FWD_ROW_B)) ? lane_tw_fwd_row   :
                ((state == ST_FWD_XTW_A) || (state == ST_FWD_XTW_B)) ? lane_tw_cross     :
                (state == ST_INV_XTW)                                  ? lane_tw_inv_cross :
                (state == ST_INV_ROW)                                  ? lane_tw_inv_row   :
                {TW_BITS{1'b0}};

            twiddle_lookup #(.B(B), .N(N)) u_tw (
                .tw_idx (tw_idx_pack[tg*TW_BITS +: TW_BITS]),
                .tw_val (tw_pack[tg*WWIDTH +: WWIDTH])
            );

            mod_mul_fermat #(B) u_mul (
                .clk    (clk),
                .rst    (rst),
                .a      (mul_a_pack[tg*WWIDTH +: WWIDTH]),
                .b      (mul_b_pack[tg*WWIDTH +: WWIDTH]),
                .result (mul_out_pack[tg*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    bivar_ntt_subntt8 #(.B(B), .L(L), .WWIDTH(WWIDTH)) u_subntt8 (
        .inverse  (inverse_subntt8),
        .in_norm  (ntt8_in_pack),
        .out_norm (ntt8_out_pack)
    );

    // Column NTT: select core based on M (determined by N=L*M with L=8 fixed).
    // All three cases are shift-only for q=65537:
    //   M=8:  omega_8  = psi_{64}^{16}  = 2^12 (reuses r2ntt_r8, WEXP=12)
    //   M=16: omega_16 = psi_{128}^{16} = 2^6  (r2ntt_r16, WEXP=6)
    //   M=32: omega_32 = psi_{256}^{16} = 2^19 (r2ntt_r32, WEXP=19)
    generate
        if (M == 8) begin : gen_col_ntt
            bivar_ntt_subntt8 #(.B(B), .L(8), .WWIDTH(WWIDTH)) u_subnttM (
                .inverse  (inverse_subnttM),
                .in_norm  (nttM_in_pack),
                .out_norm (nttM_out_pack)
            );
        end else if (M == 16) begin : gen_col_ntt
            bivar_ntt_subntt16 #(.B(B), .M(16), .WWIDTH(WWIDTH)) u_subnttM (
                .inverse  (inverse_subnttM),
                .in_norm  (nttM_in_pack),
                .out_norm (nttM_out_pack)
            );
        end else begin : gen_col_ntt
            bivar_ntt_subntt32 #(.B(B), .M(M), .WWIDTH(WWIDTH)) u_subnttM (
                .inverse  (inverse_subnttM),
                .in_norm  (nttM_in_pack),
                .out_norm (nttM_out_pack)
            );
        end
    endgenerate

    integer ci;

    // Combinational: 8-pt NTT input packing.
    always @(*) begin
        ntt8_in_pack = {L*WWIDTH{1'b0}};
        for (ci = 0; ci < L; ci = ci + 1) begin
            case (state)
                ST_FWD_ROW_A,
                ST_FWD_ROW_B:
                    // Post-multiply pre-twisted elements feed the row NTT.
                    ntt8_in_pack[ci*WWIDTH +: WWIDTH] = mul_out_pack[ci*WWIDTH +: WWIDTH];
                ST_INV_ROW:
                    // Inverse row NTT input: trans[i2*L + j1] for j1=0..L-1.
                    ntt8_in_pack[ci*WWIDTH +: WWIDTH] = trans[op_count*L + ci];
                default:
                    ntt8_in_pack[ci*WWIDTH +: WWIDTH] = {WWIDTH{1'b0}};
            endcase
        end
    end

    // Combinational: 32-pt NTT input packing.
    always @(*) begin
        nttM_in_pack = {M*WWIDTH{1'b0}};
        for (ci = 0; ci < M; ci = ci + 1) begin
            case (state)
                ST_FWD_COL_A,
                ST_FWD_COL_B:
                    // Column NTT input: trans[j1*M + i2] for i2=0..M-1.
                    nttM_in_pack[ci*WWIDTH +: WWIDTH] = trans[op_count*M + ci];
                ST_INV_COL:
                    // Inverse column NTT input: prod[j1*M + j2] for j2=0..M-1.
                    nttM_in_pack[ci*WWIDTH +: WWIDTH] = prod[op_count*M + ci];
                default:
                    nttM_in_pack[ci*WWIDTH +: WWIDTH] = {WWIDTH{1'b0}};
            endcase
        end
    end

    // Combinational: multiplier input packing.
    always @(*) begin
        mul_a_pack = {L*WWIDTH{1'b0}};
        mul_b_pack = {L*WWIDTH{1'b0}};
        for (ci = 0; ci < L; ci = ci + 1) begin
            case (state)
                ST_FWD_ROW_A: begin
                    // Pre-twist A: raw_a[i1*M + i2] * psi^{i1*M + i2}  (ci=i1, op_count=i2)
                    mul_a_pack[ci*WWIDTH +: WWIDTH] = raw_a[ci*M + op_count];
                    mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack[ci*WWIDTH +: WWIDTH];
                end
                ST_FWD_ROW_B: begin
                    // Pre-twist B: raw_b[i1*M + i2] * psi^{i1*M + i2}  (ci=i1, op_count=i2)
                    mul_a_pack[ci*WWIDTH +: WWIDTH] = raw_b[ci*M + op_count];
                    mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack[ci*WWIDTH +: WWIDTH];
                end
                ST_FWD_XTW_A: begin
                    // Cross-twiddle A: work[i2*L + j1] * psi^{2*i2*j1}
                    mul_a_pack[ci*WWIDTH +: WWIDTH] = work[op_count*L + ci];
                    mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack[ci*WWIDTH +: WWIDTH];
                end
                ST_FWD_XTW_B: begin
                    // Cross-twiddle B.
                    mul_a_pack[ci*WWIDTH +: WWIDTH] = work[op_count*L + ci];
                    mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack[ci*WWIDTH +: WWIDTH];
                end
                ST_PWM: begin
                    // Pointwise multiply: spec_a[j1*M + j2] * spec_b[j1*M + j2].
                    // op_count = j2 (0..M-1); ci = j1 (0..L-1).
                    mul_a_pack[ci*WWIDTH +: WWIDTH] = spec_a[ci*M + op_count];
                    mul_b_pack[ci*WWIDTH +: WWIDTH] = spec_b[ci*M + op_count];
                end
                ST_INV_XTW: begin
                    // Inverse cross-twiddle: work[j1*M + i2] * psi^{-(2*j1*i2)}.
                    // op_count = i2; ci = j1.
                    mul_a_pack[ci*WWIDTH +: WWIDTH] = work[ci*M + op_count];
                    mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack[ci*WWIDTH +: WWIDTH];
                end
                ST_INV_ROW: begin
                    // Un-twist: ntt8_out[i1] * psi^{-(i2*L + i1)}.
                    mul_a_pack[ci*WWIDTH +: WWIDTH] = ntt8_out_pack[ci*WWIDTH +: WWIDTH];
                    mul_b_pack[ci*WWIDTH +: WWIDTH] = tw_pack[ci*WWIDTH +: WWIDTH];
                end
                default: begin end
            endcase
        end
    end

    integer wi;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= ST_IDLE;
            op_count       <= 8'd0;
            cycle_count    <= 16'd0;
            data_out       <= {WWIDTH{1'b0}};
            data_out_valid <= 1'b0;
            done           <= 1'b0;
        end else begin
            data_out_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    done        <= 1'b0;
                    op_count    <= 8'd0;
                    cycle_count <= 16'd0;
                    if (start)
                        state <= ST_LOAD;
                end

                // Load N coefficients sequentially (natural index order).
                ST_LOAD: begin
                    raw_a[op_count] <= data_in_a;
                    raw_b[op_count] <= data_in_b;
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == N-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_ROW_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Forward row NTT for A: op_count = i2 (0..M-1=31).
                // Pre-twist L elements at raw_a[i2*L .. i2*L+L-1], then 8-pt NTT.
                // work[i2*L + j1] = row NTT output.
                ST_FWD_ROW_A: begin
                    for (wi = 0; wi < L; wi = wi + 1)
                        work[op_count*L + wi] <= ntt8_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_XTW_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Cross-twiddle for A: op_count = i2 (0..M-1=31).
                // work[i2*L + j1] *= psi^{2*i2*j1}; transpose to trans[j1*M + i2].
                ST_FWD_XTW_A: begin
                    for (wi = 0; wi < L; wi = wi + 1)
                        trans[wi*M + op_count] <= mul_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_COL_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Column NTT for A: op_count = j1 (0..L-1=7).
                // 32-pt NTT on trans[j1*M + i2] for i2=0..31.
                // spec_a[j1*M + j2] = frequency-domain output.
                ST_FWD_COL_A: begin
                    for (wi = 0; wi < M; wi = wi + 1)
                        spec_a[op_count*M + wi] <= nttM_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_ROW_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_ROW_B: begin
                    for (wi = 0; wi < L; wi = wi + 1)
                        work[op_count*L + wi] <= ntt8_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_XTW_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_XTW_B: begin
                    for (wi = 0; wi < L; wi = wi + 1)
                        trans[wi*M + op_count] <= mul_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_COL_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_COL_B: begin
                    for (wi = 0; wi < M; wi = wi + 1)
                        spec_b[op_count*M + wi] <= nttM_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L-1) begin
                        op_count <= 8'd0;
                        state    <= ST_PWM;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Pointwise multiply: op_count = j2 (0..M-1=31).
                // prod[j1*M + j2] = spec_a[j1*M+j2] * spec_b[j1*M+j2] for j1=0..L-1.
                ST_PWM: begin
                    for (wi = 0; wi < L; wi = wi + 1)
                        prod[wi*M + op_count] <= mul_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_INV_COL;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Inverse column NTT: op_count = j1 (0..L-1=7).
                // 32-pt INTT on prod[j1*M + j2]; work[j1*M + i2] = INTT output.
                ST_INV_COL: begin
                    for (wi = 0; wi < M; wi = wi + 1)
                        work[op_count*M + wi] <= nttM_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L-1) begin
                        op_count <= 8'd0;
                        state    <= ST_INV_XTW;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Inverse cross-twiddle: op_count = i2 (0..M-1=31).
                // work[j1*M + i2] *= psi^{-(2*j1*i2)}; transpose to trans[i2*L + j1].
                ST_INV_XTW: begin
                    for (wi = 0; wi < L; wi = wi + 1)
                        trans[op_count*L + wi] <= mul_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_INV_ROW;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Inverse row NTT + un-twist: op_count = i2 (0..M-1=31).
                // 8-pt INTT on trans[i2*L + j1]; then un-twist by psi^{-(i1*M + i2)}.
                // result[i1*M + i2] = final coefficient (row-major).
                ST_INV_ROW: begin
                    for (wi = 0; wi < L; wi = wi + 1)
                        result[wi*M + op_count] <= mul_out_pack[wi*WWIDTH +: WWIDTH];
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_OUTPUT;
                    end else
                        op_count <= op_count + 1'b1;
                end

                // Output N coefficients in natural index order.
                ST_OUTPUT: begin
                    data_out       <= result[op_count];
                    data_out_valid <= 1'b1;
                    cycle_count    <= cycle_count + 1'b1;
                    if (op_count == N-1) begin
                        op_count <= 8'd0;
                        done     <= 1'b1;
                        state    <= ST_DONE;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_DONE: begin
                    done <= 1'b1;
                    if (!start) begin
                        op_count <= 8'd0;
                        state    <= ST_IDLE;
                    end
                end

                default: begin
                    state    <= ST_IDLE;
                    op_count <= 8'd0;
                end
            endcase
        end
    end
endmodule

`endif // _BIVAR_NTT_TOP_GUARD
