// =============================================================================
// tb_twiddle_gen.v
// Self-checking testbench for twiddle_gen (Phase B.4).
//
// Verifies that the ROM contents satisfy:
//   psi^0 == 1
//   psi^(2N) == 1                  (psi is a 2N-th root of unity)
//   psi^N == q - 1                 (so psi^N = -1)
//   psi^k * psi^(2N-k) == 1 (mod q) for all k
//   rom[k] * rom[1] mod q == rom[k+1]
// =============================================================================

`timescale 1ns/1ps

module tb_twiddle_gen;

    localparam integer B      = 16;
    localparam integer LOGN   = 10;
    localparam integer N      = 1 << LOGN;
    localparam integer N2     = 1 << (LOGN + 1);
    localparam integer WWIDTH = B + 1;
    localparam integer Q      = (1 << B) + 1;

    reg               clk = 0;
    reg  [LOGN:0]     idx = 0;
    wire [WWIDTH-1:0] tw_out;

    twiddle_gen #(.B(B), .LOGN(LOGN)) dut (
        .clk    (clk),
        .idx    (idx),
        .tw_out (tw_out)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer k;
    reg [WWIDTH-1:0] table_local [0:(1<<(LOGN+1))-1];   // sw mirror, 2N deep
    longint          mproduct;

    function longint mmul;
        input [WWIDTH-1:0] a;
        input [WWIDTH-1:0] b;
        longint la, lb;
        begin
            la = a;
            lb = b;
            mmul = (la * lb) % Q;
        end
    endfunction

    task read_idx;
        input integer ix;
        begin
            @(negedge clk);
            idx = ix[LOGN:0];
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        // Build local software-mirror of the table
        table_local[0] = 1;
        // First, sweep the DUT to collect rom[k] values
        for (k = 0; k < N2; k = k + 1) begin
            read_idx(k);
            table_local[k] = tw_out;
        end

        // --------- Property checks ----------
        if (table_local[0] !== 1) begin
            $display("FAIL: psi^0 = %0d, expected 1", table_local[0]);
            errors = errors + 1;
        end
        if (table_local[N] !== (Q - 1)) begin
            $display("FAIL: psi^N = %0d, expected q-1 = %0d", table_local[N], Q-1);
            errors = errors + 1;
        end
        // psi^(2N) by extension would index 2N which is out of range;
        // verify via psi^(N) * psi^(N) == 1.
        if (mmul(table_local[N], table_local[N]) !== 1) begin
            $display("FAIL: psi^(2N) != 1");
            errors = errors + 1;
        end

        // Check recurrence rom[k+1] = rom[k]*psi mod q, for psi = rom[1]
        for (k = 0; k < N2 - 1; k = k + 1) begin
            if (mmul(table_local[k], table_local[1]) !== table_local[k+1]) begin
                $display("FAIL: recurrence at k=%0d: rom[k]*psi=%0d  rom[k+1]=%0d",
                    k, mmul(table_local[k], table_local[1]), table_local[k+1]);
                errors = errors + 1;
                if (errors > 8) k = N2;
            end
        end

        // psi^k * psi^(2N-k) == 1
        for (k = 1; k < N2; k = k + 1) begin
            if (mmul(table_local[k], table_local[N2 - k]) !== 1) begin
                $display("FAIL: inverse at k=%0d: %0d * %0d mod q = %0d (!=1)",
                    k, table_local[k], table_local[N2-k],
                    mmul(table_local[k], table_local[N2-k]));
                errors = errors + 1;
                if (errors > 16) k = N2;
            end
        end

        // psi^(N+k) == -psi^k  (== q - psi^k)
        for (k = 0; k < N; k = k + 1) begin
            if (table_local[N + k] !== ((Q - table_local[k]) % Q)) begin
                $display("FAIL: neg-half at k=%0d: psi^(N+k)=%0d  -psi^k=%0d",
                    k, table_local[N + k], (Q - table_local[k]) % Q);
                errors = errors + 1;
                if (errors > 16) k = N;
            end
        end

        $display("=========================================");
        $display("errors=%0d", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $display("=========================================");
        $finish;
    end

    initial begin
        #5000000;
        $display("WATCHDOG");
        $finish;
    end
endmodule
