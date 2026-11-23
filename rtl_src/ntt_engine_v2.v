`timescale 1ns / 1ps
// ============================================================================
// ntt_engine_v2 : 2-pass (4 layers per pass) NTT / INTT engine for ML-DSA
// ----------------------------------------------------------------------------
// Memory interface is the GMU one: 64 x 96-bit words (4 coeffs) per polynomial,
// 1 read (port A, 1-cycle latency) + 1 write (port B) per cycle, in place.
//
// Per pass (16-word blocks):
//   forward : RAM -> Ta(S=1) -> S1(butterfly2x2) -> Tb(S=4) -> S2(bf2x2_ntt) -> RAM
//   inverse : RAM -> S1(butterfly2x2) -> Ta(S=1) -> S2(bf2x2_ntt) -> Tb(S=4) -> RAM
// S1 is the existing GMU butterfly2x2 (shared with MULT/ADD/SUB in the operator),
// S2 is the new DSP-Montgomery 2x2.  Two passes cover all 8 layers, so every
// polynomial costs 2 x 64 memory cycles instead of 4 x 64.
//
// Vector mode (nvec > 1): passes of two (last group: three) polynomials are
// interleaved  P1(i) P1(i+1) P2(i) P2(i+1) ...
// so the pipeline latency of pass 1 is hidden behind the other polynomial.
// A pass-2 read never starts before the pass-1 writes of the same polynomial
// have all landed (checked with a completed-pass counter, so it is always safe).
// Address / twiddle formulas are generated from scripts/model_v2.py (verified
// against the reference NTT/INTT and the GMU NTT-domain layout).
// ============================================================================
module ntt_engine_v2 (
    input             clk,
    input             rst,
    input             start,
    input             inv,          // 0 = forward NTT, 1 = inverse NTT
    input      [3:0]  nvec,         // number of polynomials (0 or 1 = single)
    output reg        done,
    // RAM read port (data returns next cycle on rdata)
    output     [5:0]  rd_addr,      // combinational (RAM registers it)
    output     [3:0]  rd_poly,
    input      [95:0] rdata,
    // RAM write port
    output reg        we,
    output reg [5:0]  wr_addr,
    output reg [3:0]  wr_poly,
    output reg [95:0] wdata,
    output reg        wfinal,       // this write carries final (pass-2) coefficients
    // shared stage-1 butterfly (GMU butterfly2x2)
    output reg        s1_validi,
    output reg [95:0] s1_datai,
    output     [95:0] s1_zetai,
    input      [95:0] s1_datao
);
    // tag = {poly[3:0], pass, blk[1:0], n[3:0]}
    localparam TW = 11;

    // ======================================================== read scheduler
    reg        busy;
    reg [3:0]  np;             // number of polynomials
    reg [3:0]  pbase;          // first polynomial of the current group
    reg [2:0]  step;           // position in the group sequence (0 .. 2*grp-1)
    reg [1:0]  grp;            // polynomials in the current group: 1, 2 or 3
    reg [1:0]  blk;
    reg [3:0]  n;
    reg [4:0]  rseq;           // sequence number of the pass being read
    reg [4:0]  wseq;           // number of passes fully written
    reg [5:0]  wcnt;
    reg        rd_active;      // all passes issued -> 0

    // pass descriptor for the current step: group of g polynomials is read as
    //   P1(p) .. P1(p+g-1)  P2(p) .. P2(p+g-1)
    // g = 2 normally; the last group is 3 for an odd count >= 3, 1 only if nvec = 1.
    wire       cur_pass = (step >= {1'b0, grp});
    wire [2:0] sub      = cur_pass ? step - {1'b0, grp} : step;
    wire [3:0] cur_poly = pbase + {1'b0, sub};
    wire [4:0] dep_seq  = rseq - {3'd0, grp};            // P1 of the same polynomial
    wire       dep_ok   = (cur_pass == 1'b0) || (wseq > dep_seq);
    wire       issue    = busy && rd_active && dep_ok;
    wire       last_rd_of_pass = issue && (blk == 2'd3) && (n == 4'd15);
    wire       last_step = (step == {grp, 1'b0} - 3'd1);
    function [1:0] f_grp(input [3:0] remaining);
        f_grp = (remaining >= 4) ? 2'd2 : (remaining == 3) ? 2'd3 : remaining[1:0];
    endfunction

    function [5:0] f_rd_addr(input iv, input ps, input [1:0] b, input [3:0] nn);
        begin
            case ({iv, ps})
            2'b00: f_rd_addr = {nn[0], nn[1], nn[2], nn[3], b[1], b[0]};
            2'b01: f_rd_addr = {nn[2], nn[3], b[1], b[0], nn[0], nn[1]};
            2'b10: f_rd_addr = {nn[1], nn[0], b[1], b[0], nn[3], nn[2]};
            default: f_rd_addr = {nn[3], nn[2], nn[1], nn[0], b[1], b[0]};
            endcase
        end
    endfunction
    function [5:0] f_wr_addr(input iv, input ps, input [1:0] b, input [3:0] u);
        begin   // u = L*4 + j : j = u[1:0], L = u[3:2]
            case ({iv, ps})
            2'b00: f_wr_addr = {u[1], u[0], u[3], u[2], b[1], b[0]};
            2'b01: f_wr_addr = {u[3], u[2], b[1], b[0], u[1], u[0]};
            2'b10: f_wr_addr = {u[0], u[1], b[1], b[0], u[2], u[3]};
            default: f_wr_addr = {u[2], u[3], u[0], u[1], b[1], b[0]};
            endcase
        end
    endfunction

    reg        rv1;
    reg [TW-1:0] rt1;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 0; rd_active <= 0; np <= 0; pbase <= 0; step <= 0; grp <= 1;
            blk <= 0; n <= 0; rseq <= 0;
            rv1 <= 0; rt1 <= 0;
        end else begin
            rv1 <= issue;
            rt1 <= {cur_poly, cur_pass, blk, n};
            if (start && !busy) begin
                busy      <= 1'b1;
                rd_active <= 1'b1;
                np        <= (nvec == 0) ? 4'd1 : nvec;
                pbase     <= 0;
                step      <= 0;
                grp       <= f_grp((nvec == 0) ? 4'd1 : nvec);
                blk <= 0; n <= 0; rseq <= 0;
            end else if (issue) begin
                {blk, n} <= {blk, n} + 1'b1;
                if (last_rd_of_pass) begin
                    rseq <= rseq + 1'b1;
                    if (last_step) begin
                        step <= 0;
                        if (pbase + {2'd0, grp} >= np) begin
                            rd_active <= 1'b0;
                        end else begin
                            pbase <= pbase + {2'd0, grp};
                            grp   <= f_grp(np - pbase - {2'd0, grp});
                        end
                    end else begin
                        step <= step + 1'b1;
                    end
                end
            end
            if (done) busy <= 1'b0;
        end
    end
    // address is presented in the issue cycle; data and tag (rv1/rt1) arrive next cycle
    assign rd_addr = f_rd_addr(inv, cur_pass, blk, n);
    assign rd_poly = cur_poly;

    // ======================================================== twiddle index logic
    // returns {z3, z2, z1, z0} ROM indices (8 bits each) for a stage input word
    function [31:0] f_tw(input iv, input ps, input st, input [1:0] b, input [3:0] c);
        reg [7:0] p, hi, lo, t0, t2;
        begin
            case ({iv, ps, st})
            3'b000: p = 8'd0;
            3'b001: p = {c[3], c[2], 6'd0};
            3'b010: p = {b, c[1], c[0], 4'd0};
            3'b011: p = {b, c[1], c[0], c[3], c[2], 2'd0};
            3'b100: p = {b, c[3], c[2], c[1], c[0], 2'd0};
            3'b101: p = {b, c[3], c[2], 4'd0};
            3'b110: p = {c[1], c[0], 6'd0};
            default: p = 8'd0;
            endcase
            case ({iv, ps, st})
            // forward: s = 0,2,4,6 ; hi = 2^s + p>>(8-s) ; lo = 2^(s+1) + p>>(7-s)
            3'b000: begin hi = 8'd1;              lo = 8'd2;               end
            3'b001: begin hi = 8'd4  + (p >> 6);  lo = 8'd8   + (p >> 5);  end
            3'b010: begin hi = 8'd16 + (p >> 4);  lo = 8'd32  + (p >> 3);  end
            3'b011: begin hi = 8'd64 + (p >> 2);  lo = 8'd128 + (p >> 1);  end
            default: begin hi = 8'd0; lo = 8'd0; end
            endcase
            // inverse: m = 0,2,4,6 ; t0 = (256>>m)-1-(p>>(m+1)) ; t2 = (256>>(m+1))-1-(p>>(m+2))
            case ({iv, ps, st})
            3'b100: begin t0 = 8'd255 - (p >> 1); t2 = 8'd127 - (p >> 2); end
            3'b101: begin t0 = 8'd63  - (p >> 3); t2 = 8'd31  - (p >> 4); end
            3'b110: begin t0 = 8'd15  - (p >> 5); t2 = 8'd7   - (p >> 6); end
            3'b111: begin t0 = 8'd3;              t2 = 8'd1;              end
            default: begin t0 = 8'd0; t2 = 8'd0; end
            endcase
            f_tw = iv ? {t2, t2, t0 - 8'd1, t0} : {lo + 8'd1, lo, hi, hi};
        end
    endfunction

    // ======================================================== datapath
    // --- transposer A (S = 1)
    wire        ta_v;  wire [95:0] ta_d;  wire [TW-1:0] ta_t;  wire [1:0] ta_u;
    reg         ta_iv; reg  [95:0] ta_id; reg  [TW-1:0] ta_it;
    ntt_transposer #(.S(1), .TAGW(TW)) TA (clk, rst, ta_iv, ta_id, ta_it, ta_v, ta_d, ta_t, ta_u);

    // --- transposer B (S = 4)
    wire        tb_v;  wire [95:0] tb_d;  wire [TW-1:0] tb_t;  wire [3:0] tb_u;
    reg         tb_iv; reg  [95:0] tb_id; reg  [TW-1:0] tb_it;
    ntt_transposer #(.S(4), .TAGW(TW)) TB (clk, rst, tb_iv, tb_id, tb_it, tb_v, tb_d, tb_t, tb_u);

    // --- stage-1 input select + twiddle fetch (ROM latency 1 -> register data once)
    reg         s1p_v;  reg [95:0] s1p_d; reg [TW-1:0] s1p_t; reg [3:0] s1p_c;
    always @(*) begin
        if (inv) begin s1p_v = rv1;  s1p_d = rdata; s1p_t = rt1;  s1p_c = rt1[3:0]; end
        else     begin s1p_v = ta_v; s1p_d = ta_d;  s1p_t = ta_t; s1p_c = {ta_t[3:2], ta_u}; end
    end
    wire [31:0] tw1 = f_tw(inv, s1p_t[6], 1'b0, s1p_t[5:4], s1p_c);
    wire [23:0] z10, z11, z12, z13;
    tw_rom_s1 ROM1A (clk, 1'b1, tw1[7:0],   tw1[15:8],  z10, z11);
    tw_rom_s1 ROM1B (clk, 1'b1, tw1[23:16], tw1[31:24], z12, z13);
    assign s1_zetai = {z13, z12, z11, z10};

    reg [TW-1:0] s1_tag;
    always @(posedge clk) begin
        s1_validi <= rst ? 1'b0 : s1p_v;
        s1_datai  <= s1p_d;
        s1_tag    <= s1p_t;
    end

    // stage-1 latency: 16 (forward) / 18 (inverse) cycles from s1_validi
    localparam S1MAX = 18;
    reg          s1v_sr [0:S1MAX-1];
    reg [TW-1:0] s1t_sr [0:S1MAX-1];
    integer k;
    always @(posedge clk) begin
        s1v_sr[0] <= rst ? 1'b0 : s1_validi;
        s1t_sr[0] <= s1_tag;
        for (k = 1; k < S1MAX; k = k + 1) begin
            s1v_sr[k] <= rst ? 1'b0 : s1v_sr[k-1];
            s1t_sr[k] <= s1t_sr[k-1];
        end
    end
    wire          s1o_v = inv ? s1v_sr[17] : s1v_sr[15];
    wire [TW-1:0] s1o_t = inv ? s1t_sr[17] : s1t_sr[15];

    // --- routing into the transposers
    wire          s2o_v;  wire [95:0] s2o_d;  wire [TW-1:0] s2o_t;  wire [3:0] s2o_u;
    always @(*) begin
        // Ta : forward <- RAM ; inverse <- S1 output
        ta_iv = inv ? s1o_v    : rv1;
        ta_id = inv ? s1_datao : rdata;
        ta_it = inv ? s1o_t    : rt1;
        // Tb : forward <- S1 output ; inverse <- S2 output
        tb_iv = inv ? s2o_v : s1o_v;
        tb_id = inv ? s2o_d : s1_datao;
        tb_it = inv ? s2o_t : s1o_t;
    end

    // --- stage-2 input select + twiddle fetch
    reg         s2p_v;  reg [95:0] s2p_d; reg [TW-1:0] s2p_t; reg [3:0] s2p_c;
    always @(*) begin
        if (inv) begin s2p_v = ta_v; s2p_d = ta_d; s2p_t = ta_t; s2p_c = {ta_t[3:2], ta_u}; end
        else     begin s2p_v = tb_v; s2p_d = tb_d; s2p_t = tb_t; s2p_c = tb_u; end
    end
    wire [31:0] tw2 = f_tw(inv, s2p_t[6], 1'b1, s2p_t[5:4], s2p_c);
    wire [23:0] z20, z21, z22, z23;
    tw_rom_s2 ROM2A (clk, 1'b1, {inv, tw2[7:0]},   {inv, tw2[15:8]},  z20, z21);
    tw_rom_s2 ROM2B (clk, 1'b1, {inv, tw2[23:16]}, {inv, tw2[31:24]}, z22, z23);

    reg          s2_v;  reg [95:0] s2_d;  reg [TW-1:0] s2_t; reg [3:0] s2_u;
    always @(posedge clk) begin
        s2_v <= rst ? 1'b0 : s2p_v;
        s2_d <= s2p_d;
        s2_t <= s2p_t;
        s2_u <= s2p_c;
    end
    wire [95:0] s2_out;
    bf2x2_ntt S2 (.clk(clk), .inv(inv), .datai(s2_d), .zetai({z23, z22, z21, z20}), .datao(s2_out));

    localparam S2LAT = 20;
    reg          s2v_sr [0:S2LAT-1];
    reg [TW-1:0] s2t_sr [0:S2LAT-1];
    reg [3:0]    s2u_sr [0:S2LAT-1];
    always @(posedge clk) begin
        s2v_sr[0] <= rst ? 1'b0 : s2_v;
        s2t_sr[0] <= s2_t;
        s2u_sr[0] <= s2_u;
        for (k = 1; k < S2LAT; k = k + 1) begin
            s2v_sr[k] <= rst ? 1'b0 : s2v_sr[k-1];
            s2t_sr[k] <= s2t_sr[k-1];
            s2u_sr[k] <= s2u_sr[k-1];
        end
    end
    assign s2o_v = s2v_sr[S2LAT-1];
    assign s2o_d = s2_out;
    assign s2o_t = s2t_sr[S2LAT-1];
    assign s2o_u = s2u_sr[S2LAT-1];

    // ======================================================== write back
    wire          wv = inv ? tb_v : s2o_v;
    wire [95:0]   wd = inv ? tb_d : s2o_d;
    wire [TW-1:0] wt = inv ? tb_t : s2o_t;
    wire [3:0]    wu = inv ? tb_u : s2o_u;

    always @(posedge clk) begin
        if (rst) begin
            we <= 0; wr_addr <= 0; wr_poly <= 0; wdata <= 0; wfinal <= 0;
            wcnt <= 0; wseq <= 0; done <= 0;
        end else begin
            we      <= wv;
            wfinal  <= wv & wt[6];
            wr_addr <= f_wr_addr(inv, wt[6], wt[5:4], wu);
            wr_poly <= wt[10:7];
            wdata   <= wd;
            done    <= 1'b0;
            if (start && !busy) begin
                wcnt <= 0; wseq <= 0;
            end else if (wv) begin
                wcnt <= wcnt + 1'b1;
                if (wcnt == 6'd63) begin
                    wseq <= wseq + 1'b1;
                    if (wseq + 1'b1 == {np, 1'b0}) done <= 1'b1;
                end
            end
        end
    end
endmodule
