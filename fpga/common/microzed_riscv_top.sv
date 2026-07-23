`default_nettype none
module microzed_riscv_top (
  inout wire [14:0] DDR_addr, inout wire [2:0] DDR_ba, inout wire DDR_cas_n,
  inout wire DDR_ck_n, inout wire DDR_ck_p, inout wire DDR_cke, inout wire DDR_cs_n,
  inout wire [3:0] DDR_dm, inout wire [31:0] DDR_dq, inout wire [3:0] DDR_dqs_n,
  inout wire [3:0] DDR_dqs_p, inout wire DDR_odt, inout wire DDR_ras_n,
  inout wire DDR_reset_n, inout wire DDR_we_n, inout wire FIXED_IO_ddr_vrn,
  inout wire FIXED_IO_ddr_vrp, inout wire [53:0] FIXED_IO_mio,
  inout wire FIXED_IO_ps_clk, inout wire FIXED_IO_ps_porb, inout wire FIXED_IO_ps_srstb
);
  wire FCLK_CLK0_0, FCLK_RESET0_N_0;
  wire [31:0] M_AXI_GP0_0_araddr,M_AXI_GP0_0_awaddr,M_AXI_GP0_0_wdata,M_AXI_GP0_0_rdata;
  wire [1:0] M_AXI_GP0_0_arburst,M_AXI_GP0_0_arlock,M_AXI_GP0_0_awburst,
             M_AXI_GP0_0_awlock,M_AXI_GP0_0_bresp,M_AXI_GP0_0_rresp;
  wire [3:0] M_AXI_GP0_0_arcache,M_AXI_GP0_0_arlen,M_AXI_GP0_0_arqos,
             M_AXI_GP0_0_awcache,M_AXI_GP0_0_awlen,M_AXI_GP0_0_awqos,M_AXI_GP0_0_wstrb;
  wire [11:0] M_AXI_GP0_0_arid,M_AXI_GP0_0_awid,M_AXI_GP0_0_bid,M_AXI_GP0_0_rid,M_AXI_GP0_0_wid;
  wire [2:0] M_AXI_GP0_0_arprot,M_AXI_GP0_0_arsize,M_AXI_GP0_0_awprot,M_AXI_GP0_0_awsize;
  wire M_AXI_GP0_0_arready,M_AXI_GP0_0_arvalid,M_AXI_GP0_0_awready,M_AXI_GP0_0_awvalid;
  wire M_AXI_GP0_0_bready,M_AXI_GP0_0_bvalid,M_AXI_GP0_0_rlast,M_AXI_GP0_0_rready;
  wire M_AXI_GP0_0_rvalid,M_AXI_GP0_0_wlast,M_AXI_GP0_0_wready,M_AXI_GP0_0_wvalid;

  microzed_riscv_shell_wrapper ps_shell (.*);

  assign M_AXI_GP0_0_bid = M_AXI_GP0_0_awid;
  assign M_AXI_GP0_0_rid = M_AXI_GP0_0_arid;
  assign M_AXI_GP0_0_rlast = 1'b1;
  wire [31:0] unused_araddr;
  wire [7:0] unused_arlen;
  wire [2:0] unused_arsize;
  wire [1:0] unused_arburst;
  wire unused_arvalid,unused_rready;
  cv32e40x_nn_soc_wrapper riscv_soc (
    .aclk(FCLK_CLK0_0),.aresetn(FCLK_RESET0_N_0),
    .s_axi_awaddr(M_AXI_GP0_0_awaddr[7:0]),.s_axi_awvalid(M_AXI_GP0_0_awvalid),
    .s_axi_awready(M_AXI_GP0_0_awready),.s_axi_wdata(M_AXI_GP0_0_wdata),
    .s_axi_wstrb(M_AXI_GP0_0_wstrb),.s_axi_wvalid(M_AXI_GP0_0_wvalid),
    .s_axi_wready(M_AXI_GP0_0_wready),.s_axi_bresp(M_AXI_GP0_0_bresp),
    .s_axi_bvalid(M_AXI_GP0_0_bvalid),.s_axi_bready(M_AXI_GP0_0_bready),
    .s_axi_araddr(M_AXI_GP0_0_araddr[7:0]),.s_axi_arvalid(M_AXI_GP0_0_arvalid),
    .s_axi_arready(M_AXI_GP0_0_arready),.s_axi_rdata(M_AXI_GP0_0_rdata),
    .s_axi_rresp(M_AXI_GP0_0_rresp),.s_axi_rvalid(M_AXI_GP0_0_rvalid),
    .s_axi_rready(M_AXI_GP0_0_rready),
    .m_axi_araddr(unused_araddr),.m_axi_arlen(unused_arlen),.m_axi_arsize(unused_arsize),
    .m_axi_arburst(unused_arburst),.m_axi_arvalid(unused_arvalid),.m_axi_arready(1'b0),
    .m_axi_rdata('0),.m_axi_rresp('0),.m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),
    .m_axi_rready(unused_rready));
  wire unused = ^{M_AXI_GP0_0_arcache,M_AXI_GP0_0_arlen,M_AXI_GP0_0_arlock,
    M_AXI_GP0_0_arprot,M_AXI_GP0_0_arqos,M_AXI_GP0_0_arsize,M_AXI_GP0_0_awburst,
    M_AXI_GP0_0_awcache,M_AXI_GP0_0_awlen,M_AXI_GP0_0_awlock,M_AXI_GP0_0_awprot,
    M_AXI_GP0_0_awqos,M_AXI_GP0_0_awsize,M_AXI_GP0_0_wid,M_AXI_GP0_0_wlast,
    unused_araddr,unused_arlen,unused_arsize,unused_arburst,unused_arvalid,unused_rready};
endmodule
`default_nettype wire
