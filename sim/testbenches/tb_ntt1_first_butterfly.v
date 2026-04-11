// Verify first NTT1 stage as a sanity check
// Compare elementary butterfly operation with golden model

`timescale 1ns/1ps

module tb_ntt1_first_butterfly;
    localparam B = 16;

    // Test first butterfly: should combine a[0], a[64], a[128], a[192]
    // Since stage 0 has is_Rhat_stage=1, r2ntt_r4 outputs only substage 0 results
    // Substage 0: with twiddle=1 (no rotation):
    //    t0 = a0 + a2,  t2 = a0 - a2
    //    t1 = a1 + a3,  t3 = a1 - a3
    // So A0=t0, A1=t1, A2=t2, A3=t3

    reg [B:0] a0, a1, a2, a3;  // inputs
    wire [B:0] A0, A1, A2, A3;  // outputs

    r2ntt_r4 #(.B(B), .KSHIFT(4)) u_bfly_test (
        .a0(a0), .a1(a1), .a2(a2), .a3(a3),
        .is_Rhat_stage(1'b1),  // First stage, mixed-radix
        .A0(A0), .A1(A1), .A2(A2), .A3(A3)
    );

    // D1 conversion functions
    function [B:0] normalize(input [B:0] in);
        normalize = (in == (1 << B)) ? 0 : in + 1;
    endfunction

    function [B:0] d1_encode(input [B:0] norm);
        d1_encode = (norm == 0) ? (1 << B) : norm - 1;
    endfunction

    initial begin
        // Test case 1: Simple values in normal form
        // Let's use a0=5, a1=3 (from earlier tests that worked)
        // This should give: t0=5+3=8, t1=5-3=2, etc.
        
        // Wait one cycle for I/O width issues then test
        #1;
        
        // Convert to D1: norm_to_d1(x) = x-1 for x>0, or 2^B for x=0
        a0 = d1_encode(5);  // D1(5) = 4
        a1 = d1_encode(3);  // D1(3) = 2
        a2 = d1_encode(0);  // D1(0) = 2^B (unused for first substage)
        a3 = d1_encode(0);  // D1(0) = 2^B (unused)

        #10;

        $display("=== First Butterfly Test ===");
        $display("Inputs (in D1): a0=%5h, a1=%5h, a2=%5h, a3=%5h", a0, a1, a2, a3);
        $display("Outputs (in D1): A0=%5h, A1=%5h, A2=%5h, A3=%5h", A0, A1, A2, A3);
        $display("Outputs (normalized): A0=%5h, A1=%5h, A2=%5h, A3=%5h", 
            normalize(A0), normalize(A1), normalize(A2), normalize(A3));
        
        // Expected: A0 should represent 5+3=8 → D1(8)=7
        //           A1 should represent 5-3=2 → D1(2)=1
        $display("Expected: A0≈7 (D1(8)), A1≈1 (D1(2))");

        #10;
        $finish;
    end
endmodule
