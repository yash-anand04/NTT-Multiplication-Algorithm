`timescale 1ns/1ps

module tb_check_load;
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

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);

        rst = 1'b1;
        start = 1'b0;
        data_in_a = 0;
        data_in_b = 0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        @(negedge clk);
        data_in_a = input_a[0];
        data_in_b = input_b[0];
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        // Hold coeff[0] until the first LOAD write edge has passed.
        @(negedge clk);

        for (i = 1; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            @(negedge clk);
        end
        data_in_a = 0;
        data_in_b = 0;

        // Wait until NTT1 starts.
        wait(dut.u_ctrl.fsm_state == 3'd2);
        @(posedge clk);

        $display("=== LOAD CHECK ===");
        $display("state=%0d load_cnt=%0d seq_cnt=%0d", dut.u_ctrl.fsm_state, dut.u_ctrl.load_cnt, dut.seq_cnt);

        // Dump first 8 coefficients from each half using physical bank layout.
        $display("idx=0 bank=0 row=0 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[0].mem[0][WWIDTH-1:0],
            dut.u_membanks.gen_banks[0].mem[0][2*WWIDTH-1:WWIDTH], input_a[0], input_b[0]);
        $display("idx=1 bank=1 row=0 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[1].mem[0][WWIDTH-1:0],
            dut.u_membanks.gen_banks[1].mem[0][2*WWIDTH-1:WWIDTH], input_a[1], input_b[1]);
        $display("idx=2 bank=2 row=0 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[2].mem[0][WWIDTH-1:0],
            dut.u_membanks.gen_banks[2].mem[0][2*WWIDTH-1:WWIDTH], input_a[2], input_b[2]);
        $display("idx=3 bank=3 row=0 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[3].mem[0][WWIDTH-1:0],
            dut.u_membanks.gen_banks[3].mem[0][2*WWIDTH-1:WWIDTH], input_a[3], input_b[3]);
        $display("idx=4 bank=0 row=1 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[0].mem[1][WWIDTH-1:0],
            dut.u_membanks.gen_banks[0].mem[1][2*WWIDTH-1:WWIDTH], input_a[4], input_b[4]);
        $display("idx=5 bank=1 row=1 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[1].mem[1][WWIDTH-1:0],
            dut.u_membanks.gen_banks[1].mem[1][2*WWIDTH-1:WWIDTH], input_a[5], input_b[5]);
        $display("idx=6 bank=2 row=1 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[2].mem[1][WWIDTH-1:0],
            dut.u_membanks.gen_banks[2].mem[1][2*WWIDTH-1:WWIDTH], input_a[6], input_b[6]);
        $display("idx=7 bank=3 row=1 low=%05h up=%05h in_a=%05h in_b=%05h",
            dut.u_membanks.gen_banks[3].mem[1][WWIDTH-1:0],
            dut.u_membanks.gen_banks[3].mem[1][2*WWIDTH-1:WWIDTH], input_a[7], input_b[7]);

        $finish;
    end
endmodule
