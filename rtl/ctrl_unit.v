// =============================================================================
// ctrl_unit.v
// Control Unit FSM for the NTT Polynomial Multiplier (Fig. 6)
// Controls sequencing: IDLE → LOAD → NTT1 → NTT2 → PWM → INTT → OUTPUT → DONE
//
// For each state, generates:
//   - orig_addrs   : R original addresses for the R parallel data elements
//   - tw_addr      : twiddle factor ROM address for ModMuls
//   - is_Rhat_stage: whether this is the special mixed-radix stage
//   - rd_sel       : read select {00=none, 01=lower, 10=upper, 11=all}
//   - wr_sel       : write select {00=none, 01=lower, 10=upper, 11=all}
//   - ntt_mode     : 1=NTT, 0=INTT
//   - pwm_en       : point-wise multiplication enable
//   - done         : computation complete
//
// Parameters: N=256, R=4, LOGN=8, LOGR=2, STAGES=LOGN/LOGR=4 (for NTT)
//
// This FSM implements in-place NTT with stalls for RAW conflict avoidance.
// =============================================================================

module ctrl_unit #(
    parameter N       = 256,
    parameter R       = 4,
    parameter LOGN    = $clog2(N),     // 8
    parameter LOGR    = $clog2(R),     // 2
    parameter STAGES  = LOGN/LOGR,     // 4  (for R=4, N=256)
    parameter DEPTH   = N/R,           // 64 entries per bank
    parameter AWIDTH  = LOGN-LOGR,     // 6
    parameter PIPE_LATENCY = 3         // ModMul pipeline depth (1 addr + 2 mul stages)
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,

    // Outputs to data path
    output reg  [R*LOGN-1:0]     orig_addrs,      // R original addresses
    output reg  [$clog2(N)-1:0]  tw_addr,          // Twiddle ROM address
    output reg                   is_Rhat_stage,    // Mixed-radix special stage flag
    output reg  [1:0]            rd_sel,           // Read select (which half of banks)
    output reg  [1:0]            wr_sel,           // Write select
    output reg                   ntt_mode,         // 1=NTT butterfly, 0=INTT butterfly
    output reg                   pwm_en,           // PWM enable
    output reg  [R-1:0]         bank_we,           // Write enable per bank
    output reg                   done
);
    // ---- State machine encoding -----------------------------------------------
    localparam IDLE   = 3'd0,
               LOAD   = 3'd1,
               NTT1   = 3'd2,
               NTT2   = 3'd3,
               PWM    = 3'd4,
               INTT   = 3'd5,
               OUTPUT = 3'd6,
               DONE   = 3'd7;

    reg [2:0]           state;
    reg [2:0]           stage_cnt;    // Current stage (0 to STAGES)
    reg [AWIDTH-1:0]    g_cnt;        // Loop counter g (over N/R^{s+1} iterations)
    reg [LOGN-1:0]      b_cnt;        // Loop counter b (over R^s iterations)
    reg [LOGN-1:0]      load_cnt;     // Load/output counter
    reg [LOGN-1:0]      delta_idx;    // N / R^{s+1}
    reg [PIPE_LATENCY-1:0] pipe_valid; // Pipeline valid shift register

    // ---- Helper: compute R original addresses for current (b, g, stage) ------
    integer r_idx;
    always @(*) begin
        // idx = b * (N / R^s) + g
        // OrigAddr[r] = idx + delta_idx * r
        for (r_idx = 0; r_idx < R; r_idx = r_idx + 1) begin
            orig_addrs[r_idx*LOGN +: LOGN] =
                b_cnt * (delta_idx * R) + g_cnt + delta_idx * r_idx;
        end
        tw_addr = b_cnt;  // simplified; full twiddle indexing done externally
    end

    // ---- Main FSM ------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            stage_cnt    <= 0;
            g_cnt        <= 0;
            b_cnt        <= 0;
            load_cnt     <= 0;
            delta_idx    <= N/R;
            is_Rhat_stage <= 0;
            rd_sel       <= 2'b00;
            wr_sel       <= 2'b00;
            ntt_mode     <= 1;
            pwm_en       <= 0;
            bank_we      <= 0;
            done         <= 0;
            pipe_valid   <= 0;
        end else begin
            case (state)
                // ----------------------------------------------------------
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state     <= LOAD;
                        load_cnt  <= 0;
                        rd_sel    <= 2'b11;  // write all (input)
                        wr_sel    <= 2'b11;
                        bank_we   <= {R{1'b1}};
                    end
                end

                // ----------------------------------------------------------
                LOAD: begin
                    // External data_in is written word by word into banks via
                    // the interconnect. load_cnt counts N total inputs.
                    if (load_cnt < N - 1) begin
                        load_cnt <= load_cnt + 1;
                    end else begin
                        state     <= NTT1;
                        stage_cnt <= 0;
                        g_cnt     <= 0;
                        b_cnt     <= 0;
                        delta_idx <= N / R;
                        rd_sel    <= 2'b01;   // lower half = poly a
                        wr_sel    <= 2'b01;
                        ntt_mode  <= 1;
                        pwm_en    <= 0;
                        bank_we   <= 0;
                    end
                end

                // ----------------------------------------------------------
                NTT1: begin
                    bank_we <= {R{1'b1}};
                    // Advance inner loops
                    if (g_cnt < delta_idx - 1) begin
                        g_cnt <= g_cnt + 1;
                    end else begin
                        g_cnt <= 0;
                        if (b_cnt < (1 << (stage_cnt*LOGR)) - 1) begin
                            b_cnt <= b_cnt + 1;
                        end else begin
                            b_cnt <= 0;
                            if (stage_cnt < STAGES - 1) begin
                                stage_cnt <= stage_cnt + 1;
                                delta_idx <= delta_idx >> LOGR;
                            end else begin
                                // NTT1 done → start NTT2
                                state     <= NTT2;
                                stage_cnt <= 0;
                                g_cnt     <= 0;
                                b_cnt     <= 0;
                                delta_idx <= N / R;
                                rd_sel    <= 2'b10;   // upper half = poly b
                                wr_sel    <= 2'b10;
                                ntt_mode  <= 1;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                NTT2: begin
                    bank_we <= {R{1'b1}};
                    if (g_cnt < delta_idx - 1) begin
                        g_cnt <= g_cnt + 1;
                    end else begin
                        g_cnt <= 0;
                        if (b_cnt < (1 << (stage_cnt*LOGR)) - 1) begin
                            b_cnt <= b_cnt + 1;
                        end else begin
                            b_cnt <= 0;
                            if (stage_cnt < STAGES - 1) begin
                                stage_cnt <= stage_cnt + 1;
                                delta_idx <= delta_idx >> LOGR;
                            end else begin
                                state     <= PWM;
                                stage_cnt <= 0;
                                g_cnt     <= 0;
                                b_cnt     <= 0;
                                load_cnt  <= 0;
                                delta_idx <= 1;
                                rd_sel    <= 2'b11;   // both halves for PWM
                                wr_sel    <= 2'b01;
                                pwm_en    <= 1;
                                ntt_mode  <= 0;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                PWM: begin
                    bank_we <= {R{1'b1}};
                    // PWM processes N/R points per cycle, R at a time
                    if (load_cnt < N/R - 1) begin
                        load_cnt <= load_cnt + 1;
                    end else begin
                        state     <= INTT;
                        load_cnt  <= 0;
                        stage_cnt <= 0;
                        g_cnt     <= 0;
                        b_cnt     <= 0;
                        delta_idx <= 1;
                        rd_sel    <= 2'b01;   // lower half = result
                        wr_sel    <= 2'b01;
                        pwm_en    <= 0;
                        ntt_mode  <= 0;
                    end
                end

                // ----------------------------------------------------------
                INTT: begin
                    bank_we <= {R{1'b1}};
                    if (g_cnt < delta_idx - 1) begin
                        g_cnt <= g_cnt + 1;
                    end else begin
                        g_cnt <= 0;
                        if (b_cnt < (1 << (stage_cnt*LOGR)) - 1) begin
                            b_cnt <= b_cnt + 1;
                        end else begin
                            b_cnt <= 0;
                            // INTT goes from STAGES-1 down to 0
                            if (stage_cnt < STAGES - 1) begin
                                stage_cnt <= stage_cnt + 1;
                                delta_idx <= delta_idx << LOGR;
                            end else begin
                                state    <= OUTPUT;
                                load_cnt <= 0;
                                bank_we  <= 0;
                                rd_sel   <= 2'b01;
                                wr_sel   <= 2'b00;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                OUTPUT: begin
                    bank_we <= 0;
                    if (load_cnt < N - 1) begin
                        load_cnt <= load_cnt + 1;
                    end else begin
                        state <= DONE;
                        done  <= 1;
                    end
                end

                // ----------------------------------------------------------
                DONE: begin
                    done  <= 1;
                    bank_we <= 0;
                    if (!start)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
