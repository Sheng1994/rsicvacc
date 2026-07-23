set repo_dir [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
set ps_init [file join $repo_dir build vivado microzed_system \
  microzed_system.gen sources_1 bd microzed_system ip microzed_system_ps7_0 ps7_init.tcl]
if {![file exists $ps_init]} { error "Missing PS init script: $ps_init" }
set bit_file [file join $repo_dir build vivado microzed_system \
  microzed_system.runs impl_1 microzed_system_wrapper.bit]
if {![file exists $bit_file]} { error "Missing bitstream: $bit_file" }

connect -url tcp:localhost:3121
puts "CODEX_TARGETS_BEGIN"
targets
puts "CODEX_TARGETS_END"
targets -set -nocase -filter {name =~ "*APU*"}
rst -system
after 1000
source $ps_init
ps7_init
fpga -file $bit_file
ps7_post_config
after 500

puts "CODEX_MMIO_BEGIN"
puts "DMA_ADDR=[mrd -force -value 0x43C00000]"
puts "STATUS=[mrd -force -value 0x43C00008]"
puts "VALID_ROWS=[mrd -force -value 0x43C0000C]"
puts "RESULT0=[mrd -force -value 0x43C00010]"
puts "MAC_COUNT_LO=[mrd -force -value 0x43C00020]"
puts "MAC_COUNT_HI=[mrd -force -value 0x43C00024]"
puts "CODEX_MMIO_END"
disconnect
exit
