`timescale 1ns/1ps

`ifndef R_VAL
`define R_VAL 4
`endif

`ifndef CAMPAIGN_CASES
`define CAMPAIGN_CASES 50
`endif

`ifndef CAMPAIGN_SEED_A
`define CAMPAIGN_SEED_A 32'h1234ABCD
`endif

`ifndef CAMPAIGN_SEED_B
`define CAMPAIGN_SEED_B 32'h89EF0123
`endif

module tb_ntt_random_campaign;
    localparam B      = 16;
    localparam N      = 256;
    localparam R      = `R_VAL;
    localparam Q      = (1 << B) + 1;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg  [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    reg [WWIDTH-1:0] input_a  [0:N-1];
    reg [WWIDTH-1:0] input_b  [0:N-1];
    reg [WWIDTH-1:0] expected [0:N-1];
    reg [WWIDTH-1:0] got      [0:N-1];

    integer case_idx;
    integer i, j;
    integer mismatches;
    integer pass_cases;
    integer fail_cases;
    integer first_fail_idx;

    integer seed_a;
    integer seed_b;

    reg [63:0] prod64;
    reg [63:0] acc64;
    integer s;
    integer k;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out (data_out),
        .done     (done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic generate_random_inputs;
        integer idx;
        reg [31:0] ra;
        reg [31:0] rb;
        begin
            for (idx = 0; idx < N; idx = idx + 1) begin
                ra = $urandom(seed_a);
                rb = $urandom(seed_b);
                input_a[idx] = ra % Q;
                input_b[idx] = rb % Q;
            end
        end
    endtask

    task automatic compute_expected_direct;
        integer ii, jj;
        begin
            for (ii = 0; ii < N; ii = ii + 1)
                expected[ii] = {WWIDTH{1'b0}};

            for (ii = 0; ii < N; ii = ii + 1) begin
                for (jj = 0; jj < N; jj = jj + 1) begin
                    prod64 = (input_a[ii] * input_b[jj]) % Q;
                    s = ii + jj;
                    k = s % N;

                    if (s >= N)
                        acc64 = expected[k] + Q - prod64;
                    else
                        acc64 = expected[k] + prod64;

                    expected[k] = acc64 % Q;
                end
            end
        end
    endtask

    task automatic run_single_case;
        integer idx;
        begin
            rst = 1'b1;
            start = 1'b0;
            data_in_a = {WWIDTH{1'b0}};
            data_in_b = {WWIDTH{1'b0}};

            repeat (4) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;

            @(negedge clk);
            data_in_a = input_a[0];
            data_in_b = input_b[0];
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            @(negedge clk);

            for (idx = 1; idx < N; idx = idx + 1) begin
                data_in_a = input_a[idx];
                data_in_b = input_b[idx];
                @(negedge clk);
            end
            data_in_a = {WWIDTH{1'b0}};
            data_in_b = {WWIDTH{1'b0}};

            idx = 0;
            while (idx < N) begin
                @(posedge clk);
                if (dut.u_ctrl.fsm_state == 3'd6) begin
                    got[idx] = data_out;
                    idx = idx + 1;
                end
            end

            mismatches = 0;
            first_fail_idx = -1;
            for (idx = 0; idx < N; idx = idx + 1) begin
                if (got[idx] !== expected[idx]) begin
                    mismatches = mismatches + 1;
                    if (first_fail_idx < 0)
                        first_fail_idx = idx;
                end
            end

            repeat (8) @(posedge clk);
        end
    endtask

    initial begin
        seed_a = `CAMPAIGN_SEED_A;
        seed_b = `CAMPAIGN_SEED_B;
        pass_cases = 0;
        fail_cases = 0;

        $display("RANDOM_CAMPAIGN_START N=%0d R=%0d cases=%0d seed_a=0x%08h seed_b=0x%08h",
                 N, R, `CAMPAIGN_CASES, seed_a, seed_b);

        for (case_idx = 0; case_idx < `CAMPAIGN_CASES; case_idx = case_idx + 1) begin
            generate_random_inputs();
            compute_expected_direct();
            run_single_case();

            if (mismatches == 0) begin
                pass_cases = pass_cases + 1;
                $display("CASE %0d PASS", case_idx);
            end else begin
                fail_cases = fail_cases + 1;
                $display("CASE %0d FAIL mismatches=%0d first_idx=%0d got=%05h exp=%05h",
                         case_idx, mismatches, first_fail_idx,
                         got[first_fail_idx], expected[first_fail_idx]);
            end
        end

        $display("RANDOM_CAMPAIGN_SUMMARY pass=%0d fail=%0d total=%0d",
                 pass_cases, fail_cases, `CAMPAIGN_CASES);

        if (fail_cases != 0)
            $fatal(1, "Randomized campaign failed");

        $finish;
    end
endmodule
