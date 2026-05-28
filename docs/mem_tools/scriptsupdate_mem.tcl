# ===== 用户配置区 =====
# 可通过 Windows 批处理或命令行环境变量覆盖；未设置时使用默认值。
if {[info exists ::env(BASE_BIT)]} {
    set BASE_BIT $::env(BASE_BIT)
} else {
    set BASE_BIT "cpu_base.bit"
}

if {[info exists ::env(MMI_FILE)]} {
    set MMI_FILE $::env(MMI_FILE)
} else {
    set MMI_FILE "cpu_base.mmi"
}

if {[info exists ::env(MEM_FILE)]} {
    set MEM_FILE $::env(MEM_FILE)
} else {
    set MEM_FILE "mem/test.mem"
}

set timestamp [clock format [clock seconds] -format "%H%M%S"]
if {[info exists ::env(OUT_BIT)]} {
    set OUT_BIT $::env(OUT_BIT)
} else {
    set OUT_BIT "cpu_$timestamp.bit"
}

if {[info exists ::env(PROC_PATH)]} {
    set PROC_PATH $::env(PROC_PATH)
} else {
    set PROC_PATH "my_cpu/u_inst_ram/u_xpm_inst_rom/xpm_memory_base_inst"
}

# ===== 自动执行 =====
puts "=== Running updatemem ==="
puts "BASE_BIT : $BASE_BIT"
puts "MMI_FILE : $MMI_FILE"
puts "MEM_FILE : $MEM_FILE"
puts "OUT_BIT  : $OUT_BIT"
puts "PROC    : $PROC_PATH"

if {![file exists $MEM_FILE]} {
    puts "ERROR: mem file not found: $MEM_FILE"
    exit 1
}

if {![file exists $BASE_BIT]} {
    puts "ERROR: base bit not found: $BASE_BIT"
    exit 1
}

if {![file exists $MMI_FILE]} {
    puts "ERROR: mmi file not found: $MMI_FILE"
    exit 1
}

exec updatemem \
    -force \
    -meminfo $MMI_FILE \
    -data $MEM_FILE \
    -bit $BASE_BIT \
    -proc $PROC_PATH \
    -out $OUT_BIT

puts "=== DONE ==="
puts "Generated: $OUT_BIT"
