set repo_dir [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
set build_dir [file join $repo_dir build vivado microzed_riscv_shell]
set ps_init [file join $build_dir microzed_riscv_shell.gen sources_1 bd microzed_riscv_shell ip microzed_riscv_shell_ps7_0 ps7_init.tcl]
set bit_file [file join $build_dir microzed_riscv_shell.runs impl_1 microzed_riscv_top.bit]
set base 0x43C00000
proc read32 {address} { return [mrd -force -value $address] }
connect -url tcp:localhost:3121
targets -set -nocase -filter {name =~ "*APU*"}
rst -system; after 500
source $ps_init; ps7_init
fpga -file $bit_file; ps7_post_config; after 200
set mailbox 0
for {set i 0} {$i < 5000} {incr i} {
  set mailbox [read32 $base]
  if {$mailbox != 0} { break }
  after 1
}
set prediction [read32 [expr {$base+0x0c}]]
set label [read32 [expr {$base+0x10}]]
set macs [read32 [expr {$base+0x14}]]
set cpu_cycles [read32 [expr {$base+0x18}]]
set accel_cycles [read32 [expr {$base+0x1c}]]
if {$mailbox != 1 || $prediction != 7 || $label != 7 || $macs != 7840} {
  error [format "RISC-V MNIST failed mailbox=0x%08x prediction=%d label=%d macs=%d" $mailbox $prediction $label $macs]
}
puts "CODEX_RISCV_MNIST_SUCCESS prediction=$prediction label=$label mac_count=$macs cpu_cycles=$cpu_cycles accel_cycles=$accel_cycles"
disconnect
exit
