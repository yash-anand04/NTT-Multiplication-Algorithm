// =============================================================================
// interconnect.v
// Three Interconnect Modules as shown in Fig. 6:
//   - InterconnectBankOut : routes data from banks to operand inputs
//   - InterconnectBankAddr: routes bank addresses based on iSelect
//   - InterconnectBankIn  : routes operand outputs back to banks
//
// Based on Algorithm 7: precomputed BankIndexes and OpIndexes tables
// parameterized for R=4 (single-radix), with optional R^hat extension.
//
// For R=4, single radix (R^hat=1), the precomputed tables are:
//   BankIndexes[k][isel] = (isel + k) mod R   for k=0..R-1, isel=0..R-1
//   OpIndexes[i][isel]   = (i - isel) mod R   for i=0..R-1, isel=0..R-1
//
// iselect selects which circular-shift group to use for the MUX.
// =============================================================================

module interconnect_bank_out #(
    parameter DWIDTH = 34,   // Data width per operand (2*(B+1))
    parameter R      = 4     // Radix
)(
    input  wire [R*DWIDTH-1:0]  bank_data_out,  // From R banks
    input  wire [$clog2(R)-1:0] iselect,         // Bank index of operand 0
    output wire [R*DWIDTH-1:0]  operands_out     // R operands in correct order
);
    wire [DWIDTH-1:0] bank_arr [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_arr
            assign bank_arr[i] = bank_data_out[i*DWIDTH +: DWIDTH];
        end
    endgenerate

    // Circular shift: operand k gets data from bank (iselect + k) mod R
    genvar k;
    generate
        for (k = 0; k < R; k = k + 1) begin : gen_out
            assign operands_out[k*DWIDTH +: DWIDTH] = bank_arr[(iselect + k) % R];
        end
    endgenerate
endmodule

// ---------------------------------------------------------------------------
module interconnect_bank_addr #(
    parameter AWIDTH = 6,    // Bank address bits
    parameter R      = 4
)(
    input  wire [R*AWIDTH-1:0]  raw_addrs,      // Raw bank addresses (same for all R, from addr_gen)
    input  wire [$clog2(R)-1:0] iselect,
    output wire [R*AWIDTH-1:0]  selected_addrs  // Addresses routed to each bank
);
    wire [AWIDTH-1:0] raw_arr [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_raw
            assign raw_arr[i] = raw_addrs[i*AWIDTH +: AWIDTH];
        end
    endgenerate

    // For in-place NTT all R banks get the same address value (no conflict since
    // each bank has a unique bank index). The iselect controls which operand's
    // address goes to which bank: bank (iselect+k)%R gets raw_addr[k]
    // Therefore, bank j gets raw_addr[(j + R - iselect) % R].
    genvar j;
    generate
        for (j = 0; j < R; j = j + 1) begin : gen_addr
            assign selected_addrs[j*AWIDTH +: AWIDTH] = raw_arr[(j + R - iselect) % R];
        end
    endgenerate
endmodule

// ---------------------------------------------------------------------------
module interconnect_bank_in #(
    parameter DWIDTH = 34,
    parameter R      = 4
)(
    input  wire [R*DWIDTH-1:0]  operands_in,    // R computed results (indexed 0..R-1)
    input  wire [$clog2(R)-1:0] iselect,
    output wire [R*DWIDTH-1:0]  bank_data_in    // Data to write to each bank
);
    wire [DWIDTH-1:0] op_arr [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_op
            assign op_arr[i] = operands_in[i*DWIDTH +: DWIDTH];
        end
    endgenerate

    // Inverse circular shift: bank (iselect+k)%R receives operand k
    // Therefore, bank j receives operand[(j + R - iselect) % R].
    genvar j;
    generate
        for (j = 0; j < R; j = j + 1) begin : gen_in
            assign bank_data_in[j*DWIDTH +: DWIDTH] = op_arr[(j + R - iselect) % R];
        end
    endgenerate
endmodule
