`timescale 1ns/1ps

module tb_sub_ntt_simple;
    localparam B = 16;
    localparam L = 8;
    localparam WWIDTH = B + 1;

    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    reg start = 0;
    reg inverse = 0;
    reg  [L*WWIDTH-1:0] in_norm = 0;
    wire [L*WWIDTH-1:0] out_norm;
    wire valid;

    sub_ntt_simple #(.B(B), .L(L)) dut (
        .clk(clk), .rst(rst), .start(start), .inverse(inverse),
        .in_norm(in_norm), .out_norm(out_norm), .valid(valid)
    );

    integer i;
    task show_out;
        input [256*8-1:0] label;
        integer j;
        begin
            $display("%s out_norm:", label);
            for (j = 0; j < 8; j = j + 1)
                $display("  out[%0d] = %0d", j, out_norm[j*WWIDTH +: WWIDTH]);
        end
    endtask

    task run_one;
        input [L*WWIDTH-1:0] vec;
        input inv_flag;
        input [256*8-1:0] label;
        begin
            @(negedge clk);
            in_norm = vec;
            start = 1;
            inverse = inv_flag;
            @(negedge clk);
            start = 0;
            in_norm = 0;
            inverse = 0;
            // Wait for valid (6 cycle latency)
            @(posedge valid);
            @(negedge clk);
            show_out(label);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        // delta_0 -> all 1s
        run_one({17'd0, 17'd0, 17'd0, 17'd0, 17'd0, 17'd0, 17'd0, 17'd1}, 1'b0, "delta_0:");
        // delta_1 -> [1, 4096, 65281, 16, 65536, 61441, 256, 65521]
        run_one({17'd0, 17'd0, 17'd0, 17'd0, 17'd0, 17'd0, 17'd1, 17'd0}, 1'b0, "delta_1:");
        // Round-trip: INTT(NTT(delta_0)) = delta_0
        // (skip, just check NTT for now)
        $finish;
    end
endmodule
