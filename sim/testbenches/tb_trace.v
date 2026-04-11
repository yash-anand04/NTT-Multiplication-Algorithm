// Tracing testbench to understand what's happening
`timescale 1ns/1ps

module tb_trace;
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

    // Access internal signals via hierarchical names
    wire [7:0] seq_cnt = dut.seq_cnt;
    wire is_load = (dut.fsm_state == 3'b001);  // ST_LOAD
    wire [3:0] bank_we = dut.bank_we;

    initial clk = 0;
    always  #5 clk = ~clk;

    integer i;

    initial begin
        rst = 1; start = 0; data_in_a = 0; data_in_b = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load just first 8 values
        @(negedge clk);
        start = 1;
        for (i = 0; i < 8; i = i + 1) begin
            data_in_a = i;
            data_in_b = i + 1;
            @(negedge clk);
            if (i < 5)
                $display("[Load cycle %0d] data_in_a=%h data_in_b=%h | state=%b seq_cnt=%0d is_load=%b bank_we=%b", 
                    i, data_in_a, data_in_b, dut.fsm_state, seq_cnt, is_load, bank_we);
        end
        start = 0;

        // Rest of load
        for (i = 8; i < N; i = i + 1) begin
            data_in_a = 0;
            data_in_b = 0;
            @(negedge clk);
        end
        
        $display("Done loading");

        // Wait for done signal
        $display("Waiting for done...");
        wait(done);
        $display("Done signal asserted");

        // Now read outputs
        @(posedge clk);
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            $display("Output[%0d] = %h | seq_cnt=%0d fsm=%b is_load=%b done=%b", 
                i, data_out, seq_cnt, dut.fsm_state, is_load, done);
        end

        #100;
        $finish;
    end
endmodule
