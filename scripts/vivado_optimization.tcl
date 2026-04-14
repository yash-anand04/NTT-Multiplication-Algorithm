# ============================================
# Vivado Timing Sweep (FINAL - BATCH SAFE)
# ============================================

if {[llength [get_projects]] == 0} {
    error "No project open."
}

file mkdir Reports

set base_flow     [get_property FLOW [get_runs impl_1]]
set base_strategy [get_property STRATEGY [get_runs impl_1]]

set num_runs 3

set directives {
    {Explore AggressiveExplore}
    {ExtraNetDelay_high AggressiveFanoutOpt}
    {WLDrivenBlockPlacement Explore}
}

set csv_file "Reports/timing_results.csv"
set fp [open $csv_file w]
puts $fp "run_id,run_name,place,phys,wns"
flush $fp

set run_id 0
set best_wns -1e9
set best_desc ""

foreach d $directives {

    set place_dir [lindex $d 0]
    set phys_dir  [lindex $d 1]

    for {set i 1} {$i <= $num_runs} {incr i} {

        incr run_id
        set run_name "impl_sweep_$run_id"

        puts "\nRunning $run_name (Place=$place_dir Phys=$phys_dir)"

        if {[llength [get_runs $run_name]] > 0} {
            delete_run $run_name
        }

        create_run $run_name \
            -parent_run synth_1 \
            -flow $base_flow \
            -strategy $base_strategy

        catch {set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $place_dir [get_runs $run_name]}
        catch {set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs $run_name]}
        catch {set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $phys_dir [get_runs $run_name]}

        launch_runs $run_name -jobs 8
        wait_on_run $run_name

        # -------- FIX: Correct report path --------
        set run_dir [get_property DIRECTORY [get_runs $run_name]]
        set rpt_file "$run_dir/ntt_top_timing_summary_routed.rpt"

        set wns "NA"

        if {[file exists $rpt_file]} {

            puts "Found report: $rpt_file"

            set f [open $rpt_file r]
            while {[gets $f line] >= 0} {
                if {[regexp {WNS\s*[:=]?\s*(-?\d+\.\d+)} $line -> val]} {
                    set wns $val
                    break
                }
            }
            close $f

        } else {
            puts "❌ Report NOT found in $run_dir"
        }

        puts "RESULT: $run_name WNS = $wns"

        puts $fp "$run_id,$run_name,$place_dir,$phys_dir,$wns"
        flush $fp

        if {$wns ne "NA" && $wns > $best_wns} {
            set best_wns $wns
            set best_desc "$run_name (Place=$place_dir Phys=$phys_dir)"
        }
    }
}

close $fp

puts "\n===================================="
puts "SWEEP COMPLETE"
puts "Best WNS = $best_wns"
puts "Best Config = $best_desc"
puts "===================================="