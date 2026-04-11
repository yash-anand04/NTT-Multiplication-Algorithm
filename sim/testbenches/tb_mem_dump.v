// Dump memory contents after computation
`timescale 1ns/1ps

module tb_mem_dump;
    localparam N = 256;
    localparam R = 4;
    localparam B = 16;
    localparam DWIDTH = 2*(B+1);
    localparam LOGR = 2;
    localparam LOGN = 8;
    localparam AWIDTH = 6;

    reg clk, rst_n;
    reg [DWIDTH-1:0] data_in_a, data_in_b;
    wire [DWIDTH-1:0] data_out;
    wire done;

    ntt_top #(.N(N), .R(R), .B(B)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out(data_out),
        .done(done),
        .bfly_result_out()
    );

    // Load test data
    reg [DWIDTH-1:0] input_a[0:N-1];
    reg [DWIDTH-1:0] input_b[0:N-1];

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);
    end

    initial begin
        clk = 0;
        rst_n = 0;
        data_in_a = 0;
        data_in_b = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;

        // Load phase
        for (int i = 0; i < N; i = i + 1) begin
            @(posedge clk);
            data_in_a <= input_a[i];
            data_in_b <= input_b[i];
        end

        // Wait for done
        repeat (30000) @(posedge clk);
        if (!done) $display("ERROR: done not asserted after 30000 cycles!");

        // Dump memory after done
        $display("Memory contents after computation:");
        for (int bank = 0; bank < R; bank = bank + 1) begin
            $display("  Bank %d:", bank);
            for (int addr = 0; addr < N/R; addr = addr + 1) begin
                $display("    [%2d] = %h", addr, dut.mem_banks_inst.mem_array[bank*N/R + addr]);
            end
        end

        #10;
        $finish;
    end

    always #5 clk = ~clk;
endmodule
