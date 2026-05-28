# project2 clean migration package

This folder contains the reusable inputs from `project2` for creating a new Vivado project in another workspace.

## Recommended Vivado project settings

- Part: `xc7k325tffg900-2`
- Top module: `my_cpu`
- Source language: SystemVerilog
- Keep the new Vivado project outside old generated directories.
- Regenerate IP outputs in the new project instead of copying old `.runs`, `.cache`, `.gen`, `.sim`, `.ip_user_files`, or `.dcp` products.

## Folder contents

- `rtl/`
  - Synthesizable CPU and SoC source.
  - Add both `rtl/cpu_top` and `rtl/my_cpu` as source/include directories.
- `constraints/my_cpu.xdc`
  - Board pin and clock constraints copied from the old Vivado source set.
- `ip/`
  - `PLL.xci`
  - `divider.xci`
  - `multiplier.xci`
  - Add these IP files to the new project, then let Vivado regenerate output products.
- `board_tests/`
  - Current board program images and CoreMark/test sources.
- `board_test_legacy/`
  - Older board images kept for reference.
- `test/`
  - Simulation testbenches and hex images.
- `docs/`
  - Performance counter notes, XDC reference, and memory update helper notes.
- `scripts/`
  - COE/memory update helper scripts copied from the original project.

## Quick project creation flow

From Vivado Tcl console, after opening or creating the new project in this folder:

```tcl
set origin_dir [file normalize [pwd]]
set_property target_language SystemVerilog [current_project]

add_files -norecurse [glob -nocomplain "$origin_dir/rtl/cpu_top/*.sv" "$origin_dir/rtl/cpu_top/*.svh"]
add_files -norecurse [glob -nocomplain "$origin_dir/rtl/my_cpu/*.sv" "$origin_dir/rtl/my_cpu/*.svh"]
set_property include_dirs [list "$origin_dir/rtl/cpu_top" "$origin_dir/rtl/my_cpu"] [current_fileset]

add_files -fileset constrs_1 "$origin_dir/constraints/my_cpu.xdc"
add_files -norecurse [glob -nocomplain "$origin_dir/ip/*.xci"]
set_property top my_cpu [current_fileset]
update_compile_order -fileset sources_1
```

You can also source `scripts/create_vivado_project.tcl` from the directory that should contain the new `.xpr`.

## Notes for lower-frequency optimization work

- The existing PLL IP currently comes from the old project. If you lower the CPU clock, regenerate or reconfigure `ip/PLL.xci` in the new project.
- Keep test images under `board_tests/` or `test/hex/`; update `INST_MEM_FILE` and `DATA_MEM_FILE*` parameters or Vivado memory init settings as needed.
- The old incremental checkpoint `my_cpu.dcp` was intentionally not migrated, because it can tie the new workspace to old synthesis state.

