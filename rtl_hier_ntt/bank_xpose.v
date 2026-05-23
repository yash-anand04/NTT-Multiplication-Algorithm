// =============================================================================
// bank_xpose.v   (Phase B.5)
// Banked working-memory primitive for the hierarchical NTT.
//
// NUM_BANKS independent simple-dual-port RAMs.  Each bank has its own
// read address, write address+data+enable.  Reads are 1-cycle synchronous.
//
// All cross-lane shuffling (the "transpose") happens OUTSIDE this module: the
// FSM is responsible for routing lane data to/from the correct bank via a
// barrel rotator whose shift amount is derived from the multi-index sum mod
// NUM_BANKS.  Keeping the shuffle external lets us reuse the same storage
// across access patterns without baking pattern-specific muxes into memory.
//
// STORAGE picks the synthesis primitive hint:
//   "dist"  - distributed RAM (LUTRAM).  Bank depth <= 64.
//   "bram"  - block RAM (BRAM18).
//   "uram"  - UltraRAM (URAM288).
// =============================================================================

`ifndef _BANK_XPOSE_GUARD
`define _BANK_XPOSE_GUARD

module bank_xpose #(
    parameter integer WWIDTH     = 17,
    parameter integer NUM_BANKS  = 32,
    parameter integer BANK_DEPTH = 32,
    parameter         STORAGE    = "dist",
    parameter integer LOG_DEPTH  = (BANK_DEPTH <= 1) ? 1 : $clog2(BANK_DEPTH)
)(
    input  wire                              clk,
    input  wire [NUM_BANKS*LOG_DEPTH-1:0]    raddr_pack,
    input  wire [NUM_BANKS*LOG_DEPTH-1:0]    waddr_pack,
    input  wire [NUM_BANKS*WWIDTH-1:0]       wdata_pack,
    input  wire [NUM_BANKS-1:0]              we_pack,
    output wire [NUM_BANKS*WWIDTH-1:0]       rdata_pack
);

    genvar b;
    generate
        for (b = 0; b < NUM_BANKS; b = b + 1) begin : gen_bank
            wire [LOG_DEPTH-1:0] raddr = raddr_pack[b*LOG_DEPTH +: LOG_DEPTH];
            wire [LOG_DEPTH-1:0] waddr = waddr_pack[b*LOG_DEPTH +: LOG_DEPTH];
            wire [WWIDTH-1:0]    wdata = wdata_pack[b*WWIDTH +: WWIDTH];
            wire                 we    = we_pack[b];
            reg  [WWIDTH-1:0]    rdata_r;

            if (STORAGE == "uram") begin : gen_uram
                (* ram_style = "ultra" *)
                reg [WWIDTH-1:0] mem [0:BANK_DEPTH-1];
                always @(posedge clk) begin
                    if (we) mem[waddr] <= wdata;
                    rdata_r <= mem[raddr];
                end
            end else if (STORAGE == "bram") begin : gen_bram
                (* ram_style = "block" *)
                reg [WWIDTH-1:0] mem [0:BANK_DEPTH-1];
                always @(posedge clk) begin
                    if (we) mem[waddr] <= wdata;
                    rdata_r <= mem[raddr];
                end
            end else begin : gen_dist
                (* ram_style = "distributed" *)
                reg [WWIDTH-1:0] mem [0:BANK_DEPTH-1];
                always @(posedge clk) begin
                    if (we) mem[waddr] <= wdata;
                    rdata_r <= mem[raddr];
                end
            end

            assign rdata_pack[b*WWIDTH +: WWIDTH] = rdata_r;
        end
    endgenerate

endmodule

`endif // _BANK_XPOSE_GUARD
