// =============================================================================
// ntt_top.v  —  NTT Polynomial Multiplier Top Level  (Fig. 6)
//
// Full pipeline:  LOAD → NTT1 → NTT2 → PWM → INTT → OUTPUT
//
// Data-path:
//   LOAD  : serial data_in_a / data_in_b -> banks (simple sequential address)
//   NTT1  : lower half (poly a) through NTT butterfly
//   NTT2  : upper half (poly b) through NTT butterfly
//   PWM   : lower × upper -> lower half
//   INTT  : lower half through INTT butterfly
//   OUTPUT: sequential read of lower half -> data_out
// =============================================================================

`ifndef _NTT_TOP_GUARD
`define _NTT_TOP_GUARD

module ntt_top #(
    parameter B      = 16,
    parameter N      = 256,
    parameter R      = 4,
    parameter LOGN   = $clog2(N),       // 8
    parameter LOGR   = $clog2(R),       // 2
    parameter AWIDTH = LOGN - LOGR,     // 6  (bank address bits)
    parameter DWIDTH = 2 * (B + 1),     // 34 (lower+upper poly word)
    parameter WWIDTH = B + 1,           // 17 (one coefficient)
    // Paper-aligned area mode switches:
    // - BRAM-style synchronous read for memory banks
    // - deeper pipelined modular multiplication + optional input register
    parameter PAPER_AREA_MODE   = 0,
    parameter MEM_SYNC_READ     = PAPER_AREA_MODE ? 1 : 0,
    // Backward-compatible switch: kept for external overrides.
    parameter MODMUL_PIPELINED  = PAPER_AREA_MODE ? 1 : 0,
    // Extra FF insertion knobs for Fmax tuning.
    parameter MODMUL_INPUT_REG  = PAPER_AREA_MODE ? 1 : 0,
    parameter MODMUL_PIPE_STAGES = PAPER_AREA_MODE ? 2 : (MODMUL_PIPELINED ? 1 : 0),
    parameter WRITEBACK_DELAY   = 2 + MEM_SYNC_READ + MODMUL_INPUT_REG + MODMUL_PIPE_STAGES,
    // Stage-boundary flush spacing.
    // Area mode uses a safer default because of added datapath latency.
    parameter PIPE_LATENCY = PAPER_AREA_MODE ? ((R >= 16) ? 5 : 3) : ((R >= 16) ? 3 : 1)
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [WWIDTH-1:0] data_in_a,   // serial poly-a input
    input  wire [WWIDTH-1:0] data_in_b,   // serial poly-b input
    output wire [WWIDTH-1:0] data_out,    // serial output coefficients
    output wire              done
);

    // =========================================================================
    // CONTROL UNIT
    // =========================================================================
    wire [R*LOGN-1:0]  orig_addrs;
    wire [$clog2(2*N)-1:0] tw_step;     // twiddle step = (2*bitrev(b)+1)*delta_idx
    wire               is_Rhat_stage;
    wire [1:0]         rd_sel, wr_sel;
    wire               ntt_mode, pwm_en;
    wire [R-1:0]       ctrl_bank_we;
    wire               output_prefetch;

    // Expose the FSM state so ntt_top can decode LOAD / OUTPUT
    wire [2:0]         fsm_state;
    reg  [LOGR-1:0]    iselect_q;
    reg                is_Rhat_stage_q;
    reg  [1:0]         rd_sel_q;
    reg  [1:0]         wr_sel_q;
    reg                ntt_mode_q;
    reg                pwm_en_q;

    ctrl_unit #(
        .N(N), .R(R), .LOGN(LOGN), .LOGR(LOGR),
        .STAGES(LOGN/LOGR), .DEPTH(N/R), .AWIDTH(AWIDTH),
        .PIPE_LATENCY(PIPE_LATENCY)
    ) u_ctrl (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .orig_addrs    (orig_addrs),
        .tw_step       (tw_step),
        .is_Rhat_stage (is_Rhat_stage),
        .rd_sel        (rd_sel),
        .wr_sel        (wr_sel),
        .ntt_mode      (ntt_mode),
        .pwm_en        (pwm_en),
        .bank_we       (ctrl_bank_we),
        .done          (done),
        .fsm_state     (fsm_state),
        .output_prefetch(output_prefetch)
    );

    localparam ST_IDLE   = 3'd0,
               ST_LOAD   = 3'd1,
               ST_NTT1   = 3'd2,
               ST_NTT2   = 3'd3,
               ST_PWM    = 3'd4,
               ST_INTT   = 3'd5,
               ST_OUTPUT = 3'd6,
               ST_DONE   = 3'd7;

    localparam integer STAGES        = LOGN/LOGR;
    localparam integer R_POW_STAGES  = R ** STAGES;
    localparam integer RHAT          = (R_POW_STAGES != 0) ? (N / R_POW_STAGES) : 1;
    localparam integer R_OVER_RHAT   = (RHAT != 0) ? (R / RHAT) : 1;
    localparam integer SUPPORTS_RHAT = (RHAT > 1) && (R_OVER_RHAT == 2);
    localparam integer MM_LAT        = MODMUL_INPUT_REG + MODMUL_PIPE_STAGES;
    localparam integer MAX_MM_LAT    = 8;
    localparam [WWIDTH-1:0] TW_ONE   = {{(WWIDTH-1){1'b0}}, 1'b1};

    function [LOGN-1:0] bit_reverse;
        input [LOGN-1:0] vin;
        input integer bits;
        integer bi;
        begin
            bit_reverse = {LOGN{1'b0}};
            for (bi = 0; bi < LOGN; bi = bi + 1)
                if (bi < bits)
                    bit_reverse[bits - 1 - bi] = vin[bi];
        end
    endfunction

    wire is_load   = (fsm_state == ST_LOAD);
    wire is_output = (fsm_state == ST_OUTPUT) || (fsm_state == ST_DONE);
    wire is_ntt    = (fsm_state == ST_NTT1) || (fsm_state == ST_NTT2);
    wire is_intt   = (fsm_state == ST_INTT);
    wire is_pwm    = (fsm_state == ST_PWM);


    // =========================================================================
    // TWIDDLE FACTOR ROM — outputs R parallel factors
    // =========================================================================
    localparam TW_BITS = $clog2(2*N);

    wire [R*WWIDTH-1:0]  tw_factors;  // R twiddle values: tw_factors[r] for element r
    wire [$clog2(2*N)-1:0] tw_step_inv = ((2 * N) - tw_step) % (2 * N);
    twiddle_rom #(.B(B), .N(N), .R(R)) u_twrom (
        .tw_step (tw_step),
        .tw_out  (tw_factors)
    );

    // INTT needs inverse twiddles (omega^{-k})
    wire [R*WWIDTH-1:0] tw_factors_inv;
    twiddle_rom #(.B(B), .N(N), .R(R)) u_twrom_inv (
        .tw_step (tw_step_inv),
        .tw_out  (tw_factors_inv)
    );

    // Mixed-radix special-stage twiddles for the R_OVER_RHAT=2 case.
    // Lane k has r1=floor(k/2), r2=k%2 and uses omega^{r1*(2*bitrev(b+r2)+1)}.
    wire [LOGN-1:0] rhat_b = SUPPORTS_RHAT ? (orig_addrs[LOGN-1:0] / RHAT) : {LOGN{1'b0}};
    wire [TW_BITS-1:0] rhat_step0 = SUPPORTS_RHAT ?
        (((2 * bit_reverse(rhat_b, STAGES * LOGR)) + 1) % (2 * N)) : {TW_BITS{1'b0}};
    wire [TW_BITS-1:0] rhat_step1 = SUPPORTS_RHAT ?
        (((2 * bit_reverse(rhat_b + 1'b1, STAGES * LOGR)) + 1) % (2 * N)) : {TW_BITS{1'b0}};

    reg [R*TW_BITS-1:0] rhat_tw_idx_ntt;
    reg [R*TW_BITS-1:0] rhat_tw_idx_intt;
    integer tl;
    integer tr1;
    reg [TW_BITS-1:0] tbase;
    always @(*) begin
        for (tl = 0; tl < R; tl = tl + 1) begin
            tr1 = (R_OVER_RHAT != 0) ? (tl / R_OVER_RHAT) : 0;
            tbase = ((tl % R_OVER_RHAT) == 0) ? rhat_step0 : rhat_step1;
            rhat_tw_idx_ntt[tl*TW_BITS +: TW_BITS]  = (tr1 * tbase) % (2 * N);
            rhat_tw_idx_intt[tl*TW_BITS +: TW_BITS] = ((2 * N) - ((tr1 * tbase) % (2 * N))) % (2 * N);
        end
    end

    wire [R*WWIDTH-1:0] tw_rhat_pack;
    wire [R*WWIDTH-1:0] tw_rhat_pack_inv;
    genvar tg;
    generate
        for (tg = 0; tg < R; tg = tg + 1) begin : gen_tw_lookup_rhat
            twiddle_lookup #(.B(B), .N(N)) u_tw_lookup_ntt (
                .tw_idx (rhat_tw_idx_ntt[tg*TW_BITS +: TW_BITS]),
                .tw_val (tw_rhat_pack[tg*WWIDTH +: WWIDTH])
            );
            twiddle_lookup #(.B(B), .N(N)) u_tw_lookup_intt (
                .tw_idx (rhat_tw_idx_intt[tg*TW_BITS +: TW_BITS]),
                .tw_val (tw_rhat_pack_inv[tg*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    reg [R*WWIDTH-1:0] tw_factors_q;
    reg [R*WWIDTH-1:0] tw_factors_inv_q;
    reg [R*WWIDTH-1:0] tw_rhat_pack_q;
    reg [R*WWIDTH-1:0] tw_rhat_pack_inv_q;

    wire [R*WWIDTH-1:0] tw_factors_ntt_pipe;
    wire [R*WWIDTH-1:0] tw_factors_intt_pipe;
    assign tw_factors_ntt_pipe  = (is_Rhat_stage_q && SUPPORTS_RHAT) ? tw_rhat_pack_q     : tw_factors_q;
    assign tw_factors_intt_pipe = (is_Rhat_stage_q && SUPPORTS_RHAT) ? tw_rhat_pack_inv_q : tw_factors_inv_q;

    // =========================================================================
    // ADDRESS GENERATOR  (used during NTT / INTT / PWM)
    // =========================================================================
    wire [LOGR-1:0]       iselect;
    wire [R*AWIDTH-1:0]   bank_addrs_raw;

    addr_gen #(.N(N), .R(R), .LOGN(LOGN), .LOGR(LOGR), .AWIDTH(AWIDTH)) u_addrgen (
        .orig_addr0 (orig_addrs[LOGN-1:0]),
        .orig_addrs (orig_addrs),
        .iselect    (iselect),
        .bank_addrs (bank_addrs_raw)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            iselect_q       <= {LOGR{1'b0}};
            is_Rhat_stage_q <= 1'b0;
            rd_sel_q        <= 2'b00;
            wr_sel_q        <= 2'b00;
            ntt_mode_q      <= 1'b0;
            pwm_en_q        <= 1'b0;
            tw_factors_q    <= {R*WWIDTH{1'b0}};
            tw_factors_inv_q <= {R*WWIDTH{1'b0}};
            tw_rhat_pack_q <= {R*WWIDTH{1'b0}};
            tw_rhat_pack_inv_q <= {R*WWIDTH{1'b0}};
        end else begin
            iselect_q       <= iselect;
            is_Rhat_stage_q <= is_Rhat_stage;
            rd_sel_q        <= rd_sel;
            wr_sel_q        <= wr_sel;
            ntt_mode_q      <= ntt_mode;
            pwm_en_q        <= pwm_en;
            tw_factors_q    <= tw_factors;
            tw_factors_inv_q <= tw_factors_inv;
            tw_rhat_pack_q <= tw_rhat_pack;
            tw_rhat_pack_inv_q <= tw_rhat_pack_inv;
        end
    end

    // =========================================================================
    // LOAD / OUTPUT sequential address counter
    // Each cycle during LOAD: address = load_cnt / R, bank = load_cnt % R
    // Each cycle during OUTPUT: same pattern, read-only
    // =========================================================================
    reg  [LOGN-1:0]  seq_cnt;   // counts 0..N-1 during LOAD and OUTPUT
    always @(posedge clk or posedge rst) begin
        if (rst)
            seq_cnt <= 0;
        else if (is_load || is_output)
            seq_cnt <= (seq_cnt == N-1) ? 0 : seq_cnt + 1;
        else
            seq_cnt <= 0;
    end

    wire [AWIDTH-1:0] seq_addr = seq_cnt[LOGN-1:LOGR];   // upper bits = row
    // Bank mapping must match addr_gen's conflict-free layout (sum of LOGR-bit groups mod R).
    localparam integer FULL_GROUPS = LOGN / LOGR;
    localparam integer REM_BITS    = LOGN - (FULL_GROUPS * LOGR);
    reg  [LOGR-1:0]   seq_bank;
    reg  [LOGR-1:0]   seq_bank_rem;
    reg  [LOGR+3:0]   seq_bank_acc;
    integer sb_i;
    always @(*) begin
        seq_bank_rem = {LOGR{1'b0}};
        seq_bank_acc = {LOGR+4{1'b0}};
        for (sb_i = 0; sb_i < FULL_GROUPS; sb_i = sb_i + 1)
            seq_bank_acc = seq_bank_acc + seq_cnt[sb_i*LOGR +: LOGR];
        if (REM_BITS > 0) begin
            seq_bank_rem[REM_BITS-1:0] = seq_cnt[FULL_GROUPS*LOGR +: REM_BITS];
            seq_bank_acc = seq_bank_acc + seq_bank_rem;
        end
        seq_bank = seq_bank_acc[LOGR-1:0];
    end

    // =========================================================================
    // MEMORY BANKS
    // =========================================================================
    wire [R*DWIDTH-1:0]  bank_dout;
    wire [R*DWIDTH-1:0]  bank_din;
    wire [R*AWIDTH-1:0]  bank_waddr;
    wire [R-1:0]         bank_we;
    wire [R*AWIDTH-1:0]  bank_raddr;

    mem_banks #(
        .B(B), .N(N), .R(R), .DEPTH(N/R), .DWIDTH(DWIDTH), .AWIDTH(AWIDTH),
        .SYNC_READ(MEM_SYNC_READ)
    ) u_membanks (
        .clk        (clk),
        .bank_we    (bank_we),
        .bank_waddr (bank_waddr),
        .bank_din   (bank_din),
        .bank_raddr (bank_raddr),
        .bank_dout  (bank_dout)
    );

    // =========================================================================
    // INTERCONNECT: BankOut → Operands  (NTT/INTT/PWM)
    // =========================================================================
    wire [R*DWIDTH-1:0]  operands_out;
    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R), .RHAT(RHAT)) u_icon_out (
        .bank_data_out (bank_dout),
        .iselect       (iselect),
        .is_Rhat_stage (is_Rhat_stage),
        .operands_out  (operands_out)
    );

    reg [R*DWIDTH-1:0] operands_out_q;
    always @(posedge clk or posedge rst) begin
        if (rst)
            operands_out_q <= {R*DWIDTH{1'b0}};
        else
            operands_out_q <= operands_out;
    end

    // Optional alignment pipeline used by deeper modmul staging.
    reg [R*DWIDTH-1:0]  operands_mm_pipe [0:MAX_MM_LAT-1];
    reg [LOGR-1:0]      iselect_mm_pipe  [0:MAX_MM_LAT-1];
    reg                 is_rhat_mm_pipe  [0:MAX_MM_LAT-1];
    reg [1:0]           rd_sel_mm_pipe   [0:MAX_MM_LAT-1];
    reg [1:0]           wr_sel_mm_pipe   [0:MAX_MM_LAT-1];
    reg                 ntt_mode_mm_pipe [0:MAX_MM_LAT-1];
    reg                 pwm_en_mm_pipe   [0:MAX_MM_LAT-1];
    reg [R*WWIDTH-1:0]  tw_ntt_mm_pipe   [0:MAX_MM_LAT-1];
    reg [R*WWIDTH-1:0]  tw_intt_mm_pipe  [0:MAX_MM_LAT-1];
    integer mm_i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (mm_i = 0; mm_i < MAX_MM_LAT; mm_i = mm_i + 1) begin
                operands_mm_pipe[mm_i] <= {R*DWIDTH{1'b0}};
                iselect_mm_pipe[mm_i]  <= {LOGR{1'b0}};
                is_rhat_mm_pipe[mm_i]  <= 1'b0;
                rd_sel_mm_pipe[mm_i]   <= 2'b00;
                wr_sel_mm_pipe[mm_i]   <= 2'b00;
                ntt_mode_mm_pipe[mm_i] <= 1'b0;
                pwm_en_mm_pipe[mm_i]   <= 1'b0;
                tw_ntt_mm_pipe[mm_i]   <= {R*WWIDTH{1'b0}};
                tw_intt_mm_pipe[mm_i]  <= {R*WWIDTH{1'b0}};
            end
        end else begin
            operands_mm_pipe[0] <= operands_out_q;
            iselect_mm_pipe[0]  <= iselect_q;
            is_rhat_mm_pipe[0]  <= is_Rhat_stage_q;
            rd_sel_mm_pipe[0]   <= rd_sel_q;
            wr_sel_mm_pipe[0]   <= wr_sel_q;
            ntt_mode_mm_pipe[0] <= ntt_mode_q;
            pwm_en_mm_pipe[0]   <= pwm_en_q;
            tw_ntt_mm_pipe[0]   <= tw_factors_ntt_pipe;
            tw_intt_mm_pipe[0]  <= tw_factors_intt_pipe;
            for (mm_i = 1; mm_i < MAX_MM_LAT; mm_i = mm_i + 1) begin
                operands_mm_pipe[mm_i] <= operands_mm_pipe[mm_i-1];
                iselect_mm_pipe[mm_i]  <= iselect_mm_pipe[mm_i-1];
                is_rhat_mm_pipe[mm_i]  <= is_rhat_mm_pipe[mm_i-1];
                rd_sel_mm_pipe[mm_i]   <= rd_sel_mm_pipe[mm_i-1];
                wr_sel_mm_pipe[mm_i]   <= wr_sel_mm_pipe[mm_i-1];
                ntt_mode_mm_pipe[mm_i] <= ntt_mode_mm_pipe[mm_i-1];
                pwm_en_mm_pipe[mm_i]   <= pwm_en_mm_pipe[mm_i-1];
                tw_ntt_mm_pipe[mm_i]   <= tw_ntt_mm_pipe[mm_i-1];
                tw_intt_mm_pipe[mm_i]  <= tw_intt_mm_pipe[mm_i-1];
            end
        end
    end

    // Signals aligned to modmul inputs (optional +1 cycle when MODMUL_INPUT_REG=1).
    wire [R*DWIDTH-1:0] op_word_mm      = MODMUL_INPUT_REG ? operands_mm_pipe[0] : operands_out_q;
    wire [R*WWIDTH-1:0] tw_ntt_mm       = MODMUL_INPUT_REG ? tw_ntt_mm_pipe[0]    : tw_factors_ntt_pipe;
    wire [R*WWIDTH-1:0] tw_intt_mm      = MODMUL_INPUT_REG ? tw_intt_mm_pipe[0]   : tw_factors_intt_pipe;
    wire [1:0]          rd_sel_mm       = MODMUL_INPUT_REG ? rd_sel_mm_pipe[0]    : rd_sel_q;
    wire                is_rhat_mm      = MODMUL_INPUT_REG ? is_rhat_mm_pipe[0]   : is_Rhat_stage_q;

    // Signals aligned to modmul outputs (for write-data selection/routing).
    wire [R*DWIDTH-1:0] op_word_wb;
    wire [LOGR-1:0]     iselect_wb;
    wire                is_rhat_wb;
    wire [1:0]          wr_sel_wb;
    wire                ntt_mode_wb;
    wire                pwm_en_wb;
    generate
        if (MM_LAT == 0) begin : gen_mm_lat0
            assign op_word_wb  = operands_out_q;
            assign iselect_wb  = iselect_q;
            assign is_rhat_wb  = is_Rhat_stage_q;
            assign wr_sel_wb   = wr_sel_q;
            assign ntt_mode_wb = ntt_mode_q;
            assign pwm_en_wb   = pwm_en_q;
        end else begin : gen_mm_latn
            assign op_word_wb  = operands_mm_pipe[MM_LAT-1];
            assign iselect_wb  = iselect_mm_pipe[MM_LAT-1];
            assign is_rhat_wb  = is_rhat_mm_pipe[MM_LAT-1];
            assign wr_sel_wb   = wr_sel_mm_pipe[MM_LAT-1];
            assign ntt_mode_wb = ntt_mode_mm_pipe[MM_LAT-1];
            assign pwm_en_wb   = pwm_en_mm_pipe[MM_LAT-1];
        end
    endgenerate

    // =========================================================================
    // EXTRACT LOWER / UPPER HALVES from operands
    // =========================================================================
    wire [R*WWIDTH-1:0]  op_lower_mm, op_upper_mm;
    wire [R*WWIDTH-1:0]  op_lower_wb, op_upper_wb;
    genvar gi;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_op_extract
            assign op_lower_mm[gi*WWIDTH +: WWIDTH] = op_word_mm[gi*DWIDTH +:         WWIDTH];
            assign op_upper_mm[gi*WWIDTH +: WWIDTH] = op_word_mm[gi*DWIDTH + WWIDTH +: WWIDTH];
            assign op_lower_wb[gi*WWIDTH +: WWIDTH] = op_word_wb[gi*DWIDTH +:         WWIDTH];
            assign op_upper_wb[gi*WWIDTH +: WWIDTH] = op_word_wb[gi*DWIDTH + WWIDTH +: WWIDTH];
        end
    endgenerate

    // =========================================================================
    // NTT PATH:  Norm → ModMul (twiddle) → Norm→D1 → R2NTT → D1→Norm
    // rd_sel selects which polynomial half is read by NTT:
    //   2'b01 -> lower (NTT1), 2'b10 -> upper (NTT2)
    // =========================================================================
    wire [R*WWIDTH-1:0]  modmul_ntt_in = (rd_sel_mm == 2'b10) ? op_upper_mm : op_lower_mm;

    wire [R*WWIDTH-1:0]  mm_ntt_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_modmul_ntt
            mod_mul_fermat #(.B(B), .PIPE_STAGES(MODMUL_PIPE_STAGES)) u_mm (
                .clk    (clk),
                .rst    (rst),
                .a      (modmul_ntt_in[gi*WWIDTH +: WWIDTH]),
                .b      (tw_ntt_mm[gi*WWIDTH +: WWIDTH]),
                .result (mm_ntt_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    wire [R*WWIDTH-1:0]  ntt_d1_in;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_ntod1
            wire [WWIDTH-1:0] nd;
            norm_to_d1 #(B) u_nd1 (.in(mm_ntt_out[gi*WWIDTH +: WWIDTH]), .out(nd));
            assign ntt_d1_in[gi*WWIDTH +: WWIDTH] = nd;
        end
    endgenerate

    wire [R*WWIDTH-1:0] ntt_result_d1;
    wire [R*WWIDTH-1:0] ntt_result;
    generate
        if (R == 4) begin : gen_r2ntt_r4
            wire [WWIDTH-1:0] r2ntt_out0, r2ntt_out1, r2ntt_out2, r2ntt_out3;
            r2ntt_r4 #(.B(B), .KSHIFT(8), .KNEG(1)) u_r2ntt (
                .a0 (ntt_d1_in[0*WWIDTH +: WWIDTH]),
                .a1 (ntt_d1_in[1*WWIDTH +: WWIDTH]),
                .a2 (ntt_d1_in[2*WWIDTH +: WWIDTH]),
                .a3 (ntt_d1_in[3*WWIDTH +: WWIDTH]),
                .is_Rhat_stage (is_rhat_mm),
                .A0 (r2ntt_out0), .A1(r2ntt_out1), .A2(r2ntt_out2), .A3(r2ntt_out3)
            );
            assign ntt_result_d1 = {r2ntt_out3, r2ntt_out2, r2ntt_out1, r2ntt_out0};
        end else if (R == 8) begin : gen_r2ntt_r8
            r2ntt_r8 #(.B(B), .N(N)) u_r2ntt8 (
                .in_d1        (ntt_d1_in),
                .is_Rhat_stage(is_rhat_mm),
                .out_d1       (ntt_result_d1)
            );
        end else if (R == 16) begin : gen_r2ntt_r16
            r2ntt_r16 #(.B(B)) u_r2ntt16 (
                .in_d1        (ntt_d1_in),
                .is_Rhat_stage(is_rhat_mm),
                .out_d1       (ntt_result_d1)
            );
        end else begin : gen_r2ntt_generic
            r2ntt_generic #(.B(B), .N(N), .R(R)) u_r2ntt_g (
                .in_d1        (ntt_d1_in),
                .is_Rhat_stage(is_rhat_mm),
                .out_d1       (ntt_result_d1)
            );
        end
    endgenerate

    // Convert NTT outputs back to normal representation before write-back.
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_ntt_d1n
            d1_to_norm #(B) u_ntt_d1n (
                .in  (ntt_result_d1[gi*WWIDTH +: WWIDTH]),
                .out (ntt_result[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // INTT PATH:  R2INTT → D1→Norm → ModMul (twiddle)
    // =========================================================================
    wire [R*WWIDTH-1:0] intt_d1_in;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_intt_n2d1
            norm_to_d1 #(B) u_intt_n2d1 (
                .in  (op_lower_mm[gi*WWIDTH +: WWIDTH]),
                .out (intt_d1_in[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    wire [R*WWIDTH-1:0] intt_d1_out;
    generate
        if (R == 4) begin : gen_r2intt_r4
            wire [WWIDTH-1:0] r2intt_out0, r2intt_out1, r2intt_out2, r2intt_out3;
            r2intt_r4 #(.B(B), .KSHIFT(8), .KSHIFT_INV(8)) u_r2intt (
                .A0 (intt_d1_in[0*WWIDTH +: WWIDTH]),
                .A1 (intt_d1_in[1*WWIDTH +: WWIDTH]),
                .A2 (intt_d1_in[2*WWIDTH +: WWIDTH]),
                .A3 (intt_d1_in[3*WWIDTH +: WWIDTH]),
                .is_Rhat_stage (is_rhat_mm),
                .a0 (r2intt_out0), .a1(r2intt_out1), .a2(r2intt_out2), .a3(r2intt_out3)
            );
            assign intt_d1_out = {r2intt_out3, r2intt_out2, r2intt_out1, r2intt_out0};
        end else if (R == 8) begin : gen_r2intt_r8
            r2intt_r8 #(.B(B), .N(N)) u_r2intt8 (
                .in_d1        (intt_d1_in),
                .is_Rhat_stage(is_rhat_mm),
                .out_d1       (intt_d1_out)
            );
        end else if (R == 16) begin : gen_r2intt_r16
            r2intt_r16 #(.B(B)) u_r2intt16 (
                .in_d1        (intt_d1_in),
                .is_Rhat_stage(is_rhat_mm),
                .out_d1       (intt_d1_out)
            );
        end else begin : gen_r2intt_generic
            r2intt_generic #(.B(B), .N(N), .R(R)) u_r2intt_g (
                .in_d1        (intt_d1_in),
                .is_Rhat_stage(is_rhat_mm),
                .out_d1       (intt_d1_out)
            );
        end
    endgenerate

    wire [R*WWIDTH-1:0] intt_norm;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_intt_d1n
            wire [WWIDTH-1:0] inn;
            d1_to_norm #(B) u_id1n (.in(intt_d1_out[gi*WWIDTH +: WWIDTH]), .out(inn));
            assign intt_norm[gi*WWIDTH +: WWIDTH] = inn;
        end
    endgenerate

    wire [R*WWIDTH-1:0] mm_intt_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_modmul_intt
            mod_mul_fermat #(.B(B), .PIPE_STAGES(MODMUL_PIPE_STAGES)) u_mm_intt (
                .clk    (clk),
                .rst    (rst),
                .a      (intt_norm[gi*WWIDTH +: WWIDTH]),
                .b      (tw_intt_mm[gi*WWIDTH +: WWIDTH]),
                .result (mm_intt_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // PWM PATH:  lower × upper → lower (normal representation)
    // =========================================================================
    wire [R*WWIDTH-1:0] pwm_out;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_pwm_mul
            mod_mul_fermat #(.B(B), .PIPE_STAGES(MODMUL_PIPE_STAGES)) u_mm_pwm (
                .clk    (clk),
                .rst    (rst),
                .a      (op_lower_mm[gi*WWIDTH +: WWIDTH]),
                .b      (op_upper_mm[gi*WWIDTH +: WWIDTH]),
                .result (pwm_out[gi*WWIDTH +: WWIDTH])
            );
        end
    endgenerate

    // =========================================================================
    // WRITE-DATA MUX
    //   LOAD   : pack data_in_a (lower) + data_in_b (upper) into one word
    //   NTT1   : NTT butterfly result → lower half
    //   NTT2   : NTT butterfly result → upper half
    //   INTT   : INTT+ModMul result   → lower half
    //   PWM    : PWM result            → lower half
    // =========================================================================
    wire [DWIDTH-1:0]    load_word = {data_in_b, data_in_a};

    // Butterfly result selection (shared across R elements).
    // In area mode, data/control/twiddle are aligned through MM_LAT cycles.
    wire [R*WWIDTH-1:0]  bfly_result = pwm_en_wb   ? pwm_out :
                                        ntt_mode_wb ? ntt_result :
                                                      mm_intt_out;

    // Pack butterfly results into DWIDTH words (preserve the appropriate half)
    wire [R*DWIDTH-1:0]  bfly_data_pre;   // before bank-in interconnect routing
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_bfly_pack
            wire [WWIDTH-1:0] rw = bfly_result[gi*WWIDTH +: WWIDTH];
            wire [WWIDTH-1:0] cur_l = op_lower_wb[gi*WWIDTH +: WWIDTH];
            wire [WWIDTH-1:0] cur_u = op_upper_wb[gi*WWIDTH +: WWIDTH];
            // Preserve the non-target half to avoid corrupting the other polynomial.
            assign bfly_data_pre[gi*DWIDTH +: DWIDTH] =
                (wr_sel_wb == 2'b10) ? {rw,    cur_l} :   // update upper only
                (wr_sel_wb == 2'b01) ? {cur_u, rw   } :   // update lower only
                                       op_word_wb[gi*DWIDTH +: DWIDTH];
        end
    endgenerate

    // =========================================================================
    // INTERCONNECT: Operands → Banks  (NTT/INTT/PWM write-back)
    // BUG FIX: butterfly results must be inverse-circularly-shifted before
    // writing back, so operand[k] lands in bank[(iselect+k)%R].
    // =========================================================================
    wire [R*DWIDTH-1:0]  bfly_data_routed;

    // iselect_wb/is_rhat_wb align with the selected datapath latency.
    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R), .RHAT(RHAT)) u_icon_in (
        .operands_in  (bfly_data_pre),
        .iselect      (iselect_wb),
        .is_Rhat_stage(is_rhat_wb),
        .bank_data_in (bfly_data_routed)
    );

    // LOAD: only the active bank (seq_bank) gets the new word; all others get 0
    wire [R*DWIDTH-1:0]  load_data;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_pack
            assign load_data[gi*DWIDTH +: DWIDTH] =
                (seq_bank == gi[LOGR-1:0]) ? load_word : {DWIDTH{1'b0}};
        end
    endgenerate

    // Register compute write-back payload to break long comb paths into BRAM ports.
    reg [R*DWIDTH-1:0] bfly_data_routed_q;
    always @(posedge clk or posedge rst) begin
        if (rst)
            bfly_data_routed_q <= {R*DWIDTH{1'b0}};
        else
            bfly_data_routed_q <= bfly_data_routed;
    end

    // Final bank_din mux
    assign bank_din = is_load ? load_data : bfly_data_routed_q;

    // =========================================================================
    // BANK WRITE ADDRESS
    // =========================================================================
    wire [R*AWIDTH-1:0]  ntt_waddr;
    interconnect_bank_addr #(.AWIDTH(AWIDTH), .R(R), .RHAT(RHAT)) u_icon_addr (
        .raw_addrs      (bank_addrs_raw),
        .iselect        (iselect),
        .is_Rhat_stage  (is_Rhat_stage),
        .selected_addrs (ntt_waddr)
    );

    // During LOAD, all banks get seq_addr (only one is enabled via bank_we)
    wire [R*AWIDTH-1:0]  load_waddr;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_waddr
            assign load_waddr[gi*AWIDTH +: AWIDTH] = seq_addr;
        end
    endgenerate

    localparam integer WB_DELAY = WRITEBACK_DELAY;
    reg [R*AWIDTH-1:0] ntt_waddr_pipe [0:WB_DELAY-1];
    integer wb_i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (wb_i = 0; wb_i < WB_DELAY; wb_i = wb_i + 1)
                ntt_waddr_pipe[wb_i] <= {R*AWIDTH{1'b0}};
        end else begin
            ntt_waddr_pipe[0] <= ntt_waddr;
            for (wb_i = 1; wb_i < WB_DELAY; wb_i = wb_i + 1)
                ntt_waddr_pipe[wb_i] <= ntt_waddr_pipe[wb_i-1];
        end
    end

    assign bank_waddr = is_load ? load_waddr : ntt_waddr_pipe[WB_DELAY-1];

    // =========================================================================
    // BANK WRITE ENABLE  (direct from ctrl_unit each cycle)
    // =========================================================================
    wire [R-1:0] load_we;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_load_we
            assign load_we[gi] = (seq_bank == gi[LOGR-1:0]);
        end
    endgenerate

    reg [R-1:0] ctrl_bank_we_pipe [0:WB_DELAY-1];
    integer we_i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (we_i = 0; we_i < WB_DELAY; we_i = we_i + 1)
                ctrl_bank_we_pipe[we_i] <= {R{1'b0}};
        end else begin
            ctrl_bank_we_pipe[0] <= ctrl_bank_we;
            for (we_i = 1; we_i < WB_DELAY; we_i = we_i + 1)
                ctrl_bank_we_pipe[we_i] <= ctrl_bank_we_pipe[we_i-1];
        end
    end

    assign bank_we = is_load ? load_we : ctrl_bank_we_pipe[WB_DELAY-1];

    // =========================================================================
    // BANK READ ADDRESS
    //   NTT/INTT/PWM : from mapped addresses (Algorithm 7, InterconnectBankAddr)
    //   OUTPUT        : sequential scan, overriding bank_raddr
    // =========================================================================
    wire [R*AWIDTH-1:0]  out_raddr;
    generate
        for (gi = 0; gi < R; gi = gi + 1) begin : gen_out_raddr
            assign out_raddr[gi*AWIDTH +: AWIDTH] = seq_addr;
        end
    endgenerate

    wire output_prefetch_en = MEM_SYNC_READ && output_prefetch;
    assign bank_raddr = (is_output || output_prefetch_en) ? out_raddr : ntt_waddr;

    // =========================================================================
    // OUTPUT: serial read from bank seq_bank, lower WWIDTH bits
    // =========================================================================
    reg [WWIDTH-1:0] dout_r;
    always @(*) begin : gen_dout
        integer b;
        dout_r = {WWIDTH{1'b0}};
        for (b = 0; b < R; b = b + 1) begin
            if (seq_bank == b[LOGR-1:0])
                dout_r = bank_dout[b*DWIDTH +: WWIDTH];
        end
    end
    assign data_out = dout_r;

endmodule

`endif // _NTT_TOP_GUARD
