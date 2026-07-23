`default_nettype none
module nn_cache128 #(
  parameter int unsigned DEPTH=49, AW=$clog2(DEPTH)
)(
  input wire logic clk_i,input wire logic wr_en_i,input wire logic [1:0] wr_word_i,
  input wire logic [AW-1:0] wr_addr_i,input wire logic [31:0] wr_data_i,
  input wire logic [AW-1:0] rd_addr_i,output logic [127:0] rd_data_o
);
  (* ram_style="block" *) logic [127:0] mem[0:DEPTH-1];
  always_ff @(posedge clk_i) begin
    if(wr_en_i) mem[wr_addr_i][32*wr_word_i+:32]<=wr_data_i;
    rd_data_o<=mem[rd_addr_i];
  end
endmodule

module nn_mnist_accel_10x16(
  input wire logic clk_i,input wire logic rst_ni,
  input wire logic reg_valid_i,input wire logic reg_write_i,
  input wire logic [7:0] reg_addr_i,input wire logic [31:0] reg_wdata_i,
  output logic [31:0] reg_rdata_o,
  output logic [31:0] m_axi_araddr_o,output logic [7:0] m_axi_arlen_o,
  output logic [2:0] m_axi_arsize_o,output logic [1:0] m_axi_arburst_o,
  output logic m_axi_arvalid_o,input wire logic m_axi_arready_i,
  input wire logic [31:0] m_axi_rdata_i,input wire logic [1:0] m_axi_rresp_i,
  input wire logic m_axi_rlast_i,input wire logic m_axi_rvalid_i,output logic m_axi_rready_o
);
  localparam int ROWS=10,TILES=49,BLOCKS=4,WORDS_COLD=4+ROWS*BLOCKS;
  typedef enum logic[3:0] {IDLE,DMA_ISSUE,DMA_WAIT,CACHE_READ,CACHE_WAIT,
                           PRODUCT_ISSUE,PRODUCT_WAIT,ACCUMULATE,NEXT_TILE,DONE} state_t;
  state_t state_q;
  logic [31:0] image_base_q,weight_base_q;
  logic [5:0] tile_q;
  logic [5:0] stream_word_q;
  logic weight_valid_q,done_q,error_q;
  logic dma_start,dma_busy,dma_done,dma_error;
  logic stream_valid,stream_ready,stream_last;
  logic [31:0] stream_data;
  logic [127:0] activation_data,weight_data[0:ROWS-1];
  logic signed [31:0] accum_q[0:ROWS-1];
  logic signed [15:0] product[0:ROWS-1][0:15];
  logic signed [20:0] product_sum[0:ROWS-1];
  logic [63:0] mac_count_q;
  logic activation_wr;
  logic [1:0] activation_wr_word,weight_wr_word;
  logic [3:0] weight_wr_row;
  logic weight_wr;

  assign dma_start=state_q==DMA_ISSUE;
  assign stream_ready=1'b1;
  assign activation_wr=stream_valid&&stream_word_q<4;
  assign activation_wr_word=stream_word_q[1:0];
  assign weight_wr=stream_valid&&stream_word_q>=4;
  assign weight_wr_row=4'((stream_word_q-4)/4);
  assign weight_wr_word=(stream_word_q-4)%4;

  nn_cache128 #(.DEPTH(TILES)) activation_cache_i(
    .clk_i,.wr_en_i(activation_wr),.wr_word_i(activation_wr_word),
    .wr_addr_i(tile_q),.wr_data_i(stream_data),.rd_addr_i(tile_q),.rd_data_o(activation_data));
  for(genvar r=0;r<ROWS;r++) begin:gen_weight_cache
    nn_cache128 #(.DEPTH(TILES)) cache_i(
      .clk_i,.wr_en_i(weight_wr&&weight_wr_row==r),.wr_word_i(weight_wr_word),
      .wr_addr_i(tile_q),.wr_data_i(stream_data),.rd_addr_i(tile_q),.rd_data_o(weight_data[r]));
  end

  for(genvar r=0;r<ROWS;r++) begin:gen_row
    always_comb begin
      product_sum[r]='0;
      for(int l=0;l<16;l++) product_sum[r]+=$signed(product[r][l]);
    end
    for(genvar l=0;l<16;l++) begin:gen_lane
`ifdef XILINX_FPGA
      logic [17:0] a,b;logic [35:0] p;
      assign a={{10{activation_data[8*l+7]}},activation_data[8*l+:8]};
      assign b={{10{weight_data[r][8*l+7]}},weight_data[r][8*l+:8]};
      MULT_MACRO #(.DEVICE("7SERIES"),.LATENCY(1),.WIDTH_A(18),.WIDTH_B(18)) mul_i(
        .P(p),.A(a),.B(b),.CE(1'b1),.CLK(clk_i),.RST(1'b0));
      assign product[r][l]=p[15:0];
