// =============================================================================
// bivar_opt_top.v
//
// Optimized Bivariate NTT Polynomial Multiplier.
//
// Functional equivalent of rtl/bivar_ntt_top.v, but with working arrays
// stored in CONFLICT-FREE banked memories (bivar_opt_mem) instead of flat
// register arrays accessed by wide muxes.  The same FSM and dataflow are
// retained; only the storage and access patterns change.
//
// Key refactorings from the original:
//   1. All 8-element parallel accesses use ROW mode (varying i1, fixed i2).
//      In the original, `work[op_count*L + ci]` was a CHUNK pattern (fixed
//      i1, 8 consecutive i2).  We re-index by transposing `work`'s layout
//      so the access becomes `work[ci*M + op_count]` = ROW(i2=op_count).
//   2. All 32-element parallel accesses use COL mode (fixed i1, varying i2).
//   3. ram_style="distributed" hints in bivar_opt_mem trigger LUTRAM
//      inference for the small per-bank storage.
//
// Expected metrics vs original at N=64: LUT 19K -> ~3-5K.  DSP=8 unchanged.
// =============================================================================

`ifndef _BIVAR_OPT_TOP_GUARD
`define _BIVAR_OPT_TOP_GUARD

module bivar_opt_top #(
    parameter B       = 16,
    parameter L       = 8,
    parameter M       = 32,
    parameter N       = L * M,
    parameter WWIDTH  = B + 1,
    parameter TW_BITS = $clog2(2*N),
    parameter BANKS   = M,                // conflict-free banking dimension
    parameter LOGM    = $clog2(M),
    parameter POSW    = $clog2(L),
    parameter LINW    = $clog2(L*M)
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

    // =========================================================================
    // FSM states (identical to original bivar_ntt_top).
    // =========================================================================
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

    // =========================================================================
    // ModMul + sub-NTT data path (unchanged from original).
    // =========================================================================
    reg  [L*WWIDTH-1:0]  mul_a_pack;
    reg  [L*WWIDTH-1:0]  mul_b_pack;
    wire [L*WWIDTH-1:0]  mul_out_pack;
    wire [L*WWIDTH-1:0]  tw_pack;
    wire [L*TW_BITS-1:0] tw_idx_pack;

    reg  [L*WWIDTH-1:0]  ntt8_in_pack;
    wire [L*WWIDTH-1:0]  ntt8_out_pack;

    reg  [M*WWIDTH-1:0]  nttM_in_pack;
    wire [M*WWIDTH-1:0]  nttM_out_pack;

    wire inverse_subntt8 = (state == ST_INV_ROW);
    wire inverse_subnttM = (state == ST_INV_COL);

    function [TW_BITS-1:0] inv_tw_idx;
        input [TW_BITS-1:0] idx;
        begin
            inv_tw_idx = ((2*N) - idx) % (2*N);
        end
    endfunction

    genvar tg;
    generate
        for (tg = 0; tg < L; tg = tg + 1) begin : gen_tw_lanes
            wire [TW_BITS-1:0] lane_tw_fwd_row   = (tg * M + op_count) % (2*N);
            wire [TW_BITS-1:0] lane_tw_cross     = (2 * op_count * tg) % (2*N);
            wire [TW_BITS-1:0] lane_tw_inv_cross = inv_tw_idx((2 * tg * op_count) % (2*N));
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

            mod_mul_fermat #(.B(B), .PIPELINED(0)) u_mul (
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

    // =========================================================================
    // BANKED MEMORIES (conflict-free, per array).
    // Each memory uses bivar_opt_mem with B banks of L positions, banking
    // formula bank(i1, i2) = (i1+i2) mod B, position = i1.
    //
    // Eight arrays, all same physical interface:
    //   raw_a, raw_b      - input polynomials (loaded sequentially)
    //   work              - post-row-NTT pre-transpose buffer (REFACTORED layout)
    //   trans             - post-cross-twiddle (FWD) / post-inverse-cross (INV)
    //   spec_a, spec_b    - frequency-domain polynomials
    //   prod              - PWM result
    //   result            - inverse-NTT'd coefficients (output)
    //
    // Each memory has:
    //   - wmode/rmode    : 00=idle, 01=row, 10=col, 11=seq
    //   - row inputs     : row_i2, row_wdata[L]
    //   - col inputs     : col_i1, col_wdata[M]
    //   - seq inputs     : seq_k, seq_wdata
    //   - row read out   : rd_row[L]
    //   - col read out   : rd_col[M]
    //   - seq read out   : rd_seq
    // =========================================================================
    // For brevity, declare wires/regs grouped per array.

    // ---- Bus declarations -----------------------------------------------------
    `define MEM_PORTS(NAME) \
        reg  [1:0]              NAME``_wmode;       \
        reg  [LOGM-1:0]         NAME``_row_i2;      \
        reg  [POSW-1:0]         NAME``_col_i1;      \
        reg  [LINW-1:0]         NAME``_seq_k;       \
        reg  [L*WWIDTH-1:0]     NAME``_row_wdata;   \
        reg  [M*WWIDTH-1:0]     NAME``_col_wdata;   \
        reg  [WWIDTH-1:0]       NAME``_seq_wdata;   \
        reg  [1:0]              NAME``_rmode;       \
        reg  [LOGM-1:0]         NAME``_r_row_i2;    \
        reg  [POSW-1:0]         NAME``_r_col_i1;    \
        reg  [LINW-1:0]         NAME``_r_seq_k;     \
        wire [L*WWIDTH-1:0]     NAME``_rd_row;      \
        wire [M*WWIDTH-1:0]     NAME``_rd_col;      \
        wire [WWIDTH-1:0]       NAME``_rd_seq;

    `MEM_PORTS(raw_a_m)
    `MEM_PORTS(raw_b_m)
    `MEM_PORTS(work_m)
    `MEM_PORTS(trans_m)
    `MEM_PORTS(spec_a_m)
    `MEM_PORTS(spec_b_m)
    `MEM_PORTS(prod_m)
    `MEM_PORTS(result_m)

    `define MEM_INST(NAME) \
        bivar_opt_mem #(.WWIDTH(WWIDTH), .L(L), .M(M), .B(BANKS)) NAME``_inst ( \
            .clk(clk),                                                          \
            .wmode(NAME``_wmode), .row_i2(NAME``_row_i2),                       \
            .col_i1(NAME``_col_i1), .seq_k(NAME``_seq_k),                       \
            .row_wdata(NAME``_row_wdata), .col_wdata(NAME``_col_wdata),         \
            .seq_wdata(NAME``_seq_wdata),                                       \
            .rmode(NAME``_rmode), .r_row_i2(NAME``_r_row_i2),                   \
            .r_col_i1(NAME``_r_col_i1), .r_seq_k(NAME``_r_seq_k),               \
            .rd_row(NAME``_rd_row), .rd_col(NAME``_rd_col),                     \
            .rd_seq(NAME``_rd_seq)                                              \
        );

    `MEM_INST(raw_a_m)
    `MEM_INST(raw_b_m)
    `MEM_INST(work_m)
    `MEM_INST(trans_m)
    `MEM_INST(spec_a_m)
    `MEM_INST(spec_b_m)
    `MEM_INST(prod_m)
    `MEM_INST(result_m)

    // =========================================================================
    // READ-MUX combinational paths: drive memory rmodes and addresses
    // based on current FSM state.  Reads happen at "op_count(T)" each cycle.
    // =========================================================================
    integer ci;
    always @(*) begin
        // Default: all memories idle.
        raw_a_m_rmode    = 2'b00;
        raw_b_m_rmode    = 2'b00;
        work_m_rmode     = 2'b00;
        trans_m_rmode    = 2'b00;
        spec_a_m_rmode   = 2'b00;
        spec_b_m_rmode   = 2'b00;
        prod_m_rmode     = 2'b00;
        result_m_rmode   = 2'b00;
        raw_a_m_r_row_i2 = op_count[LOGM-1:0];
        raw_b_m_r_row_i2 = op_count[LOGM-1:0];
        work_m_r_row_i2  = op_count[LOGM-1:0];
        trans_m_r_row_i2 = op_count[LOGM-1:0];
        trans_m_r_col_i1 = op_count[POSW-1:0];
        spec_a_m_r_row_i2 = op_count[LOGM-1:0];
        spec_b_m_r_row_i2 = op_count[LOGM-1:0];
        prod_m_r_col_i1   = op_count[POSW-1:0];
        result_m_r_seq_k  = op_count[LINW-1:0];
        raw_a_m_r_col_i1  = 0;
        raw_b_m_r_col_i1  = 0;
        work_m_r_col_i1   = 0;
        spec_a_m_r_col_i1 = 0;
        spec_b_m_r_col_i1 = 0;
        prod_m_r_row_i2   = 0;
        result_m_r_col_i1 = 0;
        result_m_r_row_i2 = 0;
        raw_a_m_r_seq_k   = 0;
        raw_b_m_r_seq_k   = 0;
        work_m_r_seq_k    = 0;
        trans_m_r_seq_k   = 0;
        spec_a_m_r_seq_k  = 0;
        spec_b_m_r_seq_k  = 0;
        prod_m_r_seq_k    = 0;

        case (state)
            ST_FWD_ROW_A:  raw_a_m_rmode  = 2'b01;   // row read at i2=op_count
            ST_FWD_ROW_B:  raw_b_m_rmode  = 2'b01;
            ST_FWD_XTW_A,
            ST_FWD_XTW_B:  work_m_rmode   = 2'b01;   // row read at i2=op_count
            ST_FWD_COL_A,
            ST_FWD_COL_B:  trans_m_rmode  = 2'b10;   // col read at i1=op_count
            ST_PWM: begin
                spec_a_m_rmode = 2'b01;
                spec_b_m_rmode = 2'b01;
            end
            ST_INV_COL:    prod_m_rmode   = 2'b10;   // col read at i1=op_count
            ST_INV_XTW:    work_m_rmode   = 2'b01;   // row read at i2=op_count
            ST_INV_ROW:    trans_m_rmode  = 2'b01;   // row read at i2=op_count
            ST_OUTPUT:     result_m_rmode = 2'b11;   // seq read at k=op_count
            default: ;
        endcase
    end

    // =========================================================================
    // SUBNTT8 input packing  (input to subntt8 depends on state)
    // =========================================================================
    always @(*) begin
        ntt8_in_pack = {L*WWIDTH{1'b0}};
        case (state)
            ST_FWD_ROW_A,
            ST_FWD_ROW_B:
                // After pre-twist ModMul.
                ntt8_in_pack = mul_out_pack;
            ST_INV_ROW:
                // From trans memory (row read at i2=op_count).
                ntt8_in_pack = trans_m_rd_row;
            default: ;
        endcase
    end

    // =========================================================================
    // SUBNTTM input packing
    // =========================================================================
    always @(*) begin
        nttM_in_pack = {M*WWIDTH{1'b0}};
        case (state)
            ST_FWD_COL_A,
            ST_FWD_COL_B:  nttM_in_pack = trans_m_rd_col;
            ST_INV_COL:    nttM_in_pack = prod_m_rd_col;
            default: ;
        endcase
    end

    // =========================================================================
    // MUL INPUT packing
    //   ST_FWD_ROW_A: pre-twist  raw_a[i1=ci, i2=op_count] * psi
    //   ST_FWD_ROW_B: pre-twist  raw_b[i1=ci, i2=op_count] * psi
    //   ST_FWD_XTW_*: cross-tw   work[i1=ci, i2=op_count] * psi
    //   ST_PWM      : spec_a * spec_b
    //   ST_INV_XTW  : work * psi^{-1}      (work re-indexed via wmode logic)
    //   ST_INV_ROW  : un-twist  ntt8_out_pack * psi^{-1}
    // =========================================================================
    always @(*) begin
        mul_a_pack = {L*WWIDTH{1'b0}};
        mul_b_pack = {L*WWIDTH{1'b0}};
        case (state)
            ST_FWD_ROW_A: begin
                mul_a_pack = raw_a_m_rd_row;
                mul_b_pack = tw_pack;
            end
            ST_FWD_ROW_B: begin
                mul_a_pack = raw_b_m_rd_row;
                mul_b_pack = tw_pack;
            end
            ST_FWD_XTW_A,
            ST_FWD_XTW_B: begin
                mul_a_pack = work_m_rd_row;
                mul_b_pack = tw_pack;
            end
            ST_PWM: begin
                mul_a_pack = spec_a_m_rd_row;
                mul_b_pack = spec_b_m_rd_row;
            end
            ST_INV_XTW: begin
                mul_a_pack = work_m_rd_row;
                mul_b_pack = tw_pack;
            end
            ST_INV_ROW: begin
                mul_a_pack = ntt8_out_pack;
                mul_b_pack = tw_pack;
            end
            default: ;
        endcase
    end

    // =========================================================================
    // WRITE-MUX combinational paths: drive memory wmodes and write data.
    // Writes happen at the same op_count(T) as reads (combinational data path).
    // =========================================================================
    always @(*) begin
        // Default: all memories idle.
        raw_a_m_wmode    = 2'b00;
        raw_b_m_wmode    = 2'b00;
        work_m_wmode     = 2'b00;
        trans_m_wmode    = 2'b00;
        spec_a_m_wmode   = 2'b00;
        spec_b_m_wmode   = 2'b00;
        prod_m_wmode     = 2'b00;
        result_m_wmode   = 2'b00;

        raw_a_m_row_i2 = op_count[LOGM-1:0];
        raw_b_m_row_i2 = op_count[LOGM-1:0];
        work_m_row_i2  = op_count[LOGM-1:0];
        trans_m_row_i2 = op_count[LOGM-1:0];
        spec_a_m_col_i1 = op_count[POSW-1:0];
        spec_b_m_col_i1 = op_count[POSW-1:0];
        work_m_col_i1   = op_count[POSW-1:0];   // INV_COL writes work
        prod_m_row_i2  = op_count[LOGM-1:0];
        result_m_row_i2 = op_count[LOGM-1:0];

        raw_a_m_col_i1  = 0;
        raw_b_m_col_i1  = 0;
        trans_m_col_i1  = 0;
        prod_m_col_i1   = 0;
        result_m_col_i1 = 0;

        raw_a_m_seq_k   = op_count[LINW-1:0];
        raw_b_m_seq_k   = op_count[LINW-1:0];
        work_m_seq_k    = 0;
        trans_m_seq_k   = 0;
        spec_a_m_seq_k  = 0;
        spec_b_m_seq_k  = 0;
        prod_m_seq_k    = 0;
        result_m_seq_k  = 0;

        raw_a_m_row_wdata  = {L*WWIDTH{1'b0}};
        raw_b_m_row_wdata  = {L*WWIDTH{1'b0}};
        work_m_row_wdata   = ntt8_out_pack;       // FWD_ROW writes work
        trans_m_row_wdata  = mul_out_pack;        // FWD_XTW & INV_XTW write trans/result-like
        spec_a_m_row_wdata = {L*WWIDTH{1'b0}};
        spec_b_m_row_wdata = {L*WWIDTH{1'b0}};
        prod_m_row_wdata   = mul_out_pack;        // PWM writes prod (lanes are i1)
        result_m_row_wdata = mul_out_pack;        // INV_ROW writes result

        raw_a_m_col_wdata  = {M*WWIDTH{1'b0}};
        raw_b_m_col_wdata  = {M*WWIDTH{1'b0}};
        work_m_col_wdata   = nttM_out_pack;       // INV_COL writes work
        trans_m_col_wdata  = {M*WWIDTH{1'b0}};
        spec_a_m_col_wdata = nttM_out_pack;       // FWD_COL_A writes spec_a
        spec_b_m_col_wdata = nttM_out_pack;       // FWD_COL_B writes spec_b
        prod_m_col_wdata   = {M*WWIDTH{1'b0}};
        result_m_col_wdata = {M*WWIDTH{1'b0}};

        raw_a_m_seq_wdata  = data_in_a;
        raw_b_m_seq_wdata  = data_in_b;
        work_m_seq_wdata   = {WWIDTH{1'b0}};
        trans_m_seq_wdata  = {WWIDTH{1'b0}};
        spec_a_m_seq_wdata = {WWIDTH{1'b0}};
        spec_b_m_seq_wdata = {WWIDTH{1'b0}};
        prod_m_seq_wdata   = {WWIDTH{1'b0}};
        result_m_seq_wdata = {WWIDTH{1'b0}};

        case (state)
            ST_LOAD: begin
                raw_a_m_wmode = 2'b11;            // seq write
                raw_b_m_wmode = 2'b11;
            end
            ST_FWD_ROW_A,
            ST_FWD_ROW_B: begin
                // Write row NTT output to `work` at i2=op_count.
                work_m_wmode = 2'b01;
            end
            ST_FWD_XTW_A,
            ST_FWD_XTW_B: begin
                // Write cross-twiddle output to `trans` at i2=op_count (ROW write).
                trans_m_wmode = 2'b01;
            end
            ST_FWD_COL_A: begin
                spec_a_m_wmode = 2'b10;           // col write at i1=op_count
            end
            ST_FWD_COL_B: begin
                spec_b_m_wmode = 2'b10;
            end
            ST_PWM: begin
                prod_m_wmode = 2'b01;             // row write to prod at i2=op_count
            end
            ST_INV_COL: begin
                work_m_wmode = 2'b10;             // col write to work at i1=op_count
            end
            ST_INV_XTW: begin
                trans_m_wmode = 2'b01;            // row write to trans at i2=op_count
            end
            ST_INV_ROW: begin
                result_m_wmode = 2'b01;           // row write to result at i2=op_count
            end
            default: ;
        endcase
    end

    // =========================================================================
    // FSM
    // =========================================================================
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
                    if (start) state <= ST_LOAD;
                end

                ST_LOAD: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == N-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_ROW_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_ROW_A: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_XTW_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_XTW_A: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_COL_A;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_COL_A: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_ROW_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_ROW_B: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_XTW_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_XTW_B: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_FWD_COL_B;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_FWD_COL_B: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L-1) begin
                        op_count <= 8'd0;
                        state    <= ST_PWM;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_PWM: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_INV_COL;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_INV_COL: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == L-1) begin
                        op_count <= 8'd0;
                        state    <= ST_INV_XTW;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_INV_XTW: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_INV_ROW;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_INV_ROW: begin
                    cycle_count <= cycle_count + 1'b1;
                    if (op_count == M-1) begin
                        op_count <= 8'd0;
                        state    <= ST_OUTPUT;
                    end else
                        op_count <= op_count + 1'b1;
                end

                ST_OUTPUT: begin
                    data_out       <= result_m_rd_seq;
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

`endif // _BIVAR_OPT_TOP_GUARD
