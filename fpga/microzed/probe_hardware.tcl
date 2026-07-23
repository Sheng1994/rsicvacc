open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -quiet]
puts "CODEX_HW_TARGETS_BEGIN"
foreach target $targets { puts $target }
puts "CODEX_HW_TARGETS_END"
foreach target $targets {
  current_hw_target $target
  if {[catch {open_hw_target} message]} {
    puts "CODEX_TARGET_OPEN_ERROR=$target:$message"
    continue
  }
  puts "CODEX_HW_DEVICES_BEGIN"
  foreach device [get_hw_devices -quiet] {
    puts "DEVICE=$device PART=[get_property -quiet PART $device] IDCODE=[get_property -quiet IDCODE $device]"
  }
  puts "CODEX_HW_DEVICES_END"
  close_hw_target
}
disconnect_hw_server
close_hw_manager
exit
