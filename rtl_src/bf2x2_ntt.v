`timescale 1ns / 1ps
// ============================================================================
// bf2x2_ntt : two NTT layers on one 4-lane word using 4 x bf_ntt_dsp
// ----------------------------------------------------------------------------
// Lane wiring is identical to GMU butterfly2x2 (forward and inverse):
//   layer 1 : (x0,x1) with z0 , (x2,x3) with z1      -> (a1,b1) , (c1,d1)
//   layer 2 : (a1,c1) with z2 , (b1,d1) with z3      -> (a3,b3) , (c3,d3)
//   output lanes = {d3, c3, b3, a3}
// All four twiddles are presented together with the input word; z2/z3 are
// delayed internally by one butterfly latency.  NTT / INTT only (no MULT/ADD/SUB).
// Latency = 2 * 10 = 20 cycles, 1 word / cycle.
// ============================================================================
module bf2x2_ntt (
    input         clk,
    input         inv,
    input  [95:0] datai,     // 4 x 24-bit lanes (values < q in the low 23 bits)
    input  [95:0] zetai,     // 4 x 24-bit Montgomery twiddles
    output [95:0] datao
);
    localparam BLAT = 10;

    wire [22:0] x0 = datai[0*24 +: 23], x1 = datai[1*24 +: 23];
    wire [22:0] x2 = datai[2*24 +: 23], x3 = datai[3*24 +: 23];

    // delay z2, z3 (and inv for layer 2) by one butterfly latency
    reg [22:0] z2_d [0:BLAT-1];
    reg [22:0] z3_d [0:BLAT-1];
    reg        inv_d [0:BLAT-1];
    integer i;
    always @(posedge clk) begin
        z2_d[0] <= zetai[2*24 +: 23];
        z3_d[0] <= zetai[3*24 +: 23];
        inv_d[0] <= inv;
        for (i = 1; i < BLAT; i = i + 1) begin
            z2_d[i] <= z2_d[i-1];
            z3_d[i] <= z3_d[i-1];
            inv_d[i] <= inv_d[i-1];
        end
    end

    wire [22:0] a1, b1, c1, d1, a3, b3, c3, d3;
    bf_ntt_dsp BF1_1 (.clk(clk), .inv(inv), .u(x0), .v(x1), .w(zetai[0*24 +: 23]), .o0(a1), .o1(b1));
    bf_ntt_dsp BF1_2 (.clk(clk), .inv(inv), .u(x2), .v(x3), .w(zetai[1*24 +: 23]), .o0(c1), .o1(d1));
    bf_ntt_dsp BF2_1 (.clk(clk), .inv(inv_d[BLAT-1]), .u(a1), .v(c1), .w(z2_d[BLAT-1]), .o0(a3), .o1(b3));
    bf_ntt_dsp BF2_2 (.clk(clk), .inv(inv_d[BLAT-1]), .u(b1), .v(d1), .w(z3_d[BLAT-1]), .o0(c3), .o1(d3));

    assign datao = {1'b0, d3, 1'b0, c3, 1'b0, b3, 1'b0, a3};
endmodule
