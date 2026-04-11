// =============================================================================
// mem_banks.v
// R parallel memory banks for in-place NTT storage.
// Each bank holds N/R entries. Each entry stores 2*(B+1) bits:
//   upper (B+1) bits  = coefficient of polynomial b (for NTT2)
//   lower (B+1) bits  = coefficient of polynomial a (for NTT1/INTT)
//
// bank_we: write enable per bank
// bank_waddr: write address (log(N/R) bits) per bank
// bank_raddr: read address  (log(N/R) bits) per bank
// bank_din:  write data per bank
// bank_dout: read data per bank
// =============================================================================

module mem_banks #(
    parameter B     = 16,   // Fermat word width = B+1 bits
    parameter N     = 256,  // Polynomial degree
    parameter R     = 4,    // Radix (number of banks)
    parameter DEPTH = N/R,  // Entries per bank (=64 for N=256, R=4)
    parameter DWIDTH = 2*(B+1),  // Data width per entry (34 bits)
    parameter AWIDTH = $clog2(DEPTH)  // Address bits (=6 for DEPTH=64)
)(
    input  wire                   clk,
    // Write port (one per bank)
    input  wire [R-1:0]           bank_we,
    input  wire [R*AWIDTH-1:0]    bank_waddr,
    input  wire [R*DWIDTH-1:0]    bank_din,
    // Read port (one per bank)
    input  wire [R*AWIDTH-1:0]    bank_raddr,
    output wire [R*DWIDTH-1:0]    bank_dout
);
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_banks
            // Simple banked memory with synchronous write and combinational read.
            reg [DWIDTH-1:0] mem [0:DEPTH-1];

            always @(posedge clk) begin
                if (bank_we[i]) begin
                    mem[bank_waddr[i*AWIDTH +: AWIDTH]] <= bank_din[i*DWIDTH +: DWIDTH];
                end
            end

            assign bank_dout[i*DWIDTH +: DWIDTH] = mem[bank_raddr[i*AWIDTH +: AWIDTH]];
        end
    endgenerate
endmodule
