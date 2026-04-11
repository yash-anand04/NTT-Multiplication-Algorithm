`timescale 1ns/1ps

module tb_intt_coverage;
    localparam B      = 16;
    localparam N      = 256;
    localparam R      = 4;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    reg [WWIDTH-1:0] input_a [0:N-1];
    reg [WWIDTH-1:0] input_b [0:N-1];
    integer i;
    reg seen_intt;
    reg logged;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (dut.u_ctrl.fsm_state == 3'd5)
            seen_intt <= 1'b1;

        if (seen_intt && !logged && dut.u_ctrl.fsm_state == 3'd6) begin
            integer row;
            integer cnt_gt_q;
            integer cnt_eq_d1zero;
            logged <= 1'b1;

            cnt_gt_q = 0;
            cnt_eq_d1zero = 0;
            for (row = 0; row < (N/R); row = row + 1) begin
                if (dut.u_membanks.gen_banks[0].mem[row][WWIDTH-1:0] > 17'h10000) cnt_gt_q = cnt_gt_q + 1;
                if (dut.u_membanks.gen_banks[1].mem[row][WWIDTH-1:0] > 17'h10000) cnt_gt_q = cnt_gt_q + 1;
                if (dut.u_membanks.gen_banks[2].mem[row][WWIDTH-1:0] > 17'h10000) cnt_gt_q = cnt_gt_q + 1;
                if (dut.u_membanks.gen_banks[3].mem[row][WWIDTH-1:0] > 17'h10000) cnt_gt_q = cnt_gt_q + 1;

                if (dut.u_membanks.gen_banks[0].mem[row][WWIDTH-1:0] == 17'h10000) cnt_eq_d1zero = cnt_eq_d1zero + 1;
                if (dut.u_membanks.gen_banks[1].mem[row][WWIDTH-1:0] == 17'h10000) cnt_eq_d1zero = cnt_eq_d1zero + 1;
                if (dut.u_membanks.gen_banks[2].mem[row][WWIDTH-1:0] == 17'h10000) cnt_eq_d1zero = cnt_eq_d1zero + 1;
                if (dut.u_membanks.gen_banks[3].mem[row][WWIDTH-1:0] == 17'h10000) cnt_eq_d1zero = cnt_eq_d1zero + 1;
            end

            $display("=== INTT COVERAGE ===");
            $display("lower entries > q(0x10000): %0d / %0d", cnt_gt_q, N);
            $display("lower entries == d1_zero(0x10000): %0d / %0d", cnt_eq_d1zero, N);
            $display("sample idx0..7: %05h %05h %05h %05h %05h %05h %05h %05h",
                dut.u_membanks.gen_banks[0].mem[0][WWIDTH-1:0],
                dut.u_membanks.gen_banks[1].mem[0][WWIDTH-1:0],
                dut.u_membanks.gen_banks[2].mem[0][WWIDTH-1:0],
                dut.u_membanks.gen_banks[3].mem[0][WWIDTH-1:0],
                dut.u_membanks.gen_banks[0].mem[1][WWIDTH-1:0],
                dut.u_membanks.gen_banks[1].mem[1][WWIDTH-1:0],
                dut.u_membanks.gen_banks[2].mem[1][WWIDTH-1:0],
                dut.u_membanks.gen_banks[3].mem[1][WWIDTH-1:0]);
            #20;
            $finish;
        end
    end

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);

        rst = 1'b1;
        start = 1'b0;
        data_in_a = 0;
        data_in_b = 0;
        seen_intt = 1'b0;
        logged = 1'b0;

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

        for (i = 1; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            @(negedge clk);
        end

        repeat (300000) @(posedge clk);
        $display("TIMEOUT before INTT coverage snapshot");
        $finish;
    end
endmodule
