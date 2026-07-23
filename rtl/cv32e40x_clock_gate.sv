`default_nettype none

// Vendor-independent integration model. FPGA Stage B may replace this module
// in its adapter layer without changing the CPU or coprocessor RTL.
module cv32e40x_clock_gate #(
  parameter int LIB = 0
) (
  input  wire logic clk_i,
  input  wire logic en_i,
  input  wire logic scan_cg_en_i,
  output logic clk_o
);
  logic enable_latched;

  // A low-level latch prevents enable changes while clk_i is high. Verilator
  // classifies always_latch as combinational for COMBDLY purposes, but the NBA
  // is intentional because this is storage, not combinational logic.
  /* verilator lint_off COMBDLY */
  always_latch begin
    if (!clk_i) begin
      enable_latched <= en_i | scan_cg_en_i;
    end
  end
  /* verilator lint_on COMBDLY */

  assign clk_o = clk_i & enable_latched;

  logic unused_lib;
  assign unused_lib = (LIB != 0);
endmodule

`default_nettype wire
