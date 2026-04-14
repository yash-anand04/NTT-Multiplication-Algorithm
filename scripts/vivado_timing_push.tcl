# Vivado timing push script for NTT project.
# Usage (from Vivado Tcl console):
#   source scripts/vivado_timing_push.tcl
#
# Assumes an opened project with runs synth_1 and impl_1.

if {[llength [get_projects]] == 0} {
    error "No Vivado project is open. Open your project, then source this script."
}

set synth_run synth_1
set impl_run  impl_1

if {[llength [get_runs $synth_run]] == 0 || [llength [get_runs $impl_run]] == 0} {
    error "Expected runs synth_1 and impl_1 were not found in this project."
}

# Create reports directory if needed.
file mkdir Reports

proc safe_set {obj prop val} {
    if {[catch {set_property $prop $val $obj} emsg]} {
        puts "WARN: Could not set $prop to $val on $obj"
        puts "      $emsg"
    } else {
        puts "INFO: Set $prop to $val"
    }
}

puts "INFO: Applying timing-focused synthesis/implementation settings..."

# High-effort synthesis.
safe_set [get_runs $synth_run] strategy Flow_PerfOptimized_high
safe_set [get_runs $synth_run] STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE ExploreWithRemap
safe_set [get_runs $synth_run] STEPS.SYNTH_DESIGN.ARGS.FANOUT_LIMIT 128

# Timing-focused implementation + aggressive physical optimization.
safe_set [get_runs $impl_run] strategy Performance_ExplorePostRoutePhysOpt
safe_set [get_runs $impl_run] STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreWithRemap
safe_set [get_runs $impl_run] STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraPostPlacementOpt
safe_set [get_runs $impl_run] STEPS.PHYS_OPT_DESIGN.IS_ENABLED true
safe_set [get_runs $impl_run] STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveFanoutOpt
safe_set [get_runs $impl_run] STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore
safe_set [get_runs $impl_run] STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true
safe_set [get_runs $impl_run] STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore

puts "INFO: Resetting and launching runs..."
reset_run $synth_run
reset_run $impl_run
launch_runs $impl_run -to_step write_bitstream -jobs 16
wait_on_run $impl_run

puts "INFO: Collecting timing reports..."
open_run $impl_run
report_timing_summary -delay_type max -max_paths 20 -nworst 1 -file Reports/timing_push_summary.rpt
report_timing -delay_type max -max_paths 20 -input_pins -file Reports/timing_push_top20.rpt
report_design_analysis -congestion -file Reports/timing_push_congestion.rpt

set wns [get_property STATS.WNS [get_runs $impl_run]]
set tns [get_property STATS.TNS [get_runs $impl_run]]
puts "INFO: Timing-push run complete. WNS=$wns  TNS=$tns"
puts "INFO: Reports written to Reports/timing_push_*.rpt"
