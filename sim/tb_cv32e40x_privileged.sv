`default_nettype none

module tb_cv32e40x_privileged;
  localparam int unsigned MEM_WORDS = 16 * 1024;
  localparam int unsigned MEM_INDEX_BITS = 14;
  localparam int unsigned TIMEOUT_CYCLES = 20_000;
  localparam logic [31:0] MAILBOX_ADDR = 32'h0000_1000;
  localparam logic [31:0] IRQ_ACK_ADDR = 32'h0000_1004;
  localparam logic [31:0] IRQ_ARM_ADDR = 32'h0000_1014;
  localparam logic [31:0] DEBUG_ADDR = 32'h0000_1018;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic fetch_enable_i = 1'b0;
  logic [31:0] irq;

  logic instr_req;
  logic instr_gnt;
  logic instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic instr_err;
  logic instr_pending;
  logic [2:0] instr_delay;
  logic [31:0] instr_addr_q;

  logic data_req;
  logic data_gnt;
  logic data_rvalid;
  logic [31:0] data_addr;
  logic [3:0] data_be;
  logic data_we;
  logic [31:0] data_wdata;
  logic [31:0] data_rdata;
  logic data_err;
  logic data_pending;
  logic [2:0] data_delay;
  logic [31:0] data_addr_q;

  logic [31:0] memory [0:MEM_WORDS-1];
  logic [31:0] lfsr;
  logic random_wait;
  logic timer_pending;
  logic [63:0] mcycle;
  logic core_sleep;
  int unsigned cycles;

  always #5 clk_i = ~clk_i;

  // Requests are granted only when the corresponding single-entry response
  // slot is free. LFSR bits introduce deterministic pseudo-random grant stalls.
  assign instr_gnt = instr_req && !instr_pending && (!random_wait || lfsr[0]);
  assign data_gnt  = data_req && !data_pending && (!random_wait || lfsr[4]);
  assign instr_err = |instr_addr_q[31:MEM_INDEX_BITS+2];
  assign data_err  = |data_addr_q[31:MEM_INDEX_BITS+2];
  assign instr_rdata = instr_err ? 32'h0 : memory[instr_addr_q[MEM_INDEX_BITS+1:2]];
  assign data_rdata  = data_err  ? 32'h0 : memory[data_addr_q[MEM_INDEX_BITS+1:2]];
  assign irq = timer_pending ? 32'h0000_0080 : 32'h0;

  cv32e40x_subsystem dut (
    .clk_i,
    .rst_ni,
    .fetch_enable_i,
    .instr_req_o   (instr_req),
    .instr_gnt_i   (instr_gnt),
    .instr_rvalid_i(instr_rvalid),
    .instr_addr_o  (instr_addr),
    .instr_rdata_i (instr_rdata),
    .instr_err_i   (instr_err),
    .data_req_o    (data_req),
    .data_gnt_i    (data_gnt),
    .data_rvalid_i (data_rvalid),
    .data_addr_o   (data_addr),
    .data_be_o     (data_be),
    .data_we_o     (data_we),
    .data_wdata_o  (data_wdata),
    .data_rdata_i  (data_rdata),
    .data_err_i    (data_err),
    .irq_i         (irq),
    .mcycle_o      (mcycle),
    .core_sleep_o  (core_sleep)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lfsr           <= 32'h1ace_b00c;
      instr_pending  <= 1'b0;
      instr_rvalid   <= 1'b0;
      instr_delay    <= '0;
      instr_addr_q   <= '0;
      data_pending   <= 1'b0;
      data_rvalid    <= 1'b0;
      data_delay     <= '0;
      data_addr_q    <= '0;
      timer_pending  <= 1'b0;
    end else begin
      lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      instr_rvalid <= 1'b0;
      data_rvalid  <= 1'b0;

      if (!instr_pending) begin
        if (instr_req && instr_gnt) begin
          instr_pending <= 1'b1;
          instr_addr_q  <= instr_addr;
          instr_delay   <= random_wait ? ({1'b0, lfsr[3:2]} + 3'd1) : 3'd1;
        end
      end else if (instr_delay == 0) begin
        instr_pending <= 1'b0;
        instr_rvalid  <= 1'b1;
      end else begin
        instr_delay <= instr_delay - 3'd1;
      end

      if (!data_pending) begin
        if (data_req && data_gnt) begin
          data_pending <= 1'b1;
          data_addr_q  <= data_addr;
          data_delay   <= random_wait ? ({1'b0, lfsr[7:6]} + 3'd1) : 3'd1;
          if (data_we && !(|data_addr[31:MEM_INDEX_BITS+2])) begin
            if (data_be[0]) memory[data_addr[MEM_INDEX_BITS+1:2]][7:0]   <= data_wdata[7:0];
            if (data_be[1]) memory[data_addr[MEM_INDEX_BITS+1:2]][15:8]  <= data_wdata[15:8];
            if (data_be[2]) memory[data_addr[MEM_INDEX_BITS+1:2]][23:16] <= data_wdata[23:16];
            if (data_be[3]) memory[data_addr[MEM_INDEX_BITS+1:2]][31:24] <= data_wdata[31:24];
          end
          if (data_we && data_addr == IRQ_ARM_ADDR) timer_pending <= 1'b1;
          if (data_we && data_addr == IRQ_ACK_ADDR) timer_pending <= 1'b0;
        end
      end else if (data_delay == 0) begin
        data_pending <= 1'b0;
        data_rvalid  <= 1'b1;
      end else begin
        data_delay <= data_delay - 3'd1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cycles <= 0;
    end else begin
      cycles <= cycles + 1;
      if (data_req && data_gnt && data_we && data_addr == MAILBOX_ADDR) begin
        if (data_wdata == 32'h1 && data_be == 4'hf) begin
          $display("PASS: basic program with random OBI latency, cycles=%0d mcycle=%0d", cycles, mcycle);
          $finish;
        end else begin
          $display("FAIL MARKER: privileged error=%08x illegal=%08x ecall=%08x irq=%08x",
                   data_wdata, memory[32'h1008 >> 2], memory[32'h100c >> 2],
                   memory[32'h1010 >> 2]);
        end
      end
      if (data_req && data_gnt && data_we && data_addr == DEBUG_ADDR) begin
        $display("DEBUG: failing arithmetic result=%08x", data_wdata);
      end
      if (cycles >= TIMEOUT_CYCLES) begin
        $display("STATE: illegal=%08x ecall=%08x irq=%08x pending=%0b irq_line=%08x",
                 memory[32'h1008 >> 2], memory[32'h100c >> 2],
                 memory[32'h1010 >> 2], timer_pending, irq);
        $display("STATE: pc_if=%08x divider_state=%0d", dut.core_i.pc_if,
                 dut.core_i.ex_stage_i.div.div_i.state);
        $display("STATE: lfsr=%08x data_req=%0b data_gnt=%0b data_pending=%0b data_delay=%0d core_sleep=%0b",
                 lfsr, data_req, data_gnt, data_pending, data_delay, core_sleep);
        $display("STATE: ex_pc=%08x ex_valid=%0b div_en=%0b lsu_en=%0b kill_ex=%0b halt_ex=%0b",
                 dut.core_i.id_ex_pipe.pc, dut.core_i.id_ex_pipe.instr_valid,
                 dut.core_i.id_ex_pipe.div_en, dut.core_i.id_ex_pipe.lsu_en,
                 dut.core_i.ctrl_fsm.kill_ex, dut.core_i.ctrl_fsm.halt_ex);
        $fatal(1, "FAIL: privileged test timeout after %0d cycles", cycles);
      end
    end
  end

  initial begin
    random_wait = !$test$plusargs("NO_RANDOM");
    for (int unsigned index = 0; index < MEM_WORDS; index++) memory[index] = '0;
    if ($test$plusargs("BASIC")) begin
      $readmemh("build/test_basic.memh", memory);
    end else begin
      $readmemh("build/test_privileged.memh", memory);
    end
    repeat (5) @(posedge clk_i);
    rst_ni <= 1'b1;
    fetch_enable_i <= 1'b1;
  end
endmodule

`default_nettype wire
