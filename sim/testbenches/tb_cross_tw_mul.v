// =============================================================================
// tb_cross_tw_mul.v
// Self-checking testbench for cross_tw_mul (Phase B.2).
//
// Generates two parallel DUT instances:
//   dut_mm  : LEVEL_BOUNDARY = 0  (generic ModMul)
//   dut_sf  : LEVEL_BOUNDARY = 1  (sign-flip)
//
// For each random input vector we drive both DUTs and shift a software
// reference through a 3-cycle expected pipeline.  Compare on valid_out.
// =============================================================================

`timescale 1ns/1ps

module tb_cross_tw_mul;

    localparam integer B      = 16;
    localparam integer WWIDTH = B + 1;
    localparam integer LANES  = 32;
    localparam integer Q      = (1 << B) + 1;
    localparam integer NUM_VECS = 128;

    reg                         clk = 0;
    reg                         rst = 1;
    reg                         valid_in = 0;
    reg  [LANES*WWIDTH-1:0]     data_in   = 0;
    reg  [LANES*WWIDTH-1:0]     tw_in     = 0;
    reg  [LANES-1:0]            sign_flip = 0;

    wire [LANES*WWIDTH-1:0]     out_mm;
    wire                        v_mm;
    wire [LANES*WWIDTH-1:0]     out_sf;
    wire                        v_sf;

    cross_tw_mul #(.B(B), .LANES(LANES), .LEVEL_BOUNDARY(0)) dut_mm (
        .clk          (clk),
        .rst          (rst),
        .valid_in     (valid_in),
        .data_in      (data_in),
        .tw_in        (tw_in),
        .sign_flip_in (sign_flip),
        .data_out     (out_mm),
        .valid_out    (v_mm)
    );

    cross_tw_mul #(.B(B), .LANES(LANES), .LEVEL_BOUNDARY(1)) dut_sf (
        .clk          (clk),
        .rst          (rst),
        .valid_in     (valid_in),
        .data_in      (data_in),
        .tw_in        (tw_in),
        .sign_flip_in (sign_flip),
        .data_out     (out_sf),
        .valid_out    (v_sf)
    );

    always #5 clk = ~clk;

    // Reference combinational (function-based) for both modes
    function [WWIDTH-1:0] mm_ref;
        input [WWIDTH-1:0] a;
        input [WWIDTH-1:0] b;
        reg [2*WWIDTH-1:0] p;
        begin
            p = a * b;
            mm_ref = p % Q;
        end
    endfunction

    function [WWIDTH-1:0] sf_ref;
        input [WWIDTH-1:0] d;
        input              s;
        begin
            if (!s)            sf_ref = d % Q;
            else if (d == 0)   sf_ref = 0;
            else               sf_ref = Q - d;
        end
    endfunction

    // Expected pipelines (3 stages = pipeline latency)
    reg [LANES*WWIDTH-1:0] exp_mm [0:3];
    reg [LANES*WWIDTH-1:0] exp_sf [0:3];
    reg                    exp_v  [0:3];

    reg [LANES*WWIDTH-1:0] exp_mm_now;
    reg [LANES*WWIDTH-1:0] exp_sf_now;
    integer lane;

    always @* begin
        exp_mm_now = 0;
        exp_sf_now = 0;
        for (lane = 0; lane < LANES; lane = lane + 1) begin
            exp_mm_now[lane*WWIDTH +: WWIDTH] = mm_ref(
                data_in[lane*WWIDTH +: WWIDTH] % Q,
                tw_in  [lane*WWIDTH +: WWIDTH] % Q);
            exp_sf_now[lane*WWIDTH +: WWIDTH] = sf_ref(
                data_in[lane*WWIDTH +: WWIDTH] % Q,
                sign_flip[lane]);
        end
    end

    integer pi;
    always @(posedge clk) begin
        if (rst) begin
            for (pi = 0; pi <= 3; pi = pi + 1) begin
                exp_mm[pi] <= 0;
                exp_sf[pi] <= 0;
                exp_v [pi] <= 0;
            end
        end else begin
            exp_mm[0] <= exp_mm_now;
            exp_sf[0] <= exp_sf_now;
            exp_v [0] <= valid_in;
            for (pi = 1; pi <= 3; pi = pi + 1) begin
                exp_mm[pi] <= exp_mm[pi - 1];
                exp_sf[pi] <= exp_sf[pi - 1];
                exp_v [pi] <= exp_v [pi - 1];
            end
        end
    end

    integer errors_mm = 0, errors_sf = 0, checks = 0;
    integer chk_lane;

    always @(posedge clk) begin
        if (!rst && v_mm) begin
            if (out_mm !== exp_mm[2]) begin
                errors_mm = errors_mm + 1;
                $display("[MM FAIL] @%0t  out=%h  exp=%h", $time, out_mm, exp_mm[2]);
                for (chk_lane = 0; chk_lane < LANES; chk_lane = chk_lane + 1)
                    if (out_mm[chk_lane*WWIDTH +: WWIDTH] !== exp_mm[2][chk_lane*WWIDTH +: WWIDTH])
                        $display("        lane %0d: got=%0d  exp=%0d",
                            chk_lane,
                            out_mm[chk_lane*WWIDTH +: WWIDTH],
                            exp_mm[2][chk_lane*WWIDTH +: WWIDTH]);
            end
            if (out_sf !== exp_sf[2]) begin
                errors_sf = errors_sf + 1;
                $display("[SF FAIL] @%0t  out=%h  exp=%h", $time, out_sf, exp_sf[2]);
                for (chk_lane = 0; chk_lane < LANES; chk_lane = chk_lane + 1)
                    if (out_sf[chk_lane*WWIDTH +: WWIDTH] !== exp_sf[2][chk_lane*WWIDTH +: WWIDTH])
                        $display("        lane %0d: got=%0d  exp=%0d  sf=%b",
                            chk_lane,
                            out_sf[chk_lane*WWIDTH +: WWIDTH],
                            exp_sf[2][chk_lane*WWIDTH +: WWIDTH],
                            sign_flip[chk_lane]);
            end
            checks = checks + 1;
        end
    end

    integer seed = 32'hBADA_55ED;
    function [WWIDTH-1:0] rand_coef;
        input integer dummy;
        begin
            rand_coef = $unsigned($random(seed)) % Q;
        end
    endfunction

    task drive;
        input [LANES*WWIDTH-1:0] d;
        input [LANES*WWIDTH-1:0] t;
        input [LANES-1:0]        s;
        begin
            @(negedge clk);
            data_in   = d;
            tw_in     = t;
            sign_flip = s;
            valid_in  = 1;
        end
    endtask

    task idle;
        begin
            @(negedge clk);
            data_in   = 0;
            tw_in     = 0;
            sign_flip = 0;
            valid_in  = 0;
        end
    endtask

    integer t, k;
    reg [LANES*WWIDTH-1:0] tv_d, tv_t;
    reg [LANES-1:0]        tv_s;

    initial begin
        rst = 1;
        repeat (4) @(posedge clk);
        rst = 0;
        idle;

        $display("[Driving %0d random vectors back-to-back]", NUM_VECS);
        for (t = 0; t < NUM_VECS; t = t + 1) begin
            for (k = 0; k < LANES; k = k + 1) begin
                tv_d[k*WWIDTH +: WWIDTH] = rand_coef(0);
                tv_t[k*WWIDTH +: WWIDTH] = rand_coef(0);
                tv_s[k] = $random(seed) & 1;
            end
            drive(tv_d, tv_t, tv_s);
        end
        repeat (8) idle;

        $display("=========================================");
        $display("checks=%0d  errors_mm=%0d  errors_sf=%0d",
                  checks, errors_mm, errors_sf);
        if (errors_mm == 0 && errors_sf == 0) $display("PASS");
        else                                   $display("FAIL");
        $display("=========================================");
        $finish;
    end

    initial begin
        #50000;
        $display("WATCHDOG: simulation took too long");
        $finish;
    end

endmodule
