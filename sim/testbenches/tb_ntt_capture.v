`timescale 1ns/1ps

`ifndef R_VAL
`define R_VAL 4
`endif

module tb_ntt_capture;
    localparam B      = 16;
    localparam N      = 256;
    localparam R      = `R_VAL;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    reg [WWIDTH-1:0] input_a [0:N-1];
    reg [WWIDTH-1:0] input_b [0:N-1];

    integer i;
    integer out_idx;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out(data_out),
        .done(done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $readmemh("input_a.hex", input_a);
        $readmemh("input_b.hex", input_b);

        $display("TB_CONFIG N=%0d R=%0d", N, R);

        $display("INPUT_HEAD a=%05h %05h %05h %05h", input_a[0], input_a[1], input_a[2], input_a[3]);
        $display("INPUT_HEAD b=%05h %05h %05h %05h", input_b[0], input_b[1], input_b[2], input_b[3]);

        rst = 1'b1;
        start = 1'b0;
        data_in_a = {WWIDTH{1'b0}};
        data_in_b = {WWIDTH{1'b0}};

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Present coeff 0 before asserting start so LOAD cycle 0 captures it.
        @(negedge clk);
        data_in_a = input_a[0];
        data_in_b = input_b[0];
        $display("LOAD_STREAM[0] a=%05h b=%05h", data_in_a, data_in_b);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        // Hold coeff[0] until the first LOAD write edge has passed.
        @(negedge clk);

        // Stream remaining coefficients during LOAD.
        for (i = 1; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_b[i];
            if (i < 4)
                $display("LOAD_STREAM[%0d] a=%05h b=%05h", i, data_in_a, data_in_b);
            @(negedge clk);
        end
        data_in_a = {WWIDTH{1'b0}};
        data_in_b = {WWIDTH{1'b0}};

        // Capture exactly N outputs during OUTPUT state.
        out_idx = 0;
        while (out_idx < N) begin
            @(posedge clk);
            if (dut.u_ctrl.fsm_state == 3'd6) begin
                $display("OUTPUT[%3d] = %05h", out_idx, data_out);
                out_idx = out_idx + 1;
            end
        end

        // Keep running briefly to ensure no extra state hazards.
        repeat (8) @(posedge clk);
        $finish;
    end
endmodule
