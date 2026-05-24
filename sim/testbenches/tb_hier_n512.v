// =============================================================================
// tb_hier_n512.v - debug variant for Phase D at L=8, N=512.
// Same shape as tb_hier_n32k.v but ~30x faster.
// =============================================================================
`timescale 1ns/1ps

module tb_hier_n512;
    localparam B = 16;
    localparam L = 8;
    localparam N = L * L * L;          // 512
    localparam WWIDTH = B + 1;

    reg                   clk = 0;
    reg                   rst = 1;
    reg                   start = 0;
    reg  [WWIDTH-1:0]     data_in_a = 0;
    reg  [WWIDTH-1:0]     data_in_b = 0;
    wire [WWIDTH-1:0]     data_out;
    wire                  data_out_valid;
    wire                  done;
    wire [31:0]           cycle_count;

    hier_n512_top #(.B(B), .L(L)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .done(done), .cycle_count(cycle_count)
    );

    always #5 clk = ~clk;

    reg [WWIDTH-1:0] in_a[0:N-1], in_b[0:N-1], exp_c[0:N-1], got_c[0:N-1];
    integer i;
    integer errors_total = 0;

    task drive_one_test;
        input [256*8-1:0] label;
        integer i, out_idx, test_errs;
        begin
            test_errs = 0;
            rst = 1'b1; start = 1'b0; data_in_a = 0; data_in_b = 0;
            repeat (4) @(posedge clk);
            @(negedge clk); rst = 1'b0;
            @(negedge clk);
            data_in_a = in_a[0]; data_in_b = in_b[0]; start = 1'b1;
            @(negedge clk); start = 1'b0;
            @(negedge clk);
            for (i = 1; i < N; i = i + 1) begin
                data_in_a = in_a[i]; data_in_b = in_b[i];
                @(negedge clk);
            end
            data_in_a = 0; data_in_b = 0;
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
                        $display("[%0s FAIL] i=%0d got=%0d exp=%0d", label, i, got_c[i], exp_c[i]);
                    test_errs = test_errs + 1;
                end
            end
            $display("[%0s] errors=%0d cycle_count=%0d", label, test_errs, cycle_count);
            errors_total = errors_total + test_errs;
        end
    endtask

    // Debug: dump nonzero contents of a memory using macro-expanded loops
    `define DUMP_MEM_BANK(MEM, B) \
        for (p = 0; p < 64; p = p + 1) \
            if (dut.MEM.g_bram_storage.g_bank[B].mem[p] != 0) \
                $display("  %s[bank=%0d][pos=%0d] = %0d", `"MEM`", B, p, \
                         dut.MEM.g_bram_storage.g_bank[B].mem[p]);

    task dump_mem_a;
        integer p;
        begin
            $display("---- mem_a contents ----");
            `DUMP_MEM_BANK(u_mem_a, 0) `DUMP_MEM_BANK(u_mem_a, 1)
            `DUMP_MEM_BANK(u_mem_a, 2) `DUMP_MEM_BANK(u_mem_a, 3)
            `DUMP_MEM_BANK(u_mem_a, 4) `DUMP_MEM_BANK(u_mem_a, 5)
            `DUMP_MEM_BANK(u_mem_a, 6) `DUMP_MEM_BANK(u_mem_a, 7)
            $display("---- end mem_a ----");
        end
    endtask

    task dump_mem_work;
        integer p;
        begin
            $display("---- mem_work contents ----");
            `DUMP_MEM_BANK(u_mem_work, 0) `DUMP_MEM_BANK(u_mem_work, 1)
            `DUMP_MEM_BANK(u_mem_work, 2) `DUMP_MEM_BANK(u_mem_work, 3)
            `DUMP_MEM_BANK(u_mem_work, 4) `DUMP_MEM_BANK(u_mem_work, 5)
            `DUMP_MEM_BANK(u_mem_work, 6) `DUMP_MEM_BANK(u_mem_work, 7)
            $display("---- end mem_work ----");
        end
    endtask

    task dump_mem_trans;
        integer p;
        begin
            $display("---- mem_trans contents ----");
            `DUMP_MEM_BANK(u_mem_trans, 0) `DUMP_MEM_BANK(u_mem_trans, 1)
            `DUMP_MEM_BANK(u_mem_trans, 2) `DUMP_MEM_BANK(u_mem_trans, 3)
            `DUMP_MEM_BANK(u_mem_trans, 4) `DUMP_MEM_BANK(u_mem_trans, 5)
            `DUMP_MEM_BANK(u_mem_trans, 6) `DUMP_MEM_BANK(u_mem_trans, 7)
            $display("---- end mem_trans ----");
        end
    endtask

    // Diagnostic: load delta_0 in a, then wait for FWD_L0_A end (state==DONE), dump mem_work.
    task diag_after_fwd_l0_a;
        integer j;
        begin
            rst = 1'b1; start = 1'b0; data_in_a = 0; data_in_b = 0;
            repeat (4) @(posedge clk);
            @(negedge clk); rst = 1'b0;
            @(negedge clk);
            data_in_a = 17'd1; data_in_b = 17'd0;  // delta_0 for A; B=0 (don't care)
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            @(negedge clk);
            for (j = 1; j < N; j = j + 1) begin
                data_in_a = 0; data_in_b = 0;
                @(negedge clk);
            end
            // Now wait for state == DONE (which is what FWD_L0_A transitions to in DEBUG mode)
            wait (dut.state == 5'd19);   // ST_DONE = 5'd19
            repeat (20) @(posedge clk);  // settle: drain all writes (d12 tap = 12)
            $display("--- after FWD_L1_A on delta_0 ---");
            dump_mem_work();
            $display("Expected mem_work: 1 at all 64 cells where i1=0:");
            $display("  bank = (k2 + k3) mod 8, pos = k3*8 + k2 for all k2,k3 in [0,8)");
        end
    endtask

    // Diagnostic: load delta*delta, wait for DONE state, dump mem_a (= prod after PWM bypass)
    task diag_after_pwm;
        integer j;
        begin
            rst = 1'b1; start = 1'b0; data_in_a = 0; data_in_b = 0;
            repeat (4) @(posedge clk);
            @(negedge clk); rst = 1'b0;
            @(negedge clk);
            data_in_a = 17'd1; data_in_b = 17'd1;  // delta_0 for both
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            @(negedge clk);
            for (j = 1; j < N; j = j + 1) begin
                data_in_a = 0; data_in_b = 0;
                @(negedge clk);
            end
            wait (dut.state == 5'd19);
            repeat (20) @(posedge clk);
            $display("--- after INV_XTW2 on delta_x_delta ---");
            $display("Expected: mem_trans has 1 at 64 cells (i1=0, k2, k3): bank=(k2+k3)%%8, pos=k2+8*k3");
            dump_mem_trans();
        end
    endtask

    initial begin
        // delta * delta with bypass at PWM: mem_a should be all 1s (prod after PWM)
        for (i = 0; i < N; i = i + 1) begin in_a[i] = 0; in_b[i] = 0; exp_c[i] = 0; end
        in_a[0] = 17'h00001; in_b[0] = 17'h00001; exp_c[0] = 17'h00001;
        drive_one_test("delta_x_delta_to_pwm");
        $display("Expected mem_a (prod): 1 at all 512 cells");
        dump_mem_a();

        // Identity: a = [1, 0, ..., 0], b = anything -> c = b
        for (i = 0; i < N; i = i + 1) begin in_a[i] = 0; in_b[i] = 17'h00001 + i[16:0]; exp_c[i] = in_b[i]; end
        in_a[0] = 17'h00001;
        drive_one_test("identity");
        dump_mem_a();

        for (i = 0; i < N; i = i + 1) begin in_a[i] = 0; in_b[i] = 0; exp_c[i] = 0; end
        drive_one_test("zero");

        for (i = 0; i < N; i = i + 1) begin in_a[i] = 0; in_b[i] = 0; exp_c[i] = 0; end
        in_a[1] = 17'h00001; in_b[0] = 17'h00001; exp_c[1] = 17'h00001;
        drive_one_test("X_times_1");

        $readmemh("input_a_n512.hex", in_a);
        $readmemh("input_b_n512.hex", in_b);
        $readmemh("expected_hier_n512.hex", exp_c);
        drive_one_test("random_golden");

        $display("=== TOTAL errors=%0d ===", errors_total);
        if (errors_total == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end

    initial begin
        #5_000_000;
        $display("WATCHDOG TIMEOUT");
        $finish;
    end
endmodule
