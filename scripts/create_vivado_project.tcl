# Create a new Vivado project for the migrated project2 sources.
# Run from the migration package root:
#   vivado -mode batch -source scripts/create_vivado_project.tcl

set origin_dir [file normalize [file join [file dirname [info script]] ".."]]
set project_dir [file join $origin_dir "vivado_project"]
set project_name "riscv-graduation-migrated"
set part_name "xc7k325tffg900-2"

create_project $project_name $project_dir -part $part_name -force
set_property target_language SystemVerilog [current_project]

add_files -norecurse [glob -nocomplain "$origin_dir/rtl/cpu_top/*.sv" "$origin_dir/rtl/cpu_top/*.svh"]
add_files -norecurse [glob -nocomplain "$origin_dir/rtl/my_cpu/*.sv" "$origin_dir/rtl/my_cpu/*.svh"]
set_property include_dirs [list "$origin_dir/rtl/cpu_top" "$origin_dir/rtl/my_cpu"] [current_fileset]

add_files -fileset constrs_1 "$origin_dir/constraints/my_cpu.xdc"
add_files -norecurse [glob -nocomplain "$origin_dir/ip/*.xci"]

set_property top my_cpu [current_fileset]
update_compile_order -fileset sources_1

puts "Created $project_name at $project_dir"
puts "Next: regenerate IP output products, adjust PLL frequency if needed, then run synthesis."
