`timescale 1ns/1ps
module tb_nn_dma_mac_array;
  logic clk_i=0,rst_ni=0,dma_start_i=0,dma_bank_i=0,compute_start_i=0,compute_bank_i=0;
  logic [31:0] dma_addr_i,result_o,araddr,rdata;
  logic [1:0] result_index_i,arburst,rresp;
  logic [7:0] arlen; logic [2:0] arsize;
  logic dma_busy,dma_done,dma_error,compute_busy,compute_done,b0,b1,arvalid,arready,rlast,rvalid,rready;
  logic [63:0] mac_count;
  logic [31:0] memory[0:63];
  logic read_active; logic [7:0] beat; logic [31:0] word_index; int stall_count;
  int unsigned cycles, dma0_begin, dma0_end, overlap_begin, compute0_end, dma1_end, pipeline_end;
  always #5 clk_i=~clk_i;
  always_ff @(posedge clk_i) if(!rst_ni) cycles<=0; else cycles<=cycles+1;
  assign arready=1'b1;
  assign rvalid=read_active && (stall_count%3!=1);
  assign rdata=memory[word_index]; assign rresp=2'b00; assign rlast=beat==arlen;
  nn_dma_mac_array dut(.clk_i,.rst_ni,.dma_start_i,.dma_addr_i,.dma_bank_i,
    .gather_enable_i(1'b0),.cache_hit_i(1'b0),.activation_cache_hit_i(1'b0),.cache_group_i('0),
    .image_base_i('0),.weight_base_i('0),.tile_index_i('0),.compute_tile_i('0),.row_base_i('0),
    .compute_start_i,.compute_bank_i,.compute_accumulate_i(1'b0),.valid_rows_i(3'd4),.result_index_i,.dma_busy_o(dma_busy),
    .clear_mac_count_i(1'b0),
    .dma_done_o(dma_done),.dma_error_o(dma_error),.compute_busy_o(compute_busy),
    .compute_done_o(compute_done),.bank0_ready_o(b0),.bank1_ready_o(b1),
    .result_o,.mac_count_o(mac_count),.m_axi_araddr_o(araddr),.m_axi_arlen_o(arlen),
    .m_axi_arsize_o(arsize),.m_axi_arburst_o(arburst),.m_axi_arvalid_o(arvalid),
    .m_axi_arready_i(arready),.m_axi_rdata_i(rdata),.m_axi_rresp_i(rresp),
    .m_axi_rlast_i(rlast),.m_axi_rvalid_i(rvalid),.m_axi_rready_o(rready));
  always_ff @(posedge clk_i) begin
    if(!rst_ni) begin read_active<=0;beat<=0;word_index<=0;stall_count<=0; end
    else begin
      stall_count<=stall_count+1;
      if(arvalid&&arready) begin read_active<=1;beat<=0;word_index<=araddr>>2; end
      if(rvalid&&rready) begin
        if(rlast) read_active<=0;
        else begin beat<=beat+1'b1;word_index<=word_index+1'b1;end
      end
    end
  end
  task tick; @(posedge clk_i); #1; endtask
  task launch_dma(input logic bank,input logic[31:0] address);
    begin dma_bank_i=bank;dma_addr_i=address;dma_start_i=1;tick();dma_start_i=0;end
  endtask
  task check_results(input int a,input int b,input int c,input int d);
    int expected[0:3]; begin expected[0]=a;expected[1]=b;expected[2]=c;expected[3]=d;
      for(int r=0;r<4;r++) begin result_index_i=r[1:0];#1;
        if($signed(result_o)!=expected[r]) $fatal(1,"row%0d got%0d expected%0d",r,$signed(result_o),expected[r]);
      end
    end
  endtask
  initial begin
    for(int i=0;i<64;i++) memory[i]=0;
    for(int b=0;b<4;b++) memory[b]={8'(b*4+4),8'(b*4+3),8'(b*4+2),8'(b*4+1)};
    for(int r=0;r<4;r++) for(int b=0;b<4;b++) memory[4+r*4+b]={4{8'(r+1)}};
    for(int b=0;b<4;b++) memory[32+b]=32'h01010101;
    for(int r=0;r<4;r++) for(int b=0;b<4;b++) memory[36+r*4+b]={4{8'(r+5)}};
    repeat(3) tick();rst_ni=1;tick();
    dma0_begin=cycles; launch_dma(0,0); while(!dma_done) tick(); dma0_end=cycles;
    if(!b0||dma_error)$fatal(1,"bank0 DMA");
    overlap_begin=cycles;
    compute_bank_i=0;compute_start_i=1; dma_bank_i=1;dma_addr_i=32'd128;dma_start_i=1;tick();
    compute_start_i=0;dma_start_i=0;
    while(!compute_done) tick(); compute0_end=cycles; check_results(136,272,408,544);
    while(!dma_done) tick(); dma1_end=cycles; if(!b1||dma_error)$fatal(1,"bank1 DMA");
    compute_bank_i=1;compute_start_i=1;tick();compute_start_i=0;
    while(!compute_done) tick();pipeline_end=cycles;check_results(80,96,112,128);
    if(mac_count!=128)$fatal(1,"mac_count=%0d",mac_count);
    $display("PASS: AXI burst DMA + ping-pong buffers overlap transfer/compute, 2 tiles 128 MAC");
    $display("BENCH: dma_first_tile=%0d array_compute=%0d overlapped_two_tile_pipeline=%0d cycles",
      dma0_end-dma0_begin,compute0_end-overlap_begin,pipeline_end-overlap_begin);
    $finish;
  end
endmodule
