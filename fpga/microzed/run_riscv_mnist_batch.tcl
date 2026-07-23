if {$argc < 1 || $argc > 2} { error "usage: run_riscv_mnist_batch.tcl BATCH_FILE ?program?" }

set repo_dir [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
set build_dir [file join $repo_dir build vivado microzed_riscv_shell]
set ps_init [file join $build_dir microzed_riscv_shell.gen sources_1 bd microzed_riscv_shell \
  ip microzed_riscv_shell_ps7_0 ps7_init.tcl]
set bit_file [file join $build_dir microzed_riscv_shell.runs impl_1 microzed_riscv_top.bit]
set batch_file [file normalize [lindex $argv 0]]
set do_program [expr {$argc == 2 && [lindex $argv 1] eq "program"}]
set base 0x43C00000

proc read32 {address} { return [mrd -force -value $address] }
proc signed32 {value} {
  set value [expr {$value & 0xffffffff}]
  if {$value >= 0x80000000} { return [expr {$value - 0x100000000}] }
  return $value
}

connect -url tcp:localhost:3121
targets -set -nocase -filter {name =~ "*APU*"}
if {$do_program} {
  rst -system; after 500
  source $ps_init; ps7_init
  fpga -file $bit_file; ps7_post_config; after 200
}

set input [open $batch_file r]
set processed 0
set correct 0
set wall_start [clock milliseconds]
while {[gets $input line] >= 0} {
  set fields [split [string trim $line]]
  if {[llength $fields] == 0} { continue }
  if {[llength $fields] != 198} { error "batch row must contain index, label and 196 image words" }
  set index [lindex $fields 0]
  set label [lindex $fields 1]

  # Hold the RISC-V subsystem in reset while PS writes through BRAM port B.
  mwr -force [expr {$base + 0x80}] 1
  after 1
  mwr -force [expr {$base + 0x84}] 0x17ff
  mwr -force [expr {$base + 0x88}] $label
  mwr -force [expr {$base + 0x84}] 0x1800
  foreach word [lrange $fields 2 end] { mwr -force [expr {$base + 0x88}] $word }
  mwr -force [expr {$base + 0x80}] 0

  set mailbox 0
  for {set retry 0} {$retry < 5000} {incr retry} {
    set mailbox [read32 $base]
    if {$mailbox != 0} { break }
    after 1
  }
  if {$mailbox != 1} { error [format "sample %d failed mailbox=0x%08x" $index $mailbox] }
  set prediction [read32 [expr {$base + 0x0c}]]
  set observed_label [read32 [expr {$base + 0x10}]]
  set macs [read32 [expr {$base + 0x14}]]
  set cpu_cycles [read32 [expr {$base + 0x18}]]
  set accel_cycles [read32 [expr {$base + 0x1c}]]
  set total_cycles [read32 [expr {$base + 0x90}]]
  set scores {}
  for {set digit 0} {$digit < 10} {incr digit} {
    lappend scores [signed32 [read32 [expr {$base + 0x40 + 4*$digit}]]]
  }
  incr processed
  if {$prediction == $observed_label} { incr correct }
  set elapsed [expr {[clock milliseconds] - $wall_start}]
  puts [format "CODEX_BATCH_RESULT index=%d label=%d prediction=%d correct=%d scores=%s macs=%d cpu_cycles=%d accel_cycles=%d total_cycles=%d processed=%d correct_total=%d elapsed_ms=%d" \
    $index $observed_label $prediction [expr {$prediction == $observed_label}] [join $scores ,] \
    $macs $cpu_cycles $accel_cycles $total_cycles $processed $correct $elapsed]
  flush stdout
}
close $input
puts "CODEX_BATCH_DONE processed=$processed correct=$correct elapsed_ms=[expr {[clock milliseconds]-$wall_start}]"
disconnect
exit
