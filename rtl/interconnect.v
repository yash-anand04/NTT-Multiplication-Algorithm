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
    parameter R      = 4,    // Radix
    parameter RHAT   = 1
)(
    input  wire [R*DWIDTH-1:0]  bank_data_out,  // From R banks
    input  wire [$clog2(R)-1:0] iselect,         // Bank index of operand 0
    input  wire                  is_Rhat_stage,
    output wire [R*DWIDTH-1:0]  operands_out     // R operands in correct order
);
    localparam integer R_OVER_RHAT = (RHAT != 0) ? (R / RHAT) : 1;
    localparam integer USE_MIXED_MAP = (RHAT > 1);

    function integer map_mixed;
        input integer base;
        integer mi, mj;
        begin
            if ((RHAT > 1) && (R_OVER_RHAT > 0)) begin
                mi = base % R_OVER_RHAT;
                mj = base / R_OVER_RHAT;
                map_mixed = mi * RHAT + mj;
            end else begin
                map_mixed = base;
            end
        end
    endfunction

    wire [DWIDTH-1:0] bank_arr [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_arr
            assign bank_arr[i] = bank_data_out[i*DWIDTH +: DWIDTH];
        end
    endgenerate

    // Single-radix: circular shift (iselect + k) mod R.
    // When RHAT>1, bank-index ordering follows the mixed permutation.
    genvar k;
    generate
        for (k = 0; k < R; k = k + 1) begin : gen_out
            assign operands_out[k*DWIDTH +: DWIDTH] =
                bank_arr[(iselect + (USE_MIXED_MAP ? map_mixed(k) : k)) % R];
        end
    endgenerate
endmodule

// ---------------------------------------------------------------------------
module interconnect_bank_addr #(
    parameter AWIDTH = 6,    // Bank address bits
    parameter R      = 4,
    parameter RHAT   = 1
)(
    input  wire [R*AWIDTH-1:0]  raw_addrs,      // Raw bank addresses (same for all R, from addr_gen)
    input  wire [$clog2(R)-1:0] iselect,
    input  wire                  is_Rhat_stage,
    output wire [R*AWIDTH-1:0]  selected_addrs  // Addresses routed to each bank
);
    localparam integer LOGR = $clog2(R);
    localparam integer R_OVER_RHAT = (RHAT != 0) ? (R / RHAT) : 1;
    localparam integer USE_MIXED_MAP = (RHAT > 1);

    function integer map_mixed;
        input integer base;
        integer mi, mj;
        begin
            if ((RHAT > 1) && (R_OVER_RHAT > 0)) begin
                mi = base % R_OVER_RHAT;
                mj = base / R_OVER_RHAT;
                map_mixed = mi * RHAT + mj;
            end else begin
                map_mixed = base;
            end
        end
    endfunction

    function integer map_mixed_inv;
        input integer base;
        integer mi, mj;
        begin
            if ((RHAT > 1) && (R_OVER_RHAT > 0)) begin
                mi = base / RHAT;
                mj = base % RHAT;
                map_mixed_inv = mj * R_OVER_RHAT + mi;
            end else begin
                map_mixed_inv = base;
            end
        end
    endfunction

    wire [AWIDTH-1:0] raw_arr [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_raw
            assign raw_arr[i] = raw_addrs[i*AWIDTH +: AWIDTH];
        end
    endgenerate

    // Single-radix: bank j gets raw_addr[(j + R - iselect) % R].
    // When RHAT>1, apply inverse mixed permutation on write-address routing.
    // R is power-of-two in supported configurations (4/8/16), so subtraction on
    // LOGR bits naturally wraps modulo R without an explicit % operator.
    genvar j;
    generate
        for (j = 0; j < R; j = j + 1) begin : gen_addr
            wire [LOGR-1:0] base_idx = j[LOGR-1:0] - iselect;
            assign selected_addrs[j*AWIDTH +: AWIDTH] =
                raw_arr[USE_MIXED_MAP ? map_mixed_inv(base_idx) : base_idx];
        end
    endgenerate
endmodule

// ---------------------------------------------------------------------------
module interconnect_bank_in #(
    parameter DWIDTH = 34,
    parameter R      = 4,
    parameter RHAT   = 1
)(
    input  wire [R*DWIDTH-1:0]  operands_in,    // R computed results (indexed 0..R-1)
    input  wire [$clog2(R)-1:0] iselect,
    input  wire                  is_Rhat_stage,
    output wire [R*DWIDTH-1:0]  bank_data_in    // Data to write to each bank
);
    localparam integer R_OVER_RHAT = (RHAT != 0) ? (R / RHAT) : 1;
    localparam integer USE_MIXED_MAP = (RHAT > 1);

    function integer map_mixed;
        input integer base;
        integer mi, mj;
        begin
            if ((RHAT > 1) && (R_OVER_RHAT > 0)) begin
                mi = base % R_OVER_RHAT;
                mj = base / R_OVER_RHAT;
                map_mixed = mi * RHAT + mj;
            end else begin
                map_mixed = base;
            end
        end
    endfunction

    function integer map_mixed_inv;
        input integer base;
        integer mi, mj;
        begin
            if ((RHAT > 1) && (R_OVER_RHAT > 0)) begin
                mi = base / RHAT;
                mj = base % RHAT;
                map_mixed_inv = mj * R_OVER_RHAT + mi;
            end else begin
                map_mixed_inv = base;
            end
        end
    endfunction

    wire [DWIDTH-1:0] op_arr [0:R-1];
    genvar i;
    generate
        for (i = 0; i < R; i = i + 1) begin : gen_op
            assign op_arr[i] = operands_in[i*DWIDTH +: DWIDTH];
        end
    endgenerate

    // Single-radix: bank j receives operand[(j + R - iselect) % R].
    // When RHAT>1, apply inverse mixed permutation on write-data routing.
    genvar j;
    generate
        for (j = 0; j < R; j = j + 1) begin : gen_in
            wire [$clog2(R)-1:0] base_idx = (j + R - iselect) % R;
            assign bank_data_in[j*DWIDTH +: DWIDTH] =
                op_arr[USE_MIXED_MAP ? map_mixed_inv(base_idx) : base_idx];
        end
    endgenerate
endmodule
