// =============================================================================
// addr_gen.v
// Address Generation Module — implements the "one address generator" scheme
// from Algorithm 7 (Section IV) of the paper.
//
// For each cycle, given the R original addresses (OrigAddr[0..R-1]) computed
// by the control unit, this module:
//   1. Computes iSelect = XOR of log-R-bit groups of OrigAddr[0]
//      (bank index of first operand)
//   2. Outputs the bank addresses = OrigAddr[logN-1 : logR]  (same for all)
//
// iSelect is fed to all three interconnect modules (BankOut, BankAddr, BankIn).
//
// Parameters:
//   N      = polynomial length
//   R      = radix (number of banks)
//   LOGN   = log2(N)
//   LOGR   = log2(R)
//   AWIDTH = address bits per bank = LOGN - LOGR
// =============================================================================

module addr_gen #(
    parameter N      = 256,
    parameter R      = 4,
    parameter LOGN   = $clog2(N),   // = 8
    parameter LOGR   = $clog2(R),   // = 2
    parameter AWIDTH = LOGN - LOGR  // = 6  (bank address bits)
)(
    input  wire [LOGN-1:0]       orig_addr0,   // OrigAddr of first operand
    input  wire [R*LOGN-1:0]     orig_addrs,   // All R original addresses
    output wire [LOGR-1:0]       iselect,      // Bank index select signal (one-hot bit)
    output wire [R*AWIDTH-1:0]   bank_addrs    // Bank addresses for all R banks
);
    localparam integer FULL_GROUPS = LOGN / LOGR;
    localparam integer REM_BITS    = LOGN - (FULL_GROUPS * LOGR);

    // --- Compute iSelect: sum of base-R address groups modulo R ----------------
    // For mixed-radix (e.g., R=8, N=256), include the top partial group as well.
    genvar k;
    wire [LOGR-1:0] addr_groups [0:FULL_GROUPS-1];
    generate
        for (k = 0; k < FULL_GROUPS; k = k + 1) begin : gen_grp
            assign addr_groups[k] = orig_addr0[k*LOGR +: LOGR];
        end
    endgenerate

    // Sum all LOGR-bit groups modulo R.
    integer sg;
    reg [LOGR-1:0] rem_group;
    reg [LOGR+3:0] isel_acc;
    reg [LOGR-1:0] isel_wire;
    always @(*) begin
        rem_group = {LOGR{1'b0}};
        isel_acc = {LOGR+4{1'b0}};
        for (sg = 0; sg < FULL_GROUPS; sg = sg + 1)
            isel_acc = isel_acc + addr_groups[sg];
        if (REM_BITS > 0) begin
            rem_group[REM_BITS-1:0] = orig_addr0[FULL_GROUPS*LOGR +: REM_BITS];
            isel_acc = isel_acc + rem_group;
        end
        isel_wire = isel_acc[LOGR-1:0];
    end
    assign iselect = isel_wire;

    // --- Bank addresses: upper AWIDTH bits of each OrigAddr -------------------
    genvar j;
    generate
        for (j = 0; j < R; j = j + 1) begin : gen_baddr
            assign bank_addrs[j*AWIDTH +: AWIDTH] = orig_addrs[j*LOGN + LOGR +: AWIDTH];
        end
    endgenerate
endmodule
