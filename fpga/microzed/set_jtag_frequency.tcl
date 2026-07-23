open_hw_manager
connect_hw_server -url localhost:3121
set target [lindex [get_hw_targets -quiet] 0]
current_hw_target $target
set_property PARAM.FREQUENCY 1000000 $target
puts "CODEX_JTAG_FREQUENCY=[get_property PARAM.FREQUENCY $target]"
open_hw_target
foreach device [get_hw_devices -quiet] { puts "CODEX_DEVICE=$device" }
close_hw_target
disconnect_hw_server
close_hw_manager
exit
