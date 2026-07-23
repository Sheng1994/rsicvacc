`default_nettype none

module nn_execution_unit (
  input wire logic [2:0]  operation_i,
  input wire logic [31:0] rs1_i,
  input wire logic [31:0] rs2_i,
  input wire logic [31:0] multiplier_i,
  input wire logic [4:0]  shift_i,
  input wire logic [31:0] zero_point_i,
  output logic [31:0] result_o
);
  localparam logic [2:0] NN_DOTP4 = 3'b000;
  localparam logic [2:0] NN_RELU = 3'b001;
  localparam logic [2:0] NN_CLIP8 = 3'b010;
  localparam logic [2:0] NN_MAX4 = 3'b011;
  localparam logic [2:0] NN_REQUANT = 3'b100;
  logic [31:0] dotp4_result;
  logic [31:0] quant_result;
  logic signed [7:0] max_lane;

  nn_dotp4_unit dotp4_i (
    .lhs_i   (rs1_i),
    .rhs_i   (rs2_i),
    .result_o(dotp4_result)
  );

  nn_quant_unit quant_i (
    .value_i      (rs1_i),
    .multiplier_i (multiplier_i),
    .shift_i      (shift_i),
    .zero_point_i (zero_point_i),
    .result_o     (quant_result)
  );

  always_comb begin
    result_o = '0;
    max_lane = $signed(rs1_i[7:0]);
    for (int unsigned i = 1; i < 4; i++) begin
      if ($signed(rs1_i[i*8 +: 8]) > max_lane)
        max_lane = $signed(rs1_i[i*8 +: 8]);
    end
    case (operation_i)
      NN_DOTP4: result_o = dotp4_result;
      NN_RELU: result_o = $signed(rs1_i) < 0 ? 32'd0 : rs1_i;
      NN_CLIP8: begin
        if ($signed(rs1_i) > 127) result_o = 32'd127;
        else if ($signed(rs1_i) < -128) result_o = -32'sd128;
        else result_o = {{24{rs1_i[7]}}, rs1_i[7:0]};
      end
      NN_MAX4: result_o = {{24{max_lane[7]}}, max_lane};
      NN_REQUANT: result_o = quant_result;
      default: result_o = '0;
    endcase
  end
endmodule

`default_nettype wire
