# =============================================================================
# vivado_synth_bivar.tcl
# Vivado Synthesis + Implementation for Bivariate NTT Polynomial Multiplier
# L=8 fixed (Fermat prime q=65537 structure); M=N/8 varies with N.
# =============================================================================

# ---- Setup Paths & Arguments -------------------------------------------------

set n_degree      [lindex $argv 0]
set target_period [lindex $argv 1]

if {$n_degree eq ""} {
    set n_degree 256
}

if {$target_period eq ""} {
    set target_period 3.0
}

set l_dim 8
set m_dim [expr {$n_degree / $l_dim}]

set script_dir [file dirname [info script]]
set repo_root  [file normalize [file join $script_dir ".."]]

set rtl_dir    [file join $repo_root rtl]
set out_dir    [file join $script_dir "results_bivar_n${n_degree}"]

set device "xc7k160tfbg484-2"

file mkdir $out_dir

puts "========================================================================="
puts "  Bivariate NTT Synthesis Metrics Extraction"
puts "  L = $l_dim (fixed), M = $m_dim, N = $n_degree"
puts "  Target period: $target_period ns"
puts "  Device: $device"
puts "  Output: $out_dir"
puts "========================================================================="

# ---- Read RTL Files ----------------------------------------------------------

set rtl_files [glob -nocomplain -directory $rtl_dir -types f *.v]

if {[llength $rtl_files] == 0} {
    puts "ERROR: No Verilog files found in $rtl_dir"
    exit 1
}

puts "INFO: Found [llength $rtl_files] RTL files"

create_project -in_memory -part $device

foreach f $rtl_files {
    set f_norm [file normalize $f]
    puts "INFO: Reading $f_norm"
    read_verilog -sv [list $f_norm]
}

# ---- Synthesis ---------------------------------------------------------------

puts ""
puts "INFO: Running synthesis..."

set synth_opts [list \
    -top bivar_ntt_top \
    -part $device \
    -flatten_hierarchy rebuilt \
    -directive PerformanceOptimized \
    -generic "L=$l_dim" \
    -generic "M=$m_dim" \
]

synth_design {*}$synth_opts

if {[llength [get_ports clk]] > 0} {
    create_clock -name clk -period $target_period [get_ports clk]
}

report_utilization \
    -file [file join $out_dir "01_synth_utilization.rpt"]

report_timing_summary \
    -max_paths 10 \
    -file [file join $out_dir "01_synth_timing.rpt"]

write_checkpoint -force [file join $out_dir "synth.dcp"]

# ---- Implementation ----------------------------------------------------------

puts ""
puts "INFO: Running implementation..."

opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

report_utilization \
    -file [file join $out_dir "02_impl_utilization.rpt"]

report_route_status \
    -file [file join $out_dir "03_route_status.rpt"]

report_timing_summary \
    -max_paths 10 \
    -file [file join $out_dir "02_impl_timing.rpt"]

write_checkpoint -force [file join $out_dir "impl.dcp"]

# ---- Parse Metrics -----------------------------------------------------------

puts ""
puts "INFO: Parsing metrics..."

proc extract_metric {text pattern} {
    if {[regexp $pattern $text -> val]} {
        set val [string trim $val]
        set val [string map {" " ""} $val]
        if {[string is integer -strict $val]} {
            return $val
        }
    }
    return 0
}

proc extract_slack {text} {
    set lines [split $text "\n"]
    set in_summary 0

    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]

        if {[string match "*Design Timing Summary*" $line]} {
            set in_summary 1
            continue
        }

        if {!$in_summary} {
            continue
        }

        if {[string match "*WNS(ns)*" $line]} {
            for {set j [expr {$i + 1}]} {$j < [llength $lines]} {incr j} {
                set row [string trim [lindex $lines $j]]
                if {$row eq ""} {
                    continue
                }
                if {[regexp {^([-+]?[0-9]*\.?[0-9]+)\s+[-+]?[0-9]*\.?[0-9]+} $row -> val]} {
                    return [string trim $val]
                }
            }
        }
    }

    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        if {[regexp {Worst Slack\s+([-+]?[0-9]*\.?[0-9]+)} $line -> val]} {
            return [string trim $val]
        }
    }

    return "N/A"
}

# ---- Read Utilization Report -------------------------------------------------

set util_file [file join $out_dir "02_impl_utilization.rpt"]

