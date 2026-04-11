// Test NTT stages with simple trace data
`timescale 1ns/1ps

module tb_ntt_stages;
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

    // Internal signals
    wire [2:0] fsm_state = dut.fsm_state;
    wire [3:0] bank_we = dut.bank_we;
    wire [135:0] bank_dout = dut.bank_dout;
    wire [67:0] bfly_result = dut.bfly_result;
    wire [67:0] ntt_result = dut.ntt_result;
    wire [67:0] op_lower = dut.op_lower;
    wire [67:0] tracedata;  // Will show what we extract

    initial clk = 0;
    always  #5 clk = ~clk;

    integer i;

    initial begin
        $dumpfile("bin/tb_ntt_stages.vcd");
        $dumpvars(0, tb_ntt_stages);

        rst = 1; start = 0; data_in_a = 0; data_in_b = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load simple test pattern: fill with ascending counter
        @(negedge clk);
        start = 1;
        for (i = 0; i < N; i = i + 1) begin
            data_in_a = i;  // 0, 1, 2, ...
            data_in_b = i;  // same
            @(negedge clk);
        end
        start = 0;
        data_in_a = 0;
        data_in_b = 0;

        // Wait for done and monitor intermediate signals
        $display("[%0t] Waiting for done...", $time);
        wait(done);
        $display("[%0t] Done asserted. Monitoring computation...", $time);

        // Now look at stages: at done, we should be transitioning to OUTPUT
        // Let's trace what happens in OUTPUT
        @(posedge clk);
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            $display("[%0t] i=%0d: FSM=%b, output=%h, bank_dout[33:0]=%h", 
                $time, i, fsm_state, data_out, bank_dout[33:0]);
        end

        #100;
        $finish;
    end
endmodule
