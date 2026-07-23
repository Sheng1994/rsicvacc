`default_nettype none

module tb_cv32e40x_memory_exceptions;
  localparam int unsigned MEM_WORDS = 16 * 1024;
  localparam int unsigned MEM_INDEX_BITS = 14;
  localparam int unsigned TIMEOUT_CYCLES = 4000;
  localparam logic [31:0] MAILBOX_ADDR = 32'h1000;
  localparam logic [31:0] MONITOR_ARM  = 32'h1020;
  localparam logic [31:0] MONITOR_STOP = 32'h1024;
  localparam logic [31:0] BUS_LOAD_ADDR = 32'h4000;
  localparam logic [31:0] BUS_STORE_ADDR = 32'h4004;
  localparam logic [31:0] IFETCH_ADDR = 32'h0280;

  logic clk_i = 1'b0, rst_ni = 1'b0, fetch_enable_i = 1'b0;
  logic instr_req, instr_gnt, instr_rvalid, instr_err;
  logic [31:0] instr_addr, instr_rdata, instr_addr_q;
  logic data_req, data_gnt, data_rvalid, data_err, data_we;
  logic [31:0] data_addr, data_wdata, data_rdata, data_addr_q;
  logic [3:0] data_be;
  logic [63:0] mcycle;
  logic core_sleep;
  logic monitor_misaligned;
  logic unexpected_data_request;
  logic [31:0] memory [0:MEM_WORDS-1];
  int unsigned cycles;

  always #5 clk_i = ~clk_i;
  assign instr_gnt = instr_req;
  assign data_gnt = data_req;
  assign instr_rdata = instr_err ? 32'h0 : memory[instr_addr_q[MEM_INDEX_BITS+1:2]];
  assign data_rdata = data_err ? 32'h0 : memory[data_addr_q[MEM_INDEX_BITS+1:2]];
  assign instr_err = (instr_addr_q == IFETCH_ADDR) |
                     (|instr_addr_q[31:MEM_INDEX_BITS+2]);
  assign data_err = (data_addr_q == BUS_LOAD_ADDR) |
                    (data_addr_q == BUS_STORE_ADDR) |
                    (|data_addr_q[31:MEM_INDEX_BITS+2]);

  cv32e40x_subsystem dut (
    .clk_i, .rst_ni, .fetch_enable_i,
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt),
    .instr_rvalid_i(instr_rvalid), .instr_addr_o(instr_addr),
    .instr_rdata_i(instr_rdata), .instr_err_i(instr_err),
    .data_req_o(data_req), .data_gnt_i(data_gnt),
    .data_rvalid_i(data_rvalid), .data_addr_o(data_addr),
    .data_be_o(data_be), .data_we_o(data_we), .data_wdata_o(data_wdata),
    .data_rdata_i(data_rdata), .data_err_i(data_err),
    .irq_i('0), .mcycle_o(mcycle), .core_sleep_o(core_sleep)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_rvalid <= 1'b0;
      data_rvalid <= 1'b0;
      instr_addr_q <= '0;
      data_addr_q <= '0;
      monitor_misaligned <= 1'b0;
      unexpected_data_request <= 1'b0;
    end else begin
      instr_rvalid <= instr_req && instr_gnt;
      data_rvalid <= data_req && data_gnt;
      if (instr_req && instr_gnt) instr_addr_q <= instr_addr;
      if (data_req && data_gnt) begin
        data_addr_q <= data_addr;
        if (monitor_misaligned && data_addr != MONITOR_STOP) begin
          $display("DEBUG: unexpected data request while misalignment monitor armed: addr=%08x we=%0b be=%x", data_addr, data_we, data_be);
          unexpected_data_request <= 1'b1;
        end
        if (data_we && data_addr == MONITOR_ARM) monitor_misaligned <= 1'b1;
        if (data_we && data_addr == MONITOR_STOP) monitor_misaligned <= 1'b0;
        if (data_we && data_addr != BUS_STORE_ADDR &&
            !(|data_addr[31:MEM_INDEX_BITS+2])) begin
          if (data_be[0]) memory[data_addr[MEM_INDEX_BITS+1:2]][7:0] <= data_wdata[7:0];
          if (data_be[1]) memory[data_addr[MEM_INDEX_BITS+1:2]][15:8] <= data_wdata[15:8];
          if (data_be[2]) memory[data_addr[MEM_INDEX_BITS+1:2]][23:16] <= data_wdata[23:16];
          if (data_be[3]) memory[data_addr[MEM_INDEX_BITS+1:2]][31:24] <= data_wdata[31:24];
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) cycles <= 0;
    else begin
      cycles <= cycles + 1;
      if (data_req && data_gnt && data_we && data_addr == MAILBOX_ADDR) begin
        if (data_wdata == 1 && !unexpected_data_request) begin
          $display("PASS: misaligned load/store trapped before data OBI request, cycles=%0d mcycle=%0d", cycles, mcycle);
          $finish;
        end else begin
          $fatal(1, "FAIL: memory exception status=%08x unexpected_bus_req=%0b", data_wdata, unexpected_data_request);
        end
      end
      if (cycles >= TIMEOUT_CYCLES) begin
        $display("DEBUG: instr_addr=%08x instr_addr_q=%08x data_addr=%08x monitor=%0b unexpected=%0b",
                 instr_addr, instr_addr_q, data_addr, monitor_misaligned, unexpected_data_request);
        $fatal(1, "FAIL: memory exception timeout");
      end
    end
  end

  initial begin
    for (int unsigned i = 0; i < MEM_WORDS; i++) memory[i] = '0;
    $readmemh("build/test_memory_exceptions.memh", memory);
    repeat (5) @(posedge clk_i);
    rst_ni <= 1'b1;
    fetch_enable_i <= 1'b1;
  end
endmodule

`default_nettype wire