`else
      always_ff @(posedge clk_i) product[r][l]<=
        $signed(activation_data[8*l+:8])*$signed(weight_data[r][8*l+:8]);
`endif
    end
  end

  nn_axi_read_dma dma_i(
    .clk_i,.rst_ni,.start_i(dma_start),.base_addr_i('0),
    .words_minus_one_i(weight_valid_q?8'd3:8'(WORDS_COLD-1)),.gather_enable_i(1'b1),
    .image_base_i(image_base_q),.weight_base_i(weight_base_q),.tile_index_i({2'b0,tile_q}),.row_base_i(8'd0),
    .busy_o(dma_busy),.done_o(dma_done),.error_o(dma_error),
    .stream_valid_o(stream_valid),.stream_ready_i(stream_ready),.stream_data_o(stream_data),.stream_last_o(stream_last),
    .m_axi_araddr_o,.m_axi_arlen_o,.m_axi_arsize_o,.m_axi_arburst_o,.m_axi_arvalid_o,
    .m_axi_arready_i,.m_axi_rdata_i,.m_axi_rresp_i,.m_axi_rlast_i,.m_axi_rvalid_i,.m_axi_rready_o);

  always_comb begin
    reg_rdata_o='0;
    case(reg_addr_i)
      8'h08:reg_rdata_o={22'd0,weight_valid_q,done_q,(state_q!=IDLE),6'd0,error_q};
      8'h20:reg_rdata_o=mac_count_q[31:0];
      8'h24:reg_rdata_o=mac_count_q[63:32];
      8'h28:reg_rdata_o=image_base_q;
      8'h2c:reg_rdata_o=weight_base_q;
      8'h40:reg_rdata_o={31'd0,weight_valid_q};
      8'h60,8'h64,8'h68,8'h6c,8'h70,8'h74,8'h78,8'h7c,8'h80,8'h84:
        reg_rdata_o=accum_q[(reg_addr_i-8'h60)>>2];
      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      state_q<=IDLE;image_base_q<=32'h6000;weight_base_q<=32'h4000;tile_q<=0;
      stream_word_q<=0;weight_valid_q<=0;done_q<=0;error_q<=0;mac_count_q<=0;
      for(int r=0;r<ROWS;r++) accum_q[r]<=0;
    end else begin
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h28) image_base_q<=reg_wdata_i;
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h2c) weight_base_q<=reg_wdata_i;
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h44&&reg_wdata_i[0]) weight_valid_q<=0;
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h04&&reg_wdata_i[6]&&state_q==IDLE) begin
        tile_q<=0;done_q<=0;error_q<=0;mac_count_q<=0;state_q<=DMA_ISSUE;
        for(int r=0;r<ROWS;r++) accum_q[r]<=0;
      end
      case(state_q)
        IDLE:;
        DMA_ISSUE:begin stream_word_q<=0;state_q<=DMA_WAIT;end
        DMA_WAIT:begin
          if(stream_valid) stream_word_q<=stream_word_q+1'b1;
          if(dma_error) begin error_q<=1;state_q<=DONE;end
          else if(dma_done) state_q<=CACHE_READ;
        end
        CACHE_READ:state_q<=CACHE_WAIT;
        CACHE_WAIT:state_q<=PRODUCT_ISSUE;
        PRODUCT_ISSUE:state_q<=PRODUCT_WAIT;
        PRODUCT_WAIT:state_q<=ACCUMULATE;
        ACCUMULATE:begin
          for(int r=0;r<ROWS;r++) accum_q[r]<=accum_q[r]+{{11{product_sum[r][20]}},product_sum[r]};
          mac_count_q<=mac_count_q+160;state_q<=NEXT_TILE;
        end
        NEXT_TILE:begin
          if(tile_q==TILES-1) begin weight_valid_q<=1;state_q<=DONE;end
          else begin tile_q<=tile_q+1'b1;state_q<=DMA_ISSUE;end
        end
        DONE:begin done_q<=1;state_q<=IDLE;end
        default:state_q<=IDLE;
      endcase
    end
  end
  logic unused;assign unused=^{dma_busy,stream_last};
endmodule
`default_nettype wire
