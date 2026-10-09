// jev_mesh_2x2, hierarchical: the mesh tile as a top level that places four
// jev_dot_pipe engines -- our signed-off die, hardened once as a macro -- and
// keeps the mesh logic around them: Jev's router and flow control, the
// weight-stationary registers, the activation staging, the south and east link
// buffers, and the row adders. It mirrors BuildJevMeshTile (heapvm/vgpu/vgpu.cc)
// port for port and clock for clock; mesh_eq_tb.v checks it against the EDA's
// flat netlist.
//
//   north in   n_valid, n_kind, n_d0, n_d1 / n_ready   a beat a clock; lane c feeds column c
//   south out  s_valid, s_kind, s_d0, s_d1 / s_ready   activations and what is not ours
//   west in    w_valid, w_p0, w_p1 / w_ready           partial row sums (a bias at the left edge)
//   east out   e_valid, e_p0, e_p1 / e_ready           west + this tile's row sums
//
// Flit kinds: 0 act, 1 wgt, 2 cfg (reload), 3 fence. The three Jev microcode
// ROMs are kept as the tables the fabric synthesized (see jev_mesh_2x2.rom.txt).
`timescale 1ns/1ps
module jev_mesh_2x2 (
  input  wire        clk,
  input  wire        rst,
  input  wire        n_valid,
  input  wire [1:0]  n_kind,
  input  wire [31:0] n_d0,
  input  wire [31:0] n_d1,
  input  wire        s_ready,
  input  wire        w_valid,
  input  wire [31:0] w_p0,
  input  wire [31:0] w_p1,
  input  wire        e_ready,
  output wire        n_ready,
  output wire        s_valid,
  output wire [1:0]  s_kind,
  output wire [31:0] s_d0,
  output wire [31:0] s_d1,
  output wire        w_ready,
  output wire        e_valid,
  output wire [31:0] e_p0,
  output wire [31:0] e_p1
);
  localparam [1:0] STAGE = 2'd0, LOAD = 2'd1, PASS = 2'd2, RESET = 2'd3;

  // ---- jev_route: Jev's answer for (kind, weights full) ----
  reg  [3:0] wcnt;
  wire       wfull = wcnt == 4'd8;
  reg  [1:0] act;
  always @(*) begin
    case ({wfull, n_kind})
      3'b000, 3'b100: act = STAGE;  // an activation: ours, and the column's below
      3'b001:         act = LOAD;   // a weight while we fill
      3'b101:         act = PASS;   // a weight once full: the next tile's
      3'b010, 3'b110: act = RESET;  // reload: clear the fill count, tell the column
      default:        act = PASS;   // a fence
    endcase
  end

  // ---- the engines' side ----
  reg  [1:0]  akcnt;
  reg         pend;
  wire        e00_in_ready;
  wire        last_beat = akcnt == 2'd3;
  wire        x_ready = !pend || e00_in_ready;
  wire        x_ok = !last_beat || x_ready;  // the 4th beat starts the set

  // ---- jev_accept: take the north beat, or stall it ----
  reg         s_tv;
  wire        s_space = !s_tv;
  reg         take;
  always @(*) begin
    case (act)
      LOAD:    take = 1'b1;               // sinks here
      STAGE:   take = s_space && x_ok;    // staged and passed on
      default: take = s_space;            // pass, reset: passed on
    endcase
  end
  assign n_ready = take;
  wire fire = n_valid && take;
  wire stage_fire = fire && act == STAGE;
  wire load_fire = fire && act == LOAD;
  wire reset_fire = fire && act == RESET;
  wire fwd = fire && act != LOAD;

  // ---- weights: beat b of a fill writes weight (row b/4, column c, k b%4) from lane c ----
  reg [31:0] wt [0:15];  // engine (r, c) weight k at (r*2 + c)*4 + k
  integer i, j;
  always @(posedge clk) begin
    if (rst) begin
      wcnt <= 4'd0;
      for (i = 0; i < 16; i = i + 1) wt[i] <= 32'd0;
    end else begin
      if (load_fire && wcnt < 4'd8) begin
        wt[{wcnt[2], 1'b0, wcnt[1:0]}] <= n_d0;  // column 0
        wt[{wcnt[2], 1'b1, wcnt[1:0]}] <= n_d1;  // column 1
      end
      wcnt <= reset_fire ? 4'd0 : load_fire ? wcnt + 4'd1 : wcnt;
    end
  end

  // ---- activations: staging, then the set the engines hold ----
  reg  [31:0] xs [0:7];  // column c, beat k at c*4 + k
  reg  [31:0] xa [0:7];
  wire [31:0] xs_next [0:7];
  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin : stage
      assign xs_next[g] = (stage_fire && akcnt == (g % 4)) ? (g < 4 ? n_d0 : n_d1) : xs[g];
    end
  endgenerate
  wire start = stage_fire && last_beat;

  // ---- jev_join: the row sums leave east with the west sums ----
  reg         e_tv;
  wire        e_space = !e_tv;
  wire        e00_out_valid;
  wire        emit = e00_out_valid && w_valid && e_space;
  assign w_ready = emit;

  // ---- the engines: our die, four times ----
  wire [31:0] r00, r01, r10, r11;
  wire        unused_ir01, unused_ir10, unused_ir11, unused_ov01, unused_ov10, unused_ov11;
  jev_dot_pipe e0_0 (.clk(clk), .rst(rst), .x0(xa[0]), .x1(xa[1]), .x2(xa[2]), .x3(xa[3]),
                     .w0(wt[0]), .w1(wt[1]), .w2(wt[2]), .w3(wt[3]), .in_valid(pend), .out_ready(emit),
                     .in_ready(e00_in_ready), .result(r00), .out_valid(e00_out_valid));
  jev_dot_pipe e0_1 (.clk(clk), .rst(rst), .x0(xa[4]), .x1(xa[5]), .x2(xa[6]), .x3(xa[7]),
                     .w0(wt[4]), .w1(wt[5]), .w2(wt[6]), .w3(wt[7]), .in_valid(pend), .out_ready(emit),
                     .in_ready(unused_ir01), .result(r01), .out_valid(unused_ov01));
  jev_dot_pipe e1_0 (.clk(clk), .rst(rst), .x0(xa[0]), .x1(xa[1]), .x2(xa[2]), .x3(xa[3]),
                     .w0(wt[8]), .w1(wt[9]), .w2(wt[10]), .w3(wt[11]), .in_valid(pend), .out_ready(emit),
                     .in_ready(unused_ir10), .result(r10), .out_valid(unused_ov10));
  jev_dot_pipe e1_1 (.clk(clk), .rst(rst), .x0(xa[4]), .x1(xa[5]), .x2(xa[6]), .x3(xa[7]),
                     .w0(wt[12]), .w1(wt[13]), .w2(wt[14]), .w3(wt[15]), .in_valid(pend), .out_ready(emit),
                     .in_ready(unused_ir11), .result(r11), .out_valid(unused_ov11));

  always @(posedge clk) begin
    if (rst) begin
      akcnt <= 2'd0;
      pend <= 1'b0;
      for (j = 0; j < 8; j = j + 1) begin
        xs[j] <= 32'd0;
        xa[j] <= 32'd0;
      end
    end else begin
      if (stage_fire) akcnt <= akcnt + 2'd1;
      pend <= start || (pend && !e00_in_ready);
      for (j = 0; j < 8; j = j + 1) begin
        xs[j] <= xs_next[j];
        if (start) xa[j] <= xs_next[j];
      end
    end
  end

  // ---- the link buffers: two slots each, outputs from registers only ----
  // south: activations, passed weights, reloads and fences go on down
  reg        s_hv;
  reg [1:0]  s_hk, s_tk;
  reg [31:0] s_h0, s_h1, s_t0, s_t1;
  wire s_deq = s_hv && s_ready;
  wire s_hin = fwd && (!s_hv || (s_deq && !s_tv));
  wire s_htl = s_deq && s_tv;
  wire s_tin = fwd && s_hv && !s_deq;
  always @(posedge clk) begin
    if (rst) begin
      s_hv <= 1'b0; s_tv <= 1'b0; s_hk <= 2'd0; s_tk <= 2'd0;
      s_h0 <= 32'd0; s_h1 <= 32'd0; s_t0 <= 32'd0; s_t1 <= 32'd0;
    end else begin
      s_hv <= s_tv || fwd || (s_hv && !s_deq);
      s_tv <= (s_tv && !s_deq) || (fwd && s_hv && !s_deq);
      if (s_tin) begin s_tk <= n_kind; s_t0 <= n_d0; s_t1 <= n_d1; end
      if (s_htl) begin s_hk <= s_tk; s_h0 <= s_t0; s_h1 <= s_t1; end
      else if (s_hin) begin s_hk <= n_kind; s_h0 <= n_d0; s_h1 <= n_d1; end
    end
  end
  assign s_valid = s_hv;
  assign s_kind = s_hk;
  assign s_d0 = s_h0;
  assign s_d1 = s_h1;

  // east: west sums + this tile's row sums
  wire [31:0] y0 = (w_p0 + r00) + r01;
  wire [31:0] y1 = (w_p1 + r10) + r11;
  reg        e_hv;
  reg [31:0] e_h0, e_h1, e_t0, e_t1;
  wire e_deq = e_hv && e_ready;
  wire e_hin = emit && (!e_hv || (e_deq && !e_tv));
  wire e_htl = e_deq && e_tv;
  wire e_tin = emit && e_hv && !e_deq;
  always @(posedge clk) begin
    if (rst) begin
      e_hv <= 1'b0; e_tv <= 1'b0;
      e_h0 <= 32'd0; e_h1 <= 32'd0; e_t0 <= 32'd0; e_t1 <= 32'd0;
    end else begin
      e_hv <= e_tv || emit || (e_hv && !e_deq);
      e_tv <= (e_tv && !e_deq) || (emit && e_hv && !e_deq);
      if (e_tin) begin e_t0 <= y0; e_t1 <= y1; end
      if (e_htl) begin e_h0 <= e_t0; e_h1 <= e_t1; end
      else if (e_hin) begin e_h0 <= y0; e_h1 <= y1; end
    end
  end
  assign e_valid = e_hv;
  assign e_p0 = e_h0;
  assign e_p1 = e_h1;
endmodule
