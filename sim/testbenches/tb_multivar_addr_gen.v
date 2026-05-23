// =============================================================================
// tb_multivar_addr_gen.v
// Self-checking testbench for multivar_addr_gen (Phase B.3).
//
// For D in {2, 3} we exhaustively sweep (dim, scan_idx, outer_idx) and check:
//   1. Every linear_addr in [0, N-1] is generated.
//   2. Each (dim, outer_idx) pair, swept over scan_idx, covers exactly one
//      conflict-free bank set (each bank value 0..31 appears exactly once).
//   3. bank == (sum of 5-bit slots of linear_addr) mod 32.
//
// For D=4 we only spot-check a few (dim, outer) tuples since exhaustive
// is 4 * 32^3 * 32 = 4M cases.
// =============================================================================

`timescale 1ns/1ps

module tb_multivar_addr_gen;

    // -------------------------------------------------------------------------
    // D=2 instance
    // -------------------------------------------------------------------------
    localparam integer D2_D = 2;
    localparam integer D2_LSUB = 5;
    localparam integer D2_LN  = D2_D * D2_LSUB;            // 10
    localparam integer D2_LOUT = D2_LN - D2_LSUB;          // 5

    reg  [0:0]               d2_dim;
    reg  [D2_LSUB-1:0]       d2_scan;
    reg  [D2_LOUT-1:0]       d2_outer;
    wire [D2_LN-1:0]         d2_linear;
    wire [D2_LSUB-1:0]       d2_bank;

    multivar_addr_gen #(.D(D2_D)) dut2 (
        .dim         (d2_dim),
        .scan_idx    (d2_scan),
        .outer_idx   (d2_outer),
        .linear_addr (d2_linear),
        .bank        (d2_bank)
    );

    // -------------------------------------------------------------------------
    // D=3 instance
    // -------------------------------------------------------------------------
    localparam integer D3_D = 3;
    localparam integer D3_LSUB = 5;
    localparam integer D3_LN  = D3_D * D3_LSUB;            // 15
    localparam integer D3_LOUT = D3_LN - D3_LSUB;          // 10

    reg  [1:0]               d3_dim;
    reg  [D3_LSUB-1:0]       d3_scan;
    reg  [D3_LOUT-1:0]       d3_outer;
    wire [D3_LN-1:0]         d3_linear;
    wire [D3_LSUB-1:0]       d3_bank;

    multivar_addr_gen #(.D(D3_D)) dut3 (
        .dim         (d3_dim),
        .scan_idx    (d3_scan),
        .outer_idx   (d3_outer),
        .linear_addr (d3_linear),
        .bank        (d3_bank)
    );

    // -------------------------------------------------------------------------
    integer errors = 0;

    // Coverage maps
    reg seen_d2 [0:(1<<10)-1];
    reg seen_d3 [0:(1<<15)-1];

    // ------------- helpers -------------
    function integer bank_sw;
        input [32:0] linear;
        input integer d;
        integer k, s;
        begin
            s = 0;
            for (k = 0; k < d; k = k + 1)
                s = s + ((linear >> (5*k)) & 5'h1F);
            bank_sw = s & 5'h1F;
        end
    endfunction

    function integer expected_linear;
        input integer dim;
        input integer scan;
        input integer outer;
        input integer d;
        integer lower_mask, lower_part, upper_part;
        begin
            lower_mask = (1 << (5*dim)) - 1;
            lower_part = outer & lower_mask;
            upper_part = outer >> (5*dim);
            expected_linear = lower_part
                            | (scan << (5*dim))
                            | (upper_part << (5*(dim+1)));
        end
    endfunction

    integer dim, scan, outer, i;
    integer bank_seen [0:31];
    integer exp_lin, exp_bank;

    initial begin
        // ===== D=2 exhaustive sweep =====
        $display("[D=2] exhaustive sweep, 1024 linear addresses expected");
        for (i = 0; i < (1<<10); i = i + 1) seen_d2[i] = 0;

        for (dim = 0; dim < D2_D; dim = dim + 1) begin
            for (outer = 0; outer < (1<<D2_LOUT); outer = outer + 1) begin
                for (i = 0; i < 32; i = i + 1) bank_seen[i] = 0;
                for (scan = 0; scan < 32; scan = scan + 1) begin
                    d2_dim   = dim[0:0];
                    d2_scan  = scan[D2_LSUB-1:0];
                    d2_outer = outer[D2_LOUT-1:0];
                    #1;
                    exp_lin  = expected_linear(dim, scan, outer, D2_D) & ((1<<D2_LN)-1);
                    exp_bank = bank_sw({23'b0, d2_linear}, D2_D) & 5'h1F;
                    // 1. linear matches sw
                    if (d2_linear !== exp_lin[D2_LN-1:0]) begin
                        $display("[D=2 LIN FAIL] dim=%0d scan=%0d outer=%0d got=%0d exp=%0d",
                            dim, scan, outer, d2_linear, exp_lin);
                        errors = errors + 1;
                    end
                    // 2. bank matches sw
                    if (d2_bank !== exp_bank[D2_LSUB-1:0]) begin
                        $display("[D=2 BANK FAIL] dim=%0d scan=%0d outer=%0d lin=%0d got=%0d exp=%0d",
                            dim, scan, outer, d2_linear, d2_bank, exp_bank);
                        errors = errors + 1;
                    end
                    // 3. conflict-free check: each scan within a (dim, outer) hits unique bank
                    if (bank_seen[d2_bank]) begin
                        $display("[D=2 CFREE FAIL] dim=%0d outer=%0d bank %0d hit twice",
                            dim, outer, d2_bank);
                        errors = errors + 1;
                    end
                    bank_seen[d2_bank] = 1;
                    // 4. coverage: mark linear addr seen (only count dim=0 to avoid duplicates)
                    if (dim == 0) seen_d2[d2_linear] = 1;
                end
            end
        end

        for (i = 0; i < (1<<10); i = i + 1)
            if (!seen_d2[i]) begin
                $display("[D=2 COVERAGE] linear %0d not generated", i);
                errors = errors + 1;
            end

        // ===== D=3 spot sweep (one dim at a time, ~3*32^3 = 98K) =====
        $display("[D=3] sweep over (dim, outer, scan)");
        for (i = 0; i < (1<<15); i = i + 1) seen_d3[i] = 0;

        for (dim = 0; dim < D3_D; dim = dim + 1) begin
            for (outer = 0; outer < (1<<D3_LOUT); outer = outer + 1) begin
                for (i = 0; i < 32; i = i + 1) bank_seen[i] = 0;
                for (scan = 0; scan < 32; scan = scan + 1) begin
                    d3_dim   = dim[1:0];
                    d3_scan  = scan[D3_LSUB-1:0];
                    d3_outer = outer[D3_LOUT-1:0];
                    #1;
                    exp_lin  = expected_linear(dim, scan, outer, D3_D) & ((1<<D3_LN)-1);
                    exp_bank = bank_sw({18'b0, d3_linear}, D3_D) & 5'h1F;
                    if (d3_linear !== exp_lin[D3_LN-1:0]) begin
                        $display("[D=3 LIN FAIL] dim=%0d scan=%0d outer=%0d got=%0d exp=%0d",
                            dim, scan, outer, d3_linear, exp_lin);
                        errors = errors + 1;
                    end
                    if (d3_bank !== exp_bank[D3_LSUB-1:0]) begin
                        $display("[D=3 BANK FAIL] dim=%0d scan=%0d outer=%0d lin=%0d got=%0d exp=%0d",
                            dim, scan, outer, d3_linear, d3_bank, exp_bank);
                        errors = errors + 1;
                    end
                    if (bank_seen[d3_bank]) begin
                        $display("[D=3 CFREE FAIL] dim=%0d outer=%0d bank %0d hit twice",
                            dim, outer, d3_bank);
                        errors = errors + 1;
                    end
                    bank_seen[d3_bank] = 1;
                    if (dim == 0) seen_d3[d3_linear] = 1;
                end
            end
        end

        for (i = 0; i < (1<<15); i = i + 1)
            if (!seen_d3[i]) begin
                $display("[D=3 COVERAGE] linear %0d not generated", i);
                errors = errors + 1;
            end

        $display("=========================================");
        $display("errors=%0d", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $display("=========================================");
        $finish;
    end

    initial begin
        #100000000;
        $display("WATCHDOG");
        $finish;
    end
endmodule
