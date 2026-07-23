`default_nettype none
module tb_nn_random;
  logic [2:0] operation;
  logic [31:0] rs1, rs2, multiplier, zero_point, result, expected;
  logic [4:0] shift;
  integer fd, count, scanned;
  nn_execution_unit dut(
    .operation_i(operation), .rs1_i(rs1), .rs2_i(rs2),
    .multiplier_i(multiplier), .shift_i(shift), .zero_point_i(zero_point),
    .result_o(result));
  initial begin
    fd = $fopen("build/nn_vectors.txt", "r");
    if (!fd) $fatal(1, "FAIL: cannot open NN vectors");
    count = 0;
    while (!$feof(fd)) begin
      scanned = $fscanf(fd, "%h %h %h %h %h %h %h\n", operation, rs1, rs2,
                        multiplier, shift, zero_point, expected);
      if (scanned == 7) begin
        #1;
        if (result !== expected)
          $fatal(1, "FAIL: vector=%0d op=%0d rs1=%08x rs2=%08x mult=%08x shift=%0d zp=%08x got=%08x expected=%08x",
                 count, operation, rs1, rs2, multiplier, shift, zero_point, result, expected);
        count++;
      end
    end
    $fclose(fd);
    if (count != 5000) $fatal(1, "FAIL: expected 5000 vectors, read %0d", count);
    $display("PASS: 5000 Python-reference NN RTL random vectors");
    $finish;
  end
endmodule
`default_nettype wire
