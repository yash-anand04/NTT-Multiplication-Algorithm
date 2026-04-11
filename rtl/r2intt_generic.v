// =============================================================================
// r2intt_generic.v
// Generic R-point DIF-INTT core in D1 domain for R = 8/16 style configurations.
// - Full mode: computes R-point inverse NTT with R^{-1} scaling.
// - Mixed-radix mode (is_Rhat_stage): computes RHAT-point inverse NTTs on
//   interleaved groups with RHAT^{-1} scaling (last log(RHAT) substages behavior).
// =============================================================================

module r2intt_generic #(
    parameter B = 16,
    parameter N = 256,
    parameter R = 8
)(
    input  wire [R*(B+1)-1:0] in_d1,
    input  wire               is_Rhat_stage,
    output reg  [R*(B+1)-1:0] out_d1
);
    localparam integer WWIDTH = B + 1;
    localparam integer Q      = (1 << B) + 1;
    localparam integer LOGR   = $clog2(R);
    localparam integer LOGN   = $clog2(N);
    localparam integer STAGES = (LOGR == 0) ? 0 : (LOGN / LOGR);
    localparam integer RPOW   = R ** STAGES;
    localparam integer RHAT   = (RPOW != 0) ? (N / RPOW) : 1;
    localparam integer R2     = (RHAT != 0) ? (R / RHAT) : 1;
    localparam integer STEP   = (R != 0) ? ((2 * N) / R) : 0;
    localparam integer USE_RHAT = (RHAT > 1) && ((R % RHAT) == 0);

    localparam integer R_INV = (LOGR <= B) ? (Q - (1 << (B - LOGR))) : 0;
    localparam integer LOGRH = (RHAT > 1) ? $clog2(RHAT) : 0;
    localparam integer RHAT_INV = (RHAT > 1 && LOGRH <= B) ? (Q - (1 << (B - LOGRH))) : 1;

    reg [B:0] tw_mem [0:(2*N)-1];
    initial begin
        $readmemh("twiddle_factors.hex", tw_mem);
    end

    integer i, j, r1, r2;
    integer lane_in, lane_out;
    integer tw_idx;
    reg [B:0] x_norm [0:R-1];
    reg [B:0] y_norm [0:R-1];
    reg [B:0] acc;
    reg [B:0] prod;
    reg [B:0] tw;

    always @(*) begin
        // Unpack D1 inputs and clear outputs.
        for (i = 0; i < R; i = i + 1) begin
            if (in_d1[i*WWIDTH +: WWIDTH] == (1'b1 << B))
                x_norm[i] = {WWIDTH{1'b0}};
            else
                x_norm[i] = in_d1[i*WWIDTH +: WWIDTH] + 1'b1;
            y_norm[i] = {WWIDTH{1'b0}};
        end

        if (is_Rhat_stage && USE_RHAT) begin
            // Mixed-radix special stage: RHAT-point inverse NTT across interleaved lanes.
            for (r2 = 0; r2 < R2; r2 = r2 + 1) begin
                for (j = 0; j < RHAT; j = j + 1) begin
                    acc = {WWIDTH{1'b0}};
                    for (r1 = 0; r1 < RHAT; r1 = r1 + 1) begin
                        lane_in = r1 * R2 + r2;
                        tw_idx = (r1 * j * R2 * STEP) % (2 * N);
                        tw = tw_mem[((2 * N) - tw_idx) % (2 * N)];
                        prod = (x_norm[lane_in] * tw) % Q;
                        acc = (acc + prod) % Q;
                    end
                    lane_out = j * R2 + r2;
                    y_norm[lane_out] = (acc * RHAT_INV) % Q;
                end
            end
        end else begin
            // Full R-point inverse NTT.
            for (j = 0; j < R; j = j + 1) begin
                acc = {WWIDTH{1'b0}};
                for (i = 0; i < R; i = i + 1) begin
                    tw_idx = (i * j * STEP) % (2 * N);
                    tw = tw_mem[((2 * N) - tw_idx) % (2 * N)];
                    prod = (x_norm[i] * tw) % Q;
                    acc = (acc + prod) % Q;
                end
                y_norm[j] = (acc * R_INV) % Q;
            end
        end

        // Pack back to D1.
        for (i = 0; i < R; i = i + 1) begin
            if (y_norm[i] == {WWIDTH{1'b0}})
                out_d1[i*WWIDTH +: WWIDTH] = (1'b1 << B);
            else
                out_d1[i*WWIDTH +: WWIDTH] = y_norm[i] - 1'b1;
        end
    end
endmodule
