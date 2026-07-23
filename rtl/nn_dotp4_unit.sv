`default_nettype none

module nn_dotp4_unit (
  input wire logic [31:0] lhs_i,
  input wire logic [31:0] rhs_i,
  output logic [31:0] result_o
);
  logic signed [15:0] product [0:3];
  logic signed [16:0] sum_lo;
  logic signed [16:0] sum_hi;
  logic signed [17:0] sum;

  always_comb begin
    for (int unsigned i = 0; i < 4; i++) begin
      product[i] = $signed(lhs_i[i*8 +: 8]) * $signed(rhs_i[i*8 +: 8]);
    end
    sum_lo   = product[0] + product[1];
    sum_hi   = product[2] + product[3];
    sum      = sum_lo + sum_hi;
    result_o = {{14{sum[17]}}, sum};
  end
endmodule

`default_nettype wire
