`default_nettype none
module nn_axi_read_dma #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32
) (
  input wire logic clk_i, input wire logic rst_ni,
  input wire logic start_i, input wire logic [ADDR_WIDTH-1:0] base_addr_i,
  input wire logic [7:0] words_minus_one_i,
  input wire logic gather_enable_i,
  input wire logic [ADDR_WIDTH-1:0] image_base_i, weight_base_i,
  input wire logic [7:0] tile_index_i, row_base_i,
  output logic busy_o, output logic done_o, output logic error_o,
  output logic stream_valid_o, input wire logic stream_ready_i,
  output logic [DATA_WIDTH-1:0] stream_data_o, output logic stream_last_o,
  output logic [ADDR_WIDTH-1:0] m_axi_araddr_o,
  output logic [7:0] m_axi_arlen_o, output logic [2:0] m_axi_arsize_o,
  output logic [1:0] m_axi_arburst_o, output logic m_axi_arvalid_o,
  input wire logic m_axi_arready_i,
  input wire logic [DATA_WIDTH-1:0] m_axi_rdata_i, input wire logic [1:0] m_axi_rresp_i,
  input wire logic m_axi_rlast_i, input wire logic m_axi_rvalid_i, output logic m_axi_rready_o
);
  typedef enum logic [1:0] {IDLE, SEND_AR, RECEIVE} state_t;
  state_t state_q;
  logic [7:0] beat_q, length_q;
  logic [ADDR_WIDTH-1:0] address_q;
  function automatic logic [ADDR_WIDTH-1:0] gather_address(input logic [7:0] beat);
    logic [7:0] weight_word, row, block;
    begin
      if (beat < 4) gather_address = image_base_i + tile_index_i*16 + beat*4;
      else begin
        weight_word = beat - 4;
        row = row_base_i + weight_word/4;
        block = weight_word%4;
        gather_address = weight_base_i + row*784 + tile_index_i*16 + block*4;
      end
    end
  endfunction
  assign busy_o = state_q != IDLE;
  assign m_axi_araddr_o = address_q;
  // Gather data is laid out as five naturally contiguous four-word regions:
  // one activation block followed by one block for each output row.  Issue a
  // four-beat burst for each region instead of twenty single-word requests.
  // The accelerator gather format is exactly five four-word regions.  Keep
  // ARLEN stable for the complete transaction as required by AXI.
  assign m_axi_arlen_o = gather_enable_i ? 8'd3 : length_q;
  assign m_axi_arsize_o = 3'($clog2(DATA_WIDTH/8));
  assign m_axi_arburst_o = 2'b01;
  assign m_axi_arvalid_o = state_q == SEND_AR;
  assign stream_valid_o = (state_q == RECEIVE) && m_axi_rvalid_i;
  assign stream_data_o = m_axi_rdata_i;
  assign stream_last_o = beat_q == length_q;
  assign m_axi_rready_o = (state_q == RECEIVE) && stream_ready_i;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q<=IDLE; beat_q<='0; length_q<='0; address_q<='0; done_o<=0; error_o<=0;
    end else begin
      done_o <= 1'b0;
      if (state_q==IDLE && start_i) begin
        address_q<=gather_enable_i ? gather_address(0) : base_addr_i;
        length_q<=words_minus_one_i; beat_q<='0; error_o<=0; state_q<=SEND_AR;
      end else if (state_q==SEND_AR && m_axi_arready_i) begin
        state_q<=RECEIVE;
      end else if (state_q==RECEIVE && m_axi_rvalid_i && m_axi_rready_o) begin
        if (m_axi_rresp_i != 2'b00) error_o<=1'b1;
        if (gather_enable_i) begin
          if (beat_q==length_q) begin
            if (!m_axi_rlast_i) error_o<=1'b1;
            done_o<=1'b1; state_q<=IDLE;
          end else begin
            beat_q<=beat_q+1'b1;
            if (m_axi_rlast_i) begin
              address_q<=gather_address(beat_q+1'b1);
              state_q<=SEND_AR;
            end else if (beat_q[1:0]==2'b11) begin
              // Every gather segment is at most four words, so the fourth
              // accepted response must terminate the burst.
              error_o<=1'b1;
            end
          end
        end else if ((beat_q==length_q) || m_axi_rlast_i) begin
          if ((beat_q!=length_q) || !m_axi_rlast_i) error_o<=1'b1;
          done_o<=1'b1; state_q<=IDLE;
        end else beat_q<=beat_q+1'b1;
      end
    end
  end
endmodule
`default_nettype wire
