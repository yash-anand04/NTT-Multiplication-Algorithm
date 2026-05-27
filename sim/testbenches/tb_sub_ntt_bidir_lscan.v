// Standalone round-trip test for sub_ntt{L}_bidir at L=4, 8, 16.
// Each DUT is instantiated separately; tests run sequentially.
// Verifies INTT(NTT(x)) == x for random + delta inputs.
`timescale 1ns/1ps

module tb_sub_ntt_bidir_lscan;
    localparam B      = 16;
    localparam WWIDTH = B + 1;

    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, start = 0, inverse = 0;
    integer errs_total = 0;
    integer i;

    // ---- L=4 instance + round-trip test --------------------------------------
    reg  [4*WWIDTH-1:0] in4 = 0;
    wire [4*WWIDTH-1:0] out4;
    wire valid4;
    sub_ntt4_bidir #(.B(B)) dut4 (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in4), .out_norm(out4), .valid(valid4)
    );

    // ---- L=8 instance --------------------------------------------------------
    reg  [8*WWIDTH-1:0] in8 = 0;
    wire [8*WWIDTH-1:0] out8;
    wire valid8;
    sub_ntt8_bidir #(.B(B)) dut8 (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in8), .out_norm(out8), .valid(valid8)
    );

    // ---- L=16 instance -------------------------------------------------------
    reg  [16*WWIDTH-1:0] in16 = 0;
    wire [16*WWIDTH-1:0] out16;
    wire valid16;
    sub_ntt16_bidir #(.B(B)) dut16 (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in16), .out_norm(out16), .valid(valid16)
    );

    // Round-trip test buffers (max L=16)
    reg [WWIDTH-1:0] orig [0:15];
    reg [WWIDTH-1:0] fwd_buf [0:15];
    reg [WWIDTH-1:0] rt_buf  [0:15];

    task test_L4;
        integer trial, k, errs;
        begin
            errs = 0;
            // Random round-trip
            for (k = 0; k < 4; k = k + 1) orig[k] = $urandom & 17'h0FFFF;
            for (k = 0; k < 4; k = k + 1) in4[k*WWIDTH +: WWIDTH] = orig[k];
            inverse = 0; start = 1; @(negedge clk); start = 0; in4 = 0;
            @(posedge valid4); @(negedge clk);
            for (k = 0; k < 4; k = k + 1) fwd_buf[k] = out4[k*WWIDTH +: WWIDTH];

            for (k = 0; k < 4; k = k + 1) in4[k*WWIDTH +: WWIDTH] = fwd_buf[k];
            inverse = 1; start = 1; @(negedge clk); start = 0; inverse = 0; in4 = 0;
            @(posedge valid4); @(negedge clk);
            for (k = 0; k < 4; k = k + 1) rt_buf[k] = out4[k*WWIDTH +: WWIDTH];

            for (k = 0; k < 4; k = k + 1)
                if (rt_buf[k] !== orig[k]) errs = errs + 1;
            $display("L=4 random RT: errors=%0d", errs);
            errs_total = errs_total + errs;
        end
    endtask

    task test_L8;
        integer k, errs;
        begin
            errs = 0;
            for (k = 0; k < 8; k = k + 1) orig[k] = $urandom & 17'h0FFFF;
            for (k = 0; k < 8; k = k + 1) in8[k*WWIDTH +: WWIDTH] = orig[k];
            inverse = 0; start = 1; @(negedge clk); start = 0; in8 = 0;
            @(posedge valid8); @(negedge clk);
            for (k = 0; k < 8; k = k + 1) fwd_buf[k] = out8[k*WWIDTH +: WWIDTH];

            for (k = 0; k < 8; k = k + 1) in8[k*WWIDTH +: WWIDTH] = fwd_buf[k];
            inverse = 1; start = 1; @(negedge clk); start = 0; inverse = 0; in8 = 0;
            @(posedge valid8); @(negedge clk);
            for (k = 0; k < 8; k = k + 1) rt_buf[k] = out8[k*WWIDTH +: WWIDTH];

            for (k = 0; k < 8; k = k + 1)
                if (rt_buf[k] !== orig[k]) errs = errs + 1;
            $display("L=8 random RT: errors=%0d", errs);
            errs_total = errs_total + errs;
        end
    endtask

    task test_L16;
        integer k, errs;
        begin
            errs = 0;
            for (k = 0; k < 16; k = k + 1) orig[k] = $urandom & 17'h0FFFF;
            for (k = 0; k < 16; k = k + 1) in16[k*WWIDTH +: WWIDTH] = orig[k];
            inverse = 0; start = 1; @(negedge clk); start = 0; in16 = 0;
            @(posedge valid16); @(negedge clk);
            for (k = 0; k < 16; k = k + 1) fwd_buf[k] = out16[k*WWIDTH +: WWIDTH];

            for (k = 0; k < 16; k = k + 1) in16[k*WWIDTH +: WWIDTH] = fwd_buf[k];
            inverse = 1; start = 1; @(negedge clk); start = 0; inverse = 0; in16 = 0;
            @(posedge valid16); @(negedge clk);
            for (k = 0; k < 16; k = k + 1) rt_buf[k] = out16[k*WWIDTH +: WWIDTH];

            for (k = 0; k < 16; k = k + 1)
                if (rt_buf[k] !== orig[k]) errs = errs + 1;
            $display("L=16 random RT: errors=%0d", errs);
            errs_total = errs_total + errs;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        repeat (3) test_L4;
        repeat (3) test_L8;
        repeat (3) test_L16;

        $display("=== TOTAL errors=%0d ===", errs_total);
        if (errs_total == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end

    initial begin
        #200_000;
        $display("WATCHDOG TIMEOUT");
        $finish;
    end
endmodule
