set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set board_repo [file join $repo_dir references avnet-bdf]
set build_dir [file join $repo_dir build vivado microzed_system]
set_param board.repoPaths [list $board_repo]

create_project -force microzed_system $build_dir \
  -part xc7z020clg400-1
set_property board_part avnet-tria:microzed_7020:part0:1.4 [current_project]
set_property target_language Verilog [current_project]

add_files -norecurse [list \
  [file join $repo_dir rtl nn_axi_read_dma.sv] \
  [file join $repo_dir rtl nn_dma_mac_array.sv] \
  [file join $repo_dir rtl nn_dma_mmio.sv] \
  [file join $repo_dir fpga common nn_accel_axi_wrapper.sv]]
set_property file_type SystemVerilog [get_files *.sv]
set_property verilog_define {XILINX_FPGA} [current_fileset]
update_compile_order -fileset sources_1

create_bd_design microzed_system
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {apply_board_preset "1" make_external "FIXED_IO, DDR"} [get_bd_cells ps7]
set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000}] [get_bd_cells ps7]

create_bd_cell -type module -reference nn_accel_axi_wrapper accel_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* control_ic
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells control_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* dma_ic
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells dma_ic]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* pl_reset

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins control_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins control_ic/M00_AXI] [get_bd_intf_pins accel_0/s_axi]
connect_bd_intf_net [get_bd_intf_pins accel_0/m_axi] [get_bd_intf_pins dma_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_ic/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]

set pl_clk [get_bd_pins ps7/FCLK_CLK0]
connect_bd_net $pl_clk \
  [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins ps7/S_AXI_HP0_ACLK] \
  [get_bd_pins accel_0/aclk] [get_bd_pins pl_reset/slowest_sync_clk] \
  [get_bd_pins control_ic/ACLK] [get_bd_pins control_ic/S00_ACLK] \
  [get_bd_pins control_ic/M00_ACLK] [get_bd_pins dma_ic/ACLK] \
  [get_bd_pins dma_ic/S00_ACLK] [get_bd_pins dma_ic/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins pl_reset/ext_reset_in]
set pl_resetn [get_bd_pins pl_reset/peripheral_aresetn]
connect_bd_net $pl_resetn [get_bd_pins accel_0/aresetn] \
  [get_bd_pins control_ic/ARESETN] [get_bd_pins control_ic/S00_ARESETN] \
  [get_bd_pins control_ic/M00_ARESETN] [get_bd_pins dma_ic/ARESETN] \
  [get_bd_pins dma_ic/S00_ARESETN] [get_bd_pins dma_ic/M00_ARESETN]

assign_bd_address -offset 0x43C00000 -range 4K \
  -target_address_space [get_bd_addr_spaces ps7/Data] \
  [get_bd_addr_segs accel_0/s_axi/reg0]
assign_bd_address -target_address_space [get_bd_addr_spaces accel_0/m_axi] \
  [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM]

validate_bd_design
save_bd_design
set bd_file [get_files microzed_system.bd]
generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_files
set_property top microzed_system_wrapper [current_fileset]
update_compile_order -fileset sources_1

write_bd_tcl -force [file join $build_dir generated_block_design.tcl]
puts "CODEX_BD_SUCCESS"

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  error "synth_1 did not complete"
}
open_run synth_1
report_utilization -file [file join $build_dir system_utilization_synth.rpt]
report_timing_summary -file [file join $build_dir system_timing_synth.rpt]
puts "CODEX_SYSTEM_SYNTH_SUCCESS"
exit
