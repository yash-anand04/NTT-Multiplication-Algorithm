// Simple test to dump memory contents after NTT computation
`timescale 1ns/1ps

module tb_simple_dump;
    localparam B      = 16;
    localparam N      = 256;
    localparam DWIDTH = 2 * B + 2;  // 34 bits

    reg clk = 0;
    reg rst = 1;
    reg start = 0;

    wire [31:0] data_in_a, data_in_b, data_out;
    wire done;

    ntt_top #(.B(B), .N(N), .R(4)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    always #5 clk = ~clk;

    // Simple stimulus (with files)
    integer fa, fb;
    initial begin
        fa = $fopen("input_a.hex", "r");
        fb = $fopen("input_b.hex", "r");
    end

    initial begin
        #100; rst = 0; #10;
        start = 1; #10; start = 0;

        for (integer i = 0; i < N; i = i + 1) begin
            integer va, vb;
            if ($fscanf(fa, "%x", va) == 1 && $fscanf(fb, "%x", vb) == 1) begin
                // (data_in_a and data_in_b set externally somehow)
            end
            @(posedge clk);
        end

        wait(done);
        #100;

        // Dump out values
        $display("=== Reading Output ===");
        for (integer i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            $display("Out[%3d] = %5h", i, data_out);
        end

        #100; $finish;
    end
endmodule
