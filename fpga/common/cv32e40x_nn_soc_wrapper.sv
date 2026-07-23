`default_nettype none

module cv32e40x_nn_soc_wrapper #(
  parameter string MEM_FILE = "mnist_fpga.mem",
  parameter string INSTR_FILE = "mnist_dma.memh",
  parameter int unsigned MEM_WORDS = 16384
) (
  input  wire         aclk,
  input  wire         aresetn,
  input  wire [7:0]   s_axi_awaddr,
  input  wire         s_axi_awvalid,
  output logic        s_axi_awready,
  input  wire [31:0]  s_axi_wdata,
  input  wire [3:0]   s_axi_wstrb,
  input  wire         s_axi_wvalid,
  output logic        s_axi_wready,
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  wire         s_axi_bready,
  input  wire [7:0]   s_axi_araddr,
  input  wire         s_axi_arvalid,
  output logic        s_axi_arready,
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  wire         s_axi_rready,
  output logic [31:0] m_axi_araddr,
  output logic [7:0]  m_axi_arlen,
  output logic [2:0]  m_axi_arsize,
  output logic [1:0]  m_axi_arburst,
  output logic        m_axi_arvalid,
  input  wire         m_axi_arready,
  input  wire [31:0]  m_axi_rdata,
  input  wire [1:0]   m_axi_rresp,
  input  wire         m_axi_rlast,
  input  wire         m_axi_rvalid,
  output logic        m_axi_rready
);
  (* rom_style = "block" *) logic [31:0] instruction_rom [0:1023];
  initial $readmemh(INSTR_FILE, instruction_rom);

  logic instr_req, instr_rvalid, data_req, data_rvalid, data_we;
  logic [31:0] instr_addr, instr_rdata_q, data_addr, data_wdata;
  logic [3:0] data_be;
  logic [31:0] data_memory_rdata, data_mmio_rdata_q, data_response;
  logic data_mmio_q;
  wire logic data_memory_enable = data_req && !mmio_select && (data_addr[31:16] == 16'h0);
  wire logic [3:0] data_memory_we = {4{data_memory_enable && data_we}} & data_be;
  logic [63:0] mcycle, nn_instruction_count, nn_array_mac_count;
  logic mmio_select;
  logic [31:0] dma_reg_rdata;
  logic [31:0] dma_araddr, dma_rdata_q;
  logic [7:0] dma_arlen;
  logic [2:0] dma_arsize;
  logic [1:0] dma_arburst;
  logic dma_arvalid, dma_arready, dma_rvalid, dma_rready, dma_rlast;
  logic dma_read_pending_q;
  logic [7:0] dma_beats_left_q;
  logic [13:0] dma_bram_addr_q;
  logic [31:0] mailbox;
  logic [31:0] metrics_q [0:15];
  logic host_cpu_reset_q;
  logic [13:0] host_bram_addr_q;
  logic [31:0] host_bram_rdata;
  logic host_bram_write;
  logic [13:0] bram_b_addr;
  logic bram_b_enable;
  logic [31:0] completed_count_q, run_cycles_q, last_run_cycles_q;
  wire logic cpu_resetn = aresetn && !host_cpu_reset_q;
  assign bram_b_addr = host_cpu_reset_q ? host_bram_addr_q :
                       (!dma_read_pending_q ? dma_araddr[15:2] :
                        ((dma_rvalid && dma_rready && !dma_rlast) ?
                         dma_bram_addr_q + 1'b1 : dma_bram_addr_q));
  assign bram_b_enable = host_cpu_reset_q || (dma_arvalid && dma_arready) ||
                         (dma_rvalid && dma_rready && !dma_rlast);

  assign mmio_select = data_req && (data_addr[31:8] == 24'h0000f0);
  assign data_response = data_mmio_q ? data_mmio_rdata_q : data_memory_rdata;

`ifdef XILINX_FPGA
  xpm_memory_tdpram #(
    .ADDR_WIDTH_A(14),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(8),
    .CASCADE_HEIGHT(0),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE(MEM_FILE),
    .MEMORY_INIT_PARAM(""),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(524288),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_A(32), .READ_DATA_WIDTH_B(32),
    .READ_LATENCY_A(1), .READ_LATENCY_B(1),
    .READ_RESET_VALUE_A("0"),
    .RST_MODE_A("SYNC"), .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(0),
    .USE_MEM_INIT(1),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(32), .WRITE_DATA_WIDTH_B(32),
    .BYTE_WRITE_WIDTH_B(8),
    .WRITE_MODE_A("read_first"), .WRITE_MODE_B("read_first")
  ) data_bram_i (
    .dbiterra(), .douta(data_memory_rdata), .sbiterra(),
    .addra(data_addr[15:2]), .clka(aclk), .dina(data_wdata),
    .ena(data_memory_enable), .injectdbiterra(1'b0), .injectsbiterra(1'b0),
    .regcea(1'b1), .rsta(!cpu_resetn), .sleep(1'b0), .wea(data_memory_we),
    .dbiterrb(), .doutb(host_bram_rdata), .sbiterrb(),
    .addrb(bram_b_addr), .clkb(aclk), .dinb(s_axi_wdata), .enb(bram_b_enable),
    .injectdbiterrb(1'b0), .injectsbiterrb(1'b0), .regceb(1'b1),
    .rstb(!aresetn), .web({4{host_bram_write}} & s_axi_wstrb)
  );
`else
  logic [31:0] data_memory [0:MEM_WORDS-1];
  initial $readmemh(MEM_FILE, data_memory);
  always_ff @(posedge aclk) begin
    if (data_memory_enable) begin
      data_memory_rdata <= data_memory[data_addr[15:2]];
      if (data_memory_we[0]) data_memory[data_addr[15:2]][7:0]   <= data_wdata[7:0];
      if (data_memory_we[1]) data_memory[data_addr[15:2]][15:8]  <= data_wdata[15:8];
      if (data_memory_we[2]) data_memory[data_addr[15:2]][23:16] <= data_wdata[23:16];
      if (data_memory_we[3]) data_memory[data_addr[15:2]][31:24] <= data_wdata[31:24];
    end
    if (host_bram_write) begin
      if (s_axi_wstrb[0]) data_memory[host_bram_addr_q][7:0]   <= s_axi_wdata[7:0];
      if (s_axi_wstrb[1]) data_memory[host_bram_addr_q][15:8]  <= s_axi_wdata[15:8];
      if (s_axi_wstrb[2]) data_memory[host_bram_addr_q][23:16] <= s_axi_wdata[23:16];
      if (s_axi_wstrb[3]) data_memory[host_bram_addr_q][31:24] <= s_axi_wdata[31:24];
    end
    if (bram_b_enable) host_bram_rdata <= data_memory[bram_b_addr];
  end
`endif

  cv32e40x_subsystem cpu_i (
    .clk_i(aclk), .rst_ni(cpu_resetn), .fetch_enable_i(cpu_resetn),
    .instr_req_o(instr_req), .instr_gnt_i(instr_req), .instr_rvalid_i(instr_rvalid),
    .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata_q), .instr_err_i(1'b0),
    .data_req_o(data_req), .data_gnt_i(data_req), .data_rvalid_i(data_rvalid),
    .data_addr_o(data_addr), .data_be_o(data_be), .data_we_o(data_we),
    .data_wdata_o(data_wdata), .data_rdata_i(data_response), .data_err_i(1'b0),
    .irq_i('0), .mcycle_o(mcycle), .nn_instruction_count_o(nn_instruction_count),
    .nn_dotp4_count_o(), .nn_requant_count_o(), .nn_array_mac_count_o(nn_array_mac_count),
    .nn_trace_valid_o(), .nn_trace_id_o(), .nn_trace_operation_o(), .nn_trace_kill_o(),
    .nn_trace_result_o(), .core_sleep_o()
  );

  nn_mnist_accel_10x16 dma_i (
    .clk_i(aclk), .rst_ni(aresetn), .reg_valid_i(mmio_select), .reg_write_i(data_we),
    .reg_addr_i(data_addr[7:0]), .reg_wdata_i(data_wdata), .reg_rdata_o(dma_reg_rdata),
    .m_axi_araddr_o(dma_araddr), .m_axi_arlen_o(dma_arlen), .m_axi_arsize_o(dma_arsize),
    .m_axi_arburst_o(dma_arburst), .m_axi_arvalid_o(dma_arvalid), .m_axi_arready_i(dma_arready),
    .m_axi_rdata_i(dma_rdata_q), .m_axi_rresp_i(2'b00), .m_axi_rlast_i(dma_rlast),
    .m_axi_rvalid_i(dma_rvalid), .m_axi_rready_o(dma_rready)
  );

  // DMA reads the second BRAM port directly. The local AXI-shaped responder
  // supports incrementing bursts and advances the BRAM address after each
  // accepted data beat.
  assign dma_arready = !dma_read_pending_q && !host_cpu_reset_q;
  assign dma_rvalid = dma_read_pending_q;
  assign dma_rlast = dma_beats_left_q == 0;
  assign dma_rdata_q = host_bram_rdata;
  always_ff @(posedge aclk) begin
    instr_rvalid <= instr_req;
    data_rvalid <= data_req;
    data_mmio_q <= mmio_select;
    if (mmio_select) data_mmio_rdata_q <= dma_reg_rdata;
    if (instr_req) instr_rdata_q <= instruction_rom[instr_addr[11:2]];
    if (data_req) begin
      if (data_we && !mmio_select && data_addr[31:16] == 16'h0) begin
        if (data_addr == 32'h1000) mailbox <= data_wdata;
        case (data_addr)
          32'h10a0: metrics_q[0] <= data_wdata;
          32'h10a4: metrics_q[1] <= data_wdata;
          32'h10a8: metrics_q[2] <= data_wdata;
          32'h10ac: metrics_q[3] <= data_wdata;
          32'h10b0: metrics_q[4] <= data_wdata;
          32'h10b4: metrics_q[5] <= data_wdata;
          32'h10b8,32'h10bc,32'h10c0,32'h10c4,32'h10c8,
          32'h10cc,32'h10d0,32'h10d4,32'h10d8,32'h10dc:
            metrics_q[6 + ((data_addr - 32'h10b8) >> 2)] <= data_wdata;
          default: ;
        endcase
      end
    end
    if (!cpu_resetn) begin
      instr_rvalid <= 1'b0; data_rvalid <= 1'b0;
      data_mmio_q <= 1'b0; data_mmio_rdata_q <= '0;
      dma_read_pending_q <= 1'b0;
      dma_beats_left_q <= '0;
      dma_bram_addr_q <= '0;
      mailbox <= '0;
      for (int metric = 0; metric < 16; metric++) metrics_q[metric] <= '0;
    end else begin
      if (dma_arvalid && dma_arready) begin
        dma_read_pending_q <= 1'b1;
        dma_beats_left_q <= dma_arlen;
        dma_bram_addr_q <= dma_araddr[15:2];
      end else if (dma_rvalid && dma_rready) begin
        if (dma_rlast) dma_read_pending_q <= 1'b0;
        else begin
          dma_beats_left_q <= dma_beats_left_q - 1'b1;
          dma_bram_addr_q <= dma_bram_addr_q + 1'b1;
        end
      end
    end
  end

  // PS/JTAG is an observer only.  Offsets expose completion and benchmark data.
  always_comb begin
    case (s_axi_araddr)
      8'h00: s_axi_rdata = mailbox;
      8'h04: s_axi_rdata = mcycle[31:0];
      8'h08: s_axi_rdata = mcycle[63:32];
      8'h0c: s_axi_rdata = metrics_q[3]; // hardware prediction
      8'h10: s_axi_rdata = metrics_q[4]; // expected label
      8'h14: s_axi_rdata = metrics_q[5]; // DMA MAC count
      8'h18: s_axi_rdata = metrics_q[0]; // scalar CPU cycles
      8'h1c: s_axi_rdata = metrics_q[1]; // accelerator cycles
      8'h20: s_axi_rdata = nn_instruction_count[31:0];
      8'h24: s_axi_rdata = nn_array_mac_count[31:0];
      8'h40,8'h44,8'h48,8'h4c,8'h50,8'h54,8'h58,8'h5c,8'h60,8'h64:
        s_axi_rdata = metrics_q[6 + ((s_axi_araddr - 8'h40) >> 2)];
      8'h80: s_axi_rdata = {31'h0,host_cpu_reset_q};
      8'h84: s_axi_rdata = {18'h0,host_bram_addr_q};
      8'h88: s_axi_rdata = host_bram_rdata;
      8'h8c: s_axi_rdata = completed_count_q;
      8'h90: s_axi_rdata = last_run_cycles_q;
      8'h94: s_axi_rdata = run_cycles_q;
      default: s_axi_rdata = 32'h0;
    endcase
  end
  assign s_axi_awready = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
  assign s_axi_wready = s_axi_awready;
  assign s_axi_bresp = 2'b00;
  assign s_axi_arready = !s_axi_rvalid;
  assign s_axi_rresp = 2'b00;
  assign host_bram_write = s_axi_awready && (s_axi_awaddr == 8'h88) && host_cpu_reset_q;
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      s_axi_bvalid <= 1'b0; s_axi_rvalid <= 1'b0;
      host_cpu_reset_q <= 1'b0; host_bram_addr_q <= '0;
      completed_count_q <= '0; run_cycles_q <= '0; last_run_cycles_q <= '0;
    end
    else begin
      if (s_axi_awready) begin
        s_axi_bvalid <= 1'b1;
        case (s_axi_awaddr)
          8'h80: begin
            host_cpu_reset_q <= s_axi_wdata[0];
            if (s_axi_wdata[0]) run_cycles_q <= '0;
          end
          8'h84: host_bram_addr_q <= s_axi_wdata[13:0];
          8'h88: if (host_cpu_reset_q) host_bram_addr_q <= host_bram_addr_q + 1'b1;
          default: ;
        endcase
      end
      else if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
      if (s_axi_arready && s_axi_arvalid) s_axi_rvalid <= 1'b1;
      else if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
      if (!host_cpu_reset_q && mailbox == 0) run_cycles_q <= run_cycles_q + 1'b1;
      if (data_req && data_we && data_addr == 32'h1000 && data_wdata != 0) begin
        last_run_cycles_q <= run_cycles_q;
        completed_count_q <= completed_count_q + 1'b1;
      end
    end
  end

  // External master is reserved for the next DDR-backed batch-image stage.
  assign m_axi_araddr = '0; assign m_axi_arlen = '0; assign m_axi_arsize = 3'd2;
  assign m_axi_arburst = 2'b01; assign m_axi_arvalid = 1'b0; assign m_axi_rready = 1'b0;
  logic unused;
  assign unused = ^{s_axi_awaddr,s_axi_wdata,s_axi_wstrb,m_axi_arready,m_axi_rdata,
                    m_axi_rresp,m_axi_rlast,m_axi_rvalid,dma_arsize,dma_arburst};
endmodule

`default_nettype wire
