`timescale 1ns / 1ps
// ============================================================================
// Barrett (DSP version) : drop-in replacement for the GMU Barrett_8380417.v
// ----------------------------------------------------------------------------
// Same module name, ports, latency (3 cycles) and bit-exact arithmetic as the
// Chisel-generated GMU reducer, which is the mu-based Barrett of NTT-LSU
// Algorithm 4 (q = 8380417, mu = floor(2^46 / q) = 8396807):
//     quo = ((x >> 22) * mu) >> 24          stage 0
//     qq  = (quo * q) mod 2^24              stage 1
//     rem = (x mod 2^24) - qq  (mod 2^24)   stage 2, then one conditional "- q"
// GMU builds both constant multiplications from shift-add trees in LUTs; here
// they are DSP48E1 multiplies (one multiply per stage, the same timing class as
// the 24x24 product that already feeds this block in butterfly.v).
// The valid/ready handshake is kept for interface compatibility. In GMU's
// butterfly.v io_in_valid and io_out_ready are tied to 1, so the pipeline
// always advances.
// ============================================================================
(* use_dsp = "yes" *)
module Barrett(
  input         clock,
  input         reset,
  output        io_in_ready,
  input         io_in_valid,
  input  [45:0] io_in_bits,
  input         io_out_ready,
  output        io_out_valid,
  output [22:0] io_out_bits_remainder,
  output [23:0] io_out_bits_quotient
);
  localparam [23:0] MU = 24'd8396807;
  localparam [23:0] Q  = 24'd8380417;

  reg  [2:0]  v;
  reg  [23:0] ul0, quo0;
  reg  [23:0] ul1, quo1, qq1;
  reg  [22:0] rem2;
  reg  [23:0] quo2;

  wire [47:0] quo_full = io_in_bits[45:22] * MU;        // DSP
  wire [47:0] qq_full  = quo0 * Q;                      // DSP (low 24 bits used)
  wire [23:0] rem      = ul1 - qq1;
  wire [23:0] rem_mq   = rem - Q;

  wire adv = io_out_ready | ~v[2];
  assign io_in_ready  = adv;
  assign io_out_valid = v[2];
  assign io_out_bits_remainder = rem2;
  assign io_out_bits_quotient  = quo2;

  always @(posedge clock) begin
    if (reset) v <= 3'b000;
    else if (adv) v <= {v[1:0], io_in_valid};
    if (adv) begin
      ul0  <= io_in_bits[23:0];
      quo0 <= quo_full[47:24];
      ul1  <= ul0;
      quo1 <= quo0;
      qq1  <= qq_full[23:0];
      rem2 <= rem_mq[23] ? rem[22:0] : rem_mq[22:0];
      quo2 <= rem_mq[23] ? quo1 : quo1 + 24'd1;
    end
  end
endmodule
