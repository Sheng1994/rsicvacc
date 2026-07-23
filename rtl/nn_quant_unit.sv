`default_nettype none

module nn_quant_unit (
  input wire logic [31:0] value_i,
  input wire logic [31:0] multiplier_i,
  input wire logic [4:0]  shift_i,
  input wire logic [31:0] zero_point_i,
  output logic [31:0] result_o
);
  logic signed [63:0] wide;
  logic signed [63:0] magnitude;
  logic signed [63:0] rounded;
  logic signed [63:0] biased;
  logic signed [63:0] offset;

  always_comb begin
    wide = $signed(value_i) * $signed(multiplier_i);
    magnitude = (wide < 0) ? -wide : wide;
    offset = 64'sd0;
    rounded = wide;
    biased = 64'sd0;
    result_o = 32'd0;
    if (shift_i == 0) begin
      rounded = wide;
    end else begin
      offset = 64'sd1 <<< (shift_i - 1'b1);
      rounded = (magnitude + offset) >>> shift_i;
      if (wide < 0) rounded = -rounded;
    end
    biased = rounded + $signed({{32{zero_point_i[31]}}, zero_point_i});
    if (biased > 127)
      result_o = 32'd127;
    else if (biased < -128)
      result_o = -32'sd128;
    else
      result_o = {{24{biased[7]}}, biased[7:0]};
  end
endmodule

`default_nettype wire
