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
    output reg  [R*$clog2(N)-1:0]    orig_addrs,      // R original addresses (R x LOGN bits)
    output reg  [$clog2(2*N)-1:0]    tw_step,          // Twiddle step = (2*bitrev(b)+1)*delta for ROM
    output wire                       is_Rhat_stage,    // Mixed-radix special stage flag
    output reg  [1:0]            rd_sel,           // Read select (which half of banks)
    output reg  [1:0]            wr_sel,           // Write select
    output reg                   ntt_mode,         // 1=NTT butterfly, 0=INTT butterfly
    output reg                   pwm_en,           // PWM enable
    output reg  [R-1:0]         bank_we,           // Write enable per bank
    output reg                   done,
    output wire [2:0]            fsm_state          // Expose FSM state to top
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

    assign fsm_state = state;
    assign is_Rhat_stage = 1'b0;

    reg [2:0]           state;
    reg [2:0]           stage_cnt;    // Current stage (0 to STAGES-1)
    reg [LOGN-1:0]      g_cnt;        // Loop counter g (0 .. delta_idx-1)
    reg [LOGN-1:0]      b_cnt;        // Loop counter b (0 .. R^s - 1)
    reg [LOGN-1:0]      load_cnt;     // Load/output counter
    reg [LOGN-1:0]      delta_idx;    // N / R^{s+1}  (= stride between butterfly groups)
    reg [LOGN-1:0]      b_limit;      // R^s - 1  (max value of b_cnt for current stage)

    // ---- Helper: compute R original addresses and twiddle step ---------------
    // tw_step = (2*bitrev(b_cnt)+1) * delta_idx   (used to address the 2N-entry ROM)
    integer r_idx, bit_idx;
    reg [LOGN-1:0] b_rev;
    integer rev_bits;
    always @(*) begin
        // Bit-reverse b_cnt over stage_cnt*LOGR bits (b ranges 0..R^s-1).
        b_rev = 0;
        rev_bits = stage_cnt * LOGR;
        for (bit_idx = 0; bit_idx < LOGN; bit_idx = bit_idx + 1) begin
            if (bit_idx < rev_bits)
                b_rev[rev_bits - 1 - bit_idx] = b_cnt[bit_idx];
        end
        // OrigAddr[r] = b*(delta_idx*R) + g + delta_idx*r
        for (r_idx = 0; r_idx < R; r_idx = r_idx + 1) begin
            orig_addrs[r_idx*LOGN +: LOGN] =
                b_cnt * (delta_idx << LOGR) + g_cnt + (delta_idx * r_idx);
        end
        // tw_step for twiddle ROM: (2*bitrev(b)+1) * delta_idx, mod 2N
        tw_step = ((2 * b_rev + 1) * delta_idx) % (2 * N);
    end

    // ---- Main FSM ------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            stage_cnt     <= 0;
            g_cnt         <= 0;
            b_cnt         <= 0;
            b_limit       <= 0;          // R^0 - 1 = 0
            load_cnt      <= 0;
            delta_idx     <= N/R;
            rd_sel        <= 2'b00;
            wr_sel        <= 2'b00;
            ntt_mode      <= 1;
            pwm_en        <= 0;
            bank_we       <= 0;
            done          <= 0;
        end else begin
            case (state)
                // ----------------------------------------------------------
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state    <= LOAD;
                        load_cnt <= 0;
                        rd_sel   <= 2'b11;
                        wr_sel   <= 2'b11;
                        bank_we  <= {R{1'b1}};
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
                        bank_we   <= {R{1'b1}};
                    end
                end

                // ----------------------------------------------------------
                NTT1: begin
                    bank_we <= {R{1'b1}};
                    if (g_cnt < delta_idx - 1) begin
                        g_cnt <= g_cnt + 1;
                    end else begin
                        g_cnt <= 0;
                        if (b_cnt < b_limit) begin
                            b_cnt <= b_cnt + 1;
                        end else begin
                            b_cnt <= 0;
                            if (stage_cnt < STAGES - 1) begin
                                stage_cnt <= stage_cnt + 1;
                                delta_idx <= delta_idx >> LOGR;
                                b_limit   <= (b_limit << LOGR) | {LOGR{1'b1}}; // R^{s+1}-1
                            end else begin
                                // NTT1 done → NTT2
                                state     <= NTT2;
                                stage_cnt <= 0;
                                g_cnt     <= 0;
                                b_cnt     <= 0;
                                b_limit   <= 0;        // R^0-1 = 0
                                delta_idx <= N / R;
                                rd_sel    <= 2'b10;
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
                        if (b_cnt < b_limit) begin
                            b_cnt <= b_cnt + 1;
                        end else begin
                            b_cnt <= 0;
                            if (stage_cnt < STAGES - 1) begin
                                stage_cnt <= stage_cnt + 1;
                                delta_idx <= delta_idx >> LOGR;
                                b_limit   <= (b_limit << LOGR) | {LOGR{1'b1}};
                            end else begin
                                // NTT2 done → PWM
                                state     <= PWM;
                                stage_cnt <= 0;
                                g_cnt     <= 0;
                                b_cnt     <= 0;
                                b_limit   <= 0;        // only b=0 during PWM
                                delta_idx <= N / R;    // g runs 0..N/R-1
                                load_cnt  <= 0;
                                // PWM: N/R groups of R elements
                                rd_sel    <= 2'b11;
                                wr_sel    <= 2'b01;
                                pwm_en    <= 1;
                                ntt_mode  <= 0;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                // PWM: iterate through all N/R groups of R elements.
                // orig_addrs is driven by g_cnt/b_cnt so we must advance them.
                // With delta_idx=N/R and b_limit=0 (only b=0), g runs 0..N/R-1.
                PWM: begin
                    bank_we <= {R{1'b1}};
                    // delta_idx=N/R, b_limit=0 → only b=0, g runs 0..N/R-1
                    if (g_cnt < delta_idx - 1) begin
                        g_cnt <= g_cnt + 1;
                    end else begin
                        // All N/R groups done → go to INTT
                        state     <= INTT;
                        g_cnt     <= 0;
                        b_cnt     <= 0;
                        load_cnt  <= 0;
                        // Algorithm 5 runs high-radix stages from s=STAGES-1 down to 0.
                        stage_cnt <= STAGES - 1;
                        b_limit   <= (N / R) - 1;  // R^(STAGES-1)-1
                        delta_idx <= 1;            // N / R^(STAGES)
                        rd_sel    <= 2'b01;
                        wr_sel    <= 2'b01;
                        pwm_en    <= 0;
                        ntt_mode  <= 0;
                    end
                end

                // ----------------------------------------------------------
                // INTT: run stages in descending s order (Algorithm 5, line 17).
                // stage_cnt starts at STAGES-1 with delta_idx=1 and b_limit=R^(STAGES-1)-1,
                // then moves toward stage 0 with larger delta_idx and smaller b_limit.
                INTT: begin
                    bank_we <= {R{1'b1}};
                    if (g_cnt < delta_idx - 1) begin
                        g_cnt <= g_cnt + 1;
                    end else begin
                        g_cnt <= 0;
                        if (b_cnt < b_limit) begin
                            b_cnt <= b_cnt + 1;
                        end else begin
                            b_cnt <= 0;
                            if (stage_cnt > 0) begin
                                stage_cnt <= stage_cnt - 1;
                                delta_idx <= delta_idx << LOGR;
                                b_limit   <= b_limit >> LOGR;
                            end else begin
                                // INTT done → go to OUTPUT
                                state    <= OUTPUT;
                                load_cnt <= 0;  // use load_cnt to count outputs, not g_cnt
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
                    // Spend N cycles sequentially reading all output coefficients
                    // use load_cnt to count 0..N-1, then transition to DONE
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
