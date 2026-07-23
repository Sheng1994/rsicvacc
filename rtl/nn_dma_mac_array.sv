`default_nettype none
module nn_weight_cache #(
  parameter int unsigned DEPTH=588,
  parameter int unsigned AW=$clog2(DEPTH)
)(
  input wire logic clk_i,
  input wire logic wr_en_i,input wire logic [1:0] wr_row_i,
  input wire logic [AW-1:0] wr_addr_i,input wire logic [31:0] wr_data_i,
  input wire logic [AW-1:0] rd_addr_i,
  output logic [31:0] rd_row0_o,rd_row1_o,rd_row2_o,rd_row3_o
);
  (* ram_style="block" *) logic [31:0] row0[0:DEPTH-1];
  (* ram_style="block" *) logic [31:0] row1[0:DEPTH-1];
  (* ram_style="block" *) logic [31:0] row2[0:DEPTH-1];
  (* ram_style="block" *) logic [31:0] row3[0:DEPTH-1];
  always_ff @(posedge clk_i) begin
    if(wr_en_i&&wr_row_i==0) row0[wr_addr_i]<=wr_data_i;
    if(wr_en_i&&wr_row_i==1) row1[wr_addr_i]<=wr_data_i;
    if(wr_en_i&&wr_row_i==2) row2[wr_addr_i]<=wr_data_i;
    if(wr_en_i&&wr_row_i==3) row3[wr_addr_i]<=wr_data_i;
    rd_row0_o<=row0[rd_addr_i];rd_row1_o<=row1[rd_addr_i];
    rd_row2_o<=row2[rd_addr_i];rd_row3_o<=row3[rd_addr_i];
  end
endmodule

module nn_activation_cache(
  input wire logic clk_i,input wire logic wr_en_i,
  input wire logic [7:0] wr_addr_i,input wire logic [31:0] wr_data_i,
  input wire logic [7:0] rd_addr_i,output logic [31:0] rd_data_o
);
  (* ram_style="block" *) logic [31:0] mem[0:195];
  always_ff @(posedge clk_i) begin
    if(wr_en_i) mem[wr_addr_i]<=wr_data_i;
    rd_data_o<=mem[rd_addr_i];
  end
endmodule

module nn_dma_mac_array #(
  parameter int unsigned ADDR_WIDTH=32,
  parameter int unsigned ROWS=4,
  parameter int unsigned K_BLOCKS=4
) (
  input wire logic clk_i, input wire logic rst_ni,
  input wire logic dma_start_i, input wire logic [ADDR_WIDTH-1:0] dma_addr_i, input wire logic dma_bank_i,
  input wire logic gather_enable_i,
  input wire logic cache_hit_i, input wire logic activation_cache_hit_i,
  input wire logic [1:0] cache_group_i,
  input wire logic [ADDR_WIDTH-1:0] image_base_i, weight_base_i,
  input wire logic [7:0] tile_index_i, compute_tile_i, row_base_i,
  input wire logic compute_start_i, input wire logic compute_bank_i, input wire logic compute_accumulate_i,
  input wire logic clear_mac_count_i,
  input wire logic [$clog2(ROWS):0] valid_rows_i,
  input wire logic [1:0] result_index_i,
  output logic dma_busy_o, output logic dma_done_o, output logic dma_error_o,
  output logic compute_busy_o, output logic compute_done_o,
  output logic bank0_ready_o, output logic bank1_ready_o,
  output logic [31:0] result_o, output logic [63:0] mac_count_o,
  output logic [ADDR_WIDTH-1:0] m_axi_araddr_o, output logic [7:0] m_axi_arlen_o,
  output logic [2:0] m_axi_arsize_o, output logic [1:0] m_axi_arburst_o,
  output logic m_axi_arvalid_o, input wire logic m_axi_arready_i,
  input wire logic [31:0] m_axi_rdata_i, input wire logic [1:0] m_axi_rresp_i,
  input wire logic m_axi_rlast_i, input wire logic m_axi_rvalid_i, output logic m_axi_rready_o
);
  localparam int unsigned WORDS = K_BLOCKS + ROWS*K_BLOCKS;
  localparam int unsigned WORD_INDEX_WIDTH = $clog2(WORDS);
  // One activation bank and one independent weight bank per output row give
  // the array the five parallel reads it needs without creating a multi-port
  // RAM that cannot map to FPGA block memories.
  (* ram_style = "block" *) logic [31:0] activation_mem [0:1][0:K_BLOCKS-1];
  (* ram_style = "block" *) logic [31:0] weight_mem [0:1][0:ROWS-1][0:K_BLOCKS-1];
  // Four row words are packed into one 128-bit cache line.  The three default
  // groups hold all 10x784 MNIST weights (unused lanes in group two are masked).
  localparam int unsigned CACHE_GROUP_WORDS=49*K_BLOCKS;
  localparam int unsigned CACHE_DEPTH=3*CACHE_GROUP_WORDS;
  // Four independent 32-bit BRAM banks form the 128-bit read datapath.  This
  // organization gives one weight word per output row every cycle without a
  // multi-port memory or a large LUT mux.
  logic bank_ready_q[0:1], dma_bank_q, compute_bank_q;
  logic cache_hit_compute_q;
  logic activation_cache_hit_compute_q;
  logic [1:0] cache_group_compute_q;
  logic [7:0] cache_tile_compute_q;
  logic product_valid_q, issue_done_q;
  logic [WORD_INDEX_WIDTH-1:0] write_index_q;
  logic stream_valid, stream_ready, stream_last;
  logic [31:0] stream_data;
  logic [$clog2(K_BLOCKS)-1:0] block_q;
  (* use_dsp = "no" *) logic signed [31:0] accum_q[0:ROWS-1];
  (* use_dsp = "no" *) logic signed [16:0] pair_sum[0:ROWS-1][0:1];
  (* use_dsp = "no" *) logic signed [17:0] lane_sum[0:ROWS-1];
  logic signed [15:0] lane_product[0:ROWS-1][0:3];
  logic [31:0] activation_q;
  logic [31:0] weight_q[0:ROWS-1];
  logic [$clog2(CACHE_DEPTH)-1:0] cache_write_addr,cache_read_addr;
  logic cache_write_enable;
  logic [1:0] cache_write_row;
  logic [31:0] cache_rdata[0:3],weight_operand[0:3];
  logic [31:0] activation_cache_rdata,activation_operand;
  logic [7:0] activation_cache_write_addr,activation_cache_read_addr;
  logic activation_cache_write_enable;
  logic dma_busy_int,dma_done_int,dma_error_int,fake_dma_done_q;
  always_comb begin
    cache_write_addr=$clog2(CACHE_DEPTH)'(cache_group_i*CACHE_GROUP_WORDS+
                     tile_index_i*K_BLOCKS+(write_index_q-WORD_INDEX_WIDTH'(K_BLOCKS))%K_BLOCKS);
    cache_read_addr=compute_start_i ?
      $clog2(CACHE_DEPTH)'(cache_group_i*CACHE_GROUP_WORDS+compute_tile_i*K_BLOCKS) :
      $clog2(CACHE_DEPTH)'(cache_group_compute_q*CACHE_GROUP_WORDS+
                          cache_tile_compute_q*K_BLOCKS+block_q+1'b1);
    cache_write_enable=stream_valid&&stream_ready&&
                       write_index_q>=WORD_INDEX_WIDTH'(K_BLOCKS)&&
                       cache_group_i<3&&tile_index_i<49;
    cache_write_row=2'((write_index_q-WORD_INDEX_WIDTH'(K_BLOCKS))/K_BLOCKS);
    for(int r=0;r<4;r++) weight_operand[r]=cache_hit_compute_q?cache_rdata[r]:weight_q[r];
    activation_cache_write_addr=tile_index_i*K_BLOCKS+write_index_q[1:0];
    activation_cache_read_addr=compute_start_i ? compute_tile_i*K_BLOCKS :
      cache_tile_compute_q*K_BLOCKS+block_q+1'b1;
    activation_cache_write_enable=stream_valid&&stream_ready&&
                                  write_index_q<WORD_INDEX_WIDTH'(K_BLOCKS);
    activation_operand=activation_cache_hit_compute_q?activation_cache_rdata:activation_q;
  end
  nn_weight_cache #(.DEPTH(CACHE_DEPTH)) weight_cache_i(
    .clk_i,.wr_en_i(cache_write_enable),.wr_row_i(cache_write_row),
    .wr_addr_i(cache_write_addr),.wr_data_i(stream_data),.rd_addr_i(cache_read_addr),
    .rd_row0_o(cache_rdata[0]),.rd_row1_o(cache_rdata[1]),
    .rd_row2_o(cache_rdata[2]),.rd_row3_o(cache_rdata[3]));
  nn_activation_cache activation_cache_i(
    .clk_i,.wr_en_i(activation_cache_write_enable),.wr_addr_i(activation_cache_write_addr),
    .wr_data_i(stream_data),.rd_addr_i(activation_cache_read_addr),.rd_data_o(activation_cache_rdata));

  for (genvar gr=0; gr<ROWS; gr++) begin : gen_mul_row
    for (genvar gl=0; gl<4; gl++) begin : gen_mul_lane
`ifdef XILINX_FPGA
      logic [17:0] lhs_extended, rhs_extended;
      logic [35:0] product_extended;
      assign lhs_extended = {{10{activation_operand[gl*8+7]}}, activation_operand[gl*8+:8]};
      assign rhs_extended = {{10{weight_operand[gr][gl*8+7]}}, weight_operand[gr][gl*8+:8]};
      MULT_MACRO #(
        .DEVICE("7SERIES"), .LATENCY(1), .WIDTH_A(18), .WIDTH_B(18)
      ) dsp_multiplier_i (
        .P(product_extended), .A(lhs_extended), .B(rhs_extended),
        .CE(1'b1), .CLK(clk_i), .RST(1'b0)
      );
      assign lane_product[gr][gl] = product_extended[15:0];
