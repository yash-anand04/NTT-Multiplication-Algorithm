`timescale 1ns/1ps

module tb_r2ntt_impulse;
    localparam B = 16;

    // D1 encoding: 1 -> 0, 0 -> 10000
    reg  [B:0] a0, a1, a2, a3;
    reg        is_rhat;
    wire [B:0] A0, A1, A2, A3;

    r2ntt_r4 #(.B(B), .KSHIFT(4)) dut (
        .a0(a0), .a1(a1), .a2(a2), .a3(a3),
        .is_Rhat_stage(is_rhat),
        .A0(A0), .A1(A1), .A2(A2), .A3(A3)
    );

    initial begin
        // Normal impulse [1,0,0,0] in D1.
        a0 = 17'h00000;
        a1 = 17'h10000;
        a2 = 17'h10000;
        a3 = 17'h10000;

        is_rhat = 1'b0;
        #1;
        $display("full-r4 A = %05h %05h %05h %05h", A0, A1, A2, A3);

        is_rhat = 1'b1;
        #1;
        $display("rhat    A = %05h %05h %05h %05h", A0, A1, A2, A3);

        $finish;
    end
endmodule
