set repo_dir [file normalize [file join [file dirname [file normalize [info script]]] ../..]]
set ps_init [file join $repo_dir build vivado microzed_system \
  microzed_system.gen sources_1 bd microzed_system ip microzed_system_ps7_0 ps7_init.tcl]
set bit_file [file join $repo_dir build vivado microzed_system \
  microzed_system.runs impl_1 microzed_system_wrapper.bit]
set mmio 0x43C00000
set tile_address 0x00100000
set tile_words {
  0x1903f90c 0xfe0408f0 0x0106f513 0x07f70efb
  0x0103ff02 0x010002fe 0xfd0102ff 0x03fe0102
  0xff0102fd 0x0103fe02 0x0102ff02 0xff0103fe
  0x03fe0101 0x02ff0001 0x02fd0103 0x0102fe01
  0xfe02fd02 0xff010301 0x03ff0200 0xfe0201fd
}

proc read32 {address} { return [mrd -force -value $address] }
proc wait_status {address mask limit} {
  for {set i 0} {$i < $limit} {incr i} {
    set status [read32 $address]
    if {$status & 0x4} { error [format "DMA error, status=0x%08x" $status] }
    if {$status & $mask} { return $status }
    after 1
  }
  error [format "Timeout waiting for status mask 0x%x" $mask]
}

connect -url tcp:localhost:3121
targets -set -nocase -filter {name =~ "*APU*"}
rst -system
after 500
source $ps_init
ps7_init
fpga -file $bit_file
ps7_post_config
after 200

set address $tile_address
foreach word $tile_words {
  mwr -force $address $word
  incr address 4
}
set address $tile_address
foreach expected $tile_words {
  set actual [read32 $address]
  if {$actual != $expected} {
    error [format "DDR readback mismatch at 0x%08x: got 0x%08x expected 0x%08x" \
      $address $actual $expected]
  }
  incr address 4
}
puts "CODEX_DDR_READBACK_SUCCESS words=[llength $tile_words]"

mwr -force [expr {$mmio + 0x00}] $tile_address
mwr -force [expr {$mmio + 0x04}] 0x00000001
set dma_status [wait_status [expr {$mmio + 0x08}] 0x2 2000]
puts [format "CODEX_DMA_SUCCESS status=0x%08x" $dma_status]

mwr -force [expr {$mmio + 0x04}] 0x00000004
set compute_status [wait_status [expr {$mmio + 0x08}] 0x10 2000]
set expected_results {116 0xfffffff4 36 0xfffffff3}
set actual_results {}
for {set index 0} {$index < 4} {incr index} {
  lappend actual_results [read32 [expr {$mmio + 0x10 + 4*$index}]]
}
for {set index 0} {$index < 4} {incr index} {
  set actual [lindex $actual_results $index]
  set expected [lindex $expected_results $index]
  if {$actual != $expected} {
    error [format "Result %d mismatch: got 0x%08x expected 0x%08x" $index $actual $expected]
  }
}
set mac_count [read32 [expr {$mmio + 0x20}]]
if {$mac_count != 64} { error "MAC count mismatch: $mac_count" }
puts [format "CODEX_FC_HARDWARE_SUCCESS status=0x%08x results=%s mac_count=%d" \
  $compute_status $actual_results $mac_count]
disconnect
exit
