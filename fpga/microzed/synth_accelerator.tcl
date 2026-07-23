set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $repo_dir build vivado microzed_accel]
file mkdir $build_dir

create_project -force microzed_accel $build_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
add_files -norecurse [list \
  [file join $repo_dir rtl nn_axi_read_dma.sv] \
  [file join $repo_dir rtl nn_dma_mac_array.sv] \
  [file join $repo_dir rtl nn_dma_mmio.sv] \
  [file join $repo_dir fpga common nn_accel_axi_wrapper.sv]]
set_property file_type SystemVerilog [get_files *.sv]
set_property verilog_define {XILINX_FPGA} [current_fileset]
update_compile_order -fileset sources_1

synth_design -top nn_accel_axi_wrapper -part xc7z020clg400-1
create_clock -name pl_clk -period 10.000 [get_ports aclk]
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_timing_summary -file [file join $build_dir timing_synth.rpt]
write_checkpoint -force [file join $build_dir nn_accel_synth.dcp]
puts "CODEX_SYNTH_SUCCESS"
exit
