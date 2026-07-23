`default_nettype none

module tb_cv32e40x_smoke;
  localparam int unsigned MEM_WORDS = 16 * 1024;
  localparam int unsigned MEM_INDEX_BITS = 14;
  localparam logic [31:0] MAILBOX_ADDR = 32'h0000_1000;
  localparam int unsigned TIMEOUT_CYCLES = 2000;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic fetch_enable_i = 1'b0;

  logic instr_req;
  logic instr_gnt;
  logic instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic instr_err;

  logic data_req;
  logic data_gnt;
  logic data_rvalid;
  logic [31:0] data_addr;
  logic [3:0] data_be;
  logic data_we;
  logic [31:0] data_wdata;
  logic [31:0] data_rdata;
  logic data_err;

  logic [63:0] mcycle;
  logic core_sleep;
  logic [31:0] memory [0:MEM_WORDS-1];
  logic [31:0] instr_addr_q;
  logic [31:0] data_addr_q;
  int unsigned cycles;
  logic muldiv_test;
  logic dotp4_test;
  logic nnops_test;
  logic runtime_test;
  logic runtime_fail_test;
  logic cpu_baseline_test;
  logic nn_integration_test;
  logic fc_test;
  logic array_fc_test;
  logic [63:0] nn_instruction_count, nn_dotp4_count, nn_requant_count;
  logic [63:0] nn_array_mac_count;
  logic nn_trace_valid, nn_trace_kill;
  logic [3:0] nn_trace_id;
  logic [2:0] nn_trace_operation;
  logic [31:0] nn_trace_result;
  int unsigned trace_events;

  always #5 clk_i = ~clk_i;

  assign instr_gnt = instr_req;
  assign data_gnt  = data_req;
  assign instr_err = |instr_addr_q[31:MEM_INDEX_BITS+2];
  assign data_err  = |data_addr_q[31:MEM_INDEX_BITS+2];
  assign instr_rdata = instr_err ? 32'h0 : memory[instr_addr_q[MEM_INDEX_BITS+1:2]];
  assign data_rdata  = data_err  ? 32'h0 : memory[data_addr_q[MEM_INDEX_BITS+1:2]];

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
    .irq_i         (32'h0),
    .mcycle_o      (mcycle),
    .nn_instruction_count_o(nn_instruction_count),
    .nn_dotp4_count_o(nn_dotp4_count),
    .nn_requant_count_o(nn_requant_count),
    .nn_array_mac_count_o(nn_array_mac_count),
    .nn_trace_valid_o(nn_trace_valid),
    .nn_trace_id_o(nn_trace_id),
    .nn_trace_operation_o(nn_trace_operation),
    .nn_trace_kill_o(nn_trace_kill),
    .nn_trace_result_o(nn_trace_result),
    .core_sleep_o  (core_sleep)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_rvalid <= 1'b0;
      data_rvalid  <= 1'b0;
      instr_addr_q <= '0;
      data_addr_q  <= '0;
    end else begin
      instr_rvalid <= instr_req && instr_gnt;
      data_rvalid  <= data_req && data_gnt;
      if (instr_req && instr_gnt) instr_addr_q <= instr_addr;
      if (data_req && data_gnt)   data_addr_q  <= data_addr;

      if (data_req && data_gnt && data_we && !(|data_addr[31:MEM_INDEX_BITS+2])) begin
        if (data_be[0]) memory[data_addr[MEM_INDEX_BITS+1:2]][7:0]   <= data_wdata[7:0];
        if (data_be[1]) memory[data_addr[MEM_INDEX_BITS+1:2]][15:8]  <= data_wdata[15:8];
        if (data_be[2]) memory[data_addr[MEM_INDEX_BITS+1:2]][23:16] <= data_wdata[23:16];
        if (data_be[3]) memory[data_addr[MEM_INDEX_BITS+1:2]][31:24] <= data_wdata[31:24];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cycles <= 0;
      trace_events <= 0;
    end else begin
      cycles <= cycles + 1;
      if (nn_trace_valid) trace_events <= trace_events + 1;
      if (data_req && data_gnt && data_we && data_addr == MAILBOX_ADDR) begin
        if (runtime_fail_test && data_wdata == 32'h8000_0007 && data_be == 4'hf) begin
          $display("PASS: C runtime propagated expected failure status 7, cycles=%0d mcycle=%0d", cycles, mcycle);
          $finish;
        end else if (data_wdata == 32'h1 && data_be == 4'hf) begin
          if (array_fc_test) begin
            if (memory[32'h1060>>2] != 116 || $signed(memory[32'h1064>>2]) != -12 ||
                memory[32'h1068>>2] != 36 || $signed(memory[32'h106c>>2]) != -13 ||
                memory[32'h1070>>2] != 32'hfe05fc10 || nn_array_mac_count != 64)
              $fatal(1,"FAIL: array FC results/mac count");
            $display("PASS: 4x4 MAC-array FC16x4, 16 MAC/cycle, 64 MAC, outputs=%08x cycles=%0d",
                     memory[32'h1070>>2],cycles);
          end else if (fc_test) begin
            if (memory[32'h1040>>2] == 0 || memory[32'h1048>>2] == 0 ||
                memory[32'h1050>>2] != 20 || nn_instruction_count != 20 ||
                memory[32'h1054>>2] != 32'hfe05fc10 || memory[32'h1058>>2] != 32'hfe05fc10)
              $fatal(1,"FAIL: FC metrics/results swcy=%0d nncy=%0d swout=%08x nnout=%08x",memory[32'h1040>>2],memory[32'h1048>>2],memory[32'h1054>>2],memory[32'h1058>>2]);
            $display("PASS: FC16x4 application sw_cycles=%0d sw_instret=%0d nn_cycles=%0d nn_instret=%0d nn_custom=%0d hw_nn_count=%0d outputs=%08x",
                     memory[32'h1040>>2],memory[32'h1044>>2],memory[32'h1048>>2],memory[32'h104c>>2],memory[32'h1050>>2],nn_instruction_count,memory[32'h1058>>2]);
          end else if (nn_integration_test) begin
            if (nn_instruction_count != 5 || nn_dotp4_count != 2 || nn_requant_count != 2 || trace_events != 14)
              $fatal(1,"FAIL: NN counters/trace instr=%0d dot=%0d req=%0d trace=%0d",nn_instruction_count,nn_dotp4_count,nn_requant_count,trace_events);
            $display("PASS: mixed NN/CPU integration counters and trace, cycles=%0d mcycle=%0d nn=%0d dotp4=%0d requant=%0d trace=%0d",cycles,mcycle,nn_instruction_count,nn_dotp4_count,nn_requant_count,trace_events);
          end else if (cpu_baseline_test)
            $display("PASS: RV32I logic/shift/jump/load-store/x0/minstret baseline, cycles=%0d mcycle=%0d", cycles, mcycle);
          else if (runtime_test)
            $display("PASS: C runtime/data/bss/mailbox program, cycles=%0d mcycle=%0d", cycles, mcycle);
          else if (nnops_test)
            $display("PASS: NN_RELU/CLIP8/MAX4/REQUANT custom instructions, cycles=%0d mcycle=%0d", cycles, mcycle);
          else if (dotp4_test)
            $display("PASS: CV-X-IF NN_DOTP4 custom instruction, cycles=%0d mcycle=%0d", cycles, mcycle);
          else if (muldiv_test)
            $display("PASS: M-extension directed corner cases, cycles=%0d mcycle=%0d", cycles, mcycle);
          else
            $display("PASS: basic RV32I add/branch program, cycles=%0d mcycle=%0d", cycles, mcycle);
          $finish;
        end else begin
          if (array_fc_test)
            $display("ARRAY DEBUG metrics=%0d,%0d,%0d,%0d packed=%08x mac=%0d acc=%0d,%0d,%0d,%0d",
              $signed(memory[32'h1060>>2]),$signed(memory[32'h1064>>2]),
              $signed(memory[32'h1068>>2]),$signed(memory[32'h106c>>2]),memory[32'h1070>>2],
              nn_array_mac_count,$signed(dut.xif_nn_i.array_i.accumulator[0]),
              $signed(dut.xif_nn_i.array_i.accumulator[1]),$signed(dut.xif_nn_i.array_i.accumulator[2]),
              $signed(dut.xif_nn_i.array_i.accumulator[3]));
          $fatal(1, "FAIL: mailbox value=%08x be=%x", data_wdata, data_be);
        end
      end
      if (cycles >= TIMEOUT_CYCLES) begin
        $display("DEBUG: instr_addr=%08x xif_state=%0d issue_valid=%0b commit_valid=%0b result_valid=%0b",
                 instr_addr, dut.xif_nn_i.state_q, dut.xif.issue_valid,
                 dut.xif.commit_valid, dut.xif.result_valid);
        $fatal(1, "FAIL: timeout after %0d cycles", cycles);
      end
    end
  end

  initial begin
    muldiv_test = $test$plusargs("MULDIV");
    dotp4_test = $test$plusargs("DOTP4");
    nnops_test = $test$plusargs("NNOPS");
    runtime_test = $test$plusargs("RUNTIME");
    runtime_fail_test = $test$plusargs("RUNTIME_FAIL");
    cpu_baseline_test = $test$plusargs("CPU_BASELINE");
    nn_integration_test = $test$plusargs("NN_INTEGRATION");
    fc_test = $test$plusargs("FC16X4");
    array_fc_test = $test$plusargs("ARRAY_FC16X4");
    for (int unsigned index = 0; index < MEM_WORDS; index++) memory[index] = '0;
    if (array_fc_test) begin
      $readmemh("build/fc16x4_array.memh", memory);
    end else if (fc_test) begin
      $readmemh("build/fc16x4.memh", memory);
    end else if (nn_integration_test) begin
      $readmemh("build/test_nn_integration.memh", memory);
    end else if (cpu_baseline_test) begin
      $readmemh("build/test_cpu_baseline.memh", memory);
    end else if (runtime_fail_test) begin
      $readmemh("build/test_runtime_fail.memh", memory);
    end else if (runtime_test) begin
      $readmemh("build/test_runtime.memh", memory);
    end else if (nnops_test) begin
      $readmemh("build/test_nn_ops.memh", memory);
    end else if (dotp4_test) begin
      $readmemh("build/test_dotp4.memh", memory);
    end else if (muldiv_test) begin
      $readmemh("build/test_muldiv.memh", memory);
    end else begin
      $readmemh("build/test_basic.memh", memory);
    end
    repeat (5) @(posedge clk_i);
    rst_ni <= 1'b1;
    fetch_enable_i <= 1'b1;
  end
endmodule

`default_nettype wire
