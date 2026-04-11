// Test: Verify loading works correctly
// Check if data loads into memory correctly before NTT computation
`timescale 1ns/1ps

module tb_load_verification;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam WWIDTH = B + 1;
    localparam AWIDTH = 6;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out(data_out),
        .done(done)
    );

    // Load test data
    reg [WWIDTH-1:0] input_a[0:N-1];
    reg [WWIDTH-1:0] input_b[0:N-1];

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);
    end

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        data_in_a = 0;
        data_in_b = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load phase
        $display("=== LOAD PHASE ===");
        $display("Loading %d coefficients...", N);
        @(negedge clk);
        start = 1;
        for (int i = 0; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            @(negedge clk);
        end
        start = 0;
        data_in_a = 0;
        data_in_b = 0;
        
        $display("Load phase complete");
        $display("First 5 input coefficients:");
        for (int i = 0; i < 5; i = i + 1) begin
            $display("  input_a[%d] = %h, input_b[%d] = %h", 
                     i, input_a[i], i, input_b[i]);
        end

        // After load, should be in NTT1 state. Check if data is accessible
        $display("");
        $display("=== MEMORY CHECK (immediately after load) ===");
        
        // Give 1 cycle for state to transition
        @(posedge clk);
        
        // By architecture, the first load goes to bank0 (since seq_bank starts at 0)
        // After LOAD completes:
        // - coeff[0] goes to bank0 (seq_cnt=0)
        // - coeff[1] goes to bank1 (seq_cnt=1)
        // - coeff[2] goes to bank2 (seq_cnt=2)
        // - coeff[3] goes to bank3 (seq_cnt=3)
        // - coeff[4] goes to bank0 again (seq_cnt=4 → addr=(4>6B), bank=(4%4)=0)
        
        // So bank 0 address 0 should contain coeff[0] packed with some other data
        // Let me just check if the system can read and output something
        
        repeat (30000) @(posedge clk);

        if (!done) begin
            $display("TIMEOUT: done not asserted");
            $finish;
        end

        @(posedge clk);
        
        $display("=== OUTPUT CHECK ===");
        $display("After computation, reading first coefficient...");
        for (int i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            $display("  output[%d] = %h (expected ~0x0c270)", i, data_out);
        end

        $finish;
    end

    always #5 clk = ~clk;
endmodule
