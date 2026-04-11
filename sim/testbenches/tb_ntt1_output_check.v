`timescale 1ns/1ps

module tb_ntt1_output_check;
    localparam B      = 16;
    localparam N      = 256;
    localparam R      = 4;
    localparam WWIDTH = B + 1;

    reg clk, rst, start;
    reg [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    reg [WWIDTH-1:0] input_a [0:N-1];
    integer i;
    reg seen_ntt1;
    reg logged;

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

    always @(posedge clk) begin
        if (dut.u_ctrl.fsm_state == 3'd2)
            seen_ntt1 <= 1'b1;

        if (seen_ntt1 && !logged && dut.u_ctrl.fsm_state != 3'd2) begin
            integer row;
            integer changed;
            logged <= 1'b1;
            $display("=== NTT1 COMPLETE ===");
            $display("time=%0t next_state=%0d", $time, dut.u_ctrl.fsm_state);
            $display("lower half snapshot (first 8 coeffs by physical layout)");
            $display("idx0: %05h", dut.u_membanks.gen_banks[0].mem[0][WWIDTH-1:0]);
            $display("idx1: %05h", dut.u_membanks.gen_banks[1].mem[0][WWIDTH-1:0]);
            $display("idx2: %05h", dut.u_membanks.gen_banks[2].mem[0][WWIDTH-1:0]);
            $display("idx3: %05h", dut.u_membanks.gen_banks[3].mem[0][WWIDTH-1:0]);
            $display("idx4: %05h", dut.u_membanks.gen_banks[0].mem[1][WWIDTH-1:0]);
            $display("idx5: %05h", dut.u_membanks.gen_banks[1].mem[1][WWIDTH-1:0]);
            $display("idx6: %05h", dut.u_membanks.gen_banks[2].mem[1][WWIDTH-1:0]);
            $display("idx7: %05h", dut.u_membanks.gen_banks[3].mem[1][WWIDTH-1:0]);

            changed = 0;
            for (row = 0; row < (N/R); row = row + 1) begin
                if (dut.u_membanks.gen_banks[0].mem[row][WWIDTH-1:0] != 17'h10000) changed = changed + 1;
                if (dut.u_membanks.gen_banks[1].mem[row][WWIDTH-1:0] != 17'h10000) changed = changed + 1;
                if (dut.u_membanks.gen_banks[2].mem[row][WWIDTH-1:0] != 17'h10000) changed = changed + 1;
                if (dut.u_membanks.gen_banks[3].mem[row][WWIDTH-1:0] != 17'h10000) changed = changed + 1;
            end
            $display("changed lower-half entries after NTT1: %0d / %0d", changed, N);
            #20;
            $finish;
        end
    end

    initial begin
        $readmemh("input_a.hex", input_a);

        rst = 1'b1;
        start = 1'b0;
        data_in_a = {WWIDTH{1'b0}};
        data_in_b = {WWIDTH{1'b0}};
        seen_ntt1 = 1'b0;
        logged = 1'b0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Align input timing to first LOAD write edge.
        @(negedge clk);
        data_in_a = input_a[0];
        data_in_b = {WWIDTH{1'b0}};
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        @(negedge clk);

        for (i = 1; i < N; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = {WWIDTH{1'b0}};
            @(negedge clk);
        end

        repeat (200000) @(posedge clk);
        $display("TIMEOUT before NTT1 snapshot");
        $finish;
    end
endmodule
