// =============================================================================
// twiddle_gen.v   (Phase B.4)
// Twiddle generator for the hierarchical NTT.  Stores psi^k for
// k in [0, 2N) where psi is a 2N-th root of unity in F_q, q = 2^B + 1.
//
// Modes:
//   MODE = "rom_full"        : 2N-entry ROM, direct lookup.
//                              ROM bits = 2N * (B+1).
//
//   MODE = "rom_qcompressed" : N/2-entry ROM + quarter-cycle symmetry fix-up.
//                              4x smaller storage.  Uses the identities
//                                 psi^(N+k)   = -psi^k
//                                 psi^(N/2+k) =  i * psi^k    where i = sqrt(-1)
//                              For q = 65537, i = +2^8 = 256 (since
//                              2^16 = -1 mod q, so 2^8 is a 4th root of unity).
//                              Multiplication by 2^8 is a circular shift in
//                              the D1 representation (free of multipliers).
//
// One twiddle per cycle.  Caller replicates the module (or shares its
// underlying ROM via dual-port) for lane-parallel use.
// =============================================================================

`ifndef _TWIDDLE_GEN_GUARD
`define _TWIDDLE_GEN_GUARD

module twiddle_gen #(
    parameter B          = 16,
    parameter LOGN       = 10,             // N = 2^LOGN
    parameter MODE       = "rom_full",
    parameter REGISTERED = 1,
    parameter WWIDTH     = B + 1,
    parameter G          = 3
)(
    input  wire               clk,
    input  wire [LOGN:0]      idx,         // LOGN+1 bits: range [0, 2N)
    output wire [WWIDTH-1:0]  tw_out
);

    localparam integer N    = 1 << LOGN;
    localparam integer N2   = 1 << (LOGN + 1);   // 2N
    localparam integer Q    = (1 << B) + 1;

    // -------------------------------------------------------------------------
    // Modular exponentiation (elaboration / initial only).
    // -------------------------------------------------------------------------
    function [WWIDTH-1:0] modexp;
        input longint base_in;
        input longint exp_in;
        input longint mod_in;
        longint base_v, exp_v, mod_v, acc;
        begin
            acc = 1;  base_v = base_in;  exp_v = exp_in;  mod_v = mod_in;
            while (exp_v > 0) begin
                if (exp_v & 1) acc = (acc * base_v) % mod_v;
                base_v = (base_v * base_v) % mod_v;
                exp_v  = exp_v >> 1;
            end
            modexp = acc[WWIDTH-1:0];
        end
    endfunction

    generate
        // =====================================================================
        // MODE: rom_full  (2N-entry ROM)
        // =====================================================================
        if (MODE == "rom_full") begin : gen_full
            (* rom_style = "block" *)
            reg [WWIDTH-1:0] rom [0:N2-1];
            integer ki;
            longint psi_val_w, tmp;
            initial begin
                psi_val_w = modexp(G, (Q - 1) / N2, Q);
                rom[0]    = {{(WWIDTH-1){1'b0}}, 1'b1};
                for (ki = 1; ki < N2; ki = ki + 1) begin
                    tmp     = rom[ki-1] * psi_val_w;
                    rom[ki] = (tmp % Q);
                end
            end
            if (REGISTERED) begin : gen_reg
                reg [WWIDTH-1:0] tw_r;
                always @(posedge clk) tw_r <= rom[idx];
                assign tw_out = tw_r;
            end else begin : gen_comb
                assign tw_out = rom[idx];
            end
        end

        // =====================================================================
        // MODE: rom_qcompressed  (N/2-entry ROM + quadrant fix-up)
        // =====================================================================
        else if (MODE == "rom_qcompressed") begin : gen_qc
            localparam integer ROM_DEPTH  = N >> 1;             // N/2
            localparam integer LOG_INNER  = LOGN - 1;           // bits for inner index

            (* rom_style = "block" *)
            reg [WWIDTH-1:0] rom_qc [0:ROM_DEPTH-1];
            integer ki;
            longint psi_val_w, tmp;
            initial begin
                psi_val_w = modexp(G, (Q - 1) / N2, Q);
                rom_qc[0] = {{(WWIDTH-1){1'b0}}, 1'b1};
                for (ki = 1; ki < ROM_DEPTH; ki = ki + 1) begin
                    tmp        = rom_qc[ki-1] * psi_val_w;
                    rom_qc[ki] = (tmp % Q);
                end
            end

            // Decode idx into (quad, inner)
            wire [1:0]            quad  = idx[LOGN:LOGN-1];
            wire [LOG_INNER-1:0]  inner = idx[LOG_INNER-1:0];
            wire [WWIDTH-1:0]     base_val = rom_qc[inner];

            // Apply quadrant transform via D1 arithmetic.
            //   For q=65537 with the canonical psi = g^((q-1)/(2N)) and g=3,
            //   the empirically verified value is psi^(N/2) = -256 (= q-256).
            //   The "imul" path is therefore "multiply by -i", and the
            //   quadrants below select accordingly:
            //     quad=00:  out =       psi^inner                       = base
            //     quad=01:  out = psi^(N/2 + inner) = -i * base          = ineg
            //     quad=10:  out = psi^(N   + inner) =  -base             = neg
            //     quad=11:  out = psi^(3N/2 + inner)= +i * base          = imul
            wire [B:0] base_d1, imul_d1, neg_d1, ineg_d1, selected_d1;
            wire [B:0] tw_norm;
            norm_to_d1 #(B) u_n2d (.in(base_val), .out(base_d1));
            d1_mul_by_2k #(.B(B), .K(8)) u_imul (.in(base_d1), .out(imul_d1));
            d1_neg #(B) u_neg  (.in(base_d1), .out(neg_d1));
            d1_neg #(B) u_inneg(.in(imul_d1), .out(ineg_d1));
            assign selected_d1 = (quad == 2'b00) ? base_d1 :
                                 (quad == 2'b01) ? ineg_d1 :
                                 (quad == 2'b10) ? neg_d1  :
                                                   imul_d1;
            d1_to_norm #(B) u_d2n (.in(selected_d1), .out(tw_norm));

            if (REGISTERED) begin : gen_reg
                reg [WWIDTH-1:0] tw_r;
                always @(posedge clk) tw_r <= tw_norm;
                assign tw_out = tw_r;
            end else begin : gen_comb
                assign tw_out = tw_norm;
            end
        end

        // =====================================================================
        else begin : gen_unsupported
            initial begin
                $display("twiddle_gen: MODE=\"%s\" not implemented", MODE);
                $finish;
            end
            assign tw_out = {WWIDTH{1'b0}};
        end
    endgenerate

endmodule

`endif // _TWIDDLE_GEN_GUARD
