`timescale 1ns/1ps

module tb_check_read_mapping;
    localparam B      = 16;
    localparam N      = 256;
    localparam R      = 4;
    localparam LOGN   = 8;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    reg [WWIDTH-1:0] input_a [0:N-1];
    reg [WWIDTH-1:0] input_b [0:N-1];

    integer i;
    integer checks;
    integer mismatches;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function [WWIDTH-1:0] mem_low;
        input [1:0] bank;
        input [5:0] row;
        begin
            case (bank)
                2'd0: mem_low = dut.u_membanks.gen_banks[0].mem[row][WWIDTH-1:0];
                2'd1: mem_low = dut.u_membanks.gen_banks[1].mem[row][WWIDTH-1:0];
                2'd2: mem_low = dut.u_membanks.gen_banks[2].mem[row][WWIDTH-1:0];
                2'd3: mem_low = dut.u_membanks.gen_banks[3].mem[row][WWIDTH-1:0];
            endcase
        end
    endfunction

    always @(posedge clk) begin
        integer r;
        if (dut.u_ctrl.fsm_state == 3'd2 && checks < 120) begin
            for (r = 0; r < R; r = r + 1) begin
                reg [LOGN-1:0] orig;
                reg [1:0] bank;
                reg [5:0] row;
                reg [WWIDTH-1:0] exp_v;
                reg [WWIDTH-1:0] op_v;
                orig = dut.u_ctrl.orig_addrs[r*LOGN +: LOGN];
                bank = orig[1:0];
                row  = orig[7:2];
                exp_v = mem_low(bank, row);
                op_v  = dut.op_lower[r*WWIDTH +: WWIDTH];
                checks = checks + 1;
                if (op_v !== exp_v) begin
                    mismatches = mismatches + 1;
                    if (mismatches <= 16)
                        $display("MAP_MISMATCH t=%0t r=%0d orig=%0d bank=%0d row=%0d op=%05h exp=%05h",
                            $time, r, orig, bank, row, op_v, exp_v);
                end
            end
        end

        if (checks >= 120) begin
            $display("READ_MAP_CHECK checks=%0d mismatches=%0d", checks, mismatches);
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
        checks = 0;
        mismatches = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Aligned LOAD stimulus.
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

        repeat (200000) @(posedge clk);
        $display("TIMEOUT checks=%0d mismatches=%0d", checks, mismatches);
        $finish;
    end
endmodule
