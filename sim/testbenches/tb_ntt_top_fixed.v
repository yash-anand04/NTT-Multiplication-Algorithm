// Fixed tb_ntt_top that reads data DURING OUTPUT phase, not after
// This version tracks data_out while output_phase is active and seq_cnt is incrementing

`timescale 1ns/1ps

module tb_ntt_top_fixed;
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
    integer read_idx = 0;
    integer in_output_phase = 0;

    initial begin
        $readmemh("input_a.hex",      input_a);
        $readmemh("input_b.hex",      input_b);
        $readmemh("expected_out.hex", expected);

        $dumpfile("bin/tb_ntt_top_fixed.vcd");
        $dumpvars(0, tb_ntt_top_fixed);

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

        // Wait for OUTPUT phase and capture N data values while OUTPUT is active
        read_idx = 0;
        in_output_phase = 0;
        fork
            begin
                wait(done);
                #10 $finish;
            end
            begin
                // Continuously check if we're in OUTPUT phase and capture data
                forever @(posedge clk) begin
                    if (dut.u_ctrl.state == 3'd6) begin  // OUTPUT state
                        in_output_phase = 1;
                    end
                    if (in_output_phase && read_idx < N) begin
                        got_out[read_idx] = data_out;
                        if (read_idx < 10 || read_idx == 255)
                            $display("DEBUG: Read coeff[%0d] = %0h (expected %0h)", read_idx, data_out, expected[read_idx]);
                        read_idx = read_idx + 1;
                    end
                    if (in_output_phase && dut.u_ctrl.state != 3'd6) begin
                        // Just exited OUTPUT phase, stop reading
                        in_output_phase = 0;
                    end
                end
            end
        join_any

        // Compare with expected
        if (read_idx == N) begin
            $display("DEBUG: Read all %d values during OUTPUT phase", N);
            errors = 0;
            for (i = 0; i < N; i = i + 1) begin
                if (got_out[i] !== expected[i]) begin
                    if (i < 10 || i == 255)
                        $display("MISMATCH at coeff[%0d]: got=%0h expected=%0h", i, got_out[i], expected[i]);
                    errors = errors + 1;
                end
            end
            if (errors == 0)
                $display("PASS: All %0d coefficients match!", N);
            else
                $display("FAIL: %0d errors out of %0d coefficients", errors, N);
        end else begin
            $display("ERROR: Only read %d values instead of %d", read_idx, N);
        end

        #100;
        $finish;
    end

    initial begin
        @(negedge done);
        repeat(10) @(posedge clk);
        $display("Monitoring after done signal...");
        wait(!done);
    end
endmodule
