`default_nettype none

module nn_mac_array #(
  parameter int unsigned ROWS = 4,
  parameter int unsigned K_BLOCKS = 4
) (
  input wire logic clk_i,
  input wire logic rst_ni,
  input wire logic load_activation_i,
  input wire logic load_weight_i,
  input wire logic clear_i,
  input wire logic start_i,
  input wire logic [$clog2(K_BLOCKS)-1:0] block_index_i,
  input wire logic [$clog2(ROWS)-1:0] row_index_i,
  input wire logic [31:0] packed_data_i,
  output logic busy_o,
  output logic done_o,
  output logic [31:0] result_o,
  output logic [63:0] mac_count_o
);
  logic [31:0] activation_mem [0:K_BLOCKS-1];
  logic [31:0] weight_mem [0:ROWS-1][0:K_BLOCKS-1];
  logic signed [31:0] accumulator [0:ROWS-1];
  logic [$clog2(K_BLOCKS)-1:0] block_q;
  logic signed [17:0] lane_sum [0:ROWS-1];

  always_comb begin
    for (int unsigned r = 0; r < ROWS; r++) begin
      lane_sum[r] = '0;
      for (int unsigned lane = 0; lane < 4; lane++) begin
        lane_sum[r] += $signed(activation_mem[block_q][lane*8 +: 8]) *
                       $signed(weight_mem[r][block_q][lane*8 +: 8]);
      end
    end
    result_o = accumulator[row_index_i];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_o <= 1'b0;
      done_o <= 1'b0;
      block_q <= '0;
      mac_count_o <= '0;
      for (int unsigned r = 0; r < ROWS; r++) begin
        accumulator[r] <= '0;
        for (int unsigned b = 0; b < K_BLOCKS; b++) weight_mem[r][b] <= '0;
      end
      for (int unsigned b = 0; b < K_BLOCKS; b++) activation_mem[b] <= '0;
    end else begin
      if (load_activation_i && !busy_o) activation_mem[block_index_i] <= packed_data_i;
      if (load_weight_i && !busy_o) weight_mem[row_index_i][block_index_i] <= packed_data_i;
      if (clear_i && !busy_o) begin
        done_o <= 1'b0;
        mac_count_o <= '0;
        for (int unsigned r = 0; r < ROWS; r++) accumulator[r] <= '0;
      end
      if (start_i && !busy_o) begin
        busy_o <= 1'b1;
        done_o <= 1'b0;
        block_q <= '0;
        for (int unsigned r = 0; r < ROWS; r++) accumulator[r] <= '0;
      end else if (busy_o) begin
        for (int unsigned r = 0; r < ROWS; r++)
          accumulator[r] <= accumulator[r] + {{14{lane_sum[r][17]}}, lane_sum[r]};
        mac_count_o <= mac_count_o + ROWS * 4;
        if (block_q == $clog2(K_BLOCKS)'(K_BLOCKS-1)) begin
          busy_o <= 1'b0;
          done_o <= 1'b1;
        end else begin
          block_q <= block_q + 1'b1;
        end
      end
    end
  end
endmodule

`default_nettype wire
