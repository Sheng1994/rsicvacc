`timescale 1ns/1ps
module tb_nn_mac_array;
  logic clk=0, rst_n=0, load_a=0, load_w=0, clear=0, start=0;
  logic [1:0] block_index, row_index;
  logic [31:0] data, result;
  logic busy, done;
  logic [63:0] mac_count;
  always #5 clk = ~clk;
  nn_mac_array dut(.*,.clk_i(clk),.rst_ni(rst_n),.load_activation_i(load_a),
    .load_weight_i(load_w),.clear_i(clear),.start_i(start),.block_index_i(block_index),
    .row_index_i(row_index),.packed_data_i(data),.busy_o(busy),.done_o(done),
    .result_o(result),.mac_count_o(mac_count));
  task tick; @(posedge clk); #1; endtask
  initial begin
    block_index=0; row_index=0; data=0; repeat(2) tick(); rst_n=1;
    // activations 1..16, packed four signed INT8 values per word
    for (int b=0;b<4;b++) begin
      block_index=b; data={8'(b*4+4),8'(b*4+3),8'(b*4+2),8'(b*4+1)}; load_a=1; tick(); load_a=0;
    end
    // row r contains a constant signed weight r+1
    for (int r=0;r<4;r++) for (int b=0;b<4;b++) begin
      row_index=r; block_index=b; data={4{8'(r+1)}}; load_w=1; tick(); load_w=0;
    end
    start=1; tick(); start=0;
    while(!done) tick();
    for (int r=0;r<4;r++) begin
      row_index=r; #1;
      if ($signed(result) != 136*(r+1)) $fatal(1,"row %0d got %0d",r,$signed(result));
    end
    if(mac_count!=64) $fatal(1,"mac_count=%0d",mac_count);
    $display("PASS: 4x4 SIMD MAC array 16 MAC/cycle, 64 MAC in 4 compute cycles");
    $finish;
  end
endmodule
