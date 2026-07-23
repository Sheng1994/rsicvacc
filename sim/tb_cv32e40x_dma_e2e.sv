`default_nettype none
module tb_cv32e40x_dma_e2e;
 localparam int WORDS=16384;logic clk_i=0,rst_ni=0,fetch_enable_i=0;
 logic instr_req,instr_gnt,instr_rvalid,instr_err,data_req,data_gnt,data_rvalid,data_err,data_we;
 logic[31:0]instr_addr,instr_rdata,data_addr,data_wdata,data_rdata;logic[3:0]data_be;
 logic[31:0]mem[0:WORDS-1],instr_addr_q,data_rdata_q;logic[63:0]mcycle;
 logic mmio_valid,mnist_test;logic[31:0]mmio_rdata;logic[7:0]mmio_addr;
 logic[31:0]araddr,rdata;logic[7:0]arlen;logic[2:0]arsize;logic[1:0]arburst,rresp;
 logic arvalid,arready,rvalid,rready,rlast,read_active;logic[7:0]beat;logic[31:0]axi_word;int cycles,stall;
 assign instr_gnt=instr_req;assign data_gnt=data_req;assign instr_err=0;assign data_err=0;
 assign instr_rdata=mem[instr_addr_q[15:2]];assign data_rdata=data_rdata_q;
 assign mmio_valid=data_req&&data_gnt&&(data_addr[31:8]==24'h0000f0);assign mmio_addr=data_addr[7:0];
 assign arready=1;assign rvalid=read_active&&(stall%3!=1);assign rdata=mem[axi_word];assign rresp=0;assign rlast=beat==arlen;
 always #5 clk_i=~clk_i;
 cv32e40x_subsystem cpu(.clk_i,.rst_ni,.fetch_enable_i,.instr_req_o(instr_req),.instr_gnt_i(instr_gnt),
  .instr_rvalid_i(instr_rvalid),.instr_addr_o(instr_addr),.instr_rdata_i(instr_rdata),.instr_err_i(instr_err),
  .data_req_o(data_req),.data_gnt_i(data_gnt),.data_rvalid_i(data_rvalid),.data_addr_o(data_addr),
  .data_be_o(data_be),.data_we_o(data_we),.data_wdata_o(data_wdata),.data_rdata_i(data_rdata),.data_err_i(data_err),
  .irq_i(0),.mcycle_o(mcycle),.nn_instruction_count_o(),.nn_dotp4_count_o(),.nn_requant_count_o(),
  .nn_array_mac_count_o(),.nn_trace_valid_o(),.nn_trace_id_o(),.nn_trace_operation_o(),
  .nn_trace_kill_o(),.nn_trace_result_o(),.core_sleep_o());
 nn_dma_mmio dma(.clk_i,.rst_ni,.reg_valid_i(mmio_valid),.reg_write_i(data_we),.reg_addr_i(mmio_addr),
  .reg_wdata_i(data_wdata),.reg_rdata_o(mmio_rdata),.m_axi_araddr_o(araddr),.m_axi_arlen_o(arlen),
  .m_axi_arsize_o(arsize),.m_axi_arburst_o(arburst),.m_axi_arvalid_o(arvalid),.m_axi_arready_i(arready),
  .m_axi_rdata_i(rdata),.m_axi_rresp_i(rresp),.m_axi_rlast_i(rlast),.m_axi_rvalid_i(rvalid),.m_axi_rready_o(rready));
 always_ff @(posedge clk_i)begin
  if(!rst_ni)begin instr_rvalid<=0;data_rvalid<=0;instr_addr_q<=0;data_rdata_q<=0;read_active<=0;beat<=0;axi_word<=0;cycles<=0;stall<=0;end
  else begin cycles<=cycles+1;stall<=stall+1;instr_rvalid<=instr_req;data_rvalid<=data_req;
   if(instr_req)instr_addr_q<=instr_addr;
   if(data_req)begin data_rdata_q<=mmio_valid?mmio_rdata:mem[data_addr[15:2]];
    if(data_we&&!mmio_valid)begin if(data_be[0])mem[data_addr[15:2]][7:0]<=data_wdata[7:0];
     if(data_be[1])mem[data_addr[15:2]][15:8]<=data_wdata[15:8];if(data_be[2])mem[data_addr[15:2]][23:16]<=data_wdata[23:16];
     if(data_be[3])mem[data_addr[15:2]][31:24]<=data_wdata[31:24];end end
   if(arvalid&&arready)begin read_active<=1;beat<=0;axi_word<=araddr>>2;end
   if(rvalid&&rready)begin if(rlast)read_active<=0;else begin beat<=beat+1;axi_word<=axi_word+1;end end
   if(data_req&&data_we&&data_addr==32'h1000)begin
    if(data_wdata!=1)begin
     $display("DEBUG mailbox=%08x metrics=%0d,%0d,%08x,%08x,%0d acc=%0d,%0d,%0d,%0d status=%08x dma_addr=%08x",
      data_wdata,mem[32'h1080>>2],mem[32'h1084>>2],mem[32'h1088>>2],mem[32'h108c>>2],mem[32'h1090>>2],
      $signed(dma.accelerator_i.accum_q[0]),$signed(dma.accelerator_i.accum_q[1]),
      $signed(dma.accelerator_i.accum_q[2]),$signed(dma.accelerator_i.accum_q[3]),mmio_rdata,dma.dma_addr_q);
     $fatal(1,"mailbox fail %08x",data_wdata);end
    if(mnist_test)begin
     if(mem[32'h10a8>>2]!=7||mem[32'h10ac>>2]!=7||mem[32'h10b4>>2]!=7840)$fatal(1,"MNIST metrics mismatch");
     $display("PASS: MNIST image 7 CPU/DMA-array inference agree cpu_cycles=%0d hw_cycles=%0d prediction=%0d mac_slots=%0d",
      mem[32'h10a0>>2],mem[32'h10a4>>2],mem[32'h10ac>>2],mem[32'h10b4>>2]);
    end else begin
     if(mem[32'h1088>>2]!=32'hfe05fc10||mem[32'h108c>>2]!=32'hfe05fc10||mem[32'h1090>>2]!=64)$fatal(1,"result mismatch");
     $display("PASS: CPU->MMIO->AXI DMA->BRAM ping-pong->MAC end-to-end sw_cycles=%0d dma_cycles=%0d speedup=%0d.%02dx",
      mem[32'h1080>>2],mem[32'h1084>>2],mem[32'h1080>>2]/mem[32'h1084>>2],
      (100*mem[32'h1080>>2]/mem[32'h1084>>2])%100);end $finish;end
   if(cycles>(mnist_test?200000:4000))$fatal(1,"timeout");
  end
 end
 initial begin mnist_test=$test$plusargs("MNIST");for(int i=0;i<WORDS;i++)mem[i]=0;
  if(mnist_test)begin
   $readmemh("build/mnist_dma.memh",mem);$readmemh("build/mnist/weights.memh",mem,32'h4000>>2);
   $readmemh("build/mnist/bias.memh",mem,32'h5f00>>2);$readmemh("build/mnist/sample.memh",mem,32'h6000>>2);
  end else $readmemh("build/fc16x4_dma.memh",mem);
  repeat(5)@(posedge clk_i);rst_ni<=1;fetch_enable_i<=1;end
endmodule
`default_nettype wire
