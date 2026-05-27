// Phase E L=8 d=4 with sub_ntt8_bidir (shift-only) instead of sub_ntt_simple.
`timescale 1ns/1ps
module tb_hier_n4k_bidir;
    localparam B = 16, L = 8, N = L*L*L*L, WWIDTH = B + 1;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, start = 0;
    reg  [WWIDTH-1:0] data_in_a = 0, data_in_b = 0;
    wire [WWIDTH-1:0] data_out; wire data_out_valid, done;
    wire [31:0] cycle_count;
    hier_n4k_bidir_top #(.B(B), .L(L)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .done(done), .cycle_count(cycle_count));
    reg [WWIDTH-1:0] in_a[0:N-1], in_b[0:N-1], exp_c[0:N-1], got_c[0:N-1];
    integer i, errors_total = 0;
    task drive_one_test;
        input [256*8-1:0] label;
        integer i, out_idx, test_errs;
        begin
            test_errs = 0;
            rst=1'b1; start=1'b0; data_in_a=0; data_in_b=0;
            repeat(4) @(posedge clk); @(negedge clk); rst=1'b0; @(negedge clk);
            data_in_a=in_a[0]; data_in_b=in_b[0]; start=1'b1;
            @(negedge clk); start=1'b0; @(negedge clk);
            for (i=1; i<N; i=i+1) begin data_in_a=in_a[i]; data_in_b=in_b[i]; @(negedge clk); end
            data_in_a=0; data_in_b=0;
            out_idx=0;
            while (out_idx < N) begin
                @(posedge clk);
                if (data_out_valid) begin got_c[out_idx]=data_out; out_idx=out_idx+1; end
            end
            for (i=0; i<N; i=i+1) if (got_c[i] !== exp_c[i]) test_errs = test_errs + 1;
            $display("[%0s] errors=%0d cycle_count=%0d", label, test_errs, cycle_count);
            errors_total = errors_total + test_errs;
        end
    endtask
    initial begin
        for (i=0; i<N; i=i+1) begin in_a[i]=0; in_b[i]=17'd1+i[16:0]; exp_c[i]=in_b[i]; end
        in_a[0]=17'd1;
        drive_one_test("identity");
        $readmemh("input_a_n4096.hex", in_a);
        $readmemh("input_b_n4096.hex", in_b);
        $readmemh("expected_hier_n4096.hex", exp_c);
        drive_one_test("random_golden");
        $display("=== TOTAL errors=%0d ===", errors_total);
        if (errors_total==0) $display("PASS"); else $display("FAIL");
        $finish;
    end
    initial begin #50_000_000; $display("WATCHDOG"); $finish; end
endmodule
