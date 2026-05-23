// =============================================================================
// bivar_opt_mem.v
// Conflict-free banked working memory for the optimized bivariate NTT.
//
// Storage organisation (max(L,M)-banked, addressed by lane index i1):
//   - B = max(L, M) banks of L entries each (for L=8, M=N/8).
//   - Bank index   : bank(i1, i2) = (i1 + i2) mod B
//   - Within-bank  : pos = i1   (0..L-1)
//
// Supports two parallel access patterns in a single cycle:
//   (1) Row access (read/write L elements at fixed i2):
//       lane i1 in [0,L) -> bank (i1 + i2) mod B, position i1.
//       L banks active; the remaining (B-L) banks idle.
//   (2) Column access (read/write M elements at fixed i1):
//       lane i2 in [0,M) -> bank (i1 + i2) mod B, position i1.
//       All B (= M for L<=M) banks active.
//
// Sequential LOAD/OUTPUT access: 1 element per cycle, by linear index k=i1*M+i2.
//
// All banks use distributed RAM (ram_style="distributed").  For L=8 entries
// per bank, this is far cheaper than BRAM and supports asynchronous read.
// =============================================================================

`ifndef _BIVAR_OPT_MEM_GUARD
`define _BIVAR_OPT_MEM_GUARD

module bivar_opt_mem #(
    parameter WWIDTH = 17,
    parameter L      = 8,
    parameter M      = 32,
    parameter B      = M,           // banks (must be >= max(L, M))
    parameter LOGM   = $clog2(M),
    parameter LOGB   = $clog2(B),
    parameter POSW   = $clog2(L)    // intra-bank address width
)(
    input  wire                       clk,

    // Access mode select:
    //   2'b00 = idle
    //   2'b01 = row write (write L elements at row i2)
    //   2'b10 = col write (write M elements at col i1)
    //   2'b11 = seq write (1 element at linear index k)
    input  wire [1:0]                 wmode,
    input  wire [LOGM-1:0]            row_i2,        // for row write
    input  wire [POSW-1:0]            col_i1,        // for col write
    input  wire [$clog2(L*M)-1:0]     seq_k,         // for seq write
    input  wire [L*WWIDTH-1:0]        row_wdata,     // L elements packed (row write)
    input  wire [M*WWIDTH-1:0]        col_wdata,     // M elements packed (col write)
    input  wire [WWIDTH-1:0]          seq_wdata,     // 1 element (seq write)

    // Read interface is asynchronous (combinational).
    //   rmode = 2'b01 -> row read at i2: rd_row[L-1:0] = mem[(i1+i2)%B, i1]
    //   rmode = 2'b10 -> col read at i1: rd_col[M-1:0] = mem[(i1+i2)%B, i1]
    //   rmode = 2'b11 -> seq read at k:  rd_seq        = mem[bank(k), pos(k)]
    input  wire [1:0]                 rmode,
    input  wire [LOGM-1:0]            r_row_i2,
    input  wire [POSW-1:0]            r_col_i1,
    input  wire [$clog2(L*M)-1:0]     r_seq_k,
    output reg  [L*WWIDTH-1:0]        rd_row,
    output reg  [M*WWIDTH-1:0]        rd_col,
    output reg  [WWIDTH-1:0]          rd_seq
);

    // ---- Storage: B banks of L entries (distributed RAM) -------------------
    (* ram_style = "distributed" *) reg [WWIDTH-1:0] mem_bank [0:B-1][0:L-1];

    // ---- Write logic --------------------------------------------------------
    integer w_idx;
    always @(posedge clk) begin
        case (wmode)
            2'b01: begin
                // Row write: lane i1 -> bank (i1+row_i2)%B at pos i1.
                for (w_idx = 0; w_idx < L; w_idx = w_idx + 1) begin
                    mem_bank[(w_idx + row_i2) % B][w_idx] <=
                        row_wdata[w_idx*WWIDTH +: WWIDTH];
                end
            end
            2'b10: begin
                // Col write: lane i2 -> bank (col_i1+i2)%B at pos col_i1.
                for (w_idx = 0; w_idx < M; w_idx = w_idx + 1) begin
                    mem_bank[(col_i1 + w_idx) % B][col_i1] <=
                        col_wdata[w_idx*WWIDTH +: WWIDTH];
                end
            end
            2'b11: begin
                // Seq write at linear index seq_k = i1*M + i2.
                // i1 = seq_k / M, i2 = seq_k % M.
                // For power-of-two M: i1 = seq_k >> LOGM, i2 = seq_k & (M-1).
                mem_bank[((seq_k >> LOGM) + (seq_k & (M-1))) % B]
                        [seq_k >> LOGM] <= seq_wdata;
            end
            default: ;
        endcase
    end

    // ---- Read logic (asynchronous distributed-RAM read) ---------------------
    integer r_idx;
    always @(*) begin
        rd_row = {L*WWIDTH{1'b0}};
        rd_col = {M*WWIDTH{1'b0}};
        rd_seq = {WWIDTH{1'b0}};
        case (rmode)
            2'b01: begin
                for (r_idx = 0; r_idx < L; r_idx = r_idx + 1)
                    rd_row[r_idx*WWIDTH +: WWIDTH] =
                        mem_bank[(r_idx + r_row_i2) % B][r_idx];
            end
            2'b10: begin
                for (r_idx = 0; r_idx < M; r_idx = r_idx + 1)
                    rd_col[r_idx*WWIDTH +: WWIDTH] =
                        mem_bank[(r_col_i1 + r_idx) % B][r_col_i1];
            end
            2'b11: begin
                rd_seq = mem_bank[((r_seq_k >> LOGM) + (r_seq_k & (M-1))) % B]
                                 [r_seq_k >> LOGM];
            end
            default: ;
        endcase
    end

endmodule

`endif // _BIVAR_OPT_MEM_GUARD
