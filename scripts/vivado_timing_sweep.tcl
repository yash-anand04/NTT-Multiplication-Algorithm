# Vivado timing sweep for routing-dominant setup violations.
# Usage:
#   source scripts/vivado_timing_sweep.tcl
#
# Assumes an open project with runs synth_1 and impl_1.

# -------------------------------
# Safety checks
# -------------------------------
if {[llength [get_projects]] == 0} {
    error "No Vivado project is open. Open your project, then source this script."
}

set synth_run synth_1
set impl_run  impl_1

if {[llength [get_runs $synth_run]] == 0 || [llength [get_runs $impl_run]] == 0} {
    error "Expected runs synth_1 and impl_1 were not found in this project."
}

# -------------------------------
# Setup output directory
# -------------------------------
file mkdir Reports

# -------------------------------
# Safe property setter
# -------------------------------
proc safe_set {obj prop val} {
    if {[catch {set_property $prop $val $obj} emsg]} {
        puts "WARN: Could not set $prop=$val on $obj"
        puts "      $emsg"
        return 0
    }
    return 1
}

# -------------------------------
# Run synthesis (fixed high effort)
# -------------------------------
puts "INFO: Configuring synthesis run..."

safe_set [get_runs $synth_run] strategy Flow_PerfOptimized_high
safe_set [get_runs $synth_run] STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE ExploreWithRemap
safe_set [get_runs $synth_run] STEPS.SYNTH_DESIGN.ARGS.FANOUT_LIMIT 128

reset_run $synth_run
launch_runs $synth_run -jobs 16
wait_on_run $synth_run

# -------------------------------
# Sweep parameters
# -------------------------------
set seeds {1 11 23}
set variants {
    {ExtraPostPlacementOpt AggressiveFanoutOpt AggressiveExplore}
    {Explore Explore Explore}
}

# -------------------------------
# CSV logging setup
# -------------------------------
set csv_file "Reports/timing_sweep_results.csv"
set fp [open $csv_file w]
puts $fp "run_id,seed,place_dir,phys_dir,post_phys_dir,wns"
flush $fp

# -------------------------------
# Sweep loop
# -------------------------------
set run_id 0
set best_wns -1e9
set best_desc ""

foreach seed $seeds {
    foreach v $variants {

        incr run_id
        set place_dir [lindex $v 0]
        set phys_dir [lindex $v 1]
        set post_phys_dir [lindex $v 2]

        puts "\nINFO: === Sweep run #$run_id (seed=$seed, place=$place_dir, phys=$phys_dir, post_phys=$post_phys_dir) ==="

        # -------------------------------
        # Configure implementation
        # -------------------------------
        safe_set [get_runs $impl_run] strategy Performance_ExplorePostRoutePhysOpt
        safe_set [get_runs $impl_run] STEPS.OPT_DESIGN.ARGS.DIRECTIVE ExploreWithRemap
        safe_set [get_runs $impl_run] STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $place_dir
        safe_set [get_runs $impl_run] STEPS.PLACE_DESIGN.ARGS.SEED $seed
        safe_set [get_runs $impl_run] STEPS.PHYS_OPT_DESIGN.IS_ENABLED true
        safe_set [get_runs $impl_run] STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $phys_dir
        safe_set [get_runs $impl_run] STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore
        safe_set [get_runs $impl_run] STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true
        safe_set [get_runs $impl_run] STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $post_phys_dir

        # -------------------------------
        # Run implementation
        # -------------------------------
        reset_run $impl_run
        launch_runs $impl_run -to_step route_design -jobs 16
        wait_on_run $impl_run
        current_run $impl_run

        # -------------------------------
        # Extract WNS (reliable method)
        # -------------------------------
        set worst_path [get_timing_paths -max_paths 1 -nworst 1]

        if {[llength $worst_path] > 0} {
            set wns [get_property SLACK $worst_path]
        } else {
            set wns "NA"
        }

        # -------------------------------
        # Generate reports
        # -------------------------------
        set rpt_base "Reports/timing_sweep_run${run_id}"

        report_timing_summary -delay_type max -max_paths 20 -nworst 1 \
            -file "${rpt_base}_summary.rpt"

        report_timing -delay_type max -max_paths 20 -input_pins \
            -file "${rpt_base}_top20.rpt"

        report_design_analysis -congestion \
            -file "${rpt_base}_congestion.rpt"

        # -------------------------------
        # Log results
        # -------------------------------
        puts $fp "$run_id,$seed,$place_dir,$phys_dir,$post_phys_dir,$wns"
        flush $fp

        # -------------------------------
        # Track best result
        # -------------------------------
        if {$wns ne "NA" && $wns > $best_wns} {
            set best_wns $wns
            set best_desc "run=$run_id seed=$seed place=$place_dir phys=$phys_dir post_phys=$post_phys_dir"
        }

        puts "INFO: Run #$run_id complete: WNS=$wns"
    }
}

# -------------------------------
# Cleanup
# -------------------------------
close $fp

puts "\nINFO: Sweep complete."
puts "INFO: Best WNS=$best_wns ($best_desc)"
puts "INFO: Reports are in ./Reports/"
puts "INFO: CSV file: $csv_file"