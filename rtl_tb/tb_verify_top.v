/*
 * From our research paper "High-Performance Hardware Implementation of CRYSTALS-Dilithium"
 * by Luke Beckwith, Duc Tri Nguyen, Kris Gaj
 * at George Mason University, USA
 * https://eprint.iacr.org/2021/1451.pdf
 * =============================================================================
 * Copyright (c) 2021 by Cryptographic Engineering Research Group (CERG)
 * ECE Department, George Mason University
 * Fairfax, VA, U.S.A.
 * Author: Luke Beckwith
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * =============================================================================
 * @author   Luke Beckwith <lbeckwit@gmu.edu>
 */

`timescale 1ns / 1ps
`define P 10 // Clock Period = 10ns (100 MHz Frequency)

module tb_verify_top;
    reg clk = 1, rst = 0, start = 0;
  
    localparam NUM_TV = 5; // Number of Test Vectors

    reg [2:0] sec_lvl = 2; // Security levels: 2 (Dilithium2), 3 (Dilithium3), 5 (Dilithium5)
    reg [1:0] mode = 1;    // Mode 1 = Signature Verification
      
    reg valid_i,  ready_o;
    wire ready_i, valid_o;
    reg  [63:0] data_i;  
    wire [63:0] data_o;
    
    // Performance Analysis & Verification Trackers
    integer error_cnt = 0;
    integer phase_start_time = 0;
    
    // Design Under Test (DUT) Instance
    combined_top DUT (
        clk,
        rst,
        start,
        mode,
        sec_lvl,
        valid_i,
        ready_i,
        data_i,
        valid_o,
        ready_o,
        data_o
    );
  
    // Testbench State Machine Definitions
    localparam
        START         = 4'd0,
        LOAD_RHO      = 4'd1,
        LOAD_C        = 4'd2,
        LOAD_Z        = 4'd3,
        LOAD_T1       = 4'd4,
        LOAD_MLEN     = 4'd5,
        LOAD_M        = 4'd6,
        LOAD_H        = 4'd7,
        UNLOAD_RESULT = 4'd8,
        STOP          = 4'd9;
  
    reg [3:0] state;
    integer ctr, c, start_time;
  
    // Storage Arrays for Verification Inputs (Message, Signature Components & Public Keys)
    reg [0:3300*8-1] m_2    [NUM_TV-1:0];
    reg [0:15]       mlen_2 [NUM_TV-1:0];
  
    reg [0:255]      c_2    [NUM_TV-1:0];
    reg [0:255]      rho_2  [NUM_TV-1:0];
    reg [0:18431]    z_2    [NUM_TV-1:0];
    reg [0:10239]    t1_2   [NUM_TV-1:0];
    reg [0:671]      h_2    [NUM_TV-1:0];

    reg [0:255]      c_3    [NUM_TV-1:0];
    reg [0:487]      h_3    [NUM_TV-1:0];
    reg [0:255]      rho_3  [NUM_TV-1:0];
    reg [0:15359]    t1_3   [NUM_TV-1:0];
    reg [0:25600-1]  z_3    [NUM_TV-1:0];
   
    reg [0:255]      c_5    [NUM_TV-1:0];
    reg [0:663]      h_5    [NUM_TV-1:0];
    reg [0:255]      rho_5  [NUM_TV-1:0];
    reg [0:20480-1]  t1_5   [NUM_TV-1:0];
    reg [0:35840-1]  z_5    [NUM_TV-1:0];
    
    initial begin
        // --- Security Level 2 KAT File Ingestion ---
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/zs_2.txt",   z_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/rho_2.txt",  rho_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/t1_2.txt",   t1_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/m_2.txt",    m_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/mlen_2.txt", mlen_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/c_2.txt",    c_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/h_2.txt",    h_2);
    
        // --- Security Level 3 KAT File Ingestion ---
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/zs_3.txt",   z_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/rho_3.txt",  rho_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/t1_3.txt",   t1_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/c_3.txt",    c_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/h_3.txt",    h_3);
    
        // --- Security Level 5 KAT File Ingestion ---
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/zs_5.txt",   z_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/rho_5.txt",  rho_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/t1_5.txt",   t1_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/c_5.txt",    c_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/h_5.txt",    h_5);
    
        c         = 0;
        ctr       = 0;
        state     = START;
        start     = 0;
        rst       = 1;
        error_cnt = 0;

        $display("==========================================================");
        $display("   STARTING DILITHIUM SIGNATURE VERIFICATION TESTBENCH    ");
        $display("==========================================================");
    end
  
    always @(posedge clk) begin
        data_i  <= 0;
        valid_i <= 0;
        ready_o <= 0;
        start   <= 0;
        rst     <= 0;
    
        case(sec_lvl)
        2: begin
            case(state)
            START: begin
                start_time       <= $time;
                phase_start_time <= $time;
                if (ctr < 2) begin
                    ctr <= ctr + 1;
                    rst <= 1;
                end else begin
                    ctr   <= 0;
                    start <= 1;
                    state <= LOAD_RHO;
                end
            end
            LOAD_RHO: begin
                data_i  <= rho_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_C;
                        ctr    <= 0;
                        data_i <= c_2[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= rho_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_C: begin
                data_i  <= c_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_Z;
                        ctr    <= 0;
                        data_i <= z_2[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= c_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_Z: begin
                data_i  <= z_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 287) begin
                        state  <= LOAD_T1;
                        ctr    <= 0;
                        data_i <= t1_2[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= z_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_T1: begin
                data_i  <= t1_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 159) begin
                        state  <= LOAD_MLEN;
                        ctr    <= 0;
                        data_i <= {48'd0, mlen_2[c]};
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= t1_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_MLEN: begin
                data_i  <= {48'd0, mlen_2[c]};
                valid_i <= 1;
            
                if (ready_i) begin
                    state  <= LOAD_M;
                    ctr    <= 0;
                    data_i <= m_2[c][(0)*64+:64];
                end
            end
            LOAD_M: begin
                data_i  <= m_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if ((ctr+1)*8 >= mlen_2[c]) begin
                        state <= LOAD_H;
                        ctr   <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= m_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_H: begin
                data_i  <= h_2[c][ctr*64+:64];
                valid_i <= 1;
        
                if (ready_i) begin
                    if (ctr == 10) begin
                        $display("  -> Phase [Input Public Key, Signature & Message Stream Loading] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        state <= UNLOAD_RESULT;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= h_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            UNLOAD_RESULT: begin
                ready_o <= 1;
                if (valid_o) begin
                    $display("  -> Phase [Verification Core Processing & Decision Logic] took %0d cycles", ($time - phase_start_time)/`P);
                    if (data_o == 1) begin
                        $display("[Dilithium2 - Test %0d] ERROR: Verification Rejected valid signature!", c);
                        error_cnt <= error_cnt + 1;
                    end else begin
                        $display("[Dilithium2 - Test %0d] SUCCESS: Verification Accepted signature", c);
                    end
                    state <= STOP;
                end
            end
            STOP: begin
                ready_o <= 1;
                c       <= c + 1;
                state   <= START;
                ctr     <= 0;

                $display("VY2[%0d] completed in %0d clock cycles", c, ($time - start_time)/`P);

                if (c == NUM_TV-1) begin
                    c       <= 0;
                    sec_lvl <= 3;
                    $display ("\nMoving to VY3");
                end       
            end
            endcase
        end

        3: begin
            case(state)
            START: begin
                start_time       <= $time;
                phase_start_time <= $time;
                if (ctr < 2) begin
                    ctr <= ctr + 1;
                end else begin
                    ctr   <= 0;
                    start <= 1;
                    state <= LOAD_RHO;
                end
            end
            LOAD_RHO: begin
                data_i  <= rho_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_C;
                        ctr    <= 0;
                        data_i <= c_3[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= rho_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_C: begin
                data_i  <= c_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_Z;
                        ctr    <= 0;
                        data_i <= z_3[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= c_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_Z: begin
                data_i  <= z_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 25600/64-1) begin
                        state  <= LOAD_T1;
                        ctr    <= 0;
                        data_i <= t1_3[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= z_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_T1: begin
                data_i  <= t1_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 15360/64-1) begin
                        state  <= LOAD_MLEN;
                        ctr    <= 0;
                        data_i <= {48'd0, mlen_2[c]};
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= t1_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_MLEN: begin
                data_i  <= {48'd0, mlen_2[c]};
                valid_i <= 1;
            
                if (ready_i) begin
                    state  <= LOAD_M;
                    ctr    <= 0;
                    data_i <= m_2[c][(0)*64+:64];
                end
            end
            LOAD_M: begin
                data_i  <= m_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if ((ctr+1)*8 >= mlen_2[c]) begin
                        state <= LOAD_H;
                        ctr   <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= m_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_H: begin
                data_i  <= h_3[c][ctr*64+:64];
                valid_i <= 1;
        
                if (ready_i) begin
                    if (ctr == 7) begin
                        $display("  -> Phase [Input Public Key, Signature & Message Stream Loading] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        state <= UNLOAD_RESULT;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= h_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            UNLOAD_RESULT: begin
                ready_o <= 1;
                if (valid_o) begin
                    $display("  -> Phase [Verification Core Processing & Decision Logic] took %0d cycles", ($time - phase_start_time)/`P);
                    if (data_o == 1) begin
                        $display("[Dilithium3 - Test %0d] ERROR: Verification Rejected valid signature!", c);
                        error_cnt <= error_cnt + 1;
                    end else begin
                        $display("[Dilithium3 - Test %0d] SUCCESS: Verification Accepted signature", c);
                    end
                    state <= STOP;
                end
            end
            STOP: begin
                ready_o <= 1;
                c       <= c + 1;
                state   <= START;
                ctr     <= 0;

                $display("VY3[%0d] completed in %0d clock cycles", c, ($time - start_time)/`P);

                if (c == NUM_TV-1) begin
                    c       <= 0;
                    sec_lvl <= 5;
                    $display ("\nMoving to VY5");
                end           
            end
            endcase
        end

        5: begin
            case(state)
            START: begin
                start_time       <= $time;
                phase_start_time <= $time;
                if (ctr < 2) begin
                    ctr <= ctr + 1;
                end else begin
                    ctr   <= 0;
                    start <= 1;
                    state <= LOAD_RHO;
                end
            end
            LOAD_RHO: begin
                data_i  <= rho_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_C;
                        ctr    <= 0;
                        data_i <= c_5[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= rho_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_C: begin
                data_i  <= c_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_Z;
                        ctr    <= 0;
                        data_i <= z_5[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= c_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_Z: begin
                data_i  <= z_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 35840/64-1) begin
                        state  <= LOAD_T1;
                        ctr    <= 0;
                        data_i <= t1_5[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= z_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_T1: begin
                data_i  <= t1_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 20480/64-1) begin
                        state  <= LOAD_MLEN;
                        ctr    <= 0;
                        data_i <= {48'd0, mlen_2[c]};
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= t1_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_MLEN: begin
                data_i  <= {48'd0, mlen_2[c]};
                valid_i <= 1;
            
                if (ready_i) begin
                    state  <= LOAD_M;
                    ctr    <= 0;
                    data_i <= m_2[c][(0)*64+:64];
                end
            end
            LOAD_M: begin
                data_i  <= m_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if ((ctr+1)*8 >= mlen_2[c]) begin
                        state <= LOAD_H;
                        ctr   <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= m_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_H: begin
                data_i  <= h_5[c][ctr*64+:64];
                valid_i <= 1;
        
                if (ready_i) begin
                    if (ctr == 10) begin
                        $display("  -> Phase [Input Public Key, Signature & Message Stream Loading] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        state <= UNLOAD_RESULT;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= h_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            UNLOAD_RESULT: begin
                ready_o <= 1;
                if (valid_o) begin
                    $display("  -> Phase [Verification Core Processing & Decision Logic] took %0d cycles", ($time - phase_start_time)/`P);
                    if (data_o == 1) begin
                        $display("[Dilithium5 - Test %0d] ERROR: Verification Rejected valid signature!", c);
                        error_cnt <= error_cnt + 1;
                    end else begin
                        $display("[Dilithium5 - Test %0d] SUCCESS: Verification Accepted signature", c);
                    end
                    state <= STOP;
                end
            end
            STOP: begin
                ready_o <= 1;
                c       <= c + 1;
                state   <= START;
                ctr     <= 0;

                $display("VY5[%0d] completed in %0d clock cycles", c, ($time - start_time)/`P);

                if (c == NUM_TV-1) begin
                    c <= 0;
                    $display("\n==========================================================");
                    if (error_cnt == 0) begin
                        $display(" *** ALL VERIFICATION KAT TESTS PASSED SUCCESSFULLY *** ");
                    end else begin
                        $display(" *** TEST FAILED: %0d VERIFICATION MISMATCHES DETECTED *** ", error_cnt);
                    end
                    $display("==========================================================");
                    $display("Testbench done.");
                    $finish;
                end        
            end
            endcase
        end
        endcase
    end
  
    // Clock Generator: 10ns Period (100MHz)
    always #(`P/2) clk = ~clk;

endmodule
`undef P