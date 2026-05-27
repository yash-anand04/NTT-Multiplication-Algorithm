// Streaming test: 64 back-to-back inputs through both modules.
// hier uses continuous start during a phase, so back-to-back behaviour matters.
`timescale 1ns/1ps
module tb_sub_ntt8_stream;
    localparam B = 16, L = 8, WWIDTH = B + 1, NTESTS = 64;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, start = 0, inverse = 0;
    reg  [L*WWIDTH-1:0] in_norm = 0;
    wire [L*WWIDTH-1:0] out_simple, out_bidir;
    wire valid_simple, valid_bidir;

    sub_ntt_simple #(.B(B), .L(L)) u_simple (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in_norm), .out_norm(out_simple), .valid(valid_simple));
    sub_ntt8_bidir #(.B(B)) u_bidir (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in_norm), .out_norm(out_bidir), .valid(valid_bidir));

    integer i, k, errs = 0, captured = 0;
    initial begin
        repeat (3) @(negedge clk); rst = 0; @(negedge clk);
        start = 1; inverse = 0;
        for (i = 0; i < NTESTS; i = i + 1) begin
            for (k = 0; k < L; k = k + 1)
                in_norm[k*WWIDTH +: WWIDTH] = (i*L + k) & 17'h0FFFF;
            @(negedge clk);
            if (valid_simple !== valid_bidir)
                $display("VALID MISMATCH i=%0d simple=%0b bidir=%0b", i, valid_simple, valid_bidir);
            if (valid_simple && valid_bidir) begin
                captured = captured + 1;
                for (k = 0; k < L; k = k + 1) begin
                    if (out_simple[k*WWIDTH +: WWIDTH] !== out_bidir[k*WWIDTH +: WWIDTH]) begin
                        if (errs < 10)
                            $display("[stream %0d k=%0d] simple=%0d bidir=%0d",
                                i, k, out_simple[k*WWIDTH +: WWIDTH], out_bidir[k*WWIDTH +: WWIDTH]);
                        errs = errs + 1;
                    end
                end
            end
        end
        start = 0; in_norm = 0;
        repeat (10) @(negedge clk);
        $display("STREAM: captured=%0d errs=%0d", captured, errs);
        if (errs == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
    initial begin #100_000; $display("WATCHDOG"); $finish; end
endmodule
