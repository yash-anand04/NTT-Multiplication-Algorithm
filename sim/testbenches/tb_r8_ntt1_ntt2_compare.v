`timescale 1ns/1ps
module tb_r8_ntt1_ntt2_compare;
    localparam B=16; localparam N=256; localparam R=8; localparam LOGN=8; localparam LOGR=3; localparam W=B+1; localparam D=2*W; localparam AW=LOGN-LOGR;
    reg clk,rst,start;
    reg [W-1:0] data_in_a,data_in_b;
    wire [W-1:0] data_out;
    wire done;
    reg [W-1:0] input_v [0:N-1];
    integer i;
    ntt_top #(.B(B),.N(N),.R(R)) dut(.clk(clk),.rst(rst),.start(start),.data_in_a(data_in_a),.data_in_b(data_in_b),.data_out(data_out),.done(done));
    initial clk=0; always #5 clk=~clk;

    function [LOGR-1:0] bank_index;
        input [LOGN-1:0] idx;
        reg [LOGR+3:0] acc;
        begin
            acc = idx[2:0] + idx[5:3] + {1'b0, idx[7:6]};
            bank_index = acc[LOGR-1:0];
        end
    endfunction

    function [D-1:0] read_word;
        input [LOGN-1:0] idx;
        reg [LOGR-1:0] b;
        reg [AW-1:0] a;
        begin
            b = bank_index(idx);
            a = idx[LOGN-1:LOGR];
            case (b)
                0: read_word = dut.u_membanks.gen_banks[0].mem[a];
                1: read_word = dut.u_membanks.gen_banks[1].mem[a];
                2: read_word = dut.u_membanks.gen_banks[2].mem[a];
                3: read_word = dut.u_membanks.gen_banks[3].mem[a];
                4: read_word = dut.u_membanks.gen_banks[4].mem[a];
                5: read_word = dut.u_membanks.gen_banks[5].mem[a];
                6: read_word = dut.u_membanks.gen_banks[6].mem[a];
                default: read_word = dut.u_membanks.gen_banks[7].mem[a];
            endcase
        end
    endfunction

    integer mism;
    reg [D-1:0] w;
    initial begin
        for (i=0;i<N;i=i+1) input_v[i] = (i*123 + 77) % 65537;
        rst=1; start=0; data_in_a=0; data_in_b=0;
        repeat(4) @(posedge clk); @(negedge clk); rst=0;
        @(negedge clk); data_in_a=input_v[0]; data_in_b=input_v[0]; start=1;
        @(negedge clk); start=0; @(negedge clk);
        for (i=1;i<N;i=i+1) begin data_in_a=input_v[i]; data_in_b=input_v[i]; @(negedge clk); end
        data_in_a=0; data_in_b=0;

        wait (dut.u_ctrl.fsm_state == 3'd4); // entered PWM => NTT1+NTT2 done
        #1;
        mism = 0;
        for (i=0;i<N;i=i+1) begin
            w = read_word(i[LOGN-1:0]);
            if (w[W-1:0] !== w[D-1:W]) mism = mism + 1;
        end
        $display("R8_NTT1_NTT2_COMPARE_MISM=%0d", mism);
        $finish;
    end
endmodule
