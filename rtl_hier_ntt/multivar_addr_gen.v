// =============================================================================
// multivar_addr_gen.v   (Phase B.3)
// d-level multivariate linear-address generator with conflict-free banking.
//
// For a d-level hierarchical NTT with N = 32^d, each coefficient has a
// multi-index (i_0, i_1, ..., i_{d-1}), each i_k in [0, 31].  The flat
// row-major linear address is:
//
//     linear_addr = i_0  |  (i_1<<5)  |  (i_2<<10)  |  ...  |  (i_{d-1}<<5(d-1))
//
// A pass that scans dimension `dim` varies i_dim from 0..31 while holding
// the other (d-1) indices fixed.  `outer_idx` packs those (d-1) indices in
// natural order (skipping the dim-th slot): the lower `dim` slots of
// outer_idx hold i_0..i_{dim-1}, the upper (D-1-dim) slots hold
// i_{dim+1}..i_{D-1}.  `scan_idx` is the current i_dim.
//
// The conflict-free bank index is also exported:
//   bank = (i_0 + i_1 + ... + i_{d-1}) mod 32.
//
// Purely combinational.  Synthesises as wires + a small mux on `dim`.
// =============================================================================

`ifndef _MULTIVAR_ADDR_GEN_GUARD
`define _MULTIVAR_ADDR_GEN_GUARD

module multivar_addr_gen #(
    parameter D        = 4,
    parameter LOG_NSUB = 5,
    parameter LOG_N    = D * LOG_NSUB,
    parameter LOG_OUT  = LOG_N - LOG_NSUB,
    parameter DIMW     = (D <= 2) ? 1 : $clog2(D)
)(
    input  wire [DIMW-1:0]       dim,
    input  wire [LOG_NSUB-1:0]   scan_idx,
    input  wire [LOG_OUT-1:0]    outer_idx,
    output wire [LOG_N-1:0]      linear_addr,
    output wire [LOG_NSUB-1:0]   bank
);

    // -------------------------------------------------------------------------
    // For each candidate `dim`, reconstruct linear_addr:
    //   lower_part : the bottom (dim * LOG_NSUB) bits of outer_idx
    //   upper_part : the top  ((D-1-dim) * LOG_NSUB) bits of outer_idx
    //   linear_addr = lower_part
    //               | (scan_idx   << (LOG_NSUB *  dim   ))
    //               | (upper_part << (LOG_NSUB * (dim+1)))
    // -------------------------------------------------------------------------
    wire [LOG_N-1:0] cand [0:D-1];

    genvar d;
    generate
        for (d = 0; d < D; d = d + 1) begin : gen_cand
            localparam integer LSHIFT = LOG_NSUB * d;
            localparam integer USHIFT = LOG_NSUB * (d + 1);

            wire [LOG_N-1:0] lower_ext;
            wire [LOG_N-1:0] mid_ext;
            wire [LOG_N-1:0] upper_ext;

            // lower_ext: bottom LSHIFT bits of outer_idx, zero-extended to LOG_N.
            if (LSHIFT == 0) begin : gen_lo_zero
                assign lower_ext = {LOG_N{1'b0}};
            end else begin : gen_lo_take
                assign lower_ext = { {LOG_N-LSHIFT{1'b0}}, outer_idx[LSHIFT-1:0] };
            end

            // mid_ext: scan_idx placed at slot `d`.
            assign mid_ext = { {LOG_N-LOG_NSUB{1'b0}}, scan_idx } << LSHIFT;

            // upper_ext: outer_idx bits >= LSHIFT, placed at slot >= d+1.
            if (USHIFT >= LOG_N) begin : gen_up_zero
                assign upper_ext = {LOG_N{1'b0}};
            end else begin : gen_up_take
                wire [LOG_OUT-1:0] u_part = outer_idx >> LSHIFT;
                assign upper_ext = { {LOG_N-LOG_OUT{1'b0}}, u_part } << USHIFT;
            end

            assign cand[d] = lower_ext | mid_ext | upper_ext;
        end
    endgenerate

    assign linear_addr = cand[dim];

    // -------------------------------------------------------------------------
    // Bank index: sum of all d sub-indices, mod 32.
    // -------------------------------------------------------------------------
    localparam integer SUMW = LOG_NSUB + $clog2(D + 1) + 1;
    reg [SUMW-1:0] sum_acc;
    integer dd;
    always @* begin
        sum_acc = {SUMW{1'b0}};
        for (dd = 0; dd < D; dd = dd + 1)
            sum_acc = sum_acc + linear_addr[dd*LOG_NSUB +: LOG_NSUB];
    end
    assign bank = sum_acc[LOG_NSUB-1:0];

endmodule

`endif // _MULTIVAR_ADDR_GEN_GUARD
