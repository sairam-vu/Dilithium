`timescale 1ns / 1ps
// ============================================================================
// ntt_transposer : double-buffered 4 x 4S block transposer for 4-lane words
// ----------------------------------------------------------------------------
// A block is 4*S consecutive valid input words.  Input word t = m*S + j
// (m = sub-block 0..3, j = 0..S-1).  Output word u = L*S + j, lane m:
//            out[u].lane[m] = in[m*S + j].lane[L]
// i.e. the lane index is swapped with the sub-block index.
//
// Storage: 4 skewed banks of distributed RAM (24-bit x 8S).  Lane L of input
// sub-block m is written to bank (L+m)%4, so every bank gets exactly one write
// and one read per cycle -> maps to RAM32M/RAM64M, no wide register muxes.
// A block is streamed out (one word per cycle) as soon as it is complete,
// while the next block fills the other half.  Latency = 4S + 1 cycles.
// TAG is sampled on the first word of each block and returned with its output.
// ============================================================================
module ntt_transposer #(
    parameter S    = 4,            // stride in words (1 or 4 used)
    parameter TAGW = 12
)(
    input                 clk,
    input                 rst,
    input                 in_valid,
    input      [95:0]     in_data,
    input      [TAGW-1:0] in_tag,
    output reg            out_valid,
    output reg [95:0]     out_data,
    output reg [TAGW-1:0] out_tag,
    output reg [IW-1:0]   out_idx      // u = L*S + j
);
    localparam BLK = 4 * S;
    localparam IW  = (BLK <= 4) ? 2 : (BLK <= 8) ? 3 : (BLK <= 16) ? 4 : 5;
    localparam SW  = (S <= 1) ? 1 : (S <= 2) ? 1 : (S <= 4) ? 2 : 3;   // bits for j (>=1)
    localparam AW  = 1 + 2 + SW;                                         // {buf, m, j}

    // ------------------------------------------------------------------ banks
    (* ram_style = "distributed" *) reg [23:0] bank0 [0:(1<<AW)-1];
    (* ram_style = "distributed" *) reg [23:0] bank1 [0:(1<<AW)-1];
    (* ram_style = "distributed" *) reg [23:0] bank2 [0:(1<<AW)-1];
    (* ram_style = "distributed" *) reg [23:0] bank3 [0:(1<<AW)-1];

    // ------------------------------------------------------------------ write side
    reg  [IW-1:0]   wc;
    reg             wbuf;
    reg  [1:0]      full;            // full[buf] : block complete, waiting / being read
    reg  [TAGW-1:0] tag_mem [0:1];

    wire [1:0]      wm = (S == 1) ? wc[1:0] : wc[IW-1 -: 2];       // m = wc / S
    wire [SW-1:0]   wj = (S == 1) ? {SW{1'b0}} : wc[SW-1:0];       // j = wc % S
    wire [AW-1:0]   waddr = {wbuf, wm, wj};

    // bank k receives lane (k - m) % 4
    wire [23:0] l0 = in_data[0*24 +: 24];
    wire [23:0] l1 = in_data[1*24 +: 24];
    wire [23:0] l2 = in_data[2*24 +: 24];
    wire [23:0] l3 = in_data[3*24 +: 24];
    reg  [23:0] wb0, wb1, wb2, wb3;
    always @(*) begin
        case (wm)
        2'd0: begin wb0 = l0; wb1 = l1; wb2 = l2; wb3 = l3; end
        2'd1: begin wb0 = l3; wb1 = l0; wb2 = l1; wb3 = l2; end
        2'd2: begin wb0 = l2; wb1 = l3; wb2 = l0; wb3 = l1; end
        default: begin wb0 = l1; wb1 = l2; wb2 = l3; wb3 = l0; end
        endcase
    end

    always @(posedge clk) begin
        if (in_valid) begin
            bank0[waddr] <= wb0;
            bank1[waddr] <= wb1;
            bank2[waddr] <= wb2;
            bank3[waddr] <= wb3;
        end
    end

    // ------------------------------------------------------------------ read side
    reg  [IW-1:0] rc;
    reg           rbuf;
    reg           busy;
    wire [1:0]    rl = (S == 1) ? rc[1:0] : rc[IW-1 -: 2];          // L = rc / S
    wire [SW-1:0] rj = (S == 1) ? {SW{1'b0}} : rc[SW-1:0];          // j = rc % S

    // bank k serves output lane m = (k - L) % 4 at entry {rbuf, m, j}
    wire [1:0] m0 = 2'd0 - rl, m1 = 2'd1 - rl, m2 = 2'd2 - rl, m3 = 2'd3 - rl;
    wire [23:0] rb0 = bank0[{rbuf, m0, rj}];
    wire [23:0] rb1 = bank1[{rbuf, m1, rj}];
    wire [23:0] rb2 = bank2[{rbuf, m2, rj}];
    wire [23:0] rb3 = bank3[{rbuf, m3, rj}];
    // output lane m comes from bank (L + m) % 4
    reg [95:0] rdat;
    always @(*) begin
        case (rl)
        2'd0: rdat = {rb3, rb2, rb1, rb0};
        2'd1: rdat = {rb0, rb3, rb2, rb1};
        2'd2: rdat = {rb1, rb0, rb3, rb2};
        default: rdat = {rb2, rb1, rb0, rb3};
        endcase
    end

    wire last_w = in_valid && (wc == BLK - 1);
    wire start_r = !busy && (full[rbuf]);
    wire last_r  = busy && (rc == BLK - 1);

    always @(posedge clk) begin
        if (rst) begin
            wc <= 0; wbuf <= 0; full <= 2'b00;
            rc <= 0; rbuf <= 0; busy <= 0;
            out_valid <= 0; out_data <= 0; out_tag <= 0; out_idx <= 0;
        end else begin
            // write bookkeeping
            if (in_valid) begin
                if (wc == 0) tag_mem[wbuf] <= in_tag;
                wc <= last_w ? 0 : wc + 1'b1;
                if (last_w) wbuf <= ~wbuf;
            end
            // full flags: set by writer, cleared by reader at block end
            if (last_w)  full[wbuf] <= 1'b1;
            if (last_r)  full[rbuf] <= 1'b0;

            // read sequencing
            if (start_r) begin
                busy <= 1'b1;
                rc   <= 0;
            end else if (busy) begin
                rc <= last_r ? 0 : rc + 1'b1;
                if (last_r) begin
                    rbuf <= ~rbuf;
                    // continue back-to-back if the other half is already complete
                    // (it may be completing in this very cycle)
                    busy <= full[~rbuf] | (last_w & (wbuf == ~rbuf));
                end
            end

            out_valid <= busy;
            out_data  <= rdat;
            out_tag   <= tag_mem[rbuf];
            out_idx   <= rc;
        end
    end
endmodule
