// Simple mem_banks test
`timescale 1ns/1ps

module tb_banks_only;
    localparam B = 16;
    localparam N = 256;
    localparam R = 4;
    localparam DEPTH = N/R;
    localparam DWIDTH = 2*(B+1);
    localparam AWIDTH = $clog2(DEPTH);

    reg clk;
    reg [R-1:0] we;
    reg [R*AWIDTH-1:0] waddr, raddr;
    reg [R*DWIDTH-1:0] din;
    wire [R*DWIDTH-1:0] dout;

    mem_banks #(.B(B), .N(N), .R(R), .DEPTH(DEPTH), .DWIDTH(DWIDTH), .AWIDTH(AWIDTH))
    u_mem (.clk(clk), .bank_we(we), .bank_waddr(waddr), .bank_raddr(raddr), 
            .bank_din(din), .bank_dout(dout));

    initial clk=0;
    always #5 clk=~clk;

    initial begin
        $dumpfile("bin/tb_banks.vcd");
        $dumpvars(0, tb_banks_only);

        // Write test data into banks
        // Bank 0, addr 0: 0x000050001  (upper=0x0000, lower=0x00001)
        // Bank 1, addr 0: 0x000070003
        // Bank 2, addr 0: 0x000090005
        // Bank 3, addr 0: 0x0000B0007

        we = 4'b1111;  // enable all banks
        waddr = 24'h000000;  // all write to address 0
        din = 128'h0000B00070005000300010000;  // packed: B3=0x0000B, B3_low=0x0007, B2_high=x0000, B2_low=0x0005, etc
        @(posedge clk);
        $display("Wrote: we=%b waddr=%h din=%h", we, waddr, din);

        // Now read back
        raddr = 24'h000000;
        @(posedge clk);
        @(posedge clk);
        $display("Read bank outputs (after 1 cycle latency): dout=%h", dout);
        $display("  Bank0 lower=%h", dout[16:0]);
        $display("  Bank1 lower=%h", dout[16+34:17]);
        $display("  Bank2 lower=%h", dout[16+68:17+34]);
        $display("  Bank3 lower=%h", dout[16+102:17+68]);

        #100;
        $finish;
    end
endmodule
