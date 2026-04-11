// Check what value is appearing at all memory addresses
`timescale 1ns/1ps

module tb_check_memory;
    localparam N = 256;
    localparam R = 4;
    localparam B = 16;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out(data_out),
        .done(done)
    );

    // Load test data
    reg [WWIDTH-1:0] input_a[0:N-1];
    reg [WWIDTH-1:0] input_b[0:N-1];

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);
    end

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        data_in_a = 0;
        data_in_b = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load phase
        @(negedge clk);
        start = 1;
        for (int i = 0; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            @(negedge clk);
        end
        start = 0;
        data_in_a = 0;
        data_in_b = 0;

        // Wait for done
        begin : wait_for_done
            integer timeout = 0;
            while (!done && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100000) begin
                $display("TIMEOUT: done never asserted!");
                $finish;
            end
        end

        // Pipeline delay after done
        @(posedge clk);
        
        // Now read first few outputs
        $display("Reading outputs after done:");
        for (int i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            $display("  data_out[%d] = %h", i, data_out);
        end

        $finish;
    end

    always #5 clk = ~clk;
endmodule
