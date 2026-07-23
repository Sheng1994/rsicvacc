set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set bit_file [file join $repo_dir build vivado microzed_system \
  microzed_system.runs impl_1 microzed_system_wrapper.bit]
if {![file exists $bit_file]} {
  error "Bitstream not found: $bit_file"
}

open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -quiet]
if {[llength $targets] != 1} {
  error "Expected one JTAG target, found [llength $targets]: $targets"
}
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices -quiet -filter {PART == "xc7z020"}]
if {[llength $devices] != 1} {
  error "Expected one xc7z020, found: [get_hw_devices -quiet]"
}
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
puts "CODEX_PROGRAM_BEGIN device=$device bitstream=$bit_file"
program_hw_devices $device
refresh_hw_device -update_hw_probes false $device
puts "CODEX_PROGRAM_FILE=[get_property PROGRAM.FILE $device]"
puts "CODEX_PROGRAM_SUCCESS device=$device"
close_hw_target
disconnect_hw_server
close_hw_manager
exit
