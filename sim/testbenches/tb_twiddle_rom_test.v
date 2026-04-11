// Test twiddle ROM lookup
`timescale 1ns/1ps

module tb_twiddle_rom;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam TW_DEPTH = 2*N;  // 512

    wire [8:0] tw_step;
    wire [R*(B+1)-1:0] tw_out;

    // Test various tw_step values
    twiddle_rom #(.B(B), .N(N), .R(R)) rom_inst (
        .tw_step(tw_step),
        .tw_out(tw_out)
    );

    wire [B:0] tw0 = tw_out[0*(B+1) +: (B+1)];
    wire [B:0] tw1 = tw_out[1*(B+1) +: (B+1)];
    wire [B:0] tw2 = tw_out[2*(B+1) +: (B+1)];
    wire [B:0] tw3 = tw_out[3*(B+1) +: (B+1)];

    reg [8:0] test_step;
    assign tw_step = test_step;

    initial begin
        $display("Twiddle ROM Lookup Test");
        $display("For tw_step values, output should be: tw[r] = mem[(r * tw_step) %% 512]");
        $display("");

        // Test tw_step = 0
        test_step = 9'h000;
        #1;
        $display("tw_step=0:");
        $display("  Expected: all outputs should be mem[0] (which is 0x00001)");
        $display("  Got: tw0=%h, tw1=%h, tw2=%h, tw3=%h", tw0, tw1, tw2, tw3);

        // Test tw_step = 1
        test_step = 9'h001;
        #1;
        $display("tw_step=1:");
        $display("  Expected: tw0=mem[0], tw1=mem[1], tw2=mem[2], tw3=mem[3]");
        $display("            tw0=0x00001, tw1=0x03ab4, tw2=0x0011a, tw3=0x0aa08");
        $display("  Got: tw0=%h, tw1=%h, tw2=%h, tw3=%h", tw0, tw1, tw2, tw3);

        // Test tw_step = 2
        test_step = 9'h002;
        #1;
        $display("tw_step=2:");
        $display("  Expected: tw0=mem[0], tw1=mem[2], tw2=mem[4], tw3=mem[6]");
        $display("            tw0=0x00001, tw1=0x0011a, tw2=0x036a3, tw3=0x02f52");
        $display("  Got: tw0=%h, tw1=%h, tw2=%h, tw3=%h", tw0, tw1, tw2, tw3);

        // Test tw_step = 128
        test_step = 9'h080;
        #1;
        $display("tw_step=128:");
        $display("  Expected indices: [0, 128%512=128, 256%512=256, 384%512=384]");
        $display("  Got: tw0=%05h, tw1=%05h, tw2=%05h, tw3=%05h", tw0, tw1, tw2, tw3);

        #10;
        $finish;
    end
endmodule
