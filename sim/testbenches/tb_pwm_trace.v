// Test to verify PWM (point-wise multiplication) stage produces reasonable results
// PWM multiplies NTT1 results (lower half) × NTT2 results (upper half)

`timescale 1ns/1ps

module tb_pwm_trace;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam WWIDTH = B + 1;

    reg             clk, rst, start;
    reg [WWIDTH-1:0] data_in_a = 0, data_in_b = 0;
    wire [WWIDTH-1:0] data_out;
    wire              done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    always #5 clk = ~clk;
    initial clk = 0;

    // Monitor when: entering PWM, during PWM, exiting PWM
    integer pwm_start_cycle = 0;
    integer pwm_cycle_count = 0;
    
    always @(posedge clk) begin
        if (dut.u_ctrl.fsm_state == 3'd4) begin  // PWM state
            if (pwm_cycle_count == 0) begin
                pwm_start_cycle = $time;
                $display("PWM STARTED at time %d", pwm_start_cycle);
            end
            pwm_cycle_count = pwm_cycle_count + 1;
            
            // Sample some intermediate values during PWM
            if (pwm_cycle_count <= 5 || pwm_cycle_count % 10 == 0) begin
                $display("PWM cycle[%3d]: g_cnt=%2d | Lower bank out: %h,%h,%h,%h",
                    pwm_cycle_count,
                    dut.u_ctrl.g_cnt,
                    dut.u_membanks.bank_dout[0*34 +: 17],
                    dut.u_membanks.bank_dout[1*34 +: 17],
                    dut.u_membanks.bank_dout[2*34 +: 17],
                    dut.u_membanks.bank_dout[3*34 +: 17]
                );
            end
        end else if (pwm_cycle_count > 0) begin
            $display("PWM COMPLETE: executed %d cycles", pwm_cycle_count);
            pwm_cycle_count = 0;
        end
    end

    initial begin
        rst = 1; start = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        #10;
        start = 1;
        #10;
        start = 0;

        // Load dummy data
        repeat(N) @(posedge clk);

        // Wait for done
        repeat(500000) @(posedge clk);
        $finish;
    end
endmodule
