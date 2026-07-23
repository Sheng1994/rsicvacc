`default_nettype none
module tb_fpga_riscv_mnist;
  int unsigned cold_cycles;
  logic clk=0, rst_n=0;
  logic [7:0] awaddr;
  logic awvalid, wvalid;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  always #5 clk=~clk;
  cv32e40x_nn_soc_wrapper #(.MEM_FILE("build/mnist_fpga.memh"),
    .INSTR_FILE("build/mnist_dma.memh")) dut (
    .aclk(clk),.aresetn(rst_n),
    .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(),.s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(),.s_axi_bresp(),.s_axi_bvalid(),
    .s_axi_bready(1'b1),.s_axi_araddr('0),.s_axi_arvalid(1'b0),.s_axi_arready(),
    .s_axi_rdata(),.s_axi_rresp(),.s_axi_rvalid(),.s_axi_rready(1'b1),
    .m_axi_araddr(),.m_axi_arlen(),.m_axi_arsize(),.m_axi_arburst(),.m_axi_arvalid(),
    .m_axi_arready(1'b0),.m_axi_rdata('0),.m_axi_rresp('0),.m_axi_rlast(1'b0),
    .m_axi_rvalid(1'b0),.m_axi_rready());
  task automatic axi_write(input logic [7:0] address, input logic [31:0] value);
    @(negedge clk); awaddr=address; wdata=value; wstrb=4'hf; awvalid=1; wvalid=1;
    @(negedge clk); awvalid=0; wvalid=0;
    repeat(2) @(posedge clk);
  endtask
  task automatic wait_pass;
    bit passed = 0;
    for (int cycles=0; cycles<250000; cycles++) begin
      @(posedge clk);
      if (dut.mailbox == 32'h1) begin
        if (dut.metrics_q[3] != 7 || dut.metrics_q[4] != 7 || dut.metrics_q[5] != 7840)
          $fatal(1,"bad MNIST result pred=%0d label=%0d mac=%0d cache=%b cycles=%0d",
            dut.metrics_q[3],dut.metrics_q[4],dut.metrics_q[5],dut.dma_i.weight_valid_q,dut.last_run_cycles_q);
        passed = 1; break;
      end
      if (dut.mailbox[31]) $fatal(1,"firmware failed mailbox=%08x",dut.mailbox);
    end
    if (!passed) $fatal(1,"timeout mailbox=%08x",dut.mailbox);
  endtask
  initial begin : run_test
    awaddr='0; awvalid=0; wvalid=0; wdata='0; wstrb='0;
    repeat(5) @(posedge clk); rst_n=1;
    wait_pass();
    cold_cycles=dut.last_run_cycles_q;
    axi_write(8'h80,32'h1);
    axi_write(8'h84,32'h17ff);
    axi_write(8'h88,32'h7);
    axi_write(8'h80,32'h0);
    wait_pass();
    if (dut.completed_count_q != 2 || dut.last_run_cycles_q == 0)
      $fatal(1,"batch control/counters failed count=%0d cycles=%0d",dut.completed_count_q,dut.last_run_cycles_q);
    if(!dut.dma_i.weight_valid_q || dut.last_run_cycles_q>=cold_cycles)
      $fatal(1,"weight cache ineffective valid=%b cold=%0d warm=%0d",
        dut.dma_i.weight_valid_q,cold_cycles,dut.last_run_cycles_q);
    $display("PASS: FPGA RISC-V persistent weight/activation cache prediction=%0d mac=%0d runs=%0d cold=%0d warm=%0d",
      dut.metrics_q[3],dut.metrics_q[5],dut.completed_count_q,cold_cycles,dut.last_run_cycles_q);
    $finish;
  end
endmodule
`default_nettype wire
