/*
 * operation_module_v2 : GMU operation_module with the NTT/INTT replaced by
 * ntt_engine_v2 (2 passes x 4 layers, DSP-Montgomery second stage, optional
 * interleaved vector mode).  MULT / ADD / SUB are unchanged (same code and
 * timing as the GMU module) and share stage 1 (butterfly2x2) with the NTT.
 *
 * Interface = GMU operation_module + three ports:
 *   nvec  : number of consecutive polynomials for NTT/INTT (0/1 = single, GMU protocol)
 *   rpoly : polynomial offset to add to the upper read address  (port A of BRAM 1)
 *   wpoly : polynomial offset to add to the upper write address (port B of BRAM 1)
 *   wfinal: the current BRAM-1 write carries final NTT/INTT output (for snooping
 *           consumers such as the signer's norm check)
 * For nvec <= 1 rpoly = wpoly = 0, so the module is a drop-in replacement.
 * Address mapping for NTT/INTT is generated internally (encode_mode is ignored
 * in those modes); the NTT-domain layout is identical to the GMU design.
 *
 * Based on: "High-Performance Hardware Implementation of CRYSTALS-Dilithium",
 * L. Beckwith, D. T. Nguyen, K. Gaj (GMU CERG), Apache License 2.0.
 */
`timescale 1ns / 1ps

module operation_module_v2(
    input clk,
    input rst,
    input start,
    input [2:0] mode,
    input [1:0] encode_mode,
    output reg done = 0,
    // BRAM 1
    output reg [5:0]  addra1 = 0,
    output reg [5:0]  addrb1 = 0,
    input      [95:0] doa1,
    input      [95:0] dob1,
    output reg        web1 = 0,
    output reg [95:0] dib1 = 0,
    // BRAM 2
    output reg [5:0]  addra2 = 0,
    output reg [5:0]  addrb2 = 0,
    input      [95:0] doa2,
    output reg        web2 = 0,
    output reg [95:0] dib2 = 0,
    // vector NTT
    input      [3:0]  nvec,
    output reg [3:0]  rpoly = 0,
    output reg [3:0]  wpoly = 0,
    output reg        wfinal = 0     // NTT/INTT write of final coefficients (pass 2)
    );

    localparam
        FORWARD_NTT_MODE = 3'd0,
        INVERSE_NTT_MODE = 3'd1,
        MULT_MODE        = 3'd2,
        ADD_MODE         = 3'd3,
        SUB_MODE         = 3'd4;

    wire ntt_mode = (mode == FORWARD_NTT_MODE) || (mode == INVERSE_NTT_MODE);

    // ------------------------------------------------------------ shared stage 1
    reg         validi_bf = 0;
    reg [95:0]  datai_bf = 0;
    reg [95:0]  zetai_bf = 0;
    reg [95:0]  acci_bf  = 0;
    wire [95:0] datao_bf;
    wire        valido_bf;

    butterfly2x2 BF_CIRCUIT(
        clk, rst, mode, validi_bf, datai_bf,
        zetai_bf, acci_bf, datao_bf, valido_bf
    );

    // ------------------------------------------------------------ NTT engine
    wire        e_done, e_we, e_s1v, e_wfinal;
    wire [5:0]  e_raddr, e_waddr;
    wire [3:0]  e_rpoly, e_wpoly;
    wire [95:0] e_wdata, e_s1d, e_s1z;
    ntt_engine_v2 ENGINE (
        .clk(clk), .rst(rst), .start(start & ntt_mode),
        .inv(mode == INVERSE_NTT_MODE), .nvec(nvec), .done(e_done),
        .rd_addr(e_raddr), .rd_poly(e_rpoly), .rdata(doa1),
        .we(e_we), .wr_addr(e_waddr), .wr_poly(e_wpoly), .wdata(e_wdata), .wfinal(e_wfinal),
        .s1_validi(e_s1v), .s1_datai(e_s1d), .s1_zetai(e_s1z), .s1_datao(datao_bf)
    );

    // ------------------------------------------------------------ MULT/ADD/SUB (GMU)
    reg done_latch = 0;
    reg en_addr, rst_addr;
    wire [5:0] ram_addr;
    wire [5:0] ram_nat;
    wire [7:0] twiddle_addr [3:0];
    wire ntt_round_done, done_addr;
    address_unit ADDR(
        clk, rst_addr, mode, encode_mode, en_addr, ram_nat, ram_addr,
        twiddle_addr[0], twiddle_addr[1],
        twiddle_addr[2], twiddle_addr[3],
        ntt_round_done, done_addr
    );

    reg running, bram_delay;
    reg [5:0] addr1_sr [8:0];
    reg [7:0] valid_sr = 0;
    integer i;

    initial begin
        running    = 0;
        bram_delay = 0;
        done_latch = 0;
        for (i = 0; i < 9; i = i + 1)
            addr1_sr[i] = 0;
    end

    always @(*) begin
        addra1 = 0; addrb1 = 0; web1 = 0; dib1 = 0;
        addra2 = 0; addrb2 = 0; web2 = 0; dib2 = 0;
        validi_bf = 0; datai_bf = 0; zetai_bf = 0; acci_bf = 0;
        rpoly = 0; wpoly = 0; wfinal = 0;
        en_addr  = 0;
        rst_addr = rst | start;

        case (mode)
        FORWARD_NTT_MODE, INVERSE_NTT_MODE: begin
            addra1    = e_raddr;
            rpoly     = e_rpoly;
            addrb1    = e_waddr;
            wpoly     = e_wpoly;
            web1      = e_we;
            wfinal    = e_wfinal;
            dib1      = e_wdata;
            validi_bf = e_s1v;
            datai_bf  = e_s1d;
            zetai_bf  = e_s1z;
        end
        MULT_MODE: begin
            en_addr = running & ~done_latch;
            addra1  = ram_addr;
            addra2  = ram_nat;
            addrb1  = ram_addr;
            datai_bf  = doa1;
            zetai_bf  = {doa2[71:48],doa2[23:0],doa2[95:72],doa2[47:24]};
            acci_bf   = dob1;
            validi_bf = bram_delay & ~done_latch & ~done;
            addrb2 = addr1_sr[8];
            web2   = valido_bf;
            dib2   = datao_bf;
        end
        ADD_MODE, SUB_MODE: begin
            en_addr = running & ~done_latch;
            addra1  = ram_addr;
            addra2  = ram_addr;
            datai_bf  = doa1;
            zetai_bf  = {doa2[71:48],doa2[23:0],doa2[95:72],doa2[47:24]};
            validi_bf = bram_delay & ~done_latch & ~done;
            addrb2 = addr1_sr[4];
            web2   = valido_bf;
            dib2   = datao_bf;
        end
        default: ;
        endcase
    end

    always @(posedge clk) begin
        done       <= 0;
        bram_delay <= running;
        if (rst) begin
            running    <= 0;
            done_latch <= 0;
            valid_sr   <= 0;
            for (i = 0; i < 9; i = i + 1)
                addr1_sr[i] <= 0;
        end else if (ntt_mode) begin
            done <= e_done;
        end else begin
            if (running) begin
                addr1_sr[0] <= ram_addr;
                for (i = 0; i < 8; i = i + 1)
                    addr1_sr[i+1] <= addr1_sr[i];
            end
            done_latch <= (done_addr) ? 1 : done_latch;
            if (running && ~done_addr && ~done_latch)
                valid_sr <= {valid_sr[6:0], 1'b1};
            else
                valid_sr <= {valid_sr[6:0], 1'b0};
            if (start)
                running <= 1;
            else if (done_latch && valid_sr[6:0] == 0) begin
                running    <= 0;
                done       <= 1;
                done_latch <= 0;
            end
        end
    end
endmodule
