// Isolated Butterfly Test - Monitor single NTT stage computation
// Purpose: Determine if butterflies are computing correctly or if they're producing 0x678c
`timescale 1ns/1ps

module tb_butterfly_isolation;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam WWIDTH = B + 1;
    localparam LOGR = 2;

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
    reg [WWIDTH-1:0] expected[0:N-1];

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);
        $readmemh("expected_out.hex", expected);
        
        // Dump waveform to bin folder
        $dumpfile("bin/tb_butterfly_isolation.vcd");
        $dumpvars(0, tb_butterfly_isolation);
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

        // Wait for computation to reach NTT1 stage
        $display("Waiting for NTT1 compute phase...");
        begin : wait_for_ntt1
            integer timeout = 0;
            while (timeout < 500 && dut.ctrl_unit_inst.state != 3'b010) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 500) begin
                $display("WARNING: NTT1 not reached after 500 cycles");
            end else begin
                $display("NTT1 compute started at cycle %d", timeout + 264);  // 256 load + 4 reset + 4 wait
            end
        end

        // Sample during different stages
        @(posedge clk) @(posedge clk);  // Let NTT1 run a bit
        
        $display("=== Monitoring Intermediate Values ===");
        
        // Monitor for first 20 NTT1 cycles
        for (int cycle = 0; cycle < 20; cycle = cycle + 1) begin
            @(posedge clk);
            $display("Cycle %3d: FSM_state=%b, done=%b, data_out=%h",
                cycle, dut.ctrl_unit_inst.state, done, data_out);
        end

        // Let it continue to completion
        begin : wait_for_final_done
            integer timeout = 0;
            while (!done && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100000) begin
                $display("TIMEOUT: done never asserted!");
                $finish;
            end
        end

        // Pipeline delay
        @(posedge clk);
        
        // Read outputs and compare
        $display("");
        $display("=== OUTPUT VERIFICATION ===");
        $display("First 10 outputs:");
        for (int i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            wire [WWIDTH-1:0] got = data_out;
            wire [WWIDTH-1:0] exp = expected[i];
            string status = (got == exp) ? "PASS" : "FAIL";
            $display("  [%3d] got=%h, expected=%h %s", i, got, exp, status);
        end

        #100;
        $finish;
    end

    always #5 clk = ~clk;
endmodule
