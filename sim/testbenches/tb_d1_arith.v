// Test D1 arithmetic in detail
`timescale 1ns/1ps

module tb_d1_arith;
    localparam B = 16;
    localparam q = (1 << B) + 1; // 65537

    // Test conversions
    wire [B:0] test_norm = 17'd4;
    wire [B:0] d1_from_4;
    wire [B:0] back_to_norm;

    norm_to_d1 #(B) u_n2d (.in(test_norm), .out(d1_from_4));
    d1_to_norm #(B) u_d2n (.in(d1_from_4), .out(back_to_norm));

    // Test D1 addition: 4 + 6 in normal = 10 in normal = 9 in D1
    wire [B:0] d1_a;  // Should represent 4 in normal
    wire [B:0] d1_b;  // Should represent 6 in normal
    wire [B:0] norm_a = 17'd4;
    wire [B:0] norm_b = 17'd6;

    norm_to_d1 #(B) u_na (.in(norm_a), .out(d1_a));
    norm_to_d1 #(B) u_nb (.in(norm_b), .out(d1_b));

    wire [B:0] d1_sum;
    wire [B:0] d1_sum_back_to_norm;
    d1_add #(B) u_add (.in1(d1_a), .in2(d1_b), .out(d1_sum));
    d1_to_norm #(B) u_sum2n (.in(d1_sum), .out(d1_sum_back_to_norm));

    // Test D1 multiplication by 2: 4*2=8, D1: 3*2=?
    wire [B:0] d1_shifted;
    wire [B:0] d1_shifted_back;
    d1_mul_by_2k #(B, 1) u_shift (.in(d1_a), .out(d1_shifted));
    d1_to_norm #(B) u_shift2n (.in(d1_shifted), .out(d1_shifted_back));

    initial begin
        #1;
        $display("=== D1 Arithmetic Tests ===");
        $display("");
        
        $display("Test 1: Conversion 4 to D1 and back");
        $display("  norm=4 -> d1=%h -> back_to_norm=%h (expect 3 -> 4)", d1_from_4, back_to_norm);
        
        $display("");
        $display("Test 2: D1 Addition (4+6=10 in normal)");
        $display("  norm_a=%h d1_a=%h", norm_a, d1_a);
        $display("  norm_b=%h d1_b=%h", norm_b, d1_b);
        $display("  d1_sum=%h (expect 9) -> backnorm=%h (expect 10)", d1_sum, d1_sum_back_to_norm);
        
        $display("");
        $display("Test 3: D1 Mul by 2^1 (4*2=8)");
        $display("  d1_a=%h -> shifted=%h -> backnorm=%h (expect 8)", d1_a, d1_shifted, d1_shifted_back);
        
        #10;
        $finish;
    end
endmodule
