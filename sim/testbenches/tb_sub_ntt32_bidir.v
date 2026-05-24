// Standalone round-trip test for sub_ntt32_bidir.
// Verifies INTT(NTT(x)) == x and a few specific known patterns.
`timescale 1ns/1ps

module tb_sub_ntt32_bidir;
    localparam B      = 16;
    localparam R      = 32;
    localparam WWIDTH = B + 1;

    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    reg start = 0;
    reg inverse = 0;
    reg  [R*WWIDTH-1:0] in_norm = 0;
    wire [R*WWIDTH-1:0] out_norm;
    wire valid;

    sub_ntt32_bidir #(.B(B)) dut (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in_norm), .out_norm(out_norm), .valid(valid)
    );

    reg [WWIDTH-1:0] orig [0:R-1];
    reg [WWIDTH-1:0] fwd_out [0:R-1];
    reg [WWIDTH-1:0] rt_out  [0:R-1];

    integer i, errs;
    initial begin
        errs = 0;

        // ---- Setup ----------------------------------------------------------
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        // ---- Test 1: INTT(NTT(x)) == x for a random pattern -----------------
        for (i = 0; i < R; i = i + 1) begin
            orig[i] = $urandom & 17'h0FFFF;  // safe range [0, 2^16)
            in_norm[i*WWIDTH +: WWIDTH] = orig[i];
        end
        inverse = 0; start = 1;
        @(negedge clk);
        start = 0; in_norm = 0;
        @(posedge valid);
        @(negedge clk);
        for (i = 0; i < R; i = i + 1) fwd_out[i] = out_norm[i*WWIDTH +: WWIDTH];

        // Feed forward output back as inverse input
        for (i = 0; i < R; i = i + 1)
            in_norm[i*WWIDTH +: WWIDTH] = fwd_out[i];
        inverse = 1; start = 1;
        @(negedge clk);
        start = 0; inverse = 0; in_norm = 0;
        @(posedge valid);
        @(negedge clk);
        for (i = 0; i < R; i = i + 1) rt_out[i] = out_norm[i*WWIDTH +: WWIDTH];

        for (i = 0; i < R; i = i + 1) begin
            if (rt_out[i] !== orig[i]) begin
                if (errs < 8)
                    $display("[RT random FAIL] i=%0d orig=%0d rt=%0d (fwd=%0d)",
                             i, orig[i], rt_out[i], fwd_out[i]);
                errs = errs + 1;
            end
        end
        $display("Test 1 (random round-trip): errors=%0d", errs);

        // ---- Test 2: INTT(NTT(delta_0)) == delta_0 -------------------------
        for (i = 0; i < R; i = i + 1)
            in_norm[i*WWIDTH +: WWIDTH] = (i == 0) ? 17'd1 : 17'd0;
        inverse = 0; start = 1;
        @(negedge clk);
        start = 0; in_norm = 0;
        @(posedge valid);
        @(negedge clk);
        for (i = 0; i < R; i = i + 1) fwd_out[i] = out_norm[i*WWIDTH +: WWIDTH];

        // NTT(delta_0) should be all 1s
        $display("NTT(delta_0): out[0]=%0d out[1]=%0d out[7]=%0d out[31]=%0d",
                 fwd_out[0], fwd_out[1], fwd_out[7], fwd_out[31]);

        for (i = 0; i < R; i = i + 1)
            in_norm[i*WWIDTH +: WWIDTH] = fwd_out[i];
        inverse = 1; start = 1;
        @(negedge clk);
        start = 0; inverse = 0; in_norm = 0;
        @(posedge valid);
        @(negedge clk);
        for (i = 0; i < R; i = i + 1) rt_out[i] = out_norm[i*WWIDTH +: WWIDTH];

        if (rt_out[0] !== 17'd1) begin
            $display("[delta_0 RT FAIL] rt[0]=%0d expected 1", rt_out[0]);
            errs = errs + 1;
        end
        for (i = 1; i < R; i = i + 1) begin
            if (rt_out[i] !== 17'd0) begin
                if (errs < 16)
                    $display("[delta_0 RT FAIL] rt[%0d]=%0d expected 0", i, rt_out[i]);
                errs = errs + 1;
            end
        end
        $display("Test 2 (delta_0 round-trip): cumulative errors=%0d", errs);

        // ---- Test 3: INTT(all_1s) == delta_0 -------------------------------
        for (i = 0; i < R; i = i + 1)
            in_norm[i*WWIDTH +: WWIDTH] = 17'd1;
        inverse = 1; start = 1;
        @(negedge clk);
        start = 0; inverse = 0; in_norm = 0;
        @(posedge valid);
        @(negedge clk);
        for (i = 0; i < R; i = i + 1) rt_out[i] = out_norm[i*WWIDTH +: WWIDTH];

        if (rt_out[0] !== 17'd1) begin
            $display("[INTT(all_1s) FAIL] rt[0]=%0d expected 1", rt_out[0]);
            errs = errs + 1;
        end
        for (i = 1; i < R; i = i + 1) begin
            if (rt_out[i] !== 17'd0) begin
                if (errs < 24)
                    $display("[INTT(all_1s) FAIL] rt[%0d]=%0d expected 0", i, rt_out[i]);
                errs = errs + 1;
            end
        end
        $display("Test 3 (INTT(all 1s)): cumulative errors=%0d", errs);

        $display("=== TOTAL errors=%0d ===", errs);
        if (errs == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end

    initial begin
        #50_000;
        $display("WATCHDOG TIMEOUT");
        $finish;
    end
endmodule
