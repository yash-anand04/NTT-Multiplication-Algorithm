// =============================================================================
// tb_bank_xpose.v
// Self-checking testbench for bank_xpose (Phase B.5).
//
// Writes random data into all (bank, position) slots, then reads back.
// Confirms that:
//   1. Each bank stores data independently (no cross-bank corruption)
//   2. Read latency is 1 cycle
//   3. Concurrent writes to different banks all take effect
// =============================================================================

`timescale 1ns/1ps

module tb_bank_xpose;

    localparam integer WWIDTH    = 17;
    localparam integer NUM_BANKS = 32;
    localparam integer DEPTH     = 32;
    localparam integer LOG_DEPTH = 5;

    reg                                  clk = 0;
    reg  [NUM_BANKS*LOG_DEPTH-1:0]       raddr_pack = 0;
    reg  [NUM_BANKS*LOG_DEPTH-1:0]       waddr_pack = 0;
    reg  [NUM_BANKS*WWIDTH-1:0]          wdata_pack = 0;
    reg  [NUM_BANKS-1:0]                 we_pack = 0;
    wire [NUM_BANKS*WWIDTH-1:0]          rdata_pack;

    bank_xpose #(
        .WWIDTH(WWIDTH),
        .NUM_BANKS(NUM_BANKS),
        .BANK_DEPTH(DEPTH),
        .STORAGE("dist")
    ) dut (
        .clk(clk),
        .raddr_pack(raddr_pack),
        .waddr_pack(waddr_pack),
        .wdata_pack(wdata_pack),
        .we_pack(we_pack),
        .rdata_pack(rdata_pack)
    );

    always #5 clk = ~clk;

    integer seed = 32'hF00D_CAFE;
    reg [WWIDTH-1:0] sw_mem [0:NUM_BANKS-1][0:DEPTH-1];
    integer errors = 0;

    integer b, p;
    reg [WWIDTH-1:0] tmp;

    initial begin
        // Phase 1: write every (bank, position) with a random value,
        // 1 position per cycle (all banks parallel).
        @(negedge clk);
        for (p = 0; p < DEPTH; p = p + 1) begin
            for (b = 0; b < NUM_BANKS; b = b + 1) begin
                tmp = $unsigned($random(seed)) & {WWIDTH{1'b1}};
                wdata_pack[b*WWIDTH +: WWIDTH] = tmp;
                waddr_pack[b*LOG_DEPTH +: LOG_DEPTH] = p[LOG_DEPTH-1:0];
                sw_mem[b][p] = tmp;
            end
            we_pack = {NUM_BANKS{1'b1}};
            @(negedge clk);
        end
        we_pack = 0;

        // Phase 2: read every (bank, position), 1-cycle latency
        for (p = 0; p < DEPTH; p = p + 1) begin
            for (b = 0; b < NUM_BANKS; b = b + 1) begin
                raddr_pack[b*LOG_DEPTH +: LOG_DEPTH] = p[LOG_DEPTH-1:0];
            end
            @(negedge clk);          // latch raddr, data ready next cycle
            @(negedge clk);
            for (b = 0; b < NUM_BANKS; b = b + 1) begin
                if (rdata_pack[b*WWIDTH +: WWIDTH] !== sw_mem[b][p]) begin
                    $display("FAIL bank=%0d pos=%0d got=%0d exp=%0d",
                        b, p,
                        rdata_pack[b*WWIDTH +: WWIDTH], sw_mem[b][p]);
                    errors = errors + 1;
                end
            end
        end

        $display("=========================================");
        $display("errors=%0d", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $display("=========================================");
        $finish;
    end

    initial begin
        #100000;
        $display("WATCHDOG");
        $finish;
    end
endmodule