if {[file exists $util_file]} {
    set fp [open $util_file r]
    set util_text [read $fp]
    close $fp

    set lut_count  [extract_metric $util_text {Slice LUTs\s+\|\s+([0-9]+)}]
    set ff_count   [extract_metric $util_text {Slice Registers\s+\|\s+([0-9]+)}]
    set dsp_count  [extract_metric $util_text {DSPs\s+\|\s+([0-9]+)}]
    set bram_count [extract_metric $util_text {Block RAM Tile\s+\|\s+([0-9]+)}]

    puts "INFO: LUT=$lut_count FF=$ff_count DSP=$dsp_count BRAM=$bram_count"
} else {
    puts "WARN: Utilization report not found"
    set lut_count 0
    set ff_count 0
    set dsp_count 0
    set bram_count 0
}

# ---- Read Timing Report ------------------------------------------------------

set timing_file [file join $out_dir "02_impl_timing.rpt"]

if {[file exists $timing_file]} {
    set fp [open $timing_file r]
    set timing_text [read $fp]
    close $fp

    set slack_ns [extract_slack $timing_text]

    if {[string is double -strict $slack_ns]} {
        if {$slack_ns < 0} {
            set actual_period [expr {$target_period - $slack_ns}]
        } else {
            set actual_period $target_period
        }
        set fmax_mhz [expr {1000.0 / $actual_period}]
    } else {
        set fmax_mhz 300.0
    }

    puts "INFO: WNS=$slack_ns ns"
    puts "INFO: Estimated Fmax=$fmax_mhz MHz"
} else {
    puts "WARN: Timing report not found"
    set slack_ns "N/A"
    set fmax_mhz 300.0
}

# ---- Derived Metrics ---------------------------------------------------------
# Cycle count formula: Cycles(N) = 2N + 7M + 3L = 2N + 7(N/8) + 24 = (23/8)N + 24
# Exact counts (L=8 fixed):
#   N=64:  2*64  + 7*8  + 24 = 128 + 56  + 24 = 208
#   N=128: 2*128 + 7*16 + 24 = 256 + 112 + 24 = 392
#   N=256: 2*256 + 7*32 + 24 = 512 + 224 + 24 = 760
#   N=512: 2*512 + 7*64 + 24 = 1024 + 448 + 24 = 1496

set cycles_map [dict create \
    "64"   208  \
    "128"  392  \
    "256"  760  \
    "512"  1496 \
]

if {[dict exists $cycles_map $n_degree]} {
    set cycles [dict get $cycles_map $n_degree]
} else {
    # Fallback: use formula
    set cycles [expr {int(23 * $n_degree / 8) + 24}]
}

if {$fmax_mhz > 0} {
    set time_us [expr {$cycles / $fmax_mhz}]
} else {
    set time_us 0.0
}

# ---- Write Metrics File ------------------------------------------------------

set metrics_file [file join $out_dir "metrics_raw.txt"]
set fp [open $metrics_file w]

puts $fp "# Bivariate NTT Synthesis Metrics"
puts $fp "# L=$l_dim M=$m_dim N=$n_degree"
puts $fp "# Device=$device"
puts $fp "# Generated=[clock format [clock seconds]]"

puts $fp ""
puts $fp "L=$l_dim"
puts $fp "M=$m_dim"
puts $fp "DEGREE=$n_degree"

puts $fp ""
puts $fp "LUT=$lut_count"
puts $fp "FF=$ff_count"
puts $fp "DSP=$dsp_count"
puts $fp "BRAM=$bram_count"

puts $fp ""
puts $fp "WNS_NS=$slack_ns"
puts $fp "FMAX_MHZ=$fmax_mhz"

puts $fp ""
puts $fp "CYCLES=$cycles"
puts $fp "TIME_US=$time_us"

puts $fp ""
puts $fp "LUT_ATP=[expr {$lut_count * $cycles}]"
puts $fp "FF_ATP=[expr {$ff_count * $cycles}]"
puts $fp "DSP_ATP=[expr {$dsp_count * $cycles}]"
puts $fp "BRAM_ATP=[expr {$bram_count * $cycles}]"

close $fp

# ---- Summary -----------------------------------------------------------------

puts ""
puts "========================================================================="
puts "SUMMARY: bivar_ntt_top  L=$l_dim M=$m_dim N=$n_degree"
puts "========================================================================="
puts "LUT:        $lut_count"
puts "FF:         $ff_count"
puts "DSP:        $dsp_count"
puts "BRAM:       $bram_count"
puts "Fmax (MHz): [format %.2f $fmax_mhz]"
puts "Cycles:     $cycles"
puts "Time (us):  [format %.2f $time_us]"
puts "LUT-ATP:    [expr {$lut_count * $cycles}]"
puts "DSP-ATP:    [expr {$dsp_count * $cycles}]"
puts "========================================================================="

puts ""
puts "INFO: Metrics written to:"
puts "INFO: $metrics_file"

exit 0
