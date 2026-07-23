`default_nettype none
module nn_dma_mmio #(
  parameter int unsigned ADDR_WIDTH=32
) (
  input wire logic clk_i, input wire logic rst_ni,
  input wire logic reg_valid_i, input wire logic reg_write_i,
  input wire logic [7:0] reg_addr_i, input wire logic [31:0] reg_wdata_i,
  output logic [31:0] reg_rdata_o,
  output logic [ADDR_WIDTH-1:0] m_axi_araddr_o, output logic [7:0] m_axi_arlen_o,
  output logic [2:0] m_axi_arsize_o, output logic [1:0] m_axi_arburst_o,
  output logic m_axi_arvalid_o, input wire logic m_axi_arready_i,
  input wire logic [31:0] m_axi_rdata_i, input wire logic [1:0] m_axi_rresp_i,
  input wire logic m_axi_rlast_i, input wire logic m_axi_rvalid_i, output logic m_axi_rready_o
);
  logic [31:0] dma_addr_q;
  logic [31:0] image_base_q, weight_base_q;
  logic [7:0] tile_index_q, row_base_q;
  logic gather_enable_q;
  logic dma_start, dma_bank, compute_start, compute_bank, compute_accumulate;
  logic [2:0] valid_rows_q;
  logic [7:0] tile_count_q, auto_tile_q;
  typedef enum logic [2:0] {AUTO_IDLE, AUTO_ISSUE_FIRST, AUTO_WAIT_FIRST,
                            AUTO_ISSUE_PAIR, AUTO_WAIT_PAIR,
                            AUTO_ISSUE_LAST, AUTO_WAIT_LAST} auto_state_t;
  auto_state_t auto_state_q;
  logic auto_done_sticky_q, auto_dma_seen_q, auto_compute_seen_q;
  logic [2:0] cache_valid_q;
  logic cache_hit_q, clear_mac_count;
  logic activation_cache_valid_q,activation_cache_hit_q;
  logic [1:0] cache_group;
  logic [7:0] cache_tag_q [0:2];
  logic [1:0] cache_replace_q;
  logic cache_lookup_hit;
  logic [1:0] cache_lookup_slot;
  logic [7:0] compute_tile;
  logic dma_busy,dma_done,dma_error,compute_busy,compute_done,b0_ready,b1_ready;
  logic dma_done_sticky_q,compute_done_sticky_q,error_sticky_q;
  logic [1:0] result_index;
  logic [31:0] result;
  logic [63:0] mac_count;
  assign result_index=reg_addr_i[3:2];
  always_comb begin
    cache_lookup_hit=1'b0;cache_lookup_slot=cache_replace_q;
    if(cache_valid_q[0]&&cache_tag_q[0]=={2'b0,row_base_q[7:2]}) begin
      cache_lookup_hit=1'b1;cache_lookup_slot=0;
    end else if(cache_valid_q[1]&&cache_tag_q[1]=={2'b0,row_base_q[7:2]}) begin
      cache_lookup_hit=1'b1;cache_lookup_slot=1;
    end else if(cache_valid_q[2]&&cache_tag_q[2]=={2'b0,row_base_q[7:2]}) begin
      cache_lookup_hit=1'b1;cache_lookup_slot=2;
    end
  end
  nn_dma_mac_array accelerator_i(
    .clk_i,.rst_ni,.dma_start_i(dma_start),.dma_addr_i(dma_addr_q),.dma_bank_i(dma_bank),
    .gather_enable_i(gather_enable_q),.cache_hit_i(cache_hit_q),
    .activation_cache_hit_i(activation_cache_hit_q),.cache_group_i(cache_group),
    .image_base_i(image_base_q),.weight_base_i(weight_base_q),
    .tile_index_i(tile_index_q),.compute_tile_i(compute_tile),.row_base_i(row_base_q),
    .compute_start_i(compute_start),.compute_bank_i(compute_bank),.compute_accumulate_i(compute_accumulate),
    .clear_mac_count_i(clear_mac_count),
    .valid_rows_i(valid_rows_q),.result_index_i(result_index),
    .dma_busy_o(dma_busy),.dma_done_o(dma_done),.dma_error_o(dma_error),
    .compute_busy_o(compute_busy),.compute_done_o(compute_done),
    .bank0_ready_o(b0_ready),.bank1_ready_o(b1_ready),.result_o(result),.mac_count_o(mac_count),
    .m_axi_araddr_o,.m_axi_arlen_o,.m_axi_arsize_o,.m_axi_arburst_o,.m_axi_arvalid_o,
    .m_axi_arready_i,.m_axi_rdata_i,.m_axi_rresp_i,.m_axi_rlast_i,.m_axi_rvalid_i,.m_axi_rready_o);
  always_comb begin
    dma_start=1'b0;compute_start=1'b0;clear_mac_count=1'b0;
    compute_tile=tile_index_q;
    dma_bank=reg_wdata_i[1];compute_bank=reg_wdata_i[3];
    compute_accumulate=reg_wdata_i[4];
    if(auto_state_q==AUTO_ISSUE_FIRST) begin
      dma_start=1'b1;dma_bank=1'b0;
    end else if(auto_state_q==AUTO_ISSUE_PAIR) begin
      dma_start=1'b1;dma_bank=auto_tile_q[0];
      compute_start=1'b1;compute_bank=~auto_tile_q[0];compute_accumulate=(auto_tile_q!=1);
      compute_tile=auto_tile_q-1'b1;
    end else if(auto_state_q==AUTO_ISSUE_LAST) begin
      compute_start=1'b1;compute_bank=auto_tile_q[0];
      compute_accumulate=(tile_count_q!=1);
      compute_tile=auto_tile_q;
    end else if(reg_valid_i&&reg_write_i&&(reg_addr_i==8'h04)) begin
      dma_start=reg_wdata_i[0];compute_start=reg_wdata_i[2];
    end
    if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h04&&reg_wdata_i[5]&&
       auto_state_q==AUTO_IDLE&&row_base_q==0)
      clear_mac_count=1'b1;
    case(reg_addr_i)
      8'h00:reg_rdata_o=dma_addr_q;
      8'h08:reg_rdata_o={23'd0,auto_done_sticky_q,(auto_state_q!=AUTO_IDLE),
                         b1_ready,b0_ready,compute_done_sticky_q,compute_busy,
                         error_sticky_q,dma_done_sticky_q,dma_busy};
      8'h0c:reg_rdata_o={29'd0,valid_rows_q};
      8'h10,8'h14,8'h18,8'h1c:reg_rdata_o=result;
      8'h20:reg_rdata_o=mac_count[31:0];
      8'h24:reg_rdata_o=mac_count[63:32];
      8'h28:reg_rdata_o=image_base_q;
      8'h2c:reg_rdata_o=weight_base_q;
      8'h30:reg_rdata_o={24'd0,tile_index_q};
      8'h34:reg_rdata_o={24'd0,row_base_q};
      8'h38:reg_rdata_o={31'd0,gather_enable_q};
      8'h3c:reg_rdata_o={24'd0,tile_count_q};
      8'h40:reg_rdata_o={26'd0,activation_cache_hit_q,activation_cache_valid_q,
                         cache_hit_q,cache_valid_q};
      8'h48:reg_rdata_o={24'd0,cache_tag_q[0]};
      8'h4c:reg_rdata_o={24'd0,cache_tag_q[1]};
      8'h50:reg_rdata_o={24'd0,cache_tag_q[2]};
      8'h54:reg_rdata_o={28'd0,cache_replace_q,2'd3};
      default:reg_rdata_o='0;
    endcase
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      dma_addr_q<='0;valid_rows_q<=3'd4;dma_done_sticky_q<=0;compute_done_sticky_q<=0;error_sticky_q<=0;
      image_base_q<=32'h6000;weight_base_q<=32'h4000;tile_index_q<='0;row_base_q<='0;gather_enable_q<=0;
      tile_count_q<=8'd49;auto_tile_q<='0;auto_state_q<=AUTO_IDLE;
      auto_done_sticky_q<=0;auto_dma_seen_q<=0;auto_compute_seen_q<=0;
      cache_valid_q<='0;cache_hit_q<=0;cache_group<=0;
      activation_cache_valid_q<=0;activation_cache_hit_q<=0;
      cache_tag_q[0]<=0;cache_tag_q[1]<=0;cache_tag_q[2]<=0;cache_replace_q<=0;
    end
    else begin
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h00) dma_addr_q<=reg_wdata_i;
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h0c)
        valid_rows_q <= (reg_wdata_i[2:0] >= 1 && reg_wdata_i[2:0] <= 4) ? reg_wdata_i[2:0] : 3'd4;
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h28) image_base_q<=reg_wdata_i;
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h2c) weight_base_q<=reg_wdata_i;
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h30) tile_index_q<=reg_wdata_i[7:0];
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h34) row_base_q<=reg_wdata_i[7:0];
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h38) gather_enable_q<=reg_wdata_i[0];
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h3c)
        tile_count_q<=(reg_wdata_i[7:0]==0)?8'd1:reg_wdata_i[7:0];
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h04&&reg_wdata_i[5]&&auto_state_q==AUTO_IDLE) begin
        auto_tile_q<=0;tile_index_q<=0;auto_state_q<=AUTO_ISSUE_FIRST;
        cache_group<=cache_lookup_slot;cache_hit_q<=cache_lookup_hit;
        activation_cache_hit_q<=(row_base_q!=0)&&activation_cache_valid_q;
        if(row_base_q==0) activation_cache_valid_q<=0;
        if(!cache_lookup_hit) begin
          cache_valid_q[cache_lookup_slot]<=1'b0;
          cache_tag_q[cache_lookup_slot]<={2'b0,row_base_q[7:2]};
          cache_replace_q<=(cache_lookup_slot==2)?0:cache_lookup_slot+1'b1;
        end
        auto_done_sticky_q<=0;auto_dma_seen_q<=0;auto_compute_seen_q<=0;
        dma_done_sticky_q<=0;compute_done_sticky_q<=0;error_sticky_q<=0;
      end
      case(auto_state_q)
        AUTO_IDLE: ;
        AUTO_ISSUE_FIRST: auto_state_q<=AUTO_WAIT_FIRST;
        AUTO_WAIT_FIRST: if(dma_done) begin
          if(tile_count_q==1) auto_state_q<=AUTO_ISSUE_LAST;
          else begin auto_tile_q<=1;tile_index_q<=1;auto_state_q<=AUTO_ISSUE_PAIR;end
        end
        AUTO_ISSUE_PAIR: begin
          auto_dma_seen_q<=0;auto_compute_seen_q<=0;auto_state_q<=AUTO_WAIT_PAIR;
        end
        AUTO_WAIT_PAIR: begin
          if(dma_done) auto_dma_seen_q<=1;
          if(compute_done) auto_compute_seen_q<=1;
          if((auto_dma_seen_q||dma_done)&&(auto_compute_seen_q||compute_done)) begin
            if(auto_tile_q==tile_count_q-1'b1) auto_state_q<=AUTO_ISSUE_LAST;
            else begin
              auto_tile_q<=auto_tile_q+1'b1;tile_index_q<=auto_tile_q+1'b1;
              auto_state_q<=AUTO_ISSUE_PAIR;
            end
          end
        end
        AUTO_ISSUE_LAST: auto_state_q<=AUTO_WAIT_LAST;
        AUTO_WAIT_LAST: if(compute_done) begin
          auto_state_q<=AUTO_IDLE;auto_done_sticky_q<=1;
          if(cache_group<3) cache_valid_q[cache_group]<=1'b1;
          if(row_base_q==0) activation_cache_valid_q<=1'b1;
        end
        default:auto_state_q<=AUTO_IDLE;
      endcase
      if(reg_valid_i&&reg_write_i&&reg_addr_i==8'h44) cache_valid_q<=cache_valid_q&~reg_wdata_i[2:0];
      if(dma_start) begin dma_done_sticky_q<=0;error_sticky_q<=0;end
      if(compute_start) compute_done_sticky_q<=0;
      if(dma_done) dma_done_sticky_q<=1;
      if(compute_done) compute_done_sticky_q<=1;
      if(dma_error) error_sticky_q<=1;
    end
  end
endmodule
`default_nettype wire
