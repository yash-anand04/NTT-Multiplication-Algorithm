// tb_hier_d5_L4_dbg.v — diagnostic: dump mem_a after PWM completion (X*1 case)
`timescale 1ns/1ps
module tb_hier_d5_L4_dbg;
    localparam L = 4, N = L*L*L*L*L, WWIDTH = 17;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, start = 0;
    reg  [WWIDTH-1:0] data_in_a = 0, data_in_b = 0;
    wire [WWIDTH-1:0] data_out;
    wire data_out_valid, done;
    wire [31:0] cycle_count;
    hier_d5_L4_top #(.B(16)) dut (.clk(clk), .rst(rst), .start(start),
        .data_in_a(data_in_a), .data_in_b(data_in_b),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .done(done), .cycle_count(cycle_count));

    reg [WWIDTH-1:0] in_a[0:N-1], in_b[0:N-1];
    integer i;

    // Dump mem_a state at given trigger
    reg dumped_load = 0, dumped_post_fwd = 0, dumped_pwm = 0;

    always @(posedge clk) begin
        // CK_LOAD: dump just after LOAD finishes (state transitions to FWD_L0_A)
        if (dut.state == 5'd2 && !dumped_load) begin // ST_FWD_L0_A = 5'd2
            dumped_load <= 1;
            $display("[CK_LOAD] cycle=%0d: mem_a bank0 pos0..3 = %0d %0d %0d %0d",
                cycle_count,
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[0],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[1],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[2],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[3]);
            $display("[CK_LOAD]                mem_a bank1 pos0..3 = %0d %0d %0d %0d",
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[0],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[1],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[2],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[3]);
        end
        // CK_POST_FWD_A: after FWD_L4_A completes (state transitions to FWD_L0_B = 5'd11)
        if (dut.state == 5'd11 && !dumped_post_fwd) begin
            dumped_post_fwd <= 1;
            $display("[CK_POST_FWD_A] cycle=%0d: mem_a bank0 pos0..7 = %0d %0d %0d %0d %0d %0d %0d %0d",
                cycle_count,
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[0],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[1],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[2],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[3],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[4],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[5],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[6],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[7]);
            $display("[CK_POST_FWD_A]                mem_a bank1 pos0..7 = %0d %0d %0d %0d %0d %0d %0d %0d",
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[0],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[1],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[2],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[3],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[4],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[5],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[6],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[7]);
        end
        // CK_PWM: after PWM, state transitions to INV_L4 (= 5'd21)
        if (dut.state == 5'd21 && !dumped_pwm) begin
            dumped_pwm <= 1;
            $display("[CK_PWM] cycle=%0d: mem_a bank0 pos0..7 = %0d %0d %0d %0d %0d %0d %0d %0d",
                cycle_count,
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[0],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[1],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[2],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[3],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[4],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[5],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[6],
                dut.u_mem_a.g_bram_storage.g_bank[0].mem[7]);
            $display("[CK_PWM]                mem_a bank1 pos0..7 = %0d %0d %0d %0d %0d %0d %0d %0d",
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[0],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[1],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[2],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[3],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[4],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[5],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[6],
                dut.u_mem_a.g_bram_storage.g_bank[1].mem[7]);
        end
    end

    // Watch INV_L4 K=255 write cycle
    integer inv_l4_start_cyc = 0;
    always @(posedge clk) begin
        if (dut.state == 5'd21 && dut.op_count == 0 && inv_l4_start_cyc == 0)
            inv_l4_start_cyc = cycle_count;
        if (inv_l4_start_cyc > 0 && cycle_count == inv_l4_start_cyc + 255 + 2) begin
            $display("[INV_L4 K=255 d2 ntt_in_reg cyc=%0d] = %0d %0d %0d %0d",
                cycle_count,
                dut.ntt_in_reg[0*17 +: 17], dut.ntt_in_reg[1*17 +: 17],
                dut.ntt_in_reg[2*17 +: 17], dut.ntt_in_reg[3*17 +: 17]);
        end
        if (inv_l4_start_cyc > 0 && cycle_count == inv_l4_start_cyc + 255 + 8) begin
            $display("[INV_L4 K=255 d8 cyc=%0d] ntt_out 0..3 = %0d %0d %0d %0d",
                cycle_count,
                dut.ntt_out_pack[0*17 +: 17],
                dut.ntt_out_pack[1*17 +: 17],
                dut.ntt_out_pack[2*17 +: 17],
                dut.ntt_out_pack[3*17 +: 17]);
            $display("    state_d[8]=%0d valid_d[8]=%0d we_pack=%b",
                dut.state_d[8], dut.valid_d[8], dut.mem_scratch_we);
            $display("    wshift_d8=%0d wpos_pack=%h",
                dut.mem_scratch_wshift, dut.mem_scratch_wpos);
        end
    end

    // Watch INV_L3 K=253 cycle (where bug starts)
    integer inv_l3_start_cyc = 0;
    always @(posedge clk) begin
        if (dut.state == 5'd23 && dut.op_count == 0 && inv_l3_start_cyc == 0)
            inv_l3_start_cyc = cycle_count;
        if (inv_l3_start_cyc > 0 && cycle_count == inv_l3_start_cyc + 253 + 1) begin
            $display("[INV_L3 K=253 rdata cyc=%0d] lanes 0..3 = %0d %0d %0d %0d",
                cycle_count,
                dut.mem_scratch_rdata[0*17 +: 17],
                dut.mem_scratch_rdata[1*17 +: 17],
                dut.mem_scratch_rdata[2*17 +: 17],
                dut.mem_scratch_rdata[3*17 +: 17]);
            $display("    op_count=%0d state=%0d state_d[1]=%0d",
                dut.op_count, dut.state, dut.state_d[1]);
            $display("    rshift_op=%0d rpos[0..3]=%0d %0d %0d %0d",
                dut.rshift_op,
                dut.mem_scratch_rpos[0*8 +: 8],
                dut.mem_scratch_rpos[1*8 +: 8],
                dut.mem_scratch_rpos[2*8 +: 8],
                dut.mem_scratch_rpos[3*8 +: 8]);
        end
    end

    // Watch INV_L0 K=1 iteration cycle-by-cycle
    integer inv_l0_start_cyc = 0;
    always @(posedge clk) begin
        if (dut.state == 5'd29 && dut.op_count == 0 && inv_l0_start_cyc == 0)
            inv_l0_start_cyc = cycle_count;
        if (inv_l0_start_cyc > 0 && cycle_count == inv_l0_start_cyc + 2) begin
            // K=1 rdata available (1-cycle BRAM sync).
            $display("[K=1 rdata cyc=%0d] scratch rdata lanes 0..3 = %0d %0d %0d %0d",
                cycle_count,
                dut.mem_scratch_rdata[0*17 +: 17],
                dut.mem_scratch_rdata[1*17 +: 17],
                dut.mem_scratch_rdata[2*17 +: 17],
                dut.mem_scratch_rdata[3*17 +: 17]);
            $display("              ntt_in_reg lanes 0..3 = %0d %0d %0d %0d",
                dut.ntt_in_reg[0*17 +: 17],
                dut.ntt_in_reg[1*17 +: 17],
                dut.ntt_in_reg[2*17 +: 17],
                dut.ntt_in_reg[3*17 +: 17]);
        end
        if (inv_l0_start_cyc > 0 && cycle_count == inv_l0_start_cyc + 1 + 8) begin
            // d8 tap (one cycle after rdata via reg, then 6 cycles NTT, then 1 cycle output reg = 8)
            // Actually d8 = read issued at T, ntt_out at T+8
            $display("[K=1 d8 cyc=%0d] ntt_out lanes 0..3 = %0d %0d %0d %0d, tw_pack 0..3 = %0d %0d %0d %0d",
                cycle_count,
                dut.ntt_out_pack[0*17 +: 17], dut.ntt_out_pack[1*17 +: 17],
                dut.ntt_out_pack[2*17 +: 17], dut.ntt_out_pack[3*17 +: 17],
                dut.tw_pack[0*17 +: 17], dut.tw_pack[1*17 +: 17],
                dut.tw_pack[2*17 +: 17], dut.tw_pack[3*17 +: 17]);
        end
        if (inv_l0_start_cyc > 0 && cycle_count == inv_l0_start_cyc + 1 + 12) begin
            $display("[K=1 d12 cyc=%0d] mul_out lanes 0..3 = %0d %0d %0d %0d",
                cycle_count,
                dut.mul_out_pack[0*17 +: 17], dut.mul_out_pack[1*17 +: 17],
                dut.mul_out_pack[2*17 +: 17], dut.mul_out_pack[3*17 +: 17]);
        end
    end

    // Dump scratch at each INV phase transition (states 22..30)
    reg [8:0] dumped_inv = 0;  // bit per state in 22..30
    integer ph;
    always @(posedge clk) begin
        for (ph = 22; ph <= 30; ph = ph + 1) begin
            if (dut.state == ph[4:0] && !dumped_inv[ph-22]) begin
                dumped_inv[ph-22] <= 1'b1;
                $display("[ST=%0d cyc=%0d] scratch B0 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    ph, cycle_count,
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[0],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[1],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[2],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[3],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[4],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[5],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[6],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[7]);
                $display("           scratch B1 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[0],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[1],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[2],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[3],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[4],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[5],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[6],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[7]);
                $display("           scratch B2 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[0],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[1],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[2],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[3],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[4],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[5],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[6],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[7]);
                $display("           scratch B3 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[0],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[1],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[2],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[3],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[4],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[5],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[6],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[7]);
                $display("    scratch[0,192]=%0d [1,208]=%0d [2,224]=%0d [3,240]=%0d",
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[192],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[208],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[224],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[240]);
                // INV_L2 K=241 reads these:
                $display("    K241read: scratch[3,240]=%0d [0,244]=%0d [1,248]=%0d [2,252]=%0d",
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[240],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[244],
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[248],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[252]);
                $display("    boundary: scratch[1,255]=%0d [2,254]=%0d [0,253]=%0d [3,252]=%0d",
                    dut.u_mem_scratch.g_bram_storage.g_bank[1].mem[255],
                    dut.u_mem_scratch.g_bram_storage.g_bank[2].mem[254],
                    dut.u_mem_scratch.g_bram_storage.g_bank[0].mem[253],
                    dut.u_mem_scratch.g_bram_storage.g_bank[3].mem[252]);
                // Also dump mem_a B0..B3 (INV_L0 writes here)
                $display("           mem_a   B0 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[0],
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[1],
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[2],
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[3],
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[4],
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[5],
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[6],
                    dut.u_mem_a.g_bram_storage.g_bank[0].mem[7]);
                $display("           mem_a   B1 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[0],
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[1],
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[2],
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[3],
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[4],
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[5],
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[6],
                    dut.u_mem_a.g_bram_storage.g_bank[1].mem[7]);
                $display("           mem_a   B2 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[0],
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[1],
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[2],
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[3],
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[4],
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[5],
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[6],
                    dut.u_mem_a.g_bram_storage.g_bank[2].mem[7]);
                $display("           mem_a   B3 pos0..7=%0d %0d %0d %0d %0d %0d %0d %0d",
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[0],
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[1],
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[2],
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[3],
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[4],
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[5],
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[6],
                    dut.u_mem_a.g_bram_storage.g_bank[3].mem[7]);
            end
        end
    end

    initial begin
        // X*1: a=[0,1,0,...], b=[1,0,...], expect c=[0,1,0,...]
        for (i=0; i<N; i=i+1) begin in_a[i]=0; in_b[i]=0; end
        in_a[1] = 17'd1;
        in_b[0] = 17'd1;

        rst=1'b1; start=1'b0; data_in_a=0; data_in_b=0;
        repeat(4) @(posedge clk); @(negedge clk); rst=1'b0; @(negedge clk);
        data_in_a=in_a[0]; data_in_b=in_b[0]; start=1'b1;
        @(negedge clk); start=1'b0; @(negedge clk);
        for (i=1; i<N; i=i+1) begin
            data_in_a=in_a[i]; data_in_b=in_b[i]; @(negedge clk);
        end
        data_in_a=0; data_in_b=0;
        // Wait until DONE
        wait (done);
        @(posedge clk);
        $display("=== DONE cycle=%0d ===", cycle_count);
        $finish;
    end
    initial begin #50_000_000; $display("WATCHDOG"); $finish; end
endmodule
