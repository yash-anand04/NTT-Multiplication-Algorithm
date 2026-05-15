// =============================================================================
// mem_banks.v
// R parallel memory banks for in-place NTT storage.
// Each bank holds N/R entries. Each entry stores 2*(B+1) bits:
//   upper (B+1) bits  = coefficient of polynomial b (for NTT2)
//   lower (B+1) bits  = coefficient of polynomial a (for NTT1/INTT)
//
// Synchronous write, combinational (async) read. ram_style="block" requests
// BRAM inference, but with async read Vivado will usually fall back to
// distributed RAM (LUT-based) since 7-series BRAMs don't support async read.
// Async read is required by the current ntt_top pipeline; switching to
// registered read would require re-aligning the entire delay pipeline.
//
// bank_we:    write enable per bank
// bank_waddr: write address (log(N/R) bits) per bank
// bank_raddr: read address  (log(N/R) bits) per bank
// bank_din:   write data per bank
// bank_dout:  read data per bank (combinational, same-cycle)
// =============================================================================

module mem_banks #(
    parameter B     = 16,
    parameter N     = 256,
    parameter R     = 4,
    parameter DEPTH = N/R,
    parameter DWIDTH = 2*(B+1),
    parameter AWIDTH = $clog2(DEPTH)
)(
    input  wire                   clk,
    input  wire [R-1:0]           bank_we,
    input  wire [R*AWIDTH-1:0]    bank_waddr,
    input  wire [R*DWIDTH-1:0]    bank_din,
    input  wire [R*AWIDTH-1:0]    bank_raddr,
    output wire [R*DWIDTH-1:0]    bank_dout
);
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_banks
            (* ram_style = "distributed" *) reg [DWIDTH-1:0] mem [0:DEPTH-1];

            always @(posedge clk) begin
                if (bank_we[i]) begin
                    mem[bank_waddr[i*AWIDTH +: AWIDTH]] <= bank_din[i*DWIDTH +: DWIDTH];
                end
            end

            assign bank_dout[i*DWIDTH +: DWIDTH] = mem[bank_raddr[i*AWIDTH +: AWIDTH]];
        end
    endgenerate
endmodule
