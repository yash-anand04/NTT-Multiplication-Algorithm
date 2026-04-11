// Trace write addresses during NTT computation
`timescale 1ns/1ps

module tb_trace_write_addr;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam LOGN = 8;
    localparam LOGR = 2;
    localparam AWIDTH = LOGN - LOGR;  // 6

    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    
    wire [31:0] data_in_a = 0;
    wire [31:0] data_in_b = 0;
    wire [31:0] data_out;
    wire done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    always #5 clk = ~clk;

    // Monitor write addresses during NTT1
    integer ntt1_cycle = 0;
    always @(posedge clk) begin
        // Very crude: just count cycles after load and trace some write addresses
        if (dut.u_ctrl.state == 3'd2) begin  // NTT1 state
            ntt1_cycle = ntt1_cycle + 1;
            if (ntt1_cycle < 20 || ntt1_cycle % 10 == 0) begin
                $display("NTT1 cycle[%3d]: stage=%d g=%d b=%d delta=%d | waddr[0]=%2h waddr[1]=%2h waddr[2]=%2h waddr[3]=%2h",
                    ntt1_cycle,
                    dut.u_ctrl.stage_cnt,
                    dut.u_ctrl.g_cnt,
                    dut.u_ctrl.b_cnt,
                    dut.u_ctrl.delta_idx,
                    dut.bank_waddr[0*AWIDTH +: AWIDTH],
                    dut.bank_waddr[1*AWIDTH +: AWIDTH],
                    dut.bank_waddr[2*AWIDTH +: AWIDTH],
                    dut.bank_waddr[3*AWIDTH +: AWIDTH]
                );
            end
        end
    end

    initial begin
        #100; rst = 0;
        #10; start = 1;
        #10; start = 0;

        repeat(20000) @(posedge clk);
        $finish;
    end
endmodule
