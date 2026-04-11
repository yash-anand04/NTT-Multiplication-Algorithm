// Debug test to trace FSM states and find where hang occurs
`timescale 1ns/1ps

module tb_fsm_debug;
    localparam B     = 16;
    localparam N     = 256;
    localparam R     = 4;
    localparam WWIDTH = B + 1;

    reg             clk, rst, start;
    wire [WWIDTH-1:0] data_in_a = 0, data_in_b = 0;
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

    initial begin
        rst = 1; start = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        #10;
        start = 1;
        #10;
        start = 0;

        // Monitor FSM states
        begin : monitor
            integer cycle = 0;
            integer prev_state = 0;
            while (cycle < 1000000) begin
                @(posedge clk);
                cycle = cycle + 1;
                
                if (dut.u_ctrl.fsm_state != prev_state) begin
                    $display("Cycle %d: FSM state changed to %d", cycle, dut.u_ctrl.fsm_state);
                    prev_state = dut.u_ctrl.fsm_state;
                end
                
                if (done) begin
                    $display("Done asserted at cycle %d", cycle);
                    break;
                end
            end
        end

        #1000;
        $finish;
    end
endmodule
