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
    parameter PIPE_LATENCY = 2         // 2-stage pipelined ModMul: 1 stall cycle between groups
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,

    // Outputs to data path
    output reg  [R*$clog2(N)-1:0]    orig_addrs,
    output reg  [$clog2(2*N)-1:0]    tw_step,
    output reg                        is_Rhat_stage,    // Mixed-radix special stage flag
    output reg  [1:0]            rd_sel,           // Read select (which half of banks)
    output reg  [1:0]            wr_sel,           // Write select
    output reg                   ntt_mode,         // 1=NTT butterfly, 0=INTT butterfly
    output reg                   pwm_en,           // PWM enable
    output wire [R-1:0]         bank_we,           // Write enable per bank
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

    localparam integer R_POW_STAGES  = R ** STAGES;
    localparam integer HAS_RHAT_STAGE = (N != R_POW_STAGES);
    localparam integer RHAT          = (R_POW_STAGES != 0) ? (N / R_POW_STAGES) : 1;
    localparam integer R_OVER_RHAT   = (RHAT != 0) ? (R / RHAT) : 1;
    localparam integer INTT_B_INIT   = (N / (R * RHAT)) - 1;

    assign fsm_state = state;

    reg [2:0]           state;
    reg [2:0]           stage_cnt;    // Current stage (0 to STAGES-1)
    reg [LOGN-1:0]      g_cnt;        // Loop counter g (0 .. delta_idx-1)
    reg [LOGN-1:0]      b_cnt;        // Loop counter b (0 .. R^s - 1)
    reg [LOGN-1:0]      load_cnt;     // Load/output counter
    reg [LOGN-1:0]      delta_idx;    // N / R^{s+1}  (= stride between butterfly groups)
    reg [LOGN-1:0]      b_limit;      // R^s - 1  (max value of b_cnt for current stage)
    reg [$clog2(PIPE_LATENCY+1)-1:0] stall_cnt;
    // intt_drain_pending = 1 marks one extra "drain" cycle in INTT before the
    // OUTPUT transition. With registered orig_addrs (1-cycle late), the LAST
    // INTT group's data is read from banks one cycle after its FSM-issue cycle.
    // Without this drain, the FSM would switch bank_raddr to out_raddr too soon
    // and the LAST R writes would land with garbage data.
    reg                 intt_drain_pending;

    wire compute_state = (state == NTT1) || (state == NTT2) || (state == PWM) || (state == INTT);
    // intt_drain_pending suppresses bank_we during the 1-cycle drain at INTT end.
    assign bank_we = (compute_state && (stall_cnt == 0) && !intt_drain_pending) ? {R{1'b1}} : {R{1'b0}};

    // ---- Helper: compute R original addresses and twiddle step ---------------
    // tw_step = (2*bitrev(b_cnt)+1) * delta_idx for normal stages.
    // In mixed-radix special stage, tw_step carries (2*bitrev(b)+1) (no delta).
    //
    // Pipelined: combinational into *_comb, then registered into the outputs.
    // Breaks the ~6-8 ns multiply-add chain out of the bank_raddr critical
    // path (was contributing to the 20 ns b_cnt -> DSP A1 path).
    integer r_idx, bit_idx;
    integer r1, r2;
    integer idx_base;
    reg [LOGN-1:0] b_rev;
    integer rev_bits;

    reg [R*LOGN-1:0]      orig_addrs_comb;
    reg [$clog2(2*N)-1:0] tw_step_comb;

    always @(*) begin
        b_rev = 0;

        if (is_Rhat_stage && HAS_RHAT_STAGE) begin
            // Mixed-radix special stage addressing (Algorithm 4/5 special branch).
            idx_base = b_cnt * RHAT;
            for (r_idx = 0; r_idx < R; r_idx = r_idx + 1) begin
                r1 = r_idx / R_OVER_RHAT;
                r2 = r_idx % R_OVER_RHAT;
                orig_addrs_comb[r_idx*LOGN +: LOGN] = idx_base + r1 + (r2 * RHAT);
            end

            rev_bits = STAGES * LOGR;
            for (bit_idx = 0; bit_idx < LOGN; bit_idx = bit_idx + 1) begin
                if (bit_idx < rev_bits)
                    b_rev[rev_bits - 1 - bit_idx] = b_cnt[bit_idx];
            end
            tw_step_comb = (2 * b_rev + 1) % (2 * N);
        end else begin
            // Standard high-radix stage addressing.
            rev_bits = stage_cnt * LOGR;
            for (bit_idx = 0; bit_idx < LOGN; bit_idx = bit_idx + 1) begin
                if (bit_idx < rev_bits)
                    b_rev[rev_bits - 1 - bit_idx] = b_cnt[bit_idx];
            end

            for (r_idx = 0; r_idx < R; r_idx = r_idx + 1) begin
                orig_addrs_comb[r_idx*LOGN +: LOGN] =
                    b_cnt * (delta_idx << LOGR) + g_cnt + (delta_idx * r_idx);
            end

            tw_step_comb = ((2 * b_rev + 1) * delta_idx) % (2 * N);
        end
    end

    // Register the outputs at the ctrl_unit boundary (1-cycle delay).
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            orig_addrs <= {R*LOGN{1'b0}};
            tw_step    <= {$clog2(2*N){1'b0}};
        end else begin
            orig_addrs <= orig_addrs_comb;
            tw_step    <= tw_step_comb;
        end
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
            stall_cnt     <= 0;
            rd_sel        <= 2'b00;
            wr_sel        <= 2'b00;
            ntt_mode      <= 1;
            pwm_en        <= 0;
            done          <= 0;
            is_Rhat_stage <= 0;
            intt_drain_pending <= 0;
        end else begin
            case (state)
                // ----------------------------------------------------------
                IDLE: begin
                    done <= 0;
                    is_Rhat_stage <= 0;
                    stall_cnt <= 0;
                    if (start) begin
                        state    <= LOAD;
                        load_cnt <= 0;
                        rd_sel   <= 2'b11;
                        wr_sel   <= 2'b11;
                    end
                end

                // ----------------------------------------------------------
                LOAD: begin
                    is_Rhat_stage <= 0;
                    stall_cnt <= 0;
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
                    end
                end

                // ----------------------------------------------------------
                NTT1: begin
                    if (stall_cnt != 0) begin
                        stall_cnt <= stall_cnt - 1'b1;
                    end else begin
                        stall_cnt <= (PIPE_LATENCY > 0) ? (PIPE_LATENCY - 1) : 0;

                        if (is_Rhat_stage) begin
                            if (b_cnt + R_OVER_RHAT <= b_limit) begin
                                b_cnt <= b_cnt + R_OVER_RHAT;
                            end else begin
                                // Mixed-radix special stage done → NTT2
                                is_Rhat_stage <= 0;
                                stall_cnt <= 0;
                                state     <= NTT2;
                                stage_cnt <= 0;
                                g_cnt     <= 0;
                                b_cnt     <= 0;
                                b_limit   <= 0;
                                delta_idx <= N / R;
                                rd_sel    <= 2'b10;
                                wr_sel    <= 2'b10;
                                ntt_mode  <= 1;
                            end
                        end else begin
                            if (g_cnt < delta_idx - 1) begin
                                g_cnt <= g_cnt + 1;
                            end else begin
                                g_cnt     <= 0;
                                if (b_cnt < b_limit) begin
                                    b_cnt <= b_cnt + 1;
                                end else begin
                                    b_cnt <= 0;
                                    if (stage_cnt < STAGES - 1) begin
                                        stage_cnt <= stage_cnt + 1;
                                        delta_idx <= delta_idx >> LOGR;
                                        b_limit   <= (b_limit << LOGR) | {LOGR{1'b1}};
                                    end else begin
                                        // Standard stages done.
                                        if (HAS_RHAT_STAGE && (RHAT != 1)) begin
                                            is_Rhat_stage <= 1;
                                            stage_cnt <= STAGES;
                                            g_cnt <= 0;
                                            b_cnt <= 0;
                                            b_limit <= R_POW_STAGES - 1;
                                            delta_idx <= 0;
                                        end else begin
                                            // NTT1 done → NTT2
                                            state     <= NTT2;
                                            stage_cnt <= 0;
                                            g_cnt     <= 0;
                                            b_cnt     <= 0;
                                            b_limit   <= 0;
                                            delta_idx <= N / R;
                                            rd_sel    <= 2'b10;
                                            wr_sel    <= 2'b10;
                                            ntt_mode  <= 1;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                NTT2: begin
                    if (stall_cnt != 0) begin
                        stall_cnt <= stall_cnt - 1'b1;
                    end else begin
                        stall_cnt <= (PIPE_LATENCY > 0) ? (PIPE_LATENCY - 1) : 0;

                        if (is_Rhat_stage) begin
                            if (b_cnt + R_OVER_RHAT <= b_limit) begin
                                b_cnt <= b_cnt + R_OVER_RHAT;
                            end else begin
                                // Mixed-radix special stage done → PWM
                                is_Rhat_stage <= 0;
                                stall_cnt <= 0;
                                state     <= PWM;
                                stage_cnt <= 0;
                                g_cnt     <= 0;
                                b_cnt     <= 0;
                                b_limit   <= 0;
                                delta_idx <= N / R;
                                load_cnt  <= 0;
                                rd_sel    <= 2'b11;
                                wr_sel    <= 2'b01;
                                pwm_en    <= 1;
                                ntt_mode  <= 0;
                            end
                        end else begin
                            if (g_cnt < delta_idx - 1) begin
                                g_cnt <= g_cnt + 1;
                            end else begin
                                g_cnt     <= 0;
                                if (b_cnt < b_limit) begin
                                    b_cnt <= b_cnt + 1;
                                end else begin
                                    b_cnt <= 0;
                                    if (stage_cnt < STAGES - 1) begin
                                        stage_cnt <= stage_cnt + 1;
                                        delta_idx <= delta_idx >> LOGR;
                                        b_limit   <= (b_limit << LOGR) | {LOGR{1'b1}};
                                    end else begin
                                        if (HAS_RHAT_STAGE && (RHAT != 1)) begin
                                            is_Rhat_stage <= 1;
                                            stage_cnt <= STAGES;
                                            g_cnt <= 0;
                                            b_cnt <= 0;
                                            b_limit <= R_POW_STAGES - 1;
                                            delta_idx <= 0;
                                        end else begin
                                            // NTT2 done → PWM
                                            state     <= PWM;
                                            stage_cnt <= 0;
                                            g_cnt     <= 0;
                                            b_cnt     <= 0;
                                            b_limit   <= 0;
                                            delta_idx <= N / R;
                                            load_cnt  <= 0;
                                            rd_sel    <= 2'b11;
                                            wr_sel    <= 2'b01;
                                            pwm_en    <= 1;
                                            ntt_mode  <= 0;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                // PWM: iterate through all N/R groups of R elements.
                // orig_addrs is driven by g_cnt/b_cnt so we must advance them.
                // With delta_idx=N/R and b_limit=0 (only b=0), g runs 0..N/R-1.
                PWM: begin
                    if (stall_cnt != 0) begin
                        stall_cnt <= stall_cnt - 1'b1;
                    end else begin
                        stall_cnt <= (PIPE_LATENCY > 0) ? (PIPE_LATENCY - 1) : 0;

                        if (g_cnt < delta_idx - 1) begin
                            g_cnt <= g_cnt + 1;
                        end else begin
                            // All N/R groups done → go to INTT
                            state     <= INTT;
                            g_cnt     <= 0;
                            b_cnt     <= 0;
                            load_cnt  <= 0;
                            rd_sel    <= 2'b01;
                            wr_sel    <= 2'b01;
                            pwm_en    <= 0;
                            ntt_mode  <= 0;

                            if (HAS_RHAT_STAGE && (RHAT != 1)) begin
                                is_Rhat_stage <= 1;
                                stage_cnt <= STAGES;
                                b_limit <= R_POW_STAGES - 1;
                                delta_idx <= 0;
                                stall_cnt <= 0;
                            end else begin
                                is_Rhat_stage <= 0;
                                // Algorithm 5 high-radix stages: s from STAGES-1 down to 0.
                                stage_cnt <= STAGES - 1;
                                b_limit   <= INTT_B_INIT;
                                delta_idx <= RHAT;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                // INTT: run stages in descending s order (Algorithm 5, line 17).
                // stage_cnt starts at STAGES-1 with delta_idx=1 and b_limit=R^(STAGES-1)-1,
                // then moves toward stage 0 with larger delta_idx and smaller b_limit.
                //
                // intt_drain_pending=1 marks the 1-cycle drain after the last
                // INTT issue. We must read the LAST INTT group's bank data with
                // bank_raddr=ntt_waddr (not out_raddr); this drain keeps state=INTT
                // for one extra cycle so the registered orig_addrs can still drive
                // the bank read before we switch to OUTPUT.
                INTT: begin
                    if (intt_drain_pending) begin
                        // Drain cycle complete -> transition to OUTPUT.
                        state              <= OUTPUT;
                        load_cnt           <= 0;
                        rd_sel             <= 2'b01;
                        wr_sel             <= 2'b00;
                        stall_cnt          <= 0;
                        intt_drain_pending <= 0;
                    end else if (stall_cnt != 0) begin
                        stall_cnt <= stall_cnt - 1'b1;
                    end else begin
                        stall_cnt <= (PIPE_LATENCY > 0) ? (PIPE_LATENCY - 1) : 0;

                        if (is_Rhat_stage) begin
                            if (b_cnt + R_OVER_RHAT <= b_limit) begin
                                b_cnt <= b_cnt + R_OVER_RHAT;
                            end else begin
                                // Mixed-radix pre-INTT stage done. Enter standard descending INTT stages.
                                is_Rhat_stage <= 0;
                                stage_cnt <= STAGES - 1;
                                g_cnt <= 0;
                                b_cnt <= 0;
                                b_limit <= INTT_B_INIT;
                                delta_idx <= RHAT;
                                stall_cnt <= 0;
                            end
                        end else begin
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
                                        // INTT done.  Schedule the drain cycle:
                                        //   set intt_drain_pending; don't transition state yet.
                                        // Bank reads for the LAST INTT group still need to
                                        // happen on the next cycle (registered orig_addrs is
                                        // 1 cycle late).  Suppress new issues via the drain
                                        // path on bank_we.
                                        intt_drain_pending <= 1'b1;
                                        stall_cnt          <= 0;
                                    end
                                end
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                OUTPUT: begin
                    is_Rhat_stage <= 0;
                    stall_cnt <= 0;
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
                    is_Rhat_stage <= 0;
                    stall_cnt <= 0;
                    if (!start)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
