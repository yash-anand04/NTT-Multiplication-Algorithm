// Simple trace to see if FSM is progressing
`timescale 1ns/1ps

module tb_fsm_trace;
    localparam N = 256;
    localparam R = 4;
    localparam B = 16;
    localparam DWIDTH = 2*(B+1);

    reg clk, rst_n;
    reg [DWIDTH-1:0] data_in_a, data_in_b;
    wire [DWIDTH-1:0] data_out;
    wire done;

    ntt_top #(.N(N), .R(R), .B(B)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out(data_out),
        .done(done),
        .bfly_result_out()
    );

    reg [DWIDTH-1:0] input_a[0:N-1];
    reg [DWIDTH-1:0] input_b[0:N-1];

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);
    end

    int cycle_count = 0;

    initial begin
        clk = 0;
        rst_n = 0;
        data_in_a = 0;
        data_in_b = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;

        // Load + compute
        for (int i = 0; i < N; i = i + 1) begin
            @(posedge clk);
            data_in_a <= input_a[i];
            data_in_b <= input_b[i];
        end

        // Wait for done, print FSM state periodically
        $display("Waiting for done...");
        while (!done && cycle_count < 40000) begin
            @(posedge clk);
            cycle_count++;
            if (cycle_count % 1000 == 0) begin
                $display("  Cycle %d: FSM=%d, done=%b", cycle_count, dut.fsm_state, done);
            end
        end

        $display("Final: cycle_count=%d, FSM=%d, done=%b, data_out=%h", cycle_count, dut.fsm_state, done, data_out);

        // Check a few output values
        repeat (20) @(posedge clk);
        $display("Some output values after done:");
        for (int i = 0; i < 5; i = i + 1) begin
            @(posedge clk);
            $display("  output[%d] = %h", dut.seq_cnt, data_out);
        end

        #10;
        $finish;
    end

    always #5 clk = ~clk;
endmodule
