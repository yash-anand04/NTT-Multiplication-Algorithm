// Test to verify NTT computations match golden model
// Focus on checking if first NTT stage produces expected intermediate results
`timescale 1ns/1ps

module tb_ntt1_verification;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;

    reg clk, rst, start;
    reg [16:0] data_in_a, data_in_b;
    wire [16:0] data_out;
    wire done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    always #5 clk = ~clk;
    initial clk = 0;

    reg [16:0] input_a[0:N-1];
    reg [16:0] input_b[0:N-1];
    reg [7:0] ntt1_dump_count = 0;

    always @(posedge clk) begin
        // Monitor transitions and stage changes
        if (dut.u_ctrl.fsm_state == 3'd2) begin  // NTT1
            if (dut.u_ctrl.stage_cnt == 0 && dut.u_ctrl.g_cnt < 5) begin
                if (dut.u_ctrl.g_cnt != ntt1_dump_count) begin
                    $display("NTT1 Stage 0, g=%d: orig_addrs=%d,%d,%d,%d", 
                        dut.u_ctrl.g_cnt,
                        dut.u_ctrl.orig_addrs[0*8 +: 8],
                        dut.u_ctrl.orig_addrs[1*8 +: 8],
                        dut.u_ctrl.orig_addrs[2*8 +: 8],
                        dut.u_ctrl.orig_addrs[3*8 +: 8]
                    );
                    ntt1_dump_count = dut.u_ctrl.g_cnt;
                end
            end
        end
    end

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);

        rst = 1; start = 0; data_in_a = 0; data_in_b = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        #10;
        start = 1;
        #10;
        start = 0;

        // Load inputs
        for (integer i = 0; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            @(negedge clk);
        end

        data_in_a = 0;
        data_in_b = 0;

        // Monitor NTT1 stage
        $display("=== Monitoring NTT1 Stage 0 ===");
        repeat(500000) @(posedge clk);
        $finish;
    end
endmodule
