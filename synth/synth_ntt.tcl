# =============================================================================
# synth_ntt.tcl  -  Vivado Out-of-Context Synthesis + Implementation
#
# Extracts Table IV metrics: LUT, FF, DSP, BRAM, Fmax
#
# Usage (from Vivado Tcl console or batch):
#   vivado -mode batch -source synth_ntt.tcl -tclargs <radix> <out_dir>
#
#   <radix>   : 4, 8, or 16
#   <out_dir> : output directory (e.g. synth/r4)
#
# Target: Virtex-7 xc7vx485tffg1761-2  (same device as paper Table IV)
#
# The script runs:
#   1. Synthesis (synth_design)
#   2. Implementation: opt_design + place_design + route_design
#   3. Timing summary  (report_timing_summary)
#   4. Utilisation report (report_utilization)
#   5. Writes parsed metrics to <out_dir>/metrics.txt
# =============================================================================

# ---- Parse arguments ---------------------------------------------------------
set radix    [lindex $argv 0]
set out_dir  [lindex $argv 1]

if {$radix eq ""} { set radix 4 }
if {$out_dir eq ""} { set out_dir [file join [file dirname [info script]] "r${radix}"] }

file mkdir $out_dir

set repo_root [file normalize [file dirname [info script]]/..]
set rtl_dir   [file join $repo_root rtl]

puts "============================================================"
puts " NTT Synthesis  R=${radix}  target=xc7vx485tffg1761-2"
puts " RTL dir  : $rtl_dir"
puts " Output   : $out_dir"
puts "============================================================"

# ---- Collect RTL files (skip backup copies) ----------------------------------
set rtl_files [glob -directory $rtl_dir *.v]

# ---- Create in-memory project ------------------------------------------------
create_project -in_memory -part xc7vx485tffg1761-2

# Read all RTL source files
foreach f $rtl_files {
    read_verilog -sv $f
}

# ---- Synthesis ---------------------------------------------------------------
set synth_opts [list \
    -top       ntt_top \
    -part      xc7vx485tffg1761-2 \
    -flatten_hierarchy rebuilt \
    -keep_equivalent_registers \
    -generics  "R=${radix}" \
]

synth_design {*}$synth_opts

# Write synthesis reports
report_utilization -file [file join $out_dir synth_util_r${radix}.rpt]
report_timing_summary -max_paths 10 -file [file join $out_dir synth_timing_r${radix}.rpt]

write_checkpoint -force [file join $out_dir synth_r${radix}.dcp]

puts "\n[INFO] Synthesis complete. Running implementation...\n"

# ---- Implementation (opt + place + route) ------------------------------------
opt_design
place_design
phys_opt_design
route_design

# Write implementation reports
report_utilization    -file [file join $out_dir impl_util_r${radix}.rpt]
report_timing_summary -max_paths 10 -file [file join $out_dir impl_timing_r${radix}.rpt]

write_checkpoint -force [file join $out_dir impl_r${radix}.dcp]

# ---- Parse & emit metrics ----------------------------------------------------
# Read utilization report
set util_file [file join $out_dir impl_util_r${radix}.rpt]
set fp [open $util_file r]
set util_text [read $fp]
close $fp

# Parse utilization (Vivado report_utilization format)
proc parse_util {text pattern} {
    if {[regexp $pattern $text -> val]} {
        return [string trim $val]
    }
    return "N/A"
}

# LUT: "| Slice LUTs*             |  <N> |"
set lut  [parse_util $util_text {Slice LUTs\*?\s+\|\s+(\d+)}]
# FF:  "| Slice Registers         |  <N> |"
set ff   [parse_util $util_text {Slice Registers\s+\|\s+(\d+)}]
# DSP: "| DSPs                    |  <N> |"
set dsp  [parse_util $util_text {DSPs\s+\|\s+(\d+)}]
# BRAM:"| Block RAM Tile          |  <N> |"
set bram [parse_util $util_text {Block RAM Tile\s+\|\s+(\d+)}]

# Read timing report for Fmax (Worst Negative Slack → WNS)
set tim_file [file join $out_dir impl_timing_r${radix}.rpt]
set fp [open $tim_file r]
set tim_text [read $fp]
close $fp

# WNS in nanoseconds: "WNS(ns)  TNS(ns) ..."  followed by the value line
set wns  [parse_util $tim_text {WNS\(ns\)\s+TNS\(ns\)[^\n]*\n\s*([-\d.]+)}]

# Fmax calculation:
# Clock period = 10 ns (100 MHz reference); Fmax = 1000 / (10 - WNS)
if {[string is double -strict $wns]} {
    set clk_period 10.0
    set achieved_period [expr {$clk_period - double($wns)}]
    if {$achieved_period > 0} {
        set fmax [expr {int(1000.0 / $achieved_period)}]
    } else {
        set fmax "N/A (WNS positive, timing met with margin)"
    }
} else {
    set fmax "N/A"
}

# Write metrics file
set mf [open [file join $out_dir metrics_r${radix}.txt] w]
puts $mf "# Table IV Metrics - R=${radix}"
puts $mf "RADIX   ${radix}"
puts $mf "LUT     ${lut}"
puts $mf "FF      ${ff}"
puts $mf "DSP     ${dsp}"
puts $mf "BRAM    ${bram}"
puts $mf "WNS_ns  ${wns}"
puts $mf "FMAX_MHz ${fmax}"
close $mf

puts "\n============================================================"
puts " SYNTHESIS METRICS  R=${radix}"
puts "   LUT  : ${lut}"
puts "   FF   : ${ff}"
puts "   DSP  : ${dsp}"
puts "   BRAM : ${bram}"
puts "   WNS  : ${wns} ns"
puts "   Fmax : ${fmax} MHz"
puts "============================================================\n"
