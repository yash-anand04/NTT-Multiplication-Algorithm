// Dump memory contents after computation
// to check if all values are identical or if output reading is broken
`timescale 1ns/1ps

module tb_memory_dump;
    localparam B = 16;
    localparam LOGN = 8;
    localparam N = 256;
    localparam R = 4;
    localparam DEPTH = N/R;  // 64
    localparam DWIDTH = 2 * B + 2;   // 34 bits per entry

    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    
    wire [31:0] data_in_a, data_in_b;
    wire [31:0] data_out;
    wire done;

    // Input data reader
    integer fa, cnt_a = 0;
    integer fb, cnt_b = 0;
    initial begin
        fa = $fopen("input_a.hex", "r");
        fb = $fopen("input_b.hex", "r");
    end

    always @(posedge clk) begin
        if ($fscanf(fa, "%x", data_in_a) == 1) cnt_a = cnt_a + 1;
        if ($fscanf(fb, "%x", data_in_b) == 1) cnt_b = cnt_b + 1;
    end

    // Top NTT
    ntt_top u_ntt (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        #100;
        rst = 0;
        start = 1;
        #10;
        start = 0;

        wait(done);
        #100;

        $display("=== Memory Contents Dump ===");
        $display("Checking if all memory values are 0x678c or different");
        $display("");

        // Dump first few banks
        $dumpall;

        #100000;
        $finish;
    end
endmodule
