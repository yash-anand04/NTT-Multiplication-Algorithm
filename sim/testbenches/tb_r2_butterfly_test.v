// Test single R2 (Radix-2) butterfly operation
// Isolate whether butterfly computation is correct
`timescale 1ns/1ps

module tb_r2_butterfly_test;
    localparam B = 16;
    localparam LOGN = 8;
    localparam LOGR = 2;
    localparam KSHIFT = 4;

    // Test inputs in D1 representation
    // For a basic DIT butterfly at stage 0:
    // Input: a0, a1, twiddle=1
    // Output: A0 = a0 + a1, A1 = a0 - a1
    
    // Let's compute with real values
    // a0 = 5 → D1(5) = 4
    // a1 = 3 → D1(3) = 2
    // Expected: A0 = 5+3 = 8 → D1(8) = 7
    //           A1 = 5-3 = 2 → D1(2) = 1
    
    wire [B:0] a0 = 17'd4;  // D1(5)
    wire [B:0] a1 = 17'd2;  // D1(3)
    wire [B:0] a2 = 17'd0;  // unused for first substage
    wire [B:0] a3 = 17'd0;  // unused for first substage
    
    wire is_Rhat = 1'b1;  // Run only first substage (butterfly with twiddle=1)
    
    wire [B:0] A0, A1, A2, A3;

    // Instantiate 4-point R2NTT wrapper (can run as 2-point with zeroed inputs)
    r2ntt_r4 #(.B(B), .KSHIFT(KSHIFT)) u_bfly (
        .a0(a0), .a1(a1), .a2(a2), .a3(a3),
        .is_Rhat_stage(is_Rhat),
        .A0(A0), .A1(A1), .A2(A2), .A3(A3)
    );

    // Convert back to normal representation to verify
    wire [B:0] A0_norm, A1_norm;
    d1_to_norm #(B) u_d1ton_0 (.in(A0), .out(A0_norm));
    d1_to_norm #(B) u_d1ton_1 (.in(A1), .out(A1_norm));

    initial begin
        #1;
        $display("=== R2 Butterfly Basic Test ===");
        $display("Computing: a0=5, a1=3 (in D1 = 4, 2)");
        $display("Expected: A0 = 5+3 = 8, A1 = 5-3 = 2");
        $display("");
        $display("Results:");
        $display("  A0_d1 = %h → A0_norm = %h (expect 8)", A0, A0_norm);
        $display("  A1_d1 = %h → A1_norm = %h (expect 2)", A1, A1_norm);
        
        if (A0_norm == 8 && A1_norm == 2) begin
            $display("");
            $display("PASS: R2 butterfly computing correctly!");
        end else begin
            $display("");
            $display("FAIL: R2 butterfly output incorrect!");
            $display("This indicates the butterfly implementation has bugs");
        end

        #10;
        $finish;
    end
endmodule
