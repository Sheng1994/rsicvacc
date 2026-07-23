set repo_dir [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set_param board.repoPaths [list [file join $repo_dir references avnet-bdf]]
set board_parts [get_board_parts -quiet *microzed*]
puts "CODEX_BOARD_PARTS_BEGIN"
foreach item $board_parts { puts $item }
puts "CODEX_BOARD_PARTS_END"
set device_parts [get_parts -quiet xc7z020clg400-1]
puts "CODEX_DEVICE_PARTS_BEGIN"
foreach item $device_parts { puts $item }
puts "CODEX_DEVICE_PARTS_END"
exit
