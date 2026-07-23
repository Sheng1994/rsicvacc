`default_nettype none
module cv32e40x_nn_bd_shim (
  input wire aclk, input wire aresetn,
  input wire [7:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
  input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid,
  output wire s_axi_wready, output wire [1:0] s_axi_bresp, output wire s_axi_bvalid,
  input wire s_axi_bready, input wire [7:0] s_axi_araddr, input wire s_axi_arvalid,
  output wire s_axi_arready, output wire [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp,
  output wire s_axi_rvalid, input wire s_axi_rready,
  output wire [31:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
  output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst,
  output wire m_axi_arvalid, input wire m_axi_arready, input wire [31:0] m_axi_rdata,
  input wire [1:0] m_axi_rresp, input wire m_axi_rlast, input wire m_axi_rvalid,
  output wire m_axi_rready
);
  cv32e40x_nn_soc_wrapper impl (.*);
endmodule
`default_nettype wire
