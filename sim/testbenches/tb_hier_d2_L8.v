// =============================================================================
// tb_hier_n1024.v
// Self-checking testbench for hier_d2_L8_top (Phase C).
//
// Test 1 (identity):  a = [1, 0, ..., 0],  b = [b_0, b_1, ..., b_{N-1}]
//                     expected c = b  (because A(X) = 1 is the multiplicative
//                     identity for polynomial mul mod X^N + 1).
//
// Test 2 (zero):      a = b = 0  -> c = 0.
//
// Test 3 (impulse):   a = [0, 1, 0, ..., 0],  b = [1, 0, ..., 0]
//                     expected c = [0, 1, 0, ..., 0]  (X * 1 = X).
// =============================================================================

`timescale 1ns/1ps

module tb_hier_d2_L8;

    localparam B      = 16;
    localparam L      = 8;
    localparam M      = 8;
    localparam N      = L * M;
    localparam WWIDTH = B + 1;
    localparam Q      = (1 << B) + 1;

    reg                   clk = 0;
    reg                   rst = 1;
    reg                   start = 0;
    reg  [WWIDTH-1:0]     data_in_a = 0;
    reg  [WWIDTH-1:0]     data_in_b = 0;
    wire [WWIDTH-1:0]     data_out;
    wire                  data_out_valid;
    wire                  done;
    wire [15:0]           cycle_count;

    hier_d2_L8_top #(.B(B), .L(L), .M(M)) dut (
        .clk            (clk),
        .rst            (rst),
        .start          (start),
        .data_in_a      (data_in_a),
        .data_in_b      (data_in_b),
        .data_out       (data_out),
        .data_out_valid (data_out_valid),
        .done           (done),
        .cycle_count    (cycle_count)
    );

    always #5 clk = ~clk;

    reg [WWIDTH-1:0] in_a    [0:N-1];
    reg [WWIDTH-1:0] in_b    [0:N-1];
    reg [WWIDTH-1:0] exp_c   [0:N-1];
    reg [WWIDTH-1:0] got_c   [0:N-1];

    integer i;
    integer errors_total = 0;

    task drive_one_test;
        input [256*8-1:0] label;
        integer i, out_idx;
        integer test_errs;
        begin
            test_errs = 0;
            rst = 1'b1;
            start = 1'b0;
            data_in_a = 0;
            data_in_b = 0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;

            @(negedge clk);
            data_in_a = in_a[0];
            data_in_b = in_b[0];
            start     = 1'b1;
            @(negedge clk);
            start     = 1'b0;
            @(negedge clk);                  // give LOAD one cycle on in_a[0]
            for (i = 1; i < N; i = i + 1) begin
                data_in_a = in_a[i];
                data_in_b = in_b[i];
                @(negedge clk);
            end
            data_in_a = 0;
            data_in_b = 0;

            out_idx = 0;
            while (out_idx < N) begin
                @(posedge clk);
                if (data_out_valid) begin
                    got_c[out_idx] = data_out;
                    out_idx = out_idx + 1;
                end
            end

            for (i = 0; i < N; i = i + 1) begin
                if (got_c[i] !== exp_c[i]) begin
                    if (test_errs < 8)
                        $display("[%0s FAIL] i=%0d  got=%0d  exp=%0d",
                                 label, i, got_c[i], exp_c[i]);
                    test_errs = test_errs + 1;
                end
            end
            // (Diagnostic snapshots removed after refactor.)
            result_we_count = 0; work_we_count = 0; trans_we_count = 0;
            first_result_we_cycle = -1; first_work_we_cycle = -1; first_work_data = -1;
            $display("[%0s] errors=%0d  cycle_count=%0d", label, test_errs, cycle_count);
            errors_total = errors_total + test_errs;
        end
    endtask

    // Diagnostic: count we firings during the run
    integer result_we_count = 0, work_we_count = 0, trans_we_count = 0;
    integer first_result_we_cycle = -1, first_work_we_cycle = -1;
    integer first_work_data = -1;
    always @(posedge clk) begin
        if (!rst) begin
            if (|dut.mem_a_we) result_we_count = result_we_count + 1;
            if (|dut.mem_work_we) begin
                work_we_count = work_we_count + 1;
                if (first_work_we_cycle < 0) begin
                    first_work_we_cycle = dut.cycle_count;
                    first_work_data = dut.mem_work_wdata[16:0];
                end
            end
            if (|dut.mem_trans_we) trans_we_count = trans_we_count + 1;
            if (|dut.mem_a_we && first_result_we_cycle < 0) first_result_we_cycle = dut.cycle_count;
        end
    end

    initial begin
        // --------------------- Test 1: identity ---------------------------
        for (i = 0; i < N; i = i + 1) begin
            in_a[i] = (i == 0) ? 17'd1 : 17'd0;
            in_b[i] = (i * 37 + 1) % Q;          // arbitrary deterministic
            exp_c[i] = in_b[i];
        end
        drive_one_test("identity");

        // --------------------- Test 2: zero -------------------------------
        for (i = 0; i < N; i = i + 1) begin
            in_a[i] = 0;
            in_b[i] = 0;
            exp_c[i] = 0;
        end
        drive_one_test("zero");

        // --------------------- Test 3: X * 1 = X --------------------------
        for (i = 0; i < N; i = i + 1) begin
            in_a[i] = (i == 1) ? 17'd1 : 17'd0;
            in_b[i] = (i == 0) ? 17'd1 : 17'd0;
            exp_c[i] = (i == 1) ? 17'd1 : 17'd0;
        end
        drive_one_test("X_times_1");

        // --------------------- Test 4: random vs Python golden -----------
        $readmemh("input_a_hier.hex",        in_a);
        $readmemh("input_b_hier.hex",        in_b);
        $readmemh("expected_hier_n64.hex", exp_c);
        drive_one_test("random_golden");

        $display("=========================================");
        $display("TOTAL errors=%0d", errors_total);
        if (errors_total == 0) $display("PASS");
        else                    $display("FAIL");
        $display("=========================================");
        $finish;
    end

    initial begin
        #5000000;
        $display("WATCHDOG");
        $finish;
    end
endmodule
