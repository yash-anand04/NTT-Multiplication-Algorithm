#!/usr/bin/env python3
"""
Debug test: just load input and immediately dump without NTT/INTT for verification
"""
import subprocess
import sys

# Add debug testbench
debug_tb = """
`timescale 1ns/1ps

module tb_debug;
    localparam B     = 16;
    localparam N     = 256;
    localparam R     = 4;
    localparam WWIDTH = B + 1;

    reg             clk, rst, start;
    reg  [WWIDTH-1:0] data_in_a, data_in_b;
    wire [WWIDTH-1:0] data_out;
    wire              done;

    ntt_top #(.B(B), .N(N), .R(R)) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .data_out (data_out),
        .done     (done)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    reg [WWIDTH-1:0] input_a  [0:N-1];
    integer i;

    initial begin
        $readmemh("input_a.hex", input_a);
        $dumpfile("bin/tb_debug.vcd");
        $dumpvars(0, tb_debug);

        rst = 1; start = 0; data_in_a = 0; data_in_b = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Load only first 4 coefficients
        @(negedge clk);
        start = 1;
        for (i = 0; i < 4; i = i + 1) begin
            data_in_a = input_a[i];
            data_in_b = input_a[i];
            @(negedge clk);
            $display("LOAD %0d: data_in_a=%0h", i, data_in_a);
        end
        start = 0;
        for (i = 4; i < N; i = i + 1) begin
            data_in_a = 0;
            data_in_b = 0;
            @(negedge clk);
        end

        $display("LOAD complete at time %0t", $time);
        @(posedge clk);
    end
endmodule
"""

with open("tb_debug.v", "w") as f:
    f.write(debug_tb)

# Compile
print("Compiling debug testbench...")
result = subprocess.run([
    "/c/iverilog/bin/iverilog", "-o", "ntt_sim_debug",
    "-I", "../rtl", "tb_debug.v", "../rtl/ntt_top.v", "../rtl/ctrl_unit.v",
    "../rtl/addr_gen.v", "../rtl/mod_mul_fermat.v", "../rtl/r2ntt_r4.v",
    "../rtl/r2intt_r4.v", "../rtl/r2_butterfly.v", "../rtl/d1_arith.v",
    "../rtl/mem_banks.v", "../rtl/interconnect.v", "../rtl/twiddle_rom.v"
], cwd="sim")
if result.returncode != 0:
    sys.exit(1)

print("Running debug simulation...")
result = subprocess.run(["/c/iverilog/bin/vvp", "ntt_sim_debug"], cwd="sim",
                       capture_output=True, text=True, timeout=30)
print(result.stdout[-1000:])
if "error" in result.stderr.lower():
    print("Errors:", result.stderr[-500:])
