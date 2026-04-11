// Debug test to trace actual output values during simulation
`timescale 1ns/1ps

module tb_simple_spy;
    localparam B     = 16;
    localparam N     = 256;
    localparam R     = 4;
    localparam WWIDTH = B + 1;

    reg             clk, rst, start;
    reg [WWIDTH-1:0] data_in_a = 0, data_in_b = 0;
    wire [WWIDTH-1:0] data_out;
    wire              done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out (data_out),
        .done     (done)
    );

    initial clk = 0;
    always  #5 clk = ~clk;
    
    reg [WWIDTH-1:0] output_values [0:255];
    reg output_phase_active = 0;
    integer output_count = 0;
    
    always @(posedge clk) begin
        if (dut.u_ctrl.fsm_state == 3'd6) begin  // OUTPUT state
            output_phase_active = 1;
            if (output_count < N) begin
                output_values[output_count] = data_out;
                $display("OUTPUT[%3d] = %5h (state=%d)", output_count, data_out, dut.u_ctrl.fsm_state);
                output_count = output_count + 1;
            end
        end else if (output_phase_active && dut.u_ctrl.fsm_state != 3'd6) begin
            output_phase_active = 0;
            $display("=== Exited OUTPUT phase after %d cycles ===", output_count);
        end
    end

    initial begin
        rst = 1; start = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        #10;
        start = 1;
        #10;
        start = 0;

        repeat(200000) @(posedge clk);
        
        $display("=== Final Results ===");
        $display("Read %d output values", output_count);
        $display("First 10 outputs:");
        for (integer i = 0; i < 10 && i < output_count; i = i + 1) begin
            $display("  [%3d] = %5h", i, output_values[i]);
        end
        
        $finish;
    end
endmodule
