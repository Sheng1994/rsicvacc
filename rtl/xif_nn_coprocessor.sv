`default_nettype none

module xif_nn_coprocessor (
  input wire logic clk_i,
  input wire logic rst_ni,
  output logic [63:0] nn_instruction_count_o,
  output logic [63:0] nn_dotp4_count_o,
  output logic [63:0] nn_requant_count_o,
  output logic [63:0] nn_array_mac_count_o,
  output logic        trace_valid_o,
  output logic [3:0]  trace_id_o,
  output logic [2:0]  trace_operation_o,
  output logic        trace_kill_o,
  output logic [31:0] trace_result_o,
  cv32e40x_if_xif.coproc_compressed xif_compressed_if,
  cv32e40x_if_xif.coproc_issue      xif_issue_if,
  cv32e40x_if_xif.coproc_commit     xif_commit_if,
  cv32e40x_if_xif.coproc_mem        xif_mem_if,
  cv32e40x_if_xif.coproc_mem_result xif_mem_result_if,
  cv32e40x_if_xif.coproc_result     xif_result_if
);
  typedef enum logic [1:0] {IDLE, WAIT_COMMIT, SEND_RESULT} state_t;
  state_t state_q;

  logic decode_valid;
  logic [2:0] decode_operation;
  logic decode_rs1, decode_rs2;
  logic decode_writeback;
  logic decode_counter_read;
  logic decode_array_command;
  logic [3:0] id_q;
  logic [4:0] rd_q;
  logic [31:0] result_q;
  logic [31:0] execute_result;
  logic [2:0] operation_q;
  logic [31:0] config_value_q;
  logic writeback_q;
  logic [31:0] multiplier_q;
  logic [4:0] shift_q;
  logic [31:0] zero_point_q;
  logic counter_read_q;
  logic array_command_q;
  logic [31:0] operand2_q;
  logic array_busy, array_done;
  logic [31:0] array_result;
  logic array_load_activation, array_load_weight, array_start, array_clear;
  logic [1:0] array_row_index;

  nn_decoder decoder_i (
    .instr_i    (xif_issue_if.issue_req.instr),
    .valid_o    (decode_valid),
    .operation_o(decode_operation),
    .uses_rs1_o (decode_rs1),
    .uses_rs2_o (decode_rs2),
    .writeback_o(decode_writeback),
    .counter_read_o(decode_counter_read),
    .array_command_o(decode_array_command)
  );

  nn_mac_array array_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .load_activation_i(array_load_activation), .load_weight_i(array_load_weight),
    .clear_i(array_clear), .start_i(array_start),
    .block_index_i(config_value_q[1:0]), .row_index_i(array_row_index),
    .packed_data_i(operand2_q), .busy_o(array_busy), .done_o(array_done),
    .result_o(array_result), .mac_count_o(nn_array_mac_count_o)
  );

  nn_execution_unit execution_i (
    .operation_i(decode_operation),
    .rs1_i      (xif_issue_if.issue_req.rs[0]),
    .rs2_i      (xif_issue_if.issue_req.rs[1]),
    .multiplier_i(multiplier_q),
    .shift_i     (shift_q),
    .zero_point_i(zero_point_q),
    .result_o   (execute_result)
  );

  always_comb begin
    array_row_index = ((state_q == IDLE) && decode_array_command &&
                       (decode_operation == 3'b100)) ?
                      xif_issue_if.issue_req.rs[0][1:0] : config_value_q[3:2];
    array_load_activation = 1'b0;
    array_load_weight = 1'b0;
    array_start = 1'b0;
    array_clear = 1'b0;
    if ((state_q == WAIT_COMMIT) && xif_commit_if.commit_valid &&
        (xif_commit_if.commit.id == id_q) && !xif_commit_if.commit.commit_kill &&
        array_command_q) begin
      case (operation_q)
        3'b000: array_load_activation = 1'b1;
        3'b001: array_load_weight = 1'b1;
        3'b010: array_start = 1'b1;
        3'b101: array_clear = 1'b1;
        default: ;
      endcase
    end
    xif_compressed_if.compressed_ready = 1'b1;
    xif_compressed_if.compressed_resp  = '0;

    xif_issue_if.issue_ready           = (state_q == IDLE);
    xif_issue_if.issue_resp            = '0;
    xif_issue_if.issue_resp.accept     = decode_valid;
    // Configuration operations also request the result phase, with result.we
    // cleared, to serialize them through the CV32E40X XIF pipeline.
    xif_issue_if.issue_resp.writeback  = decode_valid;

    xif_mem_if.mem_valid               = 1'b0;
    xif_mem_if.mem_req                 = '0;

    xif_result_if.result_valid         = (state_q == SEND_RESULT);
    xif_result_if.result               = '0;
    xif_result_if.result.id            = id_q;
    xif_result_if.result.data          = result_q;
    xif_result_if.result.rd            = rd_q;
    xif_result_if.result.we            = writeback_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= IDLE;
      id_q     <= '0;
      rd_q     <= '0;
      result_q <= '0;
      operation_q <= '0;
      config_value_q <= '0;
      writeback_q <= 1'b0;
      multiplier_q <= 32'd1;
      shift_q <= '0;
      zero_point_q <= '0;
      counter_read_q <= 1'b0;
      array_command_q <= 1'b0;
      operand2_q <= '0;
      nn_instruction_count_o <= '0;
      nn_dotp4_count_o <= '0;
      nn_requant_count_o <= '0;
      trace_valid_o <= 1'b0;
      trace_id_o <= '0;
      trace_operation_o <= '0;
      trace_kill_o <= 1'b0;
      trace_result_o <= '0;
    end else begin
      trace_valid_o <= 1'b0;
      case (state_q)
        IDLE: begin
          if (xif_issue_if.issue_valid && xif_issue_if.issue_ready && decode_valid &&
              (!decode_rs1 || xif_issue_if.issue_req.rs_valid[0]) &&
              (!decode_rs2 || xif_issue_if.issue_req.rs_valid[1])) begin
            id_q     <= xif_issue_if.issue_req.id;
            rd_q     <= xif_issue_if.issue_req.instr[11:7];
            if (decode_array_command) begin
              case (decode_operation)
                3'b011: result_q <= {30'd0, array_done, array_busy};
                3'b100: result_q <= array_result;
                default: result_q <= '0;
              endcase
            end else if (decode_counter_read) begin
              case (decode_operation)
                3'b000: result_q <= nn_instruction_count_o[31:0];
                3'b001: result_q <= nn_dotp4_count_o[31:0];
                3'b010: result_q <= nn_requant_count_o[31:0];
                default: result_q <= '0;
              endcase
            end else begin
              result_q <= execute_result;
            end
            operation_q <= decode_operation;
            config_value_q <= xif_issue_if.issue_req.rs[0];
            operand2_q <= xif_issue_if.issue_req.rs[1];
            writeback_q <= decode_writeback;
            counter_read_q <= decode_counter_read;
            array_command_q <= decode_array_command;
            state_q  <= WAIT_COMMIT;
          end
        end
        WAIT_COMMIT: begin
          if (xif_commit_if.commit_valid && (xif_commit_if.commit.id == id_q)) begin
            trace_valid_o <= 1'b1;
            trace_id_o <= id_q;
            trace_operation_o <= operation_q;
            trace_kill_o <= xif_commit_if.commit.commit_kill;
            trace_result_o <= result_q;
            if (xif_commit_if.commit.commit_kill) begin
              state_q <= IDLE;
            end else begin
              if (writeback_q && !counter_read_q && !array_command_q) begin
                nn_instruction_count_o <= nn_instruction_count_o + 64'd1;
                if (operation_q == 3'b000) nn_dotp4_count_o <= nn_dotp4_count_o + 64'd1;
                if (operation_q == 3'b100) nn_requant_count_o <= nn_requant_count_o + 64'd1;
              end
              if (!writeback_q && !array_command_q) begin
                case (operation_q)
                  3'b101: multiplier_q <= config_value_q;
                  3'b110: shift_q <= config_value_q[4:0];
                  3'b111: zero_point_q <= config_value_q;
                  default: ;
                endcase
              end
              state_q <= SEND_RESULT;
            end
          end
        end
        SEND_RESULT: begin
          if (xif_result_if.result_ready) state_q <= IDLE;
        end
        default: state_q <= IDLE;
      endcase
    end
  end

  logic unused_inputs;
  always_comb begin
    unused_inputs = xif_compressed_if.compressed_valid |
                    xif_mem_if.mem_ready |
                    xif_mem_result_if.mem_result_valid;
  end
endmodule

`default_nettype wire
