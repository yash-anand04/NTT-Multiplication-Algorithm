// Trace actual memory reads during first NTT1 stage to verify correct data
`timescale 1ns/1ps

module tb_first_butterfly_reads;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam WWIDTH = B + 1;
    localparam AWIDTH = 6;  // LOGN - LOGR = 8 - 2

    reg             clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire              done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    always #5 clk = ~clk;
    initial clk = 0;

    reg [WWIDTH-1:0] input_a[0:N-1];
    reg [WWIDTH-1:0] input_b[0:N-1];
    integer first_butterfly_logged = 0;

    always @(posedge clk) begin
        // On first cycle of NTT1 stage 0
        if (dut.u_ctrl.fsm_state == 3'd2 && dut.u_ctrl.stage_cnt == 0 && 
            dut.u_ctrl.g_cnt == 0 && first_butterfly_logged == 0) begin
            
            first_butterfly_logged = 1;
            
            $display("=== FIRST BUTTERFLY MEMORY READ ===");
            $display("Time: %0t", $time);
            $display("Reading orig_addresses: %d, %d, %d, %d",
                dut.u_ctrl.orig_addrs[0*8 +: 8],
                dut.u_ctrl.orig_addrs[1*8 +: 8],
                dut.u_ctrl.orig_addrs[2*8 +: 8],
                dut.u_ctrl.orig_addrs[3*8 +: 8]
            );
            
            $display("Data loaded into banks (should be coeffs a[0,64,128,192]):");
            $display("  a[0]=%5h should be at input_a[0]=%5h", 
                input_a[0],
                input_a[0]);
            $display("  a[64]=%5h should be at input_a[64]=%5h",
                input_a[64],
                input_a[64]);
            $display("  a[128]=%5h should be at input_a[128]=%5h",
                input_a[128],
                input_a[128]);
            $display("  a[192]=%5h should be at input_a[192]=%5h",
                input_a[192],
                input_a[192]);
                
            $display("\nBank read addresses after interconnect routing:");
            $display("  Bank 0 address: %2h", dut.bank_raddr[0*AWIDTH +: AWIDTH]);
            $display("  Bank 1 address: %2h", dut.bank_raddr[1*AWIDTH +: AWIDTH]);
            $display("  Bank 2 address: %2h", dut.bank_raddr[2*AWIDTH +: AWIDTH]);
            $display("  Bank 3 address: %2h", dut.bank_raddr[3*AWIDTH +: AWIDTH]);
            
            $display("\nBank outputs (what butterfly will read):");
            $display("  Bank 0 data: %5h", dut.bank_dout[0*34 +: WWIDTH]);
            $display("  Bank 1 data: %5h", dut.bank_dout[1*34 +: WWIDTH]);
            $display("  Bank 2 data: %5h", dut.bank_dout[2*34 +: WWIDTH]);
            $display("  Bank 3 data: %5h", dut.bank_dout[3*34 +: WWIDTH]);
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

        repeat(500000) @(posedge clk);
        $finish;
    end
endmodule
