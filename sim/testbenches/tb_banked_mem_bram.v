// =============================================================================
// tb_banked_mem_bram.v
// Quick unit test for banked_mem in BRAM mode.
//   - Writes a known pattern into all 32 banks at varying positions.
//   - Reads it back and checks alignment with crossbar.
//   - Verifies the 1-cycle BRAM read latency is correctly compensated by the
//     rshift_r register inside the module.
// =============================================================================
`timescale 1ns/1ps

module tb_banked_mem_bram;

    localparam integer WWIDTH    = 17;
    localparam integer LANES     = 32;
    localparam integer DEPTH     = 1024;        // Phase-D-size: 1024 deep
    localparam integer LOG_LANES = 5;
    localparam integer LOG_DEPTH = 10;

    reg clk = 0;
    always #5 clk = ~clk;

    reg  [LOG_LANES-1:0]           rshift = 0;
    reg  [LANES*LOG_DEPTH-1:0]     rpos_pack = 0;
    wire [LANES*WWIDTH-1:0]        rdata_pack;
    reg  [LOG_LANES-1:0]           wshift = 0;
    reg  [LANES*LOG_DEPTH-1:0]     wpos_pack = 0;
    reg  [LANES*WWIDTH-1:0]        wdata_pack = 0;
    reg  [LANES-1:0]               we_pack = 0;

    banked_mem #(
        .WWIDTH(WWIDTH), .LANES(LANES), .DEPTH(DEPTH),
        .LOG_LANES(LOG_LANES), .LOG_DEPTH(LOG_DEPTH),
        .READ_LATENCY(0), .STORAGE("bram")
    ) dut (
        .clk(clk),
        .rshift(rshift), .rpos_pack(rpos_pack), .rdata_pack(rdata_pack),
        .wshift(wshift), .wpos_pack(wpos_pack), .wdata_pack(wdata_pack),
        .we_pack(we_pack)
    );

    integer i, errors;
    integer pos, sh;
    reg [WWIDTH-1:0] expected;

    initial begin
        errors = 0;
        // ---- WRITE phase: at wshift=0, wpos[k]=k, wdata[k] = pattern(k) ----
        // pattern(k) = 17'h10000 | k    so lane k writes a unique value into
        // bank k at position k.
        @(negedge clk);
        wshift = 0;
        for (i = 0; i < LANES; i = i + 1) begin
            wpos_pack [i*LOG_DEPTH +: LOG_DEPTH] = i[LOG_DEPTH-1:0];
            wdata_pack[i*WWIDTH +: WWIDTH]       = {1'b1, 16'h0000} | i[WWIDTH-1:0];
            we_pack[i] = 1'b1;
        end
        @(negedge clk);
        we_pack = {LANES{1'b0}};

        // ---- READ-BACK phase with rshift=0: lane k should get its own pattern ----
        @(negedge clk);
        rshift = 0;
        for (i = 0; i < LANES; i = i + 1)
            rpos_pack[i*LOG_DEPTH +: LOG_DEPTH] = i[LOG_DEPTH-1:0];
        @(negedge clk);  // BRAM sync read: data available next cycle
        // Sample at next negedge.  Have to wait one full cycle for BRAM rdata.
        @(negedge clk);
        for (i = 0; i < LANES; i = i + 1) begin
            expected = {1'b1, 16'h0000} | i[WWIDTH-1:0];
            if (rdata_pack[i*WWIDTH +: WWIDTH] !== expected) begin
                $display("[rshift=0 FAIL] lane %0d: got %h, exp %h",
                         i, rdata_pack[i*WWIDTH +: WWIDTH], expected);
                errors = errors + 1;
            end
        end

        // ---- READ-BACK with rshift=7: lane k reads bank (k+7) mod 32 ----
        // bank (k+7)%32 was written at position (k+7)%32 with pattern (k+7)%32.
        @(negedge clk);
        rshift = 7;
        for (i = 0; i < LANES; i = i + 1)
            rpos_pack[i*LOG_DEPTH +: LOG_DEPTH] = ((i + 7) & 5'h1f);
        @(negedge clk);
        @(negedge clk);
        for (i = 0; i < LANES; i = i + 1) begin
            expected = {1'b1, 16'h0000} | ((i + 7) & 5'h1f);
            if (rdata_pack[i*WWIDTH +: WWIDTH] !== expected) begin
                $display("[rshift=7 FAIL] lane %0d: got %h, exp %h",
                         i, rdata_pack[i*WWIDTH +: WWIDTH], expected);
                errors = errors + 1;
            end
        end

        // ---- Back-to-back reads at different rshift to test rshift_r alignment ----
        // Issue cycle T0: rshift=3, lanes read bank (k+3)%32 at pos (k+3)%32
        // Issue cycle T1: rshift=11, lanes read bank (k+11)%32 at pos (k+11)%32
        // Sample timing: rdata_pack at the negedge AFTER an issue holds that
        // issue's data, because rshift_r is latched at the intermediate posedge.
        @(negedge clk);
        rshift = 3;
        for (i = 0; i < LANES; i = i + 1)
            rpos_pack[i*LOG_DEPTH +: LOG_DEPTH] = ((i + 3) & 5'h1f);
        @(negedge clk);
        // T0 data now on rdata_pack.  Set up T1 inputs at the SAME negedge
        // (these are sampled by the next posedge).
        // -- check T0 result first --
        for (i = 0; i < LANES; i = i + 1) begin
            expected = {1'b1, 16'h0000} | ((i + 3) & 5'h1f);
            if (rdata_pack[i*WWIDTH +: WWIDTH] !== expected) begin
                $display("[btb T0 rshift=3 FAIL] lane %0d: got %h, exp %h",
                         i, rdata_pack[i*WWIDTH +: WWIDTH], expected);
                errors = errors + 1;
            end
        end
        rshift = 11;
        for (i = 0; i < LANES; i = i + 1)
            rpos_pack[i*LOG_DEPTH +: LOG_DEPTH] = ((i + 11) & 5'h1f);
        @(negedge clk);
        // T1 data now on rdata_pack.
        for (i = 0; i < LANES; i = i + 1) begin
            expected = {1'b1, 16'h0000} | ((i + 11) & 5'h1f);
            if (rdata_pack[i*WWIDTH +: WWIDTH] !== expected) begin
                $display("[btb T1 rshift=11 FAIL] lane %0d: got %h, exp %h",
                         i, rdata_pack[i*WWIDTH +: WWIDTH], expected);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("tb_banked_mem_bram: PASS  (LANES=%0d DEPTH=%0d)", LANES, DEPTH);
        else             $display("tb_banked_mem_bram: FAIL  errors=%0d", errors);
        $finish;
    end

endmodule
