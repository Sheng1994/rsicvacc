connect -url tcp:localhost:3121
puts "CODEX_TARGET_TREE_BEGIN"
targets
puts "CODEX_TARGET_TREE_END"
puts "CODEX_TARGET_PROPERTIES_BEGIN"
foreach target [targets -nocase -filter {name != ""}] {
  puts "TARGET=$target"
  catch {puts [targets -target-properties $target]}
}
puts "CODEX_TARGET_PROPERTIES_END"
puts "CODEX_JTAG_TARGETS_BEGIN"
jtag targets
puts "CODEX_JTAG_TARGETS_END"
disconnect
exit
