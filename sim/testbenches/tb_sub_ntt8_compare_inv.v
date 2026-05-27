// Compare inverse outputs of sub_ntt8_bidir and sub_ntt_simple.
`timescale 1ns/1ps
module tb_sub_ntt8_compare_inv;
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

    integer trial, k, errs_fwd = 0, errs_inv = 0;
    reg [WWIDTH-1:0] orig [0:L-1];
    initial begin
        repeat (3) @(negedge clk); rst = 0; @(negedge clk);
        for (trial = 0; trial < 3; trial = trial + 1) begin
            // Forward
            for (k = 0; k < L; k = k + 1) begin
                orig[k] = $urandom & 17'h0FFFF;
                in_norm[k*WWIDTH +: WWIDTH] = orig[k];
            end
            inverse = 0; start = 1; @(negedge clk); start = 0; in_norm = 0;
            @(posedge valid_bidir); @(negedge clk);
            for (k = 0; k < L; k = k + 1)
                if (out_simple[k*WWIDTH +: WWIDTH] !== out_bidir[k*WWIDTH +: WWIDTH])
                    errs_fwd = errs_fwd + 1;
            // Wait for valid to go low
            @(negedge clk); @(negedge clk); @(negedge clk);
            // Inverse
            for (k = 0; k < L; k = k + 1) begin
                orig[k] = $urandom & 17'h0FFFF;
                in_norm[k*WWIDTH +: WWIDTH] = orig[k];
            end
            inverse = 1; start = 1; @(negedge clk); start = 0; inverse = 0; in_norm = 0;
            @(posedge valid_bidir); @(negedge clk);
            for (k = 0; k < L; k = k + 1)
                if (out_simple[k*WWIDTH +: WWIDTH] !== out_bidir[k*WWIDTH +: WWIDTH]) begin
                    errs_inv = errs_inv + 1;
                    if (errs_inv < 10) $display("INV trial=%0d k=%0d  simple=%0d  bidir=%0d",
                        trial, k, out_simple[k*WWIDTH +: WWIDTH], out_bidir[k*WWIDTH +: WWIDTH]);
                end
            @(negedge clk); @(negedge clk); @(negedge clk);
        end
        $display("FWD errs=%0d  INV errs=%0d", errs_fwd, errs_inv);
        if (errs_fwd == 0 && errs_inv == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
    initial begin #50_000; $display("WATCHDOG"); $finish; end
endmodule
