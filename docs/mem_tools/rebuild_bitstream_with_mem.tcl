# Rebuild Vivado bitstream with XPM memory initialization files.
# Required environment variables:
#   PROJECT_XPR
#   INST_MEM_FILE
#   DATA_MEM_FILE
#   OUT_BIT

proc require_env {name} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        puts "ERROR: missing environment variable $name"
        exit 1
    }
    return $::env($name)
}

set PROJECT_XPR   [require_env PROJECT_XPR]
set INST_MEM_FILE [require_env INST_MEM_FILE]
set DATA_MEM_FILE [require_env DATA_MEM_FILE]
set OUT_BIT       [require_env OUT_BIT]

set PROJECT_XPR   [file normalize $PROJECT_XPR]
set INST_MEM_FILE [file normalize $INST_MEM_FILE]
set DATA_MEM_FILE [file normalize $DATA_MEM_FILE]
set OUT_BIT       [file normalize $OUT_BIT]
regsub -all {\\} $PROJECT_XPR {/} PROJECT_XPR
regsub -all {\\} $INST_MEM_FILE {/} INST_MEM_FILE
regsub -all {\\} $DATA_MEM_FILE {/} DATA_MEM_FILE
regsub -all {\\} $OUT_BIT {/} OUT_BIT

set PROJECT_DIR [file dirname $PROJECT_XPR]
set REPORT_FILE [file join $PROJECT_DIR "riscv-graduation.runs" "impl_1" "my_cpu_timing_summary_rebuild_with_mem.rpt"]
set RUN_BIT     [file join $PROJECT_DIR "riscv-graduation.runs" "impl_1" "my_cpu.bit"]

puts "=== Rebuild bitstream with memory initialization ==="
puts "PROJECT_XPR   : $PROJECT_XPR"
puts "INST_MEM_FILE : $INST_MEM_FILE"
puts "DATA_MEM_FILE : $DATA_MEM_FILE"
puts "OUT_BIT       : $OUT_BIT"

if {![file exists $PROJECT_XPR]} {
    puts "ERROR: project not found: $PROJECT_XPR"
    exit 1
}
if {![file exists $INST_MEM_FILE]} {
    puts "ERROR: instruction mem not found: $INST_MEM_FILE"
    exit 1
}
if {![file exists $DATA_MEM_FILE]} {
    puts "ERROR: data mem not found: $DATA_MEM_FILE"
    exit 1
}

open_project $PROJECT_XPR
set XDC_FILE [file join $PROJECT_DIR "riscv-graduation.srcs" "constrs_1" "new" "my_cpu.xdc"]
if {[file exists $XDC_FILE]} {
    if {[llength [get_files -quiet $XDC_FILE]] == 0} {
        add_files -fileset constrs_1 $XDC_FILE
    }
    set_property used_in_synthesis true [get_files $XDC_FILE]
    set_property used_in_implementation true [get_files $XDC_FILE]
    puts "XDC_FILE      : $XDC_FILE"
} else {
    puts "WARNING: XDC file not found: $XDC_FILE"
}
set_property top my_cpu [current_fileset]
set_property generic [list \
    INST_MEM_FILE=$INST_MEM_FILE \
    DATA_MEM_FILE=$DATA_MEM_FILE \
] [current_fileset]
update_compile_order -fileset sources_1
update_compile_order -fileset constrs_1

set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraPostPlacementOpt [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 STATUS: $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    puts "ERROR: impl_1 did not complete successfully."
    exit 1
}

open_run impl_1
report_timing_summary -max_paths 20 -report_unconstrained -file $REPORT_FILE

if {![file exists $RUN_BIT]} {
    puts "ERROR: run bitstream not found: $RUN_BIT"
    exit 1
}

file mkdir [file dirname $OUT_BIT]
file copy -force $RUN_BIT $OUT_BIT

puts "=== DONE ==="
puts "Generated: $OUT_BIT"
puts "Timing report: $REPORT_FILE"
exit
