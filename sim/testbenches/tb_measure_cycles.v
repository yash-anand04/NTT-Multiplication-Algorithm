// =============================================================================
// tb_measure_cycles.v
// Cycle-count measurement testbench for Table IV metrics extraction.
//
// Measures three cycle counts per radix:
//   TOTAL_CYCLES  : from start assertion to done assertion (full latency)
//   COMPUTE_CYCLES: from end of LOAD to start of OUTPUT (pure compute)
//   OUTPUT_CYCLES : cycles spent in OUTPUT state (= N, sanity check)
//
// FSM state encoding (from ctrl_unit.v):
//   0=IDLE, 1=LOAD, 2=NTT1, 3=NTT2, 4=PWM, 5=INTT, 6=OUTPUT, 7=DONE
// =============================================================================
`timescale 1ns/1ps

`ifndef R_VAL
`define R_VAL 4
`endif

`ifndef N_VAL
`define N_VAL 256
`endif

module tb_measure_cycles;
    localparam B      = 16;
    localparam N      = `N_VAL;
    localparam R      = `R_VAL;
    localparam WWIDTH = B + 1;
    localparam Q      = (1 << B) + 1;

    reg clk, rst, start;
    reg  [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire done;

    // Grab FSM state directly from DUT hierarchy
    wire [2:0] fsm_state = dut.u_ctrl.fsm_state;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .done(done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz reference clock

    // ---- Counters ------------------------------------------------------------
    integer total_cycles;    // start assertion → done assertion
    integer compute_cycles;  // end-of-LOAD → start-of-OUTPUT
    integer load_cycles;     // cycles spent in LOAD
    integer ntt1_cycles;     // cycles spent in NTT1
    integer ntt2_cycles;     // cycles spent in NTT2
    integer pwm_cycles;      // cycles spent in PWM
    integer intt_cycles;     // cycles spent in INTT
    integer output_cycles;   // cycles spent in OUTPUT

    integer counting_total;
    integer counting_compute;

    // Track state transitions with a small delay so registered state is visible
    reg [2:0] prev_state;

    // ---- Stimulus ------------------------------------------------------------
    integer i;
    reg [WWIDTH-1:0] dummy_a, dummy_b;

    initial begin
        // Initialise everything
        clk = 0; rst = 1; start = 0;
        data_in_a = 0; data_in_b = 0;
        total_cycles   = 0;
        compute_cycles = 0;
        load_cycles    = 0;
        ntt1_cycles    = 0;
        ntt2_cycles    = 0;
        pwm_cycles     = 0;
        intt_cycles    = 0;
        output_cycles  = 0;
        counting_total   = 0;
        counting_compute = 0;
        prev_state = 3'd0;

        // Hold reset for 4 cycles, then release
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Present coeff[0] one negedge before asserting start (matches tb_ntt_capture protocol)
        @(negedge clk);
        data_in_a = $urandom % Q;
        data_in_b = $urandom % Q;
        start     = 1'b1;

        // ---- Start counting total latency here ----
        @(posedge clk);   // latch the start into LOAD transition
        counting_total = 1;

        @(negedge clk);
        start = 1'b0;
        @(negedge clk);

        // Stream remaining N-1 coefficients
        for (i = 1; i < N; i = i + 1) begin
            data_in_a = $urandom % Q;
            data_in_b = $urandom % Q;
            @(negedge clk);
        end
        data_in_a = 0;
        data_in_b = 0;

        // Wait for done, counting ends when done asserts
        while (!done) @(posedge clk);

        // Final report
        $display("METRIC_RADIX         R=%0d", R);
        $display("METRIC_TOTAL_CYCLES  %0d", total_cycles);
        $display("METRIC_LOAD_CYCLES   %0d", load_cycles);
        $display("METRIC_NTT1_CYCLES   %0d", ntt1_cycles);
        $display("METRIC_NTT2_CYCLES   %0d", ntt2_cycles);
        $display("METRIC_PWM_CYCLES    %0d", pwm_cycles);
        $display("METRIC_INTT_CYCLES   %0d", intt_cycles);
        $display("METRIC_OUTPUT_CYCLES %0d", output_cycles);
        $display("METRIC_COMPUTE_CYCLES %0d", ntt1_cycles + ntt2_cycles + pwm_cycles + intt_cycles);

        repeat (4) @(posedge clk);
        $finish;
    end

    // ---- Cycle counting (per-state) at every posedge -------------------------
    always @(posedge clk) begin
        if (counting_total)
            total_cycles <= total_cycles + 1;

        case (fsm_state)
            3'd1: load_cycles    <= load_cycles   + 1;
            3'd2: ntt1_cycles    <= ntt1_cycles   + 1;
            3'd3: ntt2_cycles    <= ntt2_cycles   + 1;
            3'd4: pwm_cycles     <= pwm_cycles    + 1;
            3'd5: intt_cycles    <= intt_cycles   + 1;
            3'd6: output_cycles  <= output_cycles + 1;
            default: ;
        endcase

        // Stop total count when done fires (we are in DONE state)
        if (done && counting_total)
            counting_total <= 0;

        prev_state <= fsm_state;
    end

endmodule
