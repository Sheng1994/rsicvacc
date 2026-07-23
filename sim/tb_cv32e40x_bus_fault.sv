`default_nettype none
module tb_cv32e40x_bus_fault;
  localparam int MEM_WORDS = 16*1024;
  logic clk_i=0, rst_ni=0, fetch_enable_i=0;
  logic instr_req,instr_gnt,instr_rvalid,instr_err;
  logic [31:0] instr_addr,instr_rdata,instr_addr_q;
  logic data_req,data_gnt,data_rvalid,data_err,data_we;
  logic [31:0] data_addr,data_wdata,data_rdata,data_addr_q;
  logic [3:0] data_be;
  logic [63:0] mcycle; logic core_sleep;
  logic [31:0] memory[0:MEM_WORDS-1];
  logic mode_load, mode_store, mode_instr;
  int cycles;
  always #5 clk_i=~clk_i;
  assign instr_gnt=instr_req; assign data_gnt=data_req;
  assign instr_err=mode_instr && instr_addr_q==32'h280;
  assign data_err=(mode_load && data_addr_q==32'h4000) ||
                  (mode_store && data_addr_q==32'h4004);
  assign instr_rdata=instr_err ? 0 : memory[instr_addr_q[15:2]];
  assign data_rdata=data_err ? 0 : memory[data_addr_q[15:2]];
  cv32e40x_subsystem dut(
    .clk_i,.rst_ni,.fetch_enable_i,
    .instr_req_o(instr_req),.instr_gnt_i(instr_gnt),.instr_rvalid_i(instr_rvalid),
    .instr_addr_o(instr_addr),.instr_rdata_i(instr_rdata),.instr_err_i(instr_err),
    .data_req_o(data_req),.data_gnt_i(data_gnt),.data_rvalid_i(data_rvalid),
    .data_addr_o(data_addr),.data_be_o(data_be),.data_we_o(data_we),.data_wdata_o(data_wdata),
    .data_rdata_i(data_rdata),.data_err_i(data_err),.irq_i('0),.mcycle_o(mcycle),.core_sleep_o(core_sleep));
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin instr_rvalid<=0; data_rvalid<=0; instr_addr_q<=0; data_addr_q<=0; end
    else begin
      instr_rvalid<=instr_req&&instr_gnt; data_rvalid<=data_req&&data_gnt;
      if(instr_req&&instr_gnt) instr_addr_q<=instr_addr;
      if(data_req&&data_gnt) data_addr_q<=data_addr;
    end
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) cycles<=0; else begin cycles<=cycles+1;
      if(data_req&&data_gnt&&data_we&&data_addr==32'h1000) begin
        if((mode_load&&data_wdata==32'h80000400)||(mode_store&&data_wdata==32'h80000401)||
           (mode_instr&&data_wdata==32'h18)) begin
          $display("PASS: %s bus fault cause=%08x cycles=%0d", mode_instr?"instruction":(mode_load?"load NMI":"store NMI"),data_wdata,cycles); $finish;
        end else $fatal(1,"FAIL: bus fault signature=%08x",data_wdata);
      end
      if(cycles>2000) $fatal(1,"FAIL: bus fault timeout mode load=%0b store=%0b instr=%0b",mode_load,mode_store,mode_instr);
    end
  end
  initial begin
    mode_load=$test$plusargs("LOAD_NMI"); mode_store=$test$plusargs("STORE_NMI"); mode_instr=$test$plusargs("INSTR_FAULT");
    for(int i=0;i<MEM_WORDS;i++) memory[i]='0;
    if(mode_load) $readmemh("build/test_load_nmi.memh",memory);
    else if(mode_store) $readmemh("build/test_store_nmi.memh",memory);
    else $readmemh("build/test_instr_fault.memh",memory);
    repeat(5) @(posedge clk_i); rst_ni<=1; fetch_enable_i<=1;
  end
endmodule
`default_nettype wire
