`default_nettype none

module nn_accel_axi_wrapper #(
  parameter int unsigned ADDR_WIDTH = 32
) (
  input  wire                   aclk,
  input  wire                   aresetn,

  input  wire [7:0]             s_axi_awaddr,
  input  wire                   s_axi_awvalid,
  output logic                  s_axi_awready,
  input  wire [31:0]            s_axi_wdata,
  input  wire [3:0]             s_axi_wstrb,
  input  wire                   s_axi_wvalid,
  output logic                  s_axi_wready,
  output logic [1:0]            s_axi_bresp,
  output logic                  s_axi_bvalid,
  input  wire                   s_axi_bready,
  input  wire [7:0]             s_axi_araddr,
  input  wire                   s_axi_arvalid,
  output logic                  s_axi_arready,
  output logic [31:0]           s_axi_rdata,
  output logic [1:0]            s_axi_rresp,
  output logic                  s_axi_rvalid,
  input  wire                   s_axi_rready,

  output logic [ADDR_WIDTH-1:0] m_axi_awaddr,
  output logic [7:0]            m_axi_awlen,
  output logic [2:0]            m_axi_awsize,
  output logic [1:0]            m_axi_awburst,
  output logic                  m_axi_awvalid,
  input  wire                   m_axi_awready,
  output logic [31:0]           m_axi_wdata,
  output logic [3:0]            m_axi_wstrb,
  output logic                  m_axi_wlast,
  output logic                  m_axi_wvalid,
  input  wire                   m_axi_wready,
  input  wire [1:0]             m_axi_bresp,
  input  wire                   m_axi_bvalid,
  output logic                  m_axi_bready,
  output logic [ADDR_WIDTH-1:0] m_axi_araddr,
  output logic [7:0]            m_axi_arlen,
  output logic [2:0]            m_axi_arsize,
  output logic [1:0]            m_axi_arburst,
  output logic                  m_axi_arvalid,
  input  wire                   m_axi_arready,
  input  wire [31:0]            m_axi_rdata,
  input  wire [1:0]             m_axi_rresp,
  input  wire                   m_axi_rlast,
  input  wire                   m_axi_rvalid,
  output logic                  m_axi_rready
);
  logic aw_pending_q, w_pending_q;
  logic [7:0] awaddr_q;
  logic [31:0] wdata_q;
  logic [3:0] wstrb_q;
  logic reg_write;
  logic [7:0] reg_addr;
  logic [31:0] reg_wdata, reg_rdata;

  assign s_axi_awready = !aw_pending_q && !s_axi_bvalid;
  assign s_axi_wready  = !w_pending_q && !s_axi_bvalid;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_arready = !s_axi_rvalid;
  assign s_axi_rresp   = 2'b00;

  assign reg_write = aw_pending_q && w_pending_q && !s_axi_bvalid;
  assign reg_addr  = reg_write ? awaddr_q : s_axi_araddr;
  assign reg_wdata = wdata_q;

  // This accelerator is read-only on its DMA port. The unused AXI write
  // channels are still exposed and tied inactive so Vivado can infer a
  // complete AXI4 master interface for block-design connection automation.
  assign m_axi_awaddr  = '0;
  assign m_axi_awlen   = '0;
  assign m_axi_awsize  = 3'd2;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awvalid = 1'b0;
  assign m_axi_wdata   = '0;
  assign m_axi_wstrb   = '0;
  assign m_axi_wlast   = 1'b0;
  assign m_axi_wvalid  = 1'b0;
  assign m_axi_bready  = 1'b1;

  nn_dma_mmio #(.ADDR_WIDTH(ADDR_WIDTH)) accelerator_i (
    .clk_i(aclk),
    .rst_ni(aresetn),
    .reg_valid_i(reg_write),
    .reg_write_i(reg_write),
    .reg_addr_i(reg_addr),
    .reg_wdata_i(reg_wdata),
    .reg_rdata_o(reg_rdata),
    .m_axi_araddr_o(m_axi_araddr),
    .m_axi_arlen_o(m_axi_arlen),
    .m_axi_arsize_o(m_axi_arsize),
    .m_axi_arburst_o(m_axi_arburst),
    .m_axi_arvalid_o(m_axi_arvalid),
    .m_axi_arready_i(m_axi_arready),
    .m_axi_rdata_i(m_axi_rdata),
    .m_axi_rresp_i(m_axi_rresp),
    .m_axi_rlast_i(m_axi_rlast),
    .m_axi_rvalid_i(m_axi_rvalid),
    .m_axi_rready_o(m_axi_rready)
  );

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      aw_pending_q <= 1'b0;
      w_pending_q  <= 1'b0;
      awaddr_q     <= '0;
      wdata_q      <= '0;
      wstrb_q      <= '0;
      s_axi_bvalid <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_rdata  <= '0;
    end else begin
      if (s_axi_awready && s_axi_awvalid) begin
        aw_pending_q <= 1'b1;
        awaddr_q <= s_axi_awaddr;
      end
      if (s_axi_wready && s_axi_wvalid) begin
        w_pending_q <= 1'b1;
        wdata_q <= s_axi_wdata;
        wstrb_q <= s_axi_wstrb;
      end
      if (reg_write) begin
        aw_pending_q <= 1'b0;
        w_pending_q <= 1'b0;
        s_axi_bvalid <= 1'b1;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end
      if (s_axi_arready && s_axi_arvalid) begin
        s_axi_rdata <= reg_rdata;
        s_axi_rvalid <= 1'b1;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
      end
    end
  end

  logic unused;
  assign unused = ^{wstrb_q, m_axi_awready, m_axi_wready, m_axi_bresp, m_axi_bvalid};
endmodule

`default_nettype wire
