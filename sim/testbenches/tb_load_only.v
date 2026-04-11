// =============================================================================
// tb_load_only.v - Test LOAD/OUTPUT path without NTT
// This verifies data can be loaded and read back correctly
// =============================================================================

`timescale 1ns/1ps

module tb_load_only;
    localparam B     = 16;
    localparam N     = 256;
    localparam R     = 4;
    localparam WWIDTH = B + 1;

    reg             clk, rst, start;
    reg  [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire              done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out (data_out),
        .done     (done)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    reg [WWIDTH-1:0] input_a  [0:N-1];
    integer i, errors;

    initial begin
        $readmemh("input_a.hex", input_a);

        rst = 1; start = 0; data_in_a = 0; data_in_b = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load all N coefficients
        @(negedge clk);
        start = 1;
        for (i = 0; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_a[i] + 1;  // slight modification for b
            @(negedge clk);
        end
        start = 0;
        data_in_a = 0;
        data_in_b = 0;

        // Wait for done
        $display("[%0t] Waiting for done...", $time);
        wait(done);
        $display("[%0t] Done signal received", $time);

        // Try to read output
        @(posedge clk);
        $display("[%0t] Reading outputs...", $time);
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            $display("OUTPUT[%0d]: %0h (expected %0h)", i, data_out, input_a[i]);
        end

        #1000;
        $finish;
    end
endmodule
