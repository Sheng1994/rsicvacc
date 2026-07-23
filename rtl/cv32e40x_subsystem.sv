`default_nettype none

module cv32e40x_subsystem import cv32e40x_pkg::*; #(
  parameter logic [31:0] BOOT_ADDR = 32'h0000_0000
) (
  input  wire logic   clk_i,
  input  wire logic   rst_ni,
  input  wire logic   fetch_enable_i,

  output logic        instr_req_o,
  input  wire logic   instr_gnt_i,
  input  wire logic   instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  wire logic [31:0] instr_rdata_i,
  input  wire logic   instr_err_i,

  output logic        data_req_o,
  input  wire logic   data_gnt_i,
  input  wire logic   data_rvalid_i,
  output logic [31:0] data_addr_o,
  output logic [3:0]  data_be_o,
  output logic        data_we_o,
  output logic [31:0] data_wdata_o,
  input  wire logic [31:0] data_rdata_i,
  input  wire logic   data_err_i,

  input  wire logic [31:0] irq_i,
  output logic [63:0] mcycle_o,
  output logic [63:0] nn_instruction_count_o,
  output logic [63:0] nn_dotp4_count_o,
  output logic [63:0] nn_requant_count_o,
  output logic [63:0] nn_array_mac_count_o,
  output logic        nn_trace_valid_o,
  output logic [3:0]  nn_trace_id_o,
  output logic [2:0]  nn_trace_operation_o,
  output logic        nn_trace_kill_o,
  output logic [31:0] nn_trace_result_o,
  output logic        core_sleep_o
);
  localparam int unsigned X_NUM_RS    = 2;
  localparam int unsigned X_ID_WIDTH  = 4;
  localparam int unsigned X_MEM_WIDTH = 32;
  localparam int unsigned X_RFR_WIDTH = 32;
  localparam int unsigned X_RFW_WIDTH = 32;
  // Executable code occupies 0x0000_0000..0x0000_0fff. The default PMA
  // attribution is I/O, which rejects split/misaligned data transactions
  // before they reach OBI while still allowing naturally aligned accesses.
  localparam int unsigned PMA_NUM_REGIONS = 1;
  localparam pma_cfg_t PMA_CFG_LOCAL [PMA_NUM_REGIONS-1:0] = '{'{
    word_addr_low: 32'h0000_0000,
    word_addr_high: 32'h0000_03ff,
    main: 1'b1,
    bufferable: 1'b0,
    cacheable: 1'b0,
    atomic: 1'b0
  }};

  cv32e40x_if_xif #(
    .X_NUM_RS   (X_NUM_RS),
    .X_ID_WIDTH (X_ID_WIDTH),
    .X_MEM_WIDTH(X_MEM_WIDTH),
    .X_RFR_WIDTH(X_RFR_WIDTH),
    .X_RFW_WIDTH(X_RFW_WIDTH)
  ) xif ();

  logic [1:0] instr_memtype;
  logic [2:0] instr_prot;
  logic       instr_dbg;
  logic [1:0] data_memtype;
  logic [2:0] data_prot;
  logic       data_dbg;
  logic [5:0] data_atop;
  logic       fencei_flush_req;
  logic       debug_havereset;
  logic       debug_running;
  logic       debug_halted;
  logic       debug_pc_valid;
  logic [31:0] debug_pc;

  xif_nn_coprocessor xif_nn_i (
    .clk_i,
    .rst_ni,
    .nn_instruction_count_o,
    .nn_dotp4_count_o,
    .nn_requant_count_o,
    .nn_array_mac_count_o,
    .trace_valid_o(nn_trace_valid_o),
    .trace_id_o(nn_trace_id_o),
    .trace_operation_o(nn_trace_operation_o),
    .trace_kill_o(nn_trace_kill_o),
    .trace_result_o(nn_trace_result_o),
    .xif_compressed_if(xif),
    .xif_issue_if     (xif),
    .xif_commit_if    (xif),
    .xif_mem_if       (xif),
    .xif_mem_result_if(xif),
    .xif_result_if    (xif)
  );

  cv32e40x_core #(
    .RV32       (RV32I),
    .A_EXT      (A_NONE),
    .B_EXT      (B_NONE),
    .M_EXT      (M),
    .DEBUG      (1'b0),
    .CLIC       (1'b0),
    .X_EXT      (1'b1),
    .X_NUM_RS   (X_NUM_RS),
    .X_ID_WIDTH (X_ID_WIDTH),
    .X_MEM_WIDTH(X_MEM_WIDTH),
    .X_RFR_WIDTH(X_RFR_WIDTH),
    .X_RFW_WIDTH(X_RFW_WIDTH),
    .PMA_NUM_REGIONS(PMA_NUM_REGIONS),
    .PMA_CFG(PMA_CFG_LOCAL)
  ) core_i (
    .clk_i,
    .rst_ni,
    // FPGA implementation: keep integrated clock gates transparent so all
    // core flops remain on the routed global clock and avoid gated-clock skew.
    .scan_cg_en_i       (1'b1),
    .boot_addr_i        (BOOT_ADDR),
    .dm_exception_addr_i(32'h0000_0100),
    .dm_halt_addr_i     (32'h0000_0100),
    .mhartid_i          (32'h0),
    .mimpid_patch_i     (4'h0),
    .mtvec_addr_i       (32'h0000_0100),
    .instr_req_o,
    .instr_gnt_i,
    .instr_rvalid_i,
    .instr_addr_o,
    .instr_memtype_o    (instr_memtype),
    .instr_prot_o       (instr_prot),
    .instr_dbg_o        (instr_dbg),
    .instr_rdata_i,
    .instr_err_i,
    .data_req_o,
    .data_gnt_i,
    .data_rvalid_i,
    .data_addr_o,
    .data_be_o,
    .data_we_o,
    .data_wdata_o,
    .data_memtype_o     (data_memtype),
    .data_prot_o        (data_prot),
    .data_dbg_o         (data_dbg),
    .data_atop_o        (data_atop),
    .data_rdata_i,
    .data_err_i,
    .data_exokay_i      (1'b0),
    .mcycle_o,
    .time_i             (64'h0),
    .xif_compressed_if  (xif),
    .xif_issue_if       (xif),
    .xif_commit_if      (xif),
    .xif_mem_if         (xif),
    .xif_mem_result_if  (xif),
    .xif_result_if      (xif),
    .irq_i,
    .wu_wfe_i           (1'b0),
    .clic_irq_i         (1'b0),
    .clic_irq_id_i      ('0),
    .clic_irq_level_i   ('0),
    .clic_irq_priv_i    ('0),
    .clic_irq_shv_i     (1'b0),
    .fencei_flush_req_o (fencei_flush_req),
    .fencei_flush_ack_i (fencei_flush_req),
    .debug_req_i        (1'b0),
    .debug_havereset_o  (debug_havereset),
    .debug_running_o    (debug_running),
    .debug_halted_o     (debug_halted),
    .debug_pc_valid_o   (debug_pc_valid),
    .debug_pc_o         (debug_pc),
    .fetch_enable_i,
    .core_sleep_o
  );
endmodule

`default_nettype wire
