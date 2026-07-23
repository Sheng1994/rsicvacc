set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set build_dir [file join $repo_dir build vivado interface_probe]
create_project -force interface_probe $build_dir -part xc7z020clg400-1
add_files -norecurse [list \
  [file join $repo_dir rtl nn_axi_read_dma.sv] \
  [file join $repo_dir rtl nn_dma_mac_array.sv] \
  [file join $repo_dir rtl nn_dma_mmio.sv] \
  [file join $repo_dir fpga common nn_accel_axi_wrapper.sv]]
set_property file_type SystemVerilog [get_files *.sv]
set_property verilog_define {XILINX_FPGA} [current_fileset]
update_compile_order -fileset sources_1
create_bd_design interface_probe
create_bd_cell -type module -reference nn_accel_axi_wrapper accel_0
puts "CODEX_INTERFACES_BEGIN"
foreach item [get_bd_intf_pins -of_objects [get_bd_cells accel_0]] { puts $item }
puts "CODEX_INTERFACES_END"
puts "CODEX_PINS_BEGIN"
foreach item [get_bd_pins -of_objects [get_bd_cells accel_0]] { puts $item }
puts "CODEX_PINS_END"
exit
