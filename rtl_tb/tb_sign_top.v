/*
 * From research paper "High-Performance Hardware Implementation of CRYSTALS-Dilithium"
 * by Luke Beckwith, Duc Tri Nguyen, Kris Gaj (George Mason University)
 * Modified for optimized waveform visualization and clean state resetting.
 */

`timescale 1ns / 1ps
`define P 10 // Clock Period = 10ns (100 MHz Frequency)

module tb_sign_top;
    reg clk = 1, rst = 1, start = 0;
  
    reg [2:0] sec_lvl = 2; // Security levels: 2 (Dilithium2), 3 (Dilithium3), 5 (Dilithium5)
    reg [1:0] mode = 2;    // Mode 2 = Signature Generation
    
    localparam NUM_TV = 5; // Number of Test Vectors

    reg valid_i, ready_o;
    wire ready_i, valid_o;
    reg  [63:0] data_i;  
    wire [63:0] data_o;
    
    // Performance Analysis & Verification Trackers
    integer error_cnt = 0;
    integer phase_start_time = 0;
    
    // Design Under Test (DUT) Instance
    combined_top DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .mode(mode),
        .sec_lvl(sec_lvl),
        .valid_i(valid_i),
        .ready_i(ready_i),
        .data_i(data_i),
        .valid_o(valid_o),
        .ready_o(ready_o),
        .data_o(data_o)
    );
  
    // Testbench State Machine Definitions
    localparam
        START     = 4'd0,
        LOAD_RHO  = 4'd1,
        LOAD_MLEN = 4'd2,
        LOAD_TR   = 4'd3,
        LOAD_M    = 4'd4,
        LOAD_K    = 4'd5,
        LOAD_S1   = 4'd6,
        LOAD_S2   = 4'd7,
        LOAD_T0   = 4'd8,
        UNLOAD_Z  = 4'd9,
        UNLOAD_H  = 4'd10,
        UNLOAD_C  = 4'd11;
  
    reg [4:0] state;
    integer ctr, c = 0, start_time;
  
    // KAT Storage Arrays for Verification Output (Signature Components)
    reg [0:18431] z_2 [NUM_TV-1:0];
    reg [0:671]   h_2 [NUM_TV-1:0];
    reg [0:255]   c_2 [NUM_TV-1:0];  
  
    reg [0:25600-1]      z_3  [NUM_TV-1:0];
    reg [0:487]          h_3   [NUM_TV-1:0];
    reg [0:255]          c_3   [NUM_TV-1:0];
  
    reg [0:35840-1]      z_5  [NUM_TV-1:0];
    reg [0:255]          c_5   [NUM_TV-1:0];
    reg [0:663]          h_5   [NUM_TV-1:0];
  
    // KAT Storage Arrays for Input Vectors (Keys, Seeds & Message)
    reg [0:3300*8-1] m_2    [NUM_TV-1:0];
    reg [0:15]       mlen_2 [NUM_TV-1:0];
    reg [0:255]      k_2    [NUM_TV-1:0];
    reg [0:255]      tr_2   [NUM_TV-1:0];
    reg [0:255]      rho_2  [NUM_TV-1:0];
    reg [0:13311]    t0_2   [NUM_TV-1:0];
    reg [0:3071]     s1_2   [NUM_TV-1:0];
    reg [0:3071]     s2_2   [NUM_TV-1:0];
  
    reg [0:255]      k_3    [NUM_TV-1:0];
    reg [0:255]      tr_3   [NUM_TV-1:0];
    reg [0:255]      rho_3  [NUM_TV-1:0];
    reg [0:19967]    t0_3   [NUM_TV-1:0];
    reg [0:128/2*5*16-1] s1_3  [NUM_TV-1:0];
    reg [0:128/2*6*16-1] s2_3  [NUM_TV-1:0];
    
    reg [0:96*2*7*4-1]   s1_5  [NUM_TV-1:0];
    reg [0:96*2*8*4-1]   s2_5  [NUM_TV-1:0];
    reg [0:255]          k_5   [NUM_TV-1:0];
    reg [0:255]          rho_5 [NUM_TV-1:0];
    reg [0:26624-1]      t0_5  [NUM_TV-1:0];
    reg [0:255]          tr_5  [NUM_TV-1:0];
    
    initial begin
        // --- Security Level 2 KAT File Ingestion ---
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/zs_2.txt",  z_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/h_2.txt",   h_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/c_2.txt",   c_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/rho_2.txt", rho_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/m_2.txt",   m_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/mlen_2.txt", mlen_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/k_2.txt",   k_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/tr_2.txt",  tr_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/t0_2.txt",  t0_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/s1_2.txt",  s1_2);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/s2_2.txt",  s2_2);

        // --- Security Level 3 KAT File Ingestion ---
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/zs_3.txt",  z_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/h_3.txt",   h_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/c_3.txt",   c_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/rho_3.txt", rho_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/k_3.txt",   k_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/tr_3.txt",  tr_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/t0_3.txt",  t0_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/s1_3.txt",  s1_3);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/s2_3.txt",  s2_3);
    
        // --- Security Level 5 KAT File Ingestion ---
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/zs_5.txt",  z_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/h_5.txt",   h_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/c_5.txt",   c_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/rho_5.txt", rho_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/k_5.txt",   k_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/tr_5.txt",  tr_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/t0_5.txt",  t0_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/s1_5.txt",  s1_5);
        $readmemh("C:/Users/bharg/Downloads/Dilithium-master/Dilithium-master/project_1/project_1.sim/sim_1/behav/xsim/s2_5.txt",  s2_5);
    
        ctr       = 0;
        state     = START;
        start     = 0;
        error_cnt = 0;

        $display("==========================================================");
        $display("   STARTING DILITHIUM SIGNATURE GENERATION VERIFICATION   ");
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

                if (ctr == 0) begin
                    rst <= 1; // Assert reset for 1 clock cycle to reset DUT state 9
                    ctr <= 1;
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
                        state  <= LOAD_MLEN;
                        ctr    <= 0;
                        data_i <= {48'd0, mlen_2[c]};
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= rho_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_MLEN: begin
                data_i  <= {48'd0, mlen_2[c]};
                valid_i <= 1;
            
                if (ready_i) begin
                    state  <= LOAD_TR;
                    ctr    <= 0;
                    data_i <= tr_2[c][(0)*64+:64];
                end
            end
            LOAD_TR: begin
                data_i  <= tr_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_M;
                        ctr    <= 0;
                        data_i <= m_2[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= tr_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_M: begin
                data_i  <= m_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if ((ctr+1)*8 >= mlen_2[c]) begin
                        state  <= LOAD_K;
                        ctr    <= 0;
                        data_i <= k_2[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= m_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_K: begin
                data_i  <= k_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_S1;
                        data_i <= s1_2[c][(0)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= k_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_S1: begin
                data_i  <= s1_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 47) begin
                        state  <= LOAD_S2;
                        data_i <= s2_2[c][(0)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= s1_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_S2: begin
                data_i  <= s2_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 47) begin
                        state  <= LOAD_T0;
                        data_i <= t0_2[c][(ctr+1)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= s2_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_T0: begin
                data_i  <= t0_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 207) begin
                        $display("  -> Phase [Input Key & Message Stream Loading] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        state  <= UNLOAD_Z;
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= t0_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            UNLOAD_Z: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o !== z_2[c][ctr*64+:64]) begin
                        $display("[Dilithium2 - Step: Signature Vector Z, Word: %0d] ERROR: Expected %h, Received %h", ctr, z_2[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 288-1) begin
                        $display("  -> Phase [Signing Compute & Response Z Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        ctr <= 0;
                        state <= UNLOAD_H;
                    end
                end
            end
            UNLOAD_H: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o != h_2[c][ctr*64+:64]) begin
                        $display("[Dilithium2 - Step: Hint Vector H, Word: %0d] ERROR: Expected %h, Received %h", ctr, h_2[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 10) begin
                        $display("  -> Phase [Hint Vector H Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        ctr <= 0;
                        state <= UNLOAD_C;
                    end
                end
            end
            UNLOAD_C: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o != c_2[c][ctr*64+:64]) begin
                        $display("[Dilithium2 - Step: Challenge Hash C, Word: %0d] ERROR: Expected %h, Received %h", ctr, c_2[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 3) begin
                        $display("  -> Phase [Challenge Hash C Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        ctr <= 0;
                        state <= START;

                        $display("SG2[%0d] completed in %0d clock cycles", c, ($time - start_time)/`P);
                        c <= c + 1;

                        if (c == NUM_TV-1) begin
                            c <= 0;
                            sec_lvl <= 3;
                            $display ("\nMoving to SG3");
                        end
                    end
                end
            end
            endcase
        end

        3: begin
            case(state)
            START: begin
                start_time       <= $time;
                phase_start_time <= $time;

                if (ctr == 0) begin
                    rst <= 1;
                    ctr <= 1;
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
                        state  <= LOAD_MLEN;
                        ctr    <= 0;
                        data_i <= {48'd0, mlen_2[c]};
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= rho_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_MLEN: begin
                data_i  <= {48'd0, mlen_2[c]};
                valid_i <= 1;
            
                if (ready_i) begin
                    state  <= LOAD_TR;
                    ctr    <= 0;
                    data_i <= tr_3[c][(0)*64+:64];
                end
            end
            LOAD_TR: begin
                data_i  <= tr_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_M;
                        ctr    <= 0;
                        data_i <= m_2[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= tr_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_M: begin
                data_i  <= m_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if ((ctr+1)*8 >= mlen_2[c]) begin
                        state  <= LOAD_K;
                        ctr    <= 0;
                        data_i <= k_3[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= m_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_K: begin
                data_i  <= k_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_S1;
                        data_i <= s1_3[c][(0)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= k_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_S1: begin
                data_i  <= s1_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 128/2*5*16/64-1) begin
                        state  <= LOAD_S2;
                        data_i <= s2_3[c][(0)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= s1_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_S2: begin
                data_i  <= s2_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 128/2*6*16/64-1) begin
                        state  <= LOAD_T0;
                        data_i <= t0_3[c][(ctr+1)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= s2_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_T0: begin
                data_i  <= t0_3[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 19968/64-1) begin
                        $display("  -> Phase [Input Key & Message Stream Loading] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        state  <= UNLOAD_Z;
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= t0_3[c][(ctr+1)*64+:64];
                    end
                end
            end
            UNLOAD_Z: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o !== z_3[c][ctr*64+:64]) begin
                        $display("[Dilithium3 - Step: Signature Vector Z, Word: %0d] ERROR: Expected %h, Received %h", ctr, z_3[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 25600/64-1) begin
                        $display("  -> Phase [Signing Compute & Response Z Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        ctr <= 0;
                        state <= UNLOAD_H;
                    end
                end
            end
            UNLOAD_H: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o != h_3[c][ctr*64+:64]) begin
                        $display("[Dilithium3 - Step: Hint Vector H, Word: %0d] ERROR: Expected %h, Received %h", ctr, h_3[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 7) begin
                        $display("  -> Phase [Hint Vector H Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        ctr <= 0;
                        state <= UNLOAD_C;
                    end
                end
            end
            UNLOAD_C: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o != c_3[c][ctr*64+:64]) begin
                        $display("[Dilithium3 - Step: Challenge Hash C, Word: %0d] ERROR: Expected %h, Received %h", ctr, c_3[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 3) begin
                        $display("  -> Phase [Challenge Hash C Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        ctr <= 0;
                        state <= START;

                        $display("SG3[%0d] completed in %0d clock cycles", c, ($time - start_time)/`P);
                        c <= c + 1;

                        if (c == NUM_TV-1) begin
                            c <= 0;
                            sec_lvl <= 5;
                            $display ("\nMoving to SG5");
                        end
                    end
                end
            end
            endcase
        end

        5: begin
            case(state)
            START: begin
                start_time       <= $time;
                phase_start_time <= $time;

                if (ctr == 0) begin
                    rst <= 1;
                    ctr <= 1;
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
                        state  <= LOAD_MLEN;
                        ctr    <= 0;
                        data_i <= {48'd0, mlen_2[c]};
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= rho_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_MLEN: begin
                data_i  <= {48'd0, mlen_2[c]};
                valid_i <= 1;
            
                if (ready_i) begin
                    state  <= LOAD_TR;
                    ctr    <= 0;
                    data_i <= tr_5[c][(0)*64+:64];
                end
            end
            LOAD_TR: begin
                data_i  <= tr_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_M;
                        ctr    <= 0;
                        data_i <= m_2[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= tr_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_M: begin
                data_i  <= m_2[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if ((ctr+1)*8 >= mlen_2[c]) begin
                        state  <= LOAD_K;
                        ctr    <= 0;
                        data_i <= k_5[c][(0)*64+:64];
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= m_2[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_K: begin
                data_i  <= k_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 3) begin
                        state  <= LOAD_S1;
                        data_i <= s1_5[c][(0)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= k_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_S1: begin
                data_i  <= s1_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 96/2*7*16/64-1) begin
                        state  <= LOAD_S2;
                        data_i <= s2_5[c][(0)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= s1_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_S2: begin
                data_i  <= s2_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 96/2*8*16/64-1) begin
                        state  <= LOAD_T0;
                        data_i <= t0_5[c][(ctr+1)*64+:64];
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= s2_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            LOAD_T0: begin
                data_i  <= t0_5[c][ctr*64+:64];
                valid_i <= 1;
            
                if (ready_i) begin
                    if (ctr == 26624/64-1) begin
                        $display("  -> Phase [Input Key & Message Stream Loading] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        state  <= UNLOAD_Z;
                        ctr    <= 0;
                    end else begin
                        ctr    <= ctr + 1;
                        data_i <= t0_5[c][(ctr+1)*64+:64];
                    end
                end
            end
            UNLOAD_Z: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o !== z_5[c][ctr*64+:64]) begin
                        $display("[Dilithium5 - Step: Signature Vector Z, Word: %0d] ERROR: Expected %h, Received %h", ctr, z_5[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 35840/64-1) begin
                        $display("  -> Phase [Signing Compute & Response Z Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        ctr <= 0;
                        state <= UNLOAD_H;
                    end
                end
            end
            UNLOAD_H: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o != h_5[c][ctr*64+:64]) begin
                        $display("[Dilithium5 - Step: Hint Vector H, Word: %0d] ERROR: Expected %h, Received %h", ctr, h_5[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 10) begin
                        $display("  -> Phase [Hint Vector H Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        phase_start_time <= $time;
                        ctr <= 0;
                        state <= UNLOAD_C;
                    end
                end
            end
            UNLOAD_C: begin
                ready_o <= 1;
                if (valid_o) begin
                    if (data_o != c_5[c][ctr*64+:64]) begin
                        $display("[Dilithium5 - Step: Challenge Hash C, Word: %0d] ERROR: Expected %h, Received %h", ctr, c_5[c][ctr*64+:64], data_o); 
                        error_cnt <= error_cnt + 1;
                    end

                    ctr <= ctr + 1;
                
                    if (ctr == 3) begin
                        $display("  -> Phase [Challenge Hash C Extraction] took %0d cycles", ($time - phase_start_time)/`P);
                        ctr <= 0;
                        state <= START;

                        $display("SG5[%0d] completed in %0d clock cycles", c, ($time - start_time)/`P);
                        c <= c + 1;

                        if (c == NUM_TV-1) begin
                            c <= 0;
                            $display("\n==========================================================");
                            if (error_cnt == 0) begin
                                $display(" *** ALL SIGNATURE KAT TESTS PASSED SUCCESSFULLY *** ");
                            end else begin
                                $display(" *** TEST FAILED: %0d KAT MISMATCHES DETECTED *** ", error_cnt);
                            end
                            $display("==========================================================");
                            $display("Testbench Done.");
                            $finish;
                        end
                    end
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