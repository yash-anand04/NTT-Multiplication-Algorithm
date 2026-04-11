// Debug trace: monitor what gets computed and written to memory
`timescale 1ns/1ps

module tb_d1_debug;
    localparam N = 256;
    localparam R = 4;
    localparam B = 16;
    localparam WWIDTH = 2*(B+1);

    reg clk, rst_n;
    ntt_top #(.N(N), .R(R), .B(B)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in_a(32'h0),
        .data_in_b(32'h0),
        .data_out(),
        .done(),
        .bfly_result_out()
    );

    initial begin
        clk = 0;
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;

        // Let FSM run through to done
        repeat (30000) @(posedge clk);

        // At end, dump some signals
        $display("FSM state: %d", dut.fsm_state);
        $display("done signal: %b", dut.done);
        $display("Load addr[0]: %h", dut.load_addr[0]);
        $display("Memory bank 0 entry 0: %h", dut.mem_banks_inst.mem0.mem[0]);

        #10;
        $finish;
    end

    always #5 clk = ~clk;
endmodule
