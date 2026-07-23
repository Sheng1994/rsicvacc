`default_nettype none

// Safe CV-X-IF placeholder used before the NN coprocessor is integrated.
// Every instruction is rejected, so the core retains its illegal-instruction
// behavior for unknown/custom encodings.
module xif_null_coprocessor (
  cv32e40x_if_xif.coproc_compressed   xif_compressed_if,
  cv32e40x_if_xif.coproc_issue        xif_issue_if,
  cv32e40x_if_xif.coproc_commit       xif_commit_if,
  cv32e40x_if_xif.coproc_mem          xif_mem_if,
  cv32e40x_if_xif.coproc_mem_result   xif_mem_result_if,
  cv32e40x_if_xif.coproc_result       xif_result_if
);
  always_comb begin
    xif_compressed_if.compressed_ready = 1'b1;
    xif_compressed_if.compressed_resp  = '0;

    xif_issue_if.issue_ready = 1'b1;
    xif_issue_if.issue_resp  = '0;

    xif_mem_if.mem_valid = 1'b0;
    xif_mem_if.mem_req   = '0;

    xif_result_if.result_valid = 1'b0;
    xif_result_if.result       = '0;
  end

  logic unused_inputs;
  always_comb begin
    unused_inputs = xif_compressed_if.compressed_valid |
                    xif_issue_if.issue_valid |
                    xif_commit_if.commit_valid |
                    xif_mem_if.mem_ready |
                    xif_mem_result_if.mem_result_valid |
                    xif_result_if.result_ready;
  end
endmodule

`default_nettype wire
