set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set board_repo [file join $repo_dir references avnet-bdf]
set build_dir [file join $repo_dir build vivado microzed_riscv_shell]
set_param board.repoPaths [list $board_repo]
create_project -force microzed_riscv_shell $build_dir -part xc7z020clg400-1
set_property board_part avnet-tria:microzed_7020:part0:1.4 [current_project]
create_bd_design microzed_riscv_shell
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {apply_board_preset "1" make_external "FIXED_IO, DDR"} [get_bd_cells ps7]
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {20.0}] [get_bd_cells ps7]
make_bd_intf_pins_external [get_bd_intf_pins ps7/M_AXI_GP0]
make_bd_pins_external [get_bd_pins ps7/FCLK_CLK0]
make_bd_pins_external [get_bd_pins ps7/FCLK_RESET0_N]
set_property CONFIG.FREQ_HZ 20000000 [get_bd_intf_ports M_AXI_GP0_0]
set_property CONFIG.ASSOCIATED_BUSIF M_AXI_GP0_0 [get_bd_ports FCLK_CLK0_0]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
validate_bd_design
save_bd_design
set bd_file [get_files microzed_riscv_shell.bd]
generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper_files
puts "CODEX_PS_SHELL_SUCCESS wrapper=$wrapper_files"
exit
