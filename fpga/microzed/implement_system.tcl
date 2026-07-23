set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
set board_repo [file join $repo_dir references avnet-bdf]
set build_dir [file join $repo_dir build vivado microzed_system]
set_param board.repoPaths [list $board_repo]

open_project [file join $build_dir microzed_system.xpr]
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  error "impl_1 did not complete"
}
open_run impl_1
report_utilization -file [file join $build_dir system_utilization_impl.rpt]
report_timing_summary -file [file join $build_dir system_timing_impl.rpt]
report_drc -file [file join $build_dir system_drc_impl.rpt]
write_hw_platform -fixed -include_bit -force \
  [file join $build_dir microzed_nn_accel.xsa]
puts "CODEX_IMPLEMENTATION_SUCCESS"
exit
