// Round-trip test: INTT(NTT(x)) should equal x
`timescale 1ns/1ps

module tb_sub_ntt_simple_rt;
    localparam B = 16;
    localparam L = 8;
    localparam WWIDTH = B + 1;

    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    reg start = 0;
    reg inverse = 0;
    reg  [L*WWIDTH-1:0] in_norm = 0;
    wire [L*WWIDTH-1:0] out_norm;
    wire valid;

    sub_ntt_simple #(.B(B), .L(L)) dut (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in_norm), .out_norm(out_norm), .valid(valid)
    );

    reg  [L*WWIDTH-1:0] after_fwd;
    integer i;
    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        // Forward pass on delta_0
        in_norm = 0;
        in_norm[0*WWIDTH +: WWIDTH] = 17'd1;
        start = 1;
        inverse = 0;
        @(negedge clk);
        start = 0; in_norm = 0;
        @(posedge valid);
        @(negedge clk);
        after_fwd = out_norm;
        $display("after FWD delta_0:");
        for (i = 0; i < L; i = i + 1)
            $display("  out[%0d]=%0d", i, after_fwd[i*WWIDTH +: WWIDTH]);

        // Now feed it back as inverse
        @(negedge clk);
        in_norm = after_fwd;
        start = 1;
        inverse = 1;
        @(negedge clk);
        start = 0; in_norm = 0; inverse = 0;
        @(posedge valid);
        @(negedge clk);
        $display("after INTT(FWD(delta_0)):");
        for (i = 0; i < L; i = i + 1)
            $display("  out[%0d]=%0d (expected: %0d at i=0, 0 elsewhere)",
                     i, out_norm[i*WWIDTH +: WWIDTH], (i==0) ? 1 : 0);

        // Direct test: INTT([1,1,1,1,1,1,1,1])
        @(negedge clk);
        in_norm = {17'd1, 17'd1, 17'd1, 17'd1, 17'd1, 17'd1, 17'd1, 17'd1};
        start = 1;
        inverse = 1;
        @(negedge clk);
        start = 0; in_norm = 0; inverse = 0;
        @(posedge valid);
        @(negedge clk);
        $display("after INTT(all_1s):");
        for (i = 0; i < L; i = i + 1)
            $display("  out[%0d]=%0d (expected: %0d at i=0, 0 elsewhere)",
                     i, out_norm[i*WWIDTH +: WWIDTH], (i==0) ? 1 : 0);
        $finish;
    end
endmodule
