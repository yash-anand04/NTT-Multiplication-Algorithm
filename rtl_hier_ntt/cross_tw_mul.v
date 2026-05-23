// =============================================================================
// cross_tw_mul.v   (Phase B.2)
// LANES-wide cross-twiddle multiplier bank for the hierarchical NTT.
//
// Two modes:
//
//   LEVEL_BOUNDARY = 0  (generic cross-twiddle, used at intra-level positions)
//     LANES parallel 3-stage pipelined mod_mul_fermat instances.
//     data_out[i] = (data_in[i] * tw_in[i]) mod q,  q = 2^B + 1.
//     DSP cost: LANES.
//
//   LEVEL_BOUNDARY = 1  (the architectural contribution)
//     At 32-pt-level boundaries, the cross-twiddle reduces algebraically:
//        psi^(j * 32) = ((2^16)^j) mod (2^16 + 1) = ((-1))^j
//     So the multiplication collapses to a conditional negation governed by
//     the LSB of the level-pair index.  Implementation:
//        data_out[i] = sign_flip_in[i] ? (q - data_in[i]) : data_in[i]
//     DSP cost: 0.
//
// Pipeline depth is 3 cycles in BOTH modes so downstream FSM is mode-agnostic.
// All I/O are in NORMAL representation (matching mod_mul_fermat).
// =============================================================================

`ifndef _CROSS_TW_MUL_GUARD
`define _CROSS_TW_MUL_GUARD

module cross_tw_mul #(
    parameter B              = 16,
    parameter LANES          = 32,
    parameter LEVEL_BOUNDARY = 0,
    parameter WWIDTH         = B + 1
)(
    input  wire                       clk,
    input  wire                       rst,
    input  wire                       valid_in,
    input  wire [LANES*WWIDTH-1:0]    data_in,
    input  wire [LANES*WWIDTH-1:0]    tw_in,        // ignored when LEVEL_BOUNDARY=1
    input  wire [LANES-1:0]           sign_flip_in, // ignored when LEVEL_BOUNDARY=0
    output wire [LANES*WWIDTH-1:0]    data_out,
    output wire                       valid_out
);

    localparam integer Q = (1 << B) + 1;

    genvar i;
    generate
        if (LEVEL_BOUNDARY == 0) begin : gen_modmul
            // ---------------- Generic cross-twiddle -----------------
            wire [WWIDTH-1:0] prod_lane [0:LANES-1];
            for (i = 0; i < LANES; i = i + 1) begin : gen_lane
                (* USE_DSP = "yes" *)
                mod_mul_fermat #(.B(B), .PIPELINED(1)) u_mul (
                    .clk    (clk),
                    .rst    (rst),
                    .a      (data_in[i*WWIDTH +: WWIDTH]),
                    .b      (tw_in  [i*WWIDTH +: WWIDTH]),
                    .result (prod_lane[i])
                );
                assign data_out[i*WWIDTH +: WWIDTH] = prod_lane[i];
            end
        end else begin : gen_signflip
            // ---------------- Sign-flip (zero-DSP) ------------------
            // Stage 1: register data + sign_flip
            // Stage 2: compute conditional q - data
            // Stage 3: register output (matches generic 3-cycle latency)
            reg [WWIDTH-1:0]    s1_data [0:LANES-1];
            reg [LANES-1:0]     s1_sign;
            reg [WWIDTH-1:0]    s2_out  [0:LANES-1];
            reg [WWIDTH-1:0]    s3_out  [0:LANES-1];

            integer k;
            always @(posedge clk) begin
                if (rst) begin
                    s1_sign <= {LANES{1'b0}};
                    for (k = 0; k < LANES; k = k + 1) begin
                        s1_data[k] <= {WWIDTH{1'b0}};
                        s2_out [k] <= {WWIDTH{1'b0}};
                        s3_out [k] <= {WWIDTH{1'b0}};
                    end
                end else begin
                    s1_sign <= sign_flip_in;
                    for (k = 0; k < LANES; k = k + 1) begin
                        s1_data[k] <= data_in[k*WWIDTH +: WWIDTH];
                        // Stage 2: conditional negation
                        //   neg(0) = 0; neg(x) = q - x  for x in [1, q-1]
                        s2_out[k]  <= s1_sign[k]
                                      ? ((s1_data[k] == {WWIDTH{1'b0}})
                                         ? {WWIDTH{1'b0}}
                                         : (Q[WWIDTH-1:0] - s1_data[k]))
                                      : s1_data[k];
                        s3_out[k]  <= s2_out[k];
                    end
                end
            end

            for (i = 0; i < LANES; i = i + 1) begin : gen_out
                assign data_out[i*WWIDTH +: WWIDTH] = s3_out[i];
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // valid pipeline (3 cycles to match data path in both modes)
    // -------------------------------------------------------------------------
    reg [2:0] valid_sr;
    always @(posedge clk) begin
        if (rst) valid_sr <= 3'b0;
        else     valid_sr <= {valid_sr[1:0], valid_in};
    end
    assign valid_out = valid_sr[2];

endmodule

`endif // _CROSS_TW_MUL_GUARD
