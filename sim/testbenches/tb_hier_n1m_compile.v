// Minimal compile-only TB for hier_n1m_top.
// Used to validate the RTL elaborates cleanly without running the full
// (very slow) L=32 N=10^6 sim.
`timescale 1ns/1ps

module tb_hier_n1m_compile;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, start = 0;
    reg [16:0] din_a = 0, din_b = 0;
    wire [16:0] dout;
    wire valid, dn;
    wire [31:0] cyc;

    hier_n1m_top dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(din_a), .data_in_b(din_b),
        .data_out(dout), .data_out_valid(valid),
        .done(dn), .cycle_count(cyc)
    );

    initial begin
        repeat (10) @(negedge clk);
        rst = 0;
        // Just tick a few cycles to ensure no X-propagation explosions.
        repeat (20) @(negedge clk);
        $display("compile check: clock ticking, design elaborated");
        $finish;
    end
endmodule
