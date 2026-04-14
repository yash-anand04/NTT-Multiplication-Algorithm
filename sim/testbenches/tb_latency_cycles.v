`timescale 1ns/1ps

`ifndef R_VAL
`define R_VAL 4
`endif

`ifndef AREA_MODE
`define AREA_MODE 0
`endif

module tb_latency_cycles;
    localparam B      = 16;
    localparam N      = 256;
    localparam R      = `R_VAL;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    integer cycles;
    integer c_idle, c_load, c_ntt1, c_ntt2, c_pwm, c_intt, c_output, c_done;

    ntt_top #(
        .B(B), .N(N), .R(R),
        .PAPER_AREA_MODE(`AREA_MODE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out(data_out),
        .done(done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task bump_state_counts;
        begin
            case (dut.u_ctrl.fsm_state)
                3'd0: c_idle   = c_idle + 1;
                3'd1: c_load   = c_load + 1;
                3'd2: c_ntt1   = c_ntt1 + 1;
                3'd3: c_ntt2   = c_ntt2 + 1;
                3'd4: c_pwm    = c_pwm + 1;
                3'd5: c_intt   = c_intt + 1;
                3'd6: c_output = c_output + 1;
                3'd7: c_done   = c_done + 1;
            endcase
        end
    endtask

    initial begin
        rst = 1'b1;
        start = 1'b0;
        data_in_a = {WWIDTH{1'b0}};
        data_in_b = {WWIDTH{1'b0}};

        cycles = 0;
        c_idle = 0;
        c_load = 0;
        c_ntt1 = 0;
        c_ntt2 = 0;
        c_pwm = 0;
        c_intt = 0;
        c_output = 0;
        c_done = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Start pulse and keep zero-valued stream. Latency is control-path driven.
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done) begin
            @(posedge clk);
            cycles = cycles + 1;
            bump_state_counts();
            if (cycles > 5000) begin
                $display("LATENCY_TIMEOUT R=%0d AREA_MODE=%0d", R, `AREA_MODE);
                $finish;
            end
        end

        $display("LATENCY_SUMMARY R=%0d AREA_MODE=%0d START_TO_DONE=%0d", R, `AREA_MODE, cycles);
        $display("LATENCY_BREAKDOWN LOAD=%0d NTT1=%0d NTT2=%0d PWM=%0d INTT=%0d OUTPUT=%0d DONE=%0d",
                 c_load, c_ntt1, c_ntt2, c_pwm, c_intt, c_output, c_done);

        repeat (4) @(posedge clk);
        $finish;
    end
endmodule