`else
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) lane_product[gr][gl] <= '0;
        else lane_product[gr][gl] <=
          $signed(activation_operand[gl*8+:8]) * $signed(weight_operand[gr][gl*8+:8]);
      end
`endif
    end
  end
  assign bank0_ready_o=bank_ready_q[0]; assign bank1_ready_o=bank_ready_q[1];
  assign stream_ready = !(compute_busy_o && (dma_bank_q==compute_bank_q));
  assign result_o=accum_q[result_index_i];
  always_comb begin
    for(int unsigned r=0;r<ROWS;r++) begin
      pair_sum[r][0] = $signed(lane_product[r][0]) + $signed(lane_product[r][1]);
      pair_sum[r][1] = $signed(lane_product[r][2]) + $signed(lane_product[r][3]);
      lane_sum[r] = (r < valid_rows_i) ?
                    ($signed({pair_sum[r][0][16], pair_sum[r][0]}) +
                     $signed({pair_sum[r][1][16], pair_sum[r][1]})) : 18'sd0;
    end
  end
  nn_axi_read_dma dma_i(
    .clk_i,.rst_ni,.start_i(dma_start_i && !(activation_cache_hit_i&&cache_hit_i) &&
                            !(compute_busy_o && dma_bank_i==compute_bank_q)),
    .base_addr_i(dma_addr_i),.words_minus_one_i(cache_hit_i?8'(K_BLOCKS-1):8'(WORDS-1)),
    .gather_enable_i,.image_base_i,.weight_base_i,.tile_index_i,.row_base_i,
    .busy_o(dma_busy_int),.done_o(dma_done_int),.error_o(dma_error_int),
    .stream_valid_o(stream_valid),.stream_ready_i(stream_ready),
    .stream_data_o(stream_data),.stream_last_o(stream_last),
    .m_axi_araddr_o,.m_axi_arlen_o,.m_axi_arsize_o,.m_axi_arburst_o,.m_axi_arvalid_o,
    .m_axi_arready_i,.m_axi_rdata_i,.m_axi_rresp_i,.m_axi_rlast_i,.m_axi_rvalid_i,.m_axi_rready_o);
  assign dma_busy_o=dma_busy_int;
  assign dma_done_o=dma_done_int|fake_dma_done_q;
  assign dma_error_o=dma_error_int;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      dma_bank_q<=0; compute_bank_q<=0; write_index_q<='0;
      cache_hit_compute_q<=0;activation_cache_hit_compute_q<=0;
      cache_group_compute_q<=0;cache_tile_compute_q<=0;fake_dma_done_q<=0;
      compute_busy_o<=0; compute_done_o<=0; block_q<='0; mac_count_o<='0;
      product_valid_q<=0; issue_done_q<=0;
      activation_q<='0;
      bank_ready_q[0]<=0; bank_ready_q[1]<=0;
      for(int r=0;r<ROWS;r++) begin accum_q[r]<='0;weight_q[r]<='0;end
    end else begin
      compute_done_o<=0;
      fake_dma_done_q<=0;
      if(dma_start_i && activation_cache_hit_i && cache_hit_i && !compute_busy_o) begin
        dma_bank_q<=dma_bank_i;bank_ready_q[dma_bank_i]<=1;fake_dma_done_q<=1;
      end else if(dma_start_i && !dma_busy_o && !(compute_busy_o && dma_bank_i==compute_bank_q)) begin
        dma_bank_q<=dma_bank_i; write_index_q<='0; bank_ready_q[dma_bank_i]<=0;
      end
      if(stream_valid && stream_ready) begin
        if(write_index_q < WORD_INDEX_WIDTH'(K_BLOCKS))
          activation_mem[dma_bank_q][$clog2(K_BLOCKS)'(write_index_q)]<=stream_data;
        else begin
          weight_mem[dma_bank_q]
                    [$clog2(ROWS)'((write_index_q-WORD_INDEX_WIDTH'(K_BLOCKS))/K_BLOCKS)]
                    [$clog2(K_BLOCKS)'((write_index_q-WORD_INDEX_WIDTH'(K_BLOCKS))%K_BLOCKS)]<=stream_data;
        end
        write_index_q<=write_index_q+1'b1;
        if(stream_last) bank_ready_q[dma_bank_q]<=1;
      end
      if(dma_error_int) bank_ready_q[dma_bank_q]<=0;
      if(compute_start_i && !compute_busy_o && bank_ready_q[compute_bank_i]) begin
        compute_bank_q<=compute_bank_i; compute_busy_o<=1; block_q<='0;
        cache_hit_compute_q<=cache_hit_i;activation_cache_hit_compute_q<=activation_cache_hit_i;
        cache_group_compute_q<=cache_group_i;
        cache_tile_compute_q<=compute_tile_i;
        product_valid_q<=0; issue_done_q<=0;
        bank_ready_q[compute_bank_i]<=0;
        activation_q<=activation_mem[compute_bank_i][0];
        if(!cache_hit_i) for(int r=0;r<ROWS;r++) weight_q[r]<=weight_mem[compute_bank_i][r][0];
        if(!compute_accumulate_i) for(int r=0;r<ROWS;r++) accum_q[r]<='0;
      end else if(compute_busy_o) begin
        if(product_valid_q) begin
          for(int r=0;r<ROWS;r++) accum_q[r]<=accum_q[r]+{{14{lane_sum[r][17]}},lane_sum[r]};
          mac_count_o<=mac_count_o+valid_rows_i*4;
        end
        if(!issue_done_q) begin
          product_valid_q<=1;
          if(block_q==$clog2(K_BLOCKS)'(K_BLOCKS-1)) issue_done_q<=1;
          else begin
            block_q<=block_q+1'b1;
            activation_q<=activation_mem[compute_bank_q][block_q+1'b1];
            if(!cache_hit_compute_q)
              for(int r=0;r<ROWS;r++) weight_q[r]<=weight_mem[compute_bank_q][r][block_q+1'b1];
          end
        end else begin
          compute_busy_o<=0; compute_done_o<=1;
          product_valid_q<=0; issue_done_q<=0;
        end
      end
      if(clear_mac_count_i) mac_count_o<='0;
    end
  end
endmodule
`default_nettype wire
