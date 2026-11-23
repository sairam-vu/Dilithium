`timescale 1ns / 1ps
// ============================================================================
// bf_ntt_dsp : unified CT / GS butterfly for ML-DSA (NTT-only, DSP reduction)
// ----------------------------------------------------------------------------
//  inv = 0 (CT, forward):  o0 = u + w*v ,           o1 = u - w*v
//  inv = 1 (GS, inverse):  o0 = (u + v) / 2 ,       o1 = (u - v) * w'
// The twiddle input is already in Montgomery form:
//      forward : w  = zeta * 2^23 mod q
//      inverse : w' = (q - zeta) * 2^23 / 2 mod q     (negation and the /2 folded in)
// so the inverse path matches the GMU butterfly (which negates zeta and halves
// both outputs) without any extra multiplier or halving logic on o1.
// Same shared-datapath idea as the CT/GS unit in NTT-LSU (Fig. 5), but with the
// reduction moved from LUT shift-adds into DSP48E1 slices.
// Latency LAT = 10 cycles (1 pre-add + 8 Montgomery + 1 post-add).
// ============================================================================
module bf_ntt_dsp (
    input             clk,
    input             inv,
    input      [22:0] u,
    input      [22:0] v,
    input      [22:0] w,
    output reg [22:0] o0,
    output reg [22:0] o1
);
    localparam [22:0] Q    = 23'd8380417;
    localparam [22:0] HALF = 23'd4190209;      // (q+1)/2
    localparam MLAT = 8;

    function [22:0] add_q(input [22:0] x, input [22:0] y);
        reg [23:0] s; reg [24:0] d;
        begin
            s = x + y;
            d = {1'b0, s} - {2'b0, Q};
            add_q = d[24] ? s[22:0] : d[22:0];
        end
    endfunction
    function [22:0] sub_q(input [22:0] x, input [22:0] y);
        reg [23:0] d;
        begin
            d = {1'b0, x} - {1'b0, y};
            sub_q = d[23] ? d[22:0] + Q : d[22:0];
        end
    endfunction

    // stage 0 : pre-add (GS) / pass-through (CT)
    reg [22:0] x0, w0, keep0;
    reg        inv0;
    always @(posedge clk) begin
        inv0  <= inv;
        w0    <= w;
        x0    <= inv ? sub_q(u, v) : v;
        keep0 <= inv ? add_q(u, v) : u;
    end

    // Montgomery product
    wire [22:0] t;
    mont_mul_dsp MM (.clk(clk), .a(x0), .b(w0), .r(t));

    // align keep / inv with the product (SRL-friendly delay lines)
    reg [22:0] keep_d [0:MLAT-1];
    reg        inv_d  [0:MLAT-1];
    integer i;
    always @(posedge clk) begin
        keep_d[0] <= keep0;
        inv_d[0]  <= inv0;
        for (i = 1; i < MLAT; i = i + 1) begin
            keep_d[i] <= keep_d[i-1];
            inv_d[i]  <= inv_d[i-1];
        end
    end
    wire [22:0] kp = keep_d[MLAT-1];
    wire        iv = inv_d[MLAT-1];

    // post stage
    always @(posedge clk) begin
        if (iv) begin
            o0 <= kp[0] ? (kp >> 1) + HALF : (kp >> 1);   // (u+v)/2
            o1 <= t;                                       // (u-v)*(-zeta)/2
        end else begin
            o0 <= add_q(kp, t);
            o1 <= sub_q(kp, t);
        end
    end
endmodule
