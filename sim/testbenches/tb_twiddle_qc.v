// =============================================================================
// tb_twiddle_qc.v
// Verify rom_qcompressed mode produces identical output to rom_full mode for
// all 2N twiddle indices.
// =============================================================================
`timescale 1ns/1ps

module tb_twiddle_qc;

    localparam integer B    = 16;
    localparam integer LOGN = 10;
    localparam integer N2   = 1 << (LOGN + 1);
    localparam integer WW   = B + 1;
    localparam integer Q    = (1 << B) + 1;

    reg               clk = 0;
    reg  [LOGN:0]     idx = 0;
    wire [WW-1:0]     tw_full;
    wire [WW-1:0]     tw_qc;

    twiddle_gen #(.B(B), .LOGN(LOGN), .REGISTERED(0), .MODE("rom_full")) u_full (
        .clk(clk), .idx(idx), .tw_out(tw_full));
    twiddle_gen #(.B(B), .LOGN(LOGN), .REGISTERED(0), .MODE("rom_qcompressed")) u_qc (
        .clk(clk), .idx(idx), .tw_out(tw_qc));

    integer i, errors = 0;
    initial begin
        for (i = 0; i < N2; i = i + 1) begin
            idx = i[LOGN:0];
            #1;
            if (tw_qc !== tw_full) begin
                if (errors < 16)
                    $display("MISMATCH idx=%0d  qc=%0d  full=%0d  diff=%0d",
                        i, tw_qc, tw_full,
                        (tw_qc > tw_full) ? (tw_qc - tw_full) : (tw_full - tw_qc));
                errors = errors + 1;
            end
        end
        $display("Total mismatches: %0d / %0d", errors, N2);
        if (errors == 0) $display("PASS");
        else $display("FAIL");
        $finish;
    end
endmodule
