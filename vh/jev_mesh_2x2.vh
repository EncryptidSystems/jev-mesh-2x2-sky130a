// Macro blackbox. Signal ports match rtl/jev_mesh_2x2.v.
// VPWR and VGND are the sky130_fd_sc_hd supplies of the hardened view.
// Another public PDK synthesizes the RTL and uses that PDK's supply names.
module jev_mesh_2x2(
`ifdef USE_POWER_PINS
  inout VPWR,
  inout VGND,
`endif
  input clk,
  input rst,
  input n_valid,
  input[1:0] n_kind,
  input[31:0] n_d0,
  input[31:0] n_d1,
  input s_ready,
  input w_valid,
  input[31:0] w_p0,
  input[31:0] w_p1,
  input e_ready,
  output n_ready,
  output s_valid,
  output[1:0] s_kind,
  output[31:0] s_d0,
  output[31:0] s_d1,
  output w_ready,
  output e_valid,
  output[31:0] e_p0,
  output[31:0] e_p1
);
endmodule
