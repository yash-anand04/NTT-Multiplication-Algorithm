`timescale 1ns/1ps

module tb_bivar_ntt_capture;
    localparam B      = 16;
    localparam N      = 256;
    localparam L      = 8;
    localparam M      = 32;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire data_out_valid;
    wire done;
    wire [15:0] cycle_count;

    reg [WWIDTH-1:0] input_a [0:N-1];
    reg [WWIDTH-1:0] input_b [0:N-1];

    integer i;
    integer out_idx;

    bivar_ntt_top #(.B(B), .N(N), .L(L), .M(M)) dut (
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);

        $display("TB_BIVAR_NTT_CONFIG N=%0d L=%0d M=%0d", N, L, M);
        $display("INPUT_HEAD a=%05h %05h %05h %05h",
                 input_a[0], input_a[1], input_a[2], input_a[3]);
        $display("INPUT_HEAD b=%05h %05h %05h %05h",
                 input_b[0], input_b[1], input_b[2], input_b[3]);

        rst     = 1'b1;
        start   = 1'b0;
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

        for (i = 1; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            @(negedge clk);
        end
        data_in_a = {WWIDTH{1'b0}};
        data_in_b = {WWIDTH{1'b0}};

        out_idx = 0;
        while (out_idx < N) begin
            @(posedge clk);
            if (data_out_valid) begin
                $display("OUTPUT[%3d] = %05h", out_idx, data_out);
                out_idx = out_idx + 1;
            end
        end

        $display("BIVAR_CYCLES=%0d", cycle_count);
        repeat (8) @(posedge clk);
        $finish;
    end
endmodule
