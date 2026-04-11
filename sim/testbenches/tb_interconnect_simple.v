// Simple interconnect test with clear bank labeling
`timescale 1ns/1ps

module tb_interconnect_simple;
    localparam R = 4;
    localparam DWIDTH = 34;

    // Each bank has a unique 6-bit pattern: 0xAA for bank0, 0xBB for bank1, etc
    wire [DWIDTH-1:0] bank0 = 34'h0_0000_00AA;
    wire [DWIDTH-1:0] bank1 = 34'h0_0000_00BB;
    wire [DWIDTH-1:0] bank2 = 34'h0_0000_00CC;
    wire [DWIDTH-1:0] bank3 = 34'h0_0000_00DD;
    
    wire [R*DWIDTH-1:0] bank_data = {bank3, bank2, bank1, bank0};

    // Route data from banks to operands with each iselect value
    wire [R*DWIDTH-1:0] ops_isel0, ops_isel1, ops_isel2, ops_isel3;
    integer k;

    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_0 (
        .bank_data_out(bank_data), .iselect(2'h0), .operands_out(ops_isel0)
    );
    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_1 (
        .bank_data_out(bank_data), .iselect(2'h1), .operands_out(ops_isel1)
    );
    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_2 (
        .bank_data_out(bank_data), .iselect(2'h2), .operands_out(ops_isel2)
    );
    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_3 (
        .bank_data_out(bank_data), .iselect(2'h3), .operands_out(ops_isel3)
    );

    initial begin
        #1;
        $display("Interconnect_bank_out routing test");
        $display("Bank data: bank0=%h, bank1=%h, bank2=%h, bank3=%h",
            bank0[7:0], bank1[7:0], bank2[7:0], bank3[7:0]);
        $display("");

        // For iselect=0: operand[k] = bank[(0+k)%4] = bank[k]
        $display("iselect=0 (no rotation):");
        $display("  Expected: op0=AA, op1=BB, op2=CC, op3=DD");
        $display("  Got:      op0=%02h, op1=%02h, op2=%02h, op3=%02h",
            ops_isel0[0*DWIDTH+7:0*DWIDTH], ops_isel0[1*DWIDTH+7:1*DWIDTH],
            ops_isel0[2*DWIDTH+7:2*DWIDTH], ops_isel0[3*DWIDTH+7:3*DWIDTH]);

        // For iselect=1: operand[k] = bank[(1+k)%4]
        $display("iselect=1 (rotate left by 1):");
        $display("  Expected: op0=BB, op1=CC, op2=DD, op3=AA");
        $display("  Got:      op0=%02h, op1=%02h, op2=%02h, op3=%02h",
            ops_isel1[0*DWIDTH+7:0*DWIDTH], ops_isel1[1*DWIDTH+7:1*DWIDTH],
            ops_isel1[2*DWIDTH+7:2*DWIDTH], ops_isel1[3*DWIDTH+7:3*DWIDTH]);

        // For iselect=2: operand[k] = bank[(2+k)%4]
        $display("iselect=2 (rotate left by 2):");
        $display("  Expected: op0=CC, op1=DD, op2=AA, op3=BB");
        $display("  Got:      op0=%02h, op1=%02h, op2=%02h, op3=%02h",
            ops_isel2[0*DWIDTH+7:0*DWIDTH], ops_isel2[1*DWIDTH+7:1*DWIDTH],
            ops_isel2[2*DWIDTH+7:2*DWIDTH], ops_isel2[3*DWIDTH+7:3*DWIDTH]);

        // For iselect=3: operand[k] = bank[(3+k)%4]
        $display("iselect=3 (rotate left by 3):");
        $display("  Expected: op0=DD, op1=AA, op2=BB, op3=CC");
        $display("  Got:      op0=%02h, op1=%02h, op2=%02h, op3=%02h",
            ops_isel3[0*DWIDTH+7:0*DWIDTH], ops_isel3[1*DWIDTH+7:1*DWIDTH],
            ops_isel3[2*DWIDTH+7:2*DWIDTH], ops_isel3[3*DWIDTH+7:3*DWIDTH]);

        #1;
        $finish;
    end
endmodule
