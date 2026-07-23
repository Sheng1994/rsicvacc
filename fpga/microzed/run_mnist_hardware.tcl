if {$argc != 1} { error "usage: run_mnist_hardware.tcl PLAN_FILE" }

set repo_dir [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
set ps_init [file join $repo_dir build vivado microzed_system \
  microzed_system.gen sources_1 bd microzed_system ip microzed_system_ps7_0 ps7_init.tcl]
set bit_file [file join $repo_dir build vivado microzed_system \
  microzed_system.runs impl_1 microzed_system_wrapper.bit]
set plan_file [file normalize [lindex $argv 0]]
set mmio 0x43C00000
set tile_address 0x00100000

proc read32 {address} { return [mrd -force -value $address] }
proc signed32 {value} {
  set value [expr {$value & 0xffffffff}]
  if {$value >= 0x80000000} { return [expr {$value - 0x100000000}] }
  return $value
}
proc wait_status {address mask limit} {
  for {set i 0} {$i < $limit} {incr i} {
    set status [read32 $address]
    if {$status & 0x4} { error [format "DMA error, status=0x%08x" $status] }
    if {$status & $mask} { return $status }
    after 1
  }
  error [format "Timeout waiting for status mask 0x%x" $mask]
}

set input [open $plan_file r]
set label [string trim [gets $input]]
set biases [split [string trim [gets $input]]]
if {[llength $biases] != 10} { error "plan must contain 10 biases" }
set tiles {}
while {[gets $input line] >= 0} {
  set line [string trim $line]
  if {$line ne ""} { lappend tiles [split $line] }
}
close $input
if {[llength $tiles] != 147} { error "plan must contain 147 tiles" }

connect -url tcp:localhost:3121
targets -set -nocase -filter {name =~ "*APU*"}
rst -system
after 500
source $ps_init
ps7_init
fpga -file $bit_file
ps7_post_config
after 200

set started [clock milliseconds]
set scores $biases
set tile_index 0
foreach fields $tiles {
  if {[llength $fields] != 22} { error "each tile must contain two controls and 20 words" }
  set valid_rows [lindex $fields 0]
  set accumulate [lindex $fields 1]
  if {($tile_index % 49) == 0} {
    mwr -force [expr {$mmio + 0x0c}] $valid_rows
  }
  set address $tile_address
  foreach word [lrange $fields 2 end] {
    mwr -force $address $word
    incr address 4
  }
  mwr -force [expr {$mmio + 0x00}] $tile_address
  mwr -force [expr {$mmio + 0x04}] 0x1
  wait_status [expr {$mmio + 0x08}] 0x2 2000
  set command [expr {0x4 | ($accumulate ? 0x10 : 0)}]
  mwr -force [expr {$mmio + 0x04}] $command
  wait_status [expr {$mmio + 0x08}] 0x10 2000
  if {($tile_index % 49) == 48} {
    set group [expr {$tile_index / 49}]
    for {set row 0} {$row < $valid_rows} {incr row} {
      set raw [signed32 [read32 [expr {$mmio + 0x10 + 4*$row}]]]
      set global_row [expr {$group*4 + $row}]
      lset scores $global_row [expr {$raw + [lindex $biases $global_row]}]
    }
  }
  incr tile_index
}

set prediction 0
for {set i 1} {$i < 10} {incr i} {
  if {[lindex $scores $i] > [lindex $scores $prediction]} { set prediction $i }
}
set mac_count [read32 [expr {$mmio + 0x20}]]
set elapsed [expr {[clock milliseconds] - $started}]
if {$mac_count != 7840} { error "MAC count mismatch: $mac_count" }
puts "CODEX_MNIST_HW_SUCCESS label=$label prediction=$prediction scores=[join $scores ,] mac_count=$mac_count elapsed_ms=$elapsed"
disconnect
exit
