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
    // --- Compute iSelect: XOR of log-R-bit groups of orig_addr0 ---------------
    // For LOGR=2, R=4: iSelect = orig_addr0[1:0] XOR orig_addr0[3:2] XOR orig_addr0[5:4] XOR ...
    genvar k;
    wire [LOGR-1:0] xor_groups [0:(LOGN/LOGR)-1];
    generate
        for (k = 0; k < LOGN/LOGR; k = k + 1) begin : gen_xor
            assign xor_groups[k] = orig_addr0[k*LOGR +: LOGR];
        end
    endgenerate

    // Sum all LOGR-bit groups modulo R.
    integer sg;
    reg [LOGR+3:0] isel_acc;
    reg [LOGR-1:0] isel_wire;
    always @(*) begin
        isel_acc = {LOGR+4{1'b0}};
        for (sg = 0; sg < LOGN/LOGR; sg = sg + 1)
            isel_acc = isel_acc + xor_groups[sg];
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
