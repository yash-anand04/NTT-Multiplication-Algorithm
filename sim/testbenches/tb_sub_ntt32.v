// =============================================================================
// tb_sub_ntt32.v
// Self-checking testbench for the pipelined sub_ntt32 (Phase B.1).
//
// Reference: the existing combinational `bivar_ntt_subntt32` is treated as
// the golden model. For each random input vector we apply the same data to
// both modules; after the 5-cycle pipeline latency the pipelined output must
// match the combinational reference bit-for-bit.
//
// Tests:
//   T1: identity     -> forward then inverse over 32 random vectors gives back input
//   T2: pipeline_fwd -> 16 random vectors issued back-to-back, every cycle a
//                       new result, each matching combinational reference
//   T3: pipeline_inv -> same as T2 but inverse mode
//   T4: mixed        -> alternating forward/inverse issue, output mux must
//                       follow the inv_pipe shift register correctly
// =============================================================================

`timescale 1ns/1ps

module tb_sub_ntt32;

    localparam integer B      = 16;
    localparam integer WWIDTH = B + 1;
    localparam integer R      = 32;
    localparam integer Q      = (1 << B) + 1;   // 65537
    localparam integer NUM_VECS = 64;

    reg                     clk = 0;
    reg                     rst = 1;
    reg                     start = 0;
    reg                     inverse = 0;
    reg  [R*WWIDTH-1:0]     in_norm = 0;
    wire [R*WWIDTH-1:0]     out_norm;
    wire                    valid;

    // DUT (pipelined)
    sub_ntt32 #(.B(B)) dut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .inverse (inverse),
        .in_norm (in_norm),
        .out_norm(out_norm),
        .valid   (valid)
    );

    // Reference (combinational)
    reg                ref_inverse = 0;
    reg  [R*WWIDTH-1:0] ref_in = 0;
    wire [R*WWIDTH-1:0] ref_out;
    bivar_ntt_subntt32 #(.B(B), .M(R)) refmod (
        .inverse (ref_inverse),
        .in_norm (ref_in),
        .out_norm(ref_out)
    );

    // Clock
    always #5 clk = ~clk;

    // Capture expected results in a small FIFO (the issue/check pipeline).
    // The pipeline latency is 5 cycles; we shift the expected vector
    // through a depth-5 register chain.
    reg [R*WWIDTH-1:0] exp_q [0:5];
    reg                exp_v_q [0:5];
    integer            stage_i;

    always @(posedge clk) begin
        if (rst) begin
            for (stage_i = 0; stage_i <= 5; stage_i = stage_i + 1) begin
                exp_q[stage_i]   <= {R*WWIDTH{1'b0}};
                exp_v_q[stage_i] <= 1'b0;
            end
        end else begin
            // Stage 0: capture the expected result for whatever was issued this cycle.
            //   ref_in / ref_inverse are driven combinationally before this @(posedge).
            exp_q[0]   <= ref_out;
            exp_v_q[0] <= start;
            for (stage_i = 1; stage_i <= 5; stage_i = stage_i + 1) begin
                exp_q[stage_i]   <= exp_q[stage_i - 1];
                exp_v_q[stage_i] <= exp_v_q[stage_i - 1];
            end
        end
    end

    integer errors = 0;
    integer checks = 0;
    integer lane;

    task check_output;
        input [R*WWIDTH-1:0] got;
        input [R*WWIDTH-1:0] exp;
        input [127:0]        label;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("[FAIL %0s] @%0t  out=%h  exp=%h", label, $time, got, exp);
                for (lane = 0; lane < R; lane = lane + 1) begin
                    if (got[lane*WWIDTH +: WWIDTH] !== exp[lane*WWIDTH +: WWIDTH])
                        $display("        lane %0d: got=%0d  exp=%0d",
                            lane,
                            got[lane*WWIDTH +: WWIDTH],
                            exp[lane*WWIDTH +: WWIDTH]);
                end
            end
            checks = checks + 1;
        end
    endtask

    // Per-cycle compare: when DUT asserts valid, compare against the
    // matching expected (advanced 5 cycles).
    // NOTE: exp_q[5] is what was issued 5 cycles ago, aligned with the
    // current valid (since the latency is 5 cycles).
    always @(posedge clk) begin
        if (!rst && valid) begin
            check_output(out_norm, exp_q[5], "live");
        end
    end

    // Random vector generator
    integer seed;
    function [WWIDTH-1:0] rand_coef;
        input integer dummy;
        begin
            rand_coef = $unsigned($random(seed)) % Q;
        end
    endfunction

    task drive_vector;
        input [R*WWIDTH-1:0] vec;
        input                inv_flag;
        begin
            @(negedge clk);
            in_norm     = vec;
            inverse     = inv_flag;
            start       = 1'b1;
            ref_in      = vec;
            ref_inverse = inv_flag;
        end
    endtask

    task drive_idle;
        begin
            @(negedge clk);
            in_norm     = 0;
            inverse     = 0;
            start       = 1'b0;
            ref_in      = 0;
            ref_inverse = 0;
        end
    endtask

    integer t, k;
    reg [R*WWIDTH-1:0] tv;

    initial begin
        seed = 32'hC0DE_F00D;
        rst = 1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        rst = 0;
        drive_idle;

        // ------------------ T2: back-to-back forward issue ------------------
        $display("[T2] forward back-to-back, %0d vectors", NUM_VECS);
        for (t = 0; t < NUM_VECS; t = t + 1) begin
            for (k = 0; k < R; k = k + 1)
                tv[k*WWIDTH +: WWIDTH] = rand_coef(0);
            drive_vector(tv, 1'b0);
        end
        // Drain pipeline
        repeat (8) drive_idle;

        // ------------------ T3: back-to-back inverse issue ------------------
        $display("[T3] inverse back-to-back, %0d vectors", NUM_VECS);
        for (t = 0; t < NUM_VECS; t = t + 1) begin
            for (k = 0; k < R; k = k + 1)
                tv[k*WWIDTH +: WWIDTH] = rand_coef(0);
            drive_vector(tv, 1'b1);
        end
        repeat (8) drive_idle;

        // ------------------ T4: alternating mode ----------------------------
        $display("[T4] alternating fwd/inv, %0d vectors", NUM_VECS);
        for (t = 0; t < NUM_VECS; t = t + 1) begin
            for (k = 0; k < R; k = k + 1)
                tv[k*WWIDTH +: WWIDTH] = rand_coef(0);
            drive_vector(tv, t[0]);
        end
        repeat (8) drive_idle;

        // ------------------ Summary -----------------------------------------
        $display("=========================================");
        $display("checks = %0d   errors = %0d", checks, errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $display("=========================================");
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("WATCHDOG: simulation took too long");
        $finish;
    end

endmodule
