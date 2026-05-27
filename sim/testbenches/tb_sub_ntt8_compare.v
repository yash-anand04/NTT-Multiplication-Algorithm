// Verify sub_ntt8_bidir and sub_ntt_simple produce identical NTT outputs
// after the WEXP fix to sub_ntt8_bidir.
`timescale 1ns/1ps
module tb_sub_ntt8_compare;
    localparam B = 16, L = 8, WWIDTH = B + 1;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, start = 0, inverse = 0;
    reg  [L*WWIDTH-1:0] in_norm = 0;
    wire [L*WWIDTH-1:0] out_simple, out_bidir;
    wire valid_simple, valid_bidir;

    sub_ntt_simple #(.B(B), .L(L)) u_simple (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in_norm), .out_norm(out_simple), .valid(valid_simple)
    );
    sub_ntt8_bidir #(.B(B)) u_bidir (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in_norm), .out_norm(out_bidir), .valid(valid_bidir)
    );

    integer trial, k, errs = 0;
    reg [WWIDTH-1:0] orig [0:L-1];
    initial begin
        repeat (3) @(negedge clk); rst = 0; @(negedge clk);

        for (trial = 0; trial < 3; trial = trial + 1) begin
            for (k = 0; k < L; k = k + 1) begin
                orig[k] = $urandom & 17'h0FFFF;
                in_norm[k*WWIDTH +: WWIDTH] = orig[k];
            end
            inverse = 0; start = 1; @(negedge clk); start = 0; in_norm = 0;
            @(posedge valid_bidir); @(negedge clk);
            for (k = 0; k < L; k = k + 1)
                if (out_simple[k*WWIDTH +: WWIDTH] !== out_bidir[k*WWIDTH +: WWIDTH]) begin
                    errs = errs + 1;
                    if (errs < 10) $display("trial=%0d k=%0d  simple=%0d  bidir=%0d",
                        trial, k, out_simple[k*WWIDTH +: WWIDTH], out_bidir[k*WWIDTH +: WWIDTH]);
                end
        end
        $display("FWD compare: errs=%0d", errs);
        if (errs == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
    initial begin #50_000; $display("WATCHDOG"); $finish; end
endmodule
