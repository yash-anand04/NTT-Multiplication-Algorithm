// Detailed R2 butterfly test with step-by-step tracing
`timescale 1ns/1ps

module tb_butterfly_detailed;
    localparam B = 16;

    // Test D1 addition first
    wire [B:0] d1_4 = 17'd4;  // represents 5 in normal
    wire [B:0] d1_0 = 17'd0;  // represents 1 in normal
    wire [B:0] d1_sum;
    
    d1_add #(B) u_add (.in1(d1_4), .in2(d1_0), .out(d1_sum));
    
    // Now test D1 subtraction
    wire [B:0] d1_diff;
    d1_sub #(B) u_sub (.in1(d1_4), .in2(d1_0), .out(d1_diff));
    
    // Test D1 conversions
    wire [B:0] norm_5 = 17'd5;
    wire [B:0] d1_from_5;
    wire [B:0] back_from_d1;
    
    norm_to_d1 #(B) u_n2d (.in(norm_5), .out(d1_from_5));
    d1_to_norm #(B) u_d2n (.in(d1_from_5), .out(back_from_d1));
    
    // Convert results for display
    wire [B:0] d1_sum_norm;
    wire [B:0] d1_diff_norm;
    d1_to_norm #(B) u_s2n (.in(d1_sum), .out(d1_sum_norm));
    d1_to_norm #(B) u_df2n (.in(d1_diff), .out(d1_diff_norm));

    initial begin
        #1;
        $display("=== D1 Arithmetic Verification ===");
        $display("");
        $display("Test D1 Conversions:");
        $display("  norm(5) = %h → d1 = %h → back to norm = %h (expect 5)", 
                 norm_5, d1_from_5, back_from_d1);
        
        $display("");
        $display("Test D1 Addition: d1(5) + d1(1)");  
        $display("  d1(%h) + d1(%h) = d1(%h)", d1_4, d1_0, d1_sum);
        $display("  Expected in D1: 5+1=6, D1(6)=5");
        $display("  Converted back to norm: %h (expect 6)", d1_sum_norm);
        
        $display("");
        $display("Test D1 Subtraction: d1(5) - d1(1)");
        $display("  d1(%h) - d1(%h) = d1(%h)", d1_4, d1_0, d1_diff);
        $display("  Expected in D1: 5-1=4, D1(4)=3");
        $display("  Converted back to norm: %h (expect 4)", d1_diff_norm);

        #10;
        $finish;
    end
endmodule
