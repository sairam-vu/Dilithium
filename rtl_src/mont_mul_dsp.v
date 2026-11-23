`timescale 1ns / 1ps
// ============================================================================
// mont_mul_dsp : r = a * b * 2^-23 mod q,  q = 8380417 = 2^23 - 2^13 + 1
// ----------------------------------------------------------------------------
// Montgomery reduction with R = 2^23, mapped onto DSP48E1 slices:
//   T  = a * b                       (23x23 -> 2 DSP48E1, AREG/BREG + MREG + PREG)
//   m  = (T mod 2^23) * q' mod 2^23  (q' = -q^-1 mod 2^23 = 0x7FDFFF, 2 DSP48E1)
//   S  = T + m * q                   (2 DSP48E1, T enters through the post-adder/C path)
//   r  = S >> 23 ; if (r >= q) r -= q
// Inputs a, b < q.  T < q^2 < q*2^23, so S>>23 < 2q and one subtraction suffices.
// Twiddles are stored pre-scaled by 2^23 (zeta*R mod q) so r = a*zeta mod q:
// the result is in the normal domain, identical to the baseline Barrett path.
// Latency: LAT = 8 cycles, fully pipelined (1 result / cycle).
// Unlike shift-add Barrett (paper Alg. 4 / GMU Barrett_8380417), every wide
// product here lives in DSP slices, so LUT cost is ~one 24-bit subtractor.
// ============================================================================
(* use_dsp = "yes" *)
module mont_mul_dsp (
    input             clk,
    input      [22:0] a,
    input      [22:0] b,
    output reg [22:0] r
);
    localparam [22:0] Q      = 23'd8380417;
    localparam [22:0] QPRIME = 23'h7FDFFF;     // -q^-1 mod 2^23

    // stage 1-3 : T = a*b
    reg  [22:0] a1, b1;
    reg  [45:0] t2, t3;
    // stage 4-5 : m = T_lo * q' mod 2^23
    reg  [22:0] m4, m5;
    reg  [45:0] t4, t5;
    // stage 6-7 : S = T + m*q
    reg  [46:0] s6, s7;
    // stage 8 : final correction
    wire [23:0] hi  = s7[46:23];
    wire [24:0] hiq = {1'b0, hi} - {2'b0, Q};

    always @(posedge clk) begin
        a1 <= a;              b1 <= b;
        t2 <= a1 * b1;        t3 <= t2;
        m4 <= t3[22:0] * QPRIME;   // only the low 23 bits are kept
        t4 <= t3;
        m5 <= m4;             t5 <= t4;
        s6 <= t5 + m5 * Q;
        s7 <= s6;
        r  <= hiq[24] ? hi[22:0] : hiq[22:0];
    end
endmodule
