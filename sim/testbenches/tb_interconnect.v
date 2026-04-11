// Test interconnect circular routing
`timescale 1ns/1ps

module tb_interconnect;
    localparam R = 4;
    localparam DWIDTH = 34;
    localparam AWIDTH = 6;

    // Test data: unique values for each bank
    wire [R*DWIDTH-1:0] bank_data = {
        34'h3_10001111,  // bank 3
        34'h3_10001110,  // bank 2
        34'h3_10001101,  // bank 1
        34'h3_10001100   // bank 0
    };

    wire [DWIDTH-1:0] test_ops [0:3];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin
            assign test_ops[i] = bank_data[i*DWIDTH +: DWIDTH];
        end
    endgenerate

    // Test interconnect_bank_out with different iselect values
    wire [R*DWIDTH-1:0] operands_out_isel0, operands_out_isel1, operands_out_isel2, operands_out_isel3;

    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_iout_0 (
        .bank_data_out(bank_data),
        .iselect(2'h0),
        .operands_out(operands_out_isel0)
    );

    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_iout_1 (
        .bank_data_out(bank_data),
        .iselect(2'h1),
        .operands_out(operands_out_isel1)
    );

    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_iout_2 (
        .bank_data_out(bank_data),
        .iselect(2'h2),
        .operands_out(operands_out_isel2)
    );

    interconnect_bank_out #(.DWIDTH(DWIDTH), .R(R)) u_iout_3 (
        .bank_data_out(bank_data),
        .iselect(2'h3),
        .operands_out(operands_out_isel3)
    );

    // Test interconnect_bank_in (routing computed results back to banks)
    wire [R*DWIDTH-1:0] computed = {
        34'h3_AAAAAAAA,  // result 3
        34'h2_99999999,  // result 2
        34'h1_88888888,  // result 1
        34'h0_77777777   // result 0
    };

    wire [R*DWIDTH-1:0] bank_in_isel0, bank_in_isel1, bank_in_isel2, bank_in_isel3;

    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R)) u_iin_0 (
        .operands_in(computed),
        .iselect(2'h0),
        .bank_data_in(bank_in_isel0)
    );

    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R)) u_iin_1 (
        .operands_in(computed),
        .iselect(2'h1),
        .bank_data_in(bank_in_isel1)
    );

    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R)) u_iin_2 (
        .operands_in(computed),
        .iselect(2'h2),
        .bank_data_in(bank_in_isel2)
    );

    interconnect_bank_in #(.DWIDTH(DWIDTH), .R(R)) u_iin_3 (
        .operands_in(computed),
        .iselect(2'h3),
        .bank_data_in(bank_in_isel3)
    );

    initial begin
        #1;
        $display("=== Interconnect Bank Out (data from banks to operands) ===");
        $display("Input bank_data: [bank0=%h, bank1=%h, bank2=%h, bank3=%h]",
            test_ops[0], test_ops[1], test_ops[2], test_ops[3]);

        $display("iselect=0: operands should be [0,1,2,3] banks: %h", operands_out_isel0);
        $display("iselect=1: operands should be [1,2,3,0] banks: %h", operands_out_isel1);
        $display("iselect=2: operands should be [2,3,0,1] banks: %h", operands_out_isel2);
        $display("iselect=3: operands should be [3,0,1,2] banks: %h", operands_out_isel3);

        #1;
        $display("");
        $display("=== Interconnect Bank In (results back to banks) ===");
        $display("Input computed: [res0=%h, res1=%h, res2=%h, res3=%h]",
            computed[0*DWIDTH +: DWIDTH], computed[1*DWIDTH +: DWIDTH],
            computed[2*DWIDTH +: DWIDTH], computed[3*DWIDTH +: DWIDTH]);

        $display("iselect=0: bank_in should be [0,1,2,3]: %h", bank_in_isel0);
        $display("iselect=1: bank_in should be [3,0,1,2]: %h", bank_in_isel1);
        $display("iselect=2: bank_in should be [2,3,0,1]: %h", bank_in_isel2);
        $display("iselect=3: bank_in should be [1,2,3,0]: %h", bank_in_isel3);

        #10;
        $finish;
    end
endmodule
