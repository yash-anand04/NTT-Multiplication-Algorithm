// Corrected tb_ntt_top with proper OUTPUT phase reading
`timescale 1ns/1ps

module tb_ntt_final;
    localparam B     = 16;
    localparam N     = 256;
    localparam R     = 4;
    localparam WWIDTH = B + 1;

    reg             clk, rst, start;
    reg  [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire              done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out (data_out),
        .done     (done)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    reg [WWIDTH-1:0] input_a  [0:N-1];
    reg [WWIDTH-1:0] input_b  [0:N-1];
    reg [WWIDTH-1:0] expected [0:N-1];
    reg [WWIDTH-1:0] got_out  [0:N-1];
    integer i, errors;

    initial begin
        $readmemh("input_a.hex",      input_a);
        $readmemh("input_b.hex",      input_b);
        $readmemh("expected_out.hex", expected);

        $dumpfile("bin/tb_ntt_final.vcd");
        $dumpvars(0, tb_ntt_final);

        // Reset
        rst = 1; start = 0; data_in_a = 0; data_in_b = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load N coefficients
        @(negedge clk);
        start = 1;
        for (i = 0; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            @(negedge clk);
        end
        start = 0;
        data_in_a = 0;
        data_in_b = 0;

        // Monitor OUTPUT phase and capture outputs
        $display("=== Waiting for OUTPUT phase ===");
        for (i = 0; i < N; i = i + 1) begin
            @(posedge clk);
            // Only capture while in OUTPUT state
            if (dut.u_ctrl.fsm_state == 3'd6) begin  // 6 = ST_OUTPUT
                got_out[i] = data_out;
            end else if (dut.u_ctrl.fsm_state == 3'd7) begin  // 7 = ST_DONE
                got_out[i] = data_out;
            end else if (i > 0) begin
                // Went out of OUTPUT before reading all N values
                $display("ERROR: Exited OUTPUT phase at i=%d", i);
                $display("FSM state=%d", dut.u_ctrl.fsm_state);
                break;
            end
        end

        #100;

        // Display results
        $display("=== OUTPUT COMPARISON ===");
        errors = 0;
        for (i = 0; i < N; i = i + 1) begin
            if (got_out[i] !== expected[i]) begin
                if (i < 20 || i >= N-5)
                    $display("coeff[%3d]: got=%5h expected=%5h %s", i, got_out[i], expected[i],
                             (got_out[i] == expected[i]) ? "[PASS]" : "[FAIL]");
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("\nPASS: All %d coefficients match!", N);
        else
            $display("\nFAIL: %d errors out of %d coefficients", errors, N);

        #100;
        $finish;
    end
endmodule
