// =============================================================================
// banked_mem.v
// 32-bank LUTRAM with combinational read + cyclic-shift lane<->bank crossbar.
//
// Each bank is declared as a SEPARATE 1D reg array inside its own generate
// scope.  This matches Vivado's canonical pattern for distributed-RAM
// inference (RAM32X1S/RAM64X1S).  Putting all banks in a single 2D array
// makes Vivado fall back to flip-flops because it can't prove each "row"
// is a separate small RAM.
//
// LANE INTERFACE:
//   read : lane k accesses bank (k + rshift) mod LANES at rpos[k].
//   write: lane k targets bank (k + wshift) mod LANES at wpos[k].
//
// Reads are COMBINATIONAL; writes are clocked.
// =============================================================================

`ifndef _BANKED_MEM_GUARD
`define _BANKED_MEM_GUARD

module banked_mem #(
    parameter integer WWIDTH       = 17,
    parameter integer LANES        = 32,
    parameter integer DEPTH        = 32,
    parameter integer LOG_LANES    = 5,
    parameter integer LOG_DEPTH    = 5,
    parameter integer READ_LATENCY = 0,  // 0: combinational; 1: registered
    parameter         STORAGE      = "lutram"  // "lutram" | "bram"
    // STORAGE = "bram": BRAM18 inference per bank. Read is SYNCHRONOUS
    // (1-cycle inherent latency), so READ_LATENCY=1 is forced regardless
    // of the parameter.  Use BRAM mode when DEPTH > 64 (LUTRAM gets
    // expensive past that point).
)(
    input  wire                              clk,
    // ---- Read interface ------------------------------------------------------
    //   READ_LATENCY = 0: combinational, rdata_pack valid same cycle as inputs.
    //   READ_LATENCY = 1: registered,    rdata_pack valid one cycle later.
    input  wire [LOG_LANES-1:0]              rshift,
    input  wire [LANES*LOG_DEPTH-1:0]        rpos_pack,
    output wire [LANES*WWIDTH-1:0]           rdata_pack,
    // ---- Write (clocked) ----------------------------------------------------
    input  wire [LOG_LANES-1:0]              wshift,
    input  wire [LANES*LOG_DEPTH-1:0]        wpos_pack,
    input  wire [LANES*WWIDTH-1:0]           wdata_pack,
    input  wire [LANES-1:0]                  we_pack
);

    // -------------------------------------------------------------------------
    // Per-bank addr/data/we (selected from lanes by inverse-shift)
    // -------------------------------------------------------------------------
    wire [LOG_DEPTH-1:0] bank_raddr [0:LANES-1];
    wire [LOG_DEPTH-1:0] bank_waddr [0:LANES-1];
    wire [WWIDTH-1:0]    bank_wdata [0:LANES-1];
    wire                 bank_we    [0:LANES-1];
    wire [WWIDTH-1:0]    bank_rdata [0:LANES-1];

    genvar b;
    generate
        for (b = 0; b < LANES; b = b + 1) begin : g_bank_mux
            // bank b is fed by lane (b - wshift) mod LANES
            wire [LOG_LANES-1:0] feeder_w = (b[LOG_LANES-1:0] - wshift) & {LOG_LANES{1'b1}};
            // bank b is read by lane (b - rshift) mod LANES (same permutation)
            wire [LOG_LANES-1:0] feeder_r = (b[LOG_LANES-1:0] - rshift) & {LOG_LANES{1'b1}};

            assign bank_waddr[b] = wpos_pack[feeder_w*LOG_DEPTH +: LOG_DEPTH];
            assign bank_wdata[b] = wdata_pack[feeder_w*WWIDTH +: WWIDTH];
            assign bank_we   [b] = we_pack[feeder_w];
            assign bank_raddr[b] = rpos_pack[feeder_r*LOG_DEPTH +: LOG_DEPTH];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Each bank: per-STORAGE inference.
    //   "lutram" : 1-D distributed-RAM (RAM32X1S / RAM64X1S), combinational read.
    //   "bram"   : 1-D block-RAM (RAMB18E2), synchronous read (1-cycle latency).
    //              Read address is registered inside the RAM primitive; the read
    //              data emerges one clock after the read address is presented.
    // -------------------------------------------------------------------------
    generate
        if (STORAGE == "lutram") begin : g_lutram_storage
            for (b = 0; b < LANES; b = b + 1) begin : g_bank
                (* ram_style = "distributed" *)
                reg [WWIDTH-1:0] mem [0:DEPTH-1];
                always @(posedge clk) begin
                    if (bank_we[b]) mem[bank_waddr[b]] <= bank_wdata[b];
                end
                assign bank_rdata[b] = mem[bank_raddr[b]];
            end
        end else begin : g_bram_storage
            for (b = 0; b < LANES; b = b + 1) begin : g_bank
                (* ram_style = "block" *)
                reg [WWIDTH-1:0] mem [0:DEPTH-1];
                reg [WWIDTH-1:0] rdata_r;
                always @(posedge clk) begin
                    if (bank_we[b]) mem[bank_waddr[b]] <= bank_wdata[b];
                    rdata_r <= mem[bank_raddr[b]];   // sync read
                end
                assign bank_rdata[b] = rdata_r;
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Lane-side rdata: lane k -> bank (k + rshift_eff) mod LANES.
    //
    // BRAM mode: bank_rdata is 1-cycle delayed (sync read), so rshift_eff
    // must also be 1-cycle delayed to align the crossbar with the right
    // data.  LUTRAM mode: rshift_eff = rshift (combinational).
    // -------------------------------------------------------------------------
    reg [LOG_LANES-1:0] rshift_r;
    always @(posedge clk) rshift_r <= rshift;
    wire [LOG_LANES-1:0] rshift_eff = (STORAGE == "bram") ? rshift_r : rshift;

    wire [LANES*WWIDTH-1:0] rdata_pack_comb;
    genvar k;
    generate
        for (k = 0; k < LANES; k = k + 1) begin : g_lane_rd
            wire [LOG_LANES-1:0] bnk = (k[LOG_LANES-1:0] + rshift_eff) & {LOG_LANES{1'b1}};
            assign rdata_pack_comb[k*WWIDTH +: WWIDTH] = bank_rdata[bnk];
        end
    endgenerate

    generate
        if (READ_LATENCY == 0) begin : gen_comb_rd
            assign rdata_pack = rdata_pack_comb;
        end else begin : gen_reg_rd
            // 1-cycle registered rdata. DONT_TOUCH prevents Vivado from
            // absorbing this register into downstream DSPs / muxes; without
            // it Vivado merges and the critical path remains long.
            (* DONT_TOUCH = "true" *) reg [LANES*WWIDTH-1:0] rdata_pack_reg;
            always @(posedge clk) rdata_pack_reg <= rdata_pack_comb;
            assign rdata_pack = rdata_pack_reg;
        end
    endgenerate

endmodule

`endif // _BANKED_MEM_GUARD
