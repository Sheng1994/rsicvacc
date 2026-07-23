`default_nettype none

module nn_decoder (
  input wire logic [31:0] instr_i,
  output logic        valid_o,
  output logic [2:0]  operation_o,
  output logic        uses_rs1_o,
  output logic        uses_rs2_o,
  output logic        writeback_o,
  output logic        counter_read_o,
  output logic        array_command_o
);
  localparam logic [6:0] OPCODE_CUSTOM_0 = 7'b0001011;

  always_comb begin
    valid_o     = 1'b0;
    operation_o = instr_i[14:12];
    uses_rs1_o  = 1'b0;
    uses_rs2_o  = 1'b0;
    writeback_o = 1'b0;
    counter_read_o = 1'b0;
    array_command_o = 1'b0;

    // All allocated operation/configuration encodings require funct7=0.
    // Other custom encodings retain the core's illegal-instruction behavior.
    if ((instr_i[6:0] == OPCODE_CUSTOM_0) &&
        (instr_i[31:25] == 7'b0000000)) begin
      valid_o    = 1'b1;
      uses_rs1_o = 1'b1;
      uses_rs2_o = (instr_i[14:12] == 3'b000);
      writeback_o = (instr_i[14:12] <= 3'b100);
    end else if ((instr_i[6:0] == OPCODE_CUSTOM_0) &&
                 (instr_i[31:25] == 7'b0000001) &&
                 (instr_i[14:12] <= 3'b010)) begin
      valid_o = 1'b1;
      writeback_o = 1'b1;
      counter_read_o = 1'b1;
    end else if ((instr_i[6:0] == OPCODE_CUSTOM_0) &&
                 (instr_i[31:25] == 7'b0000010) &&
                 (instr_i[14:12] <= 3'b101)) begin
      // Array commands: load activation, load weight, start, status,
      // read accumulator, and clear respectively.
      valid_o = 1'b1;
      array_command_o = 1'b1;
      uses_rs1_o = (instr_i[14:12] == 3'b000) ||
                   (instr_i[14:12] == 3'b001) ||
                   (instr_i[14:12] == 3'b100);
      uses_rs2_o = (instr_i[14:12] == 3'b000) ||
                   (instr_i[14:12] == 3'b001);
      writeback_o = (instr_i[14:12] == 3'b011) ||
                    (instr_i[14:12] == 3'b100);
    end
  end
endmodule

`default_nettype wire
