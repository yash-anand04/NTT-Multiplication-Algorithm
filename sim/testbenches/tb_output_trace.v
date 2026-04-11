// Test to trace OUTPUT address generation
// Check if we're reading from different addresses or stuck at one
`timescale 1ns/1ps

module tb_output_trace;
    localparam B = 16;
    localparam LOGN = 8;
    localparam N = 1 << LOGN;  // 256

    reg clk = 0;
    reg rst = 1;
    wire done;
    
    wire [LOGN:0] addr_out;  // output address (should be 0-255)
    wire [B:0] data_out;      // output data
    wire out_valid;

    // Top-level NTT
    ntt_top #(.B(B), .LOGN(LOGN)) u_ntt (
        .clk(clk),
        .rst(rst),
        .mem_addr(addr_out),
        .mem_data_out(data_out),
        .out_valid(out_valid),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        #100; rst = 0;
        #20;

        // Wait for done
        wait(done);
        #100;

        $display("=== Output Address Trace ===");
        $display("Checking first 20 output reads:");
        $display("Addr | Data");
        $display("-----|------");

        // Trace output addresses
        #0; // Wait for output phase
        for (integer i = 0; i < 20; i = i + 1) begin
            #1000; // Wait between reads
            $display("%3d  | %5h", addr_out, data_out);
        end

        $display("");
        $display("If all addresses are the same, OUTPUT READ is STUCK");
        $display("If addresses increment, address generation is WORKING");

        #10000;
        $finish;
    end
endmodule
