// =============================================================================
// tb_mem_debug.v - Debug memory load/store
// Load 4 simple values, immediately read them back
// =============================================================================

`timescale 1ns/1ps

module tb_mem_debug;
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

    integer i;

    initial begin
        $dumpfile("bin/tb_mem_debug.vcd");
        $dumpvars(0, tb_mem_debug);

        rst = 1; start = 0; data_in_a = 0; data_in_b = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load just 4 simple test values
        @(negedge clk);
        start = 1;
        
        data_in_a = 17'h00001; data_in_b = 17'h00002;  // Load index 0
        @(negedge clk);
        $display("LOAD[0]: a=%0h b=%0h", data_in_a, data_in_b);
        
        data_in_a = 17'h00003; data_in_b = 17'h00004;  // Load index 1
        @(negedge clk);
        $display("LOAD[1]: a=%0h b=%0h", data_in_a, data_in_b);
        
        data_in_a = 17'h00005; data_in_b = 17'h00006;  // Load index 2
        @(negedge clk);
        $display("LOAD[2]: a=%0h b=%0h", data_in_a, data_in_b);
        
        data_in_a = 17'h00007; data_in_b = 17'h00008;  // Load index 3
        @(negedge clk);
        $display("LOAD[3]: a=%0h b=%0h", data_in_a, data_in_b);

        start = 0;
        data_in_a = 0;
        data_in_b = 0;

        // Finish loading remaining 252 words with zeros
        for (i = 4; i < N; i = i + 1) begin
            @(negedge clk);
        end

        $display("[%0t] Waiting for done...", $time);
        wait(done);
        $display("[%0t] Done signal asserted", $time);

        // Wait a bit for output to stabilize
        @(posedge clk);
        @(posedge clk);
        
        // Now read the 4 values we stored
        $display("[%0t] Reading outputs...", $time);
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            $display("OUTPUT[%0d]: %0h", i, data_out);
        end

        #1000;
        $finish;
    end
endmodule
