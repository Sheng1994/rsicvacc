`default_nettype none

module tb_cv32e40x_trap;
  localparam int unsigned MEM_WORDS = 16 * 1024;
  localparam int unsigned MEM_INDEX_BITS = 14;
  localparam int unsigned TIMEOUT_CYCLES = 4000;
  localparam logic [31:0] MAILBOX_ADDR = 32'h0000_1000;
  localparam logic [31:0] IRQ_ACK_ADDR = 32'h0000_1004;
  localparam logic [31:0] IRQ_ARM_ADDR = 32'h0000_1014;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic fetch_enable_i = 1'b0;
  logic instr_req, instr_gnt, instr_rvalid, instr_err;
  logic [31:0] instr_addr, instr_rdata, instr_addr_q;
  logic data_req, data_gnt, data_rvalid, data_err, data_we;
  logic [31:0] data_addr, data_wdata, data_rdata, data_addr_q;
  logic [3:0] data_be;
  logic [31:0] irq;
  logic [63:0] mcycle;
  logic core_sleep;
  logic timer_pending;
  logic [5:0] timer_hold;
  logic [31:0] memory [0:MEM_WORDS-1];
  int unsigned cycles;

  always #5 clk_i = ~clk_i;
  assign instr_gnt = instr_req;
  assign data_gnt = data_req;
  assign instr_err = |instr_addr_q[31:MEM_INDEX_BITS+2];
  assign data_err = |data_addr_q[31:MEM_INDEX_BITS+2];
  assign instr_rdata = instr_err ? 32'h0 : memory[instr_addr_q[MEM_INDEX_BITS+1:2]];
  assign data_rdata = data_err ? 32'h0 : memory[data_addr_q[MEM_INDEX_BITS+1:2]];
  assign irq = timer_pending ? 32'h0000_0080 : 32'h0;

  cv32e40x_subsystem dut (
    .clk_i, .rst_ni, .fetch_enable_i,
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt),
    .instr_rvalid_i(instr_rvalid), .instr_addr_o(instr_addr),
    .instr_rdata_i(instr_rdata), .instr_err_i(instr_err),
    .data_req_o(data_req), .data_gnt_i(data_gnt),
    .data_rvalid_i(data_rvalid), .data_addr_o(data_addr),
    .data_be_o(data_be), .data_we_o(data_we), .data_wdata_o(data_wdata),
    .data_rdata_i(data_rdata), .data_err_i(data_err),
    .irq_i(irq), .mcycle_o(mcycle), .core_sleep_o(core_sleep)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_rvalid <= 1'b0;
      data_rvalid <= 1'b0;
      instr_addr_q <= '0;
      data_addr_q <= '0;
      timer_pending <= 1'b0;
      timer_hold <= '0;
    end else begin
      instr_rvalid <= instr_req && instr_gnt;
      data_rvalid <= data_req && data_gnt;
      if (instr_req && instr_gnt) instr_addr_q <= instr_addr;
      if (data_req && data_gnt) begin
        data_addr_q <= data_addr;
        if (data_we && !(|data_addr[31:MEM_INDEX_BITS+2])) begin
          if (data_be[0]) memory[data_addr[MEM_INDEX_BITS+1:2]][7:0] <= data_wdata[7:0];
          if (data_be[1]) memory[data_addr[MEM_INDEX_BITS+1:2]][15:8] <= data_wdata[15:8];
          if (data_be[2]) memory[data_addr[MEM_INDEX_BITS+1:2]][23:16] <= data_wdata[23:16];
          if (data_be[3]) memory[data_addr[MEM_INDEX_BITS+1:2]][31:24] <= data_wdata[31:24];
        end
        if (data_we && data_addr == IRQ_ARM_ADDR) begin
          timer_pending <= 1'b1;
          timer_hold <= '0;
        end
      end
      if (timer_pending) begin
        timer_hold <= timer_hold + 6'd1;
        if (timer_hold == 6'd24) timer_pending <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) cycles <= 0;
    else begin
      cycles <= cycles + 1;
      if (data_req && data_gnt && data_we && data_addr == MAILBOX_ADDR) begin
        if (data_wdata == 32'h1) begin
          $display("PASS: CSR/illegal/ECALL/timer IRQ/mret, cycles=%0d mcycle=%0d", cycles, mcycle);
          $finish;
        end else $fatal(1, "FAIL: trap test error=%08x", data_wdata);
      end
      if (cycles >= TIMEOUT_CYCLES) $fatal(1, "FAIL: trap test timeout");
    end
  end

  initial begin
    for (int unsigned index = 0; index < MEM_WORDS; index++) memory[index] = '0;
    $readmemh("build/test_privileged.memh", memory);
    repeat (5) @(posedge clk_i);
    rst_ni <= 1'b1;
    fetch_enable_i <= 1'b1;
  end
endmodule

`default_nettype wire
