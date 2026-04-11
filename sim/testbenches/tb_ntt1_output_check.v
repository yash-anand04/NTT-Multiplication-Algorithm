// Simple test to understand where computation diverges from golden model
// Monitor NTT1 stage outputs and compare with golden model expectations

`timescale 1ns/1ps

module tb_ntt1_output_check;
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

    reg [WWIDTH-1:0] input_a[0:N-1];

    // Track when we transition from NTT1 to NTT2
    integer ntt1_done_logged = 0;

    always @(posedge clk) begin
        // Log when exiting NTT1
        if (dut.u_ctrl.fsm_state == 3'd2 && ntt1_done_logged == 0) begin
            // Still in NTT1
        end else if (dut.u_ctrl.fsm_state != 3'd2 && ntt1_done_logged == 0) begin
            ntt1_done_logged = 1;
            $display("=== NTT1 COMPLETE ===");
            $display("NTT1 finished at cycle ~%d", $time / 10);
            $display("Transitioning to state: %d", dut.u_ctrl.fsm_state);
            
            // At this point, lower half (wr_sel=2'b01) should contain NTT1 results
            // Let me capture a few memory values
            $display("\nMemory contents after NTT1 (reading lower half):");
            for (integer bank = 0; bank < R; bank = bank + 1) begin
                for (integer addr = 0; addr < 4; addr = addr + 1) begin
                    $display("  Bank[%d][%d] = %5h", bank, addr, 
                        dut.u_membanks.banks[bank].mem[addr][0*WWIDTH +: WWIDTH]);
                end
            end
        end
    end

    initial begin
        $readmemh("input_a.hex", input_a);

        rst = 1; start = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        #10;
        start = 1;
        #10;
        start = 0;

        // Load inputs
        for (integer i = 0; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = 0;
            @(negedge clk);
        end

        repeat(500000) @(posedge clk);
        $finish;
    end
endmodule
