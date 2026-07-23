set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $repo_dir build vivado microzed_riscv_shell]
open_project [file join $build_dir microzed_riscv_shell.xpr]
set_property include_dirs [list [file join $repo_dir references cv32e40x rtl include]] [current_fileset]
set files {}
set flist [open [file join $repo_dir scripts cv32e40x_rtl.f] r]
while {[gets $flist line] >= 0} {
  set line [string trim $line]
  if {$line ne "" && ![string match "+incdir+*" $line]} { lappend files [file join $repo_dir $line] }
}
close $flist
lappend files [file join $repo_dir rtl nn_axi_read_dma.sv] \
  [file join $repo_dir rtl nn_dma_mac_array.sv] [file join $repo_dir rtl nn_dma_mmio.sv] \
  [file join $repo_dir rtl nn_mnist_accel_10x16.sv] \
  [file join $repo_dir fpga common cv32e40x_nn_soc_wrapper.sv] \
  [file join $repo_dir fpga common microzed_riscv_top.sv] \
  [file join $repo_dir build mnist_fpga.mem] [file join $repo_dir build mnist_dma.memh]
add_files -norecurse $files
set_property file_type SystemVerilog [get_files *.sv]
set_property file_type {Memory Initialization Files} [get_files mnist_fpga.mem]
set_property file_type {Memory Initialization Files} [get_files mnist_dma.memh]
set_property verilog_define {XILINX_FPGA} [current_fileset]
set_property top microzed_riscv_top [current_fileset]
update_compile_order -fileset sources_1
reset_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation did not complete" }
open_run impl_1
report_utilization -file [file join $build_dir utilization_impl.rpt]
report_timing_summary -file [file join $build_dir timing_impl.rpt]
report_drc -file [file join $build_dir drc_impl.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $build_dir microzed_riscv_nn.xsa]
puts "CODEX_RISCV_BITSTREAM_SUCCESS"
exit
