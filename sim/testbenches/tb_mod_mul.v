// Test Fermat modular multiplier standalone
`timescale 1ns/1ps

module tb_mod_mul;
    localparam B = 16;

    reg clk, rst;
    reg [B:0] a, b;
    wire [B:0] result;

    mod_mul_fermat #(.B(B)) u_mul (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .result(result)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer i;
    initial begin
        rst = 1;
        @(posedge clk);
        rst = 0;

        // Test a few multiplications
        test_mul(17'h00001, 17'h00002, "1*2");
        test_mul(17'h00003, 17'h00004, "3*4");
        test_mul(17'h00010, 17'h00020, "16*32");
        test_mul(17'h00100, 17'h00101, "256*257");

        #100;
        $finish;
    end

    task test_mul(input [B:0] a_val, input [B:0] b_val, input string label);
        a = a_val;
        b = b_val;
        #1;
        $display("test %s: a=%h b=%h result=%h", label, a_val, b_val, result);
    endtask
endmodule
