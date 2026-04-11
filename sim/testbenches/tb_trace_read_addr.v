// Trace read addresses during OUTPUT to check for stuck values
`timescale 1ns/1ps

module tb_trace_read_addr;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam LOGN = 8;
    localparam LOGR = 2;
    localparam AWIDTH = 6;

    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    
    wire [16:0] data_in_a = 0;
    wire [16:0] data_in_b = 0;
    wire [16:0] data_out;
    wire done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    always #5 clk = ~clk;

    integer output_cycle = 0;
    always @(posedge clk) begin
        if (dut.u_ctrl.state == 3'd6) begin  // OUTPUT state
            output_cycle = output_cycle + 1;
            if (output_cycle <= 20 || output_cycle % 10 == 0) begin
                $display("OUTPUT cycle[%3d]: seq_cnt=%3d | raddr[0]=%2h raddr[1]=%2h raddr[2]=%2h raddr[3]=%2h | data_out=%5h",
                    output_cycle,
                    dut.seq_cnt,
                    dut.out_raddr[0*AWIDTH +: AWIDTH],
                    dut.out_raddr[1*AWIDTH +: AWIDTH],
                    dut.out_raddr[2*AWIDTH +: AWIDTH],
                    dut.out_raddr[3*AWIDTH +: AWIDTH],
                    data_out
                );
            end
        end
    end

    initial begin
        #100; rst = 0;
        #10; start = 1;
        #10; start = 0;

        // Load dummy data (N cycles)
        repeat(N) @(posedge clk);

        // Wait for computation and output phase
        repeat(100000) @(posedge clk);
        $finish;
    end
endmodule
