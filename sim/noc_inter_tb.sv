`timescale 1ns / 1ps
//
// NoC Intermediate Stage (MM + GELU) End-to-End Testbench
// Tests: A~ * K'^T -> Requant -> GELU -> Requant -> G~
// Uses CIPS VIP API for memory access
//

`include "ibert_params.svh"

module noc_inter_tb;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    reg sim_clk;
    initial begin
        sim_clk = 0;
        forever #5 sim_clk = ~sim_clk; // 100 MHz
    end

    // DDR4 system clock (200 MHz differential)
    reg sys_clk_p;
    wire sys_clk_n;
    assign sys_clk_n = !sys_clk_p;
    initial begin
        sys_clk_p = 0;
        forever #2.5 sys_clk_p = !sys_clk_p; // 200 MHz
    end

    //==========================================================================
    // DUT Interface Signals
    //==========================================================================
    wire        ch0_ddr4_0_act_n;
    wire [16:0] ch0_ddr4_0_adr;
    wire [1:0]  ch0_ddr4_0_ba;
    wire [1:0]  ch0_ddr4_0_bg;
    wire        ch0_ddr4_0_ck_c;
    wire        ch0_ddr4_0_ck_t;
    wire        ch0_ddr4_0_cke;
    wire        ch0_ddr4_0_cs_n;
    wire [7:0]  ch0_ddr4_0_dm_n;
    wire [63:0] ch0_ddr4_0_dq;
    wire [7:0]  ch0_ddr4_0_dqs_c;
    wire [7:0]  ch0_ddr4_0_dqs_t;
    wire        ch0_ddr4_0_odt;
    wire        ch0_ddr4_0_reset_n;

    // Control Signals
    reg         start;
    wire        done;
    wire        error;
    
    // Configuration Registers
    reg [63:0] addr_A_r;
    reg [63:0] addr_K_r;
    reg [63:0] addr_G_r;
    
    reg [31:0] requant_m_mult_r;
    reg [7:0]  requant_e_mult_r;
    reg [31:0] requant_m_G_r;
    reg [7:0]  requant_e_G_r;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    // Instantiate the new intermediate wrapper
    design_1_wrapper_inter dut (
        .CH0_DDR4_0_act_n(ch0_ddr4_0_act_n),
        .CH0_DDR4_0_adr(ch0_ddr4_0_adr),
        .CH0_DDR4_0_ba(ch0_ddr4_0_ba),
        .CH0_DDR4_0_bg(ch0_ddr4_0_bg),
        .CH0_DDR4_0_ck_c(ch0_ddr4_0_ck_c),
        .CH0_DDR4_0_ck_t(ch0_ddr4_0_ck_t),
        .CH0_DDR4_0_cke(ch0_ddr4_0_cke),
        .CH0_DDR4_0_cs_n(ch0_ddr4_0_cs_n),
        .CH0_DDR4_0_dm_n(ch0_ddr4_0_dm_n),
        .CH0_DDR4_0_dq(ch0_ddr4_0_dq),
        .CH0_DDR4_0_dqs_c(ch0_ddr4_0_dqs_c),
        .CH0_DDR4_0_dqs_t(ch0_ddr4_0_dqs_t),
        .CH0_DDR4_0_odt(ch0_ddr4_0_odt),
        .CH0_DDR4_0_reset_n(ch0_ddr4_0_reset_n),
        .sys_clk0_clk_n(sys_clk_n),
        .sys_clk0_clk_p(sys_clk_p),
        
        // DUT Control & Config
        .start(start),
        .done(done),
        .error(error),
        .addr_A(addr_A_r),
        .addr_K(addr_K_r),
        .addr_G(addr_G_r),
        .requant_m_mult(requant_m_mult_r),
        .requant_e_mult(requant_e_mult_r),
        .requant_m_G(requant_m_G_r),
        .requant_e_G(requant_e_G_r)
    );

    //==========================================================================
    // Test Data Arrays
    //==========================================================================
    // Arrays for generating data files
    reg [7:0] matrix_A [0:INPUT_SIZE*HIDDEN_SIZE-1];
    reg [7:0] matrix_K [0:HIDDEN_SIZE*EXP_SIZE-1];

    //==========================================================================
    // CIPS VIP Memory Tasks
    //==========================================================================
    // NOTE: Hierarchy path to VIP must match the instantiated design_1 instance
    // Inside design_1_wrapper_inter, the BD instance is named "design_1_i"
    
    task write_ddr_from_file(
        input [63:0] addr,
        input [1023:0] filename,
        input [31:0] num_bytes
    );
        automatic bit [1:0] resp;
        begin
            dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.write_from_file(
                "NOC_API", filename, addr, num_bytes, resp
            );
            if (resp != 0)
                $display("[%t] ERROR: NoC write_from_file to 0x%h failed resp=%0d", $time, addr, resp);
        end
    endtask

    task read_ddr_to_file(
        input [63:0] addr,
        input [1023:0] filename,
        input [31:0] num_bytes
    );
        automatic bit [1:0] resp;
        begin
            dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.read_to_file(
                "NOC_API", filename, addr, num_bytes, resp
            );
            if (resp != 0)
                $display("[%t] ERROR: NoC read_to_file from 0x%h failed resp=%0d", $time, addr, resp);
            else
                $display("[%t] INFO: Read %d bytes from 0x%h to file %s", $time, num_bytes, addr, filename);
        end
    endtask

    //==========================================================================
    // CIPS Initialization
    //==========================================================================
    initial begin
        repeat(10) @(posedge sim_clk);
        // Reset and clock generation for the VIP
        dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.pl_gen_clock(0, 300);
        force dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.versal_cips_ps_vip_clk = sim_clk;
        dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.por_reset(0);
        repeat(20) @(posedge sim_clk);
        dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.por_reset(1);
        repeat(50) @(posedge sim_clk);
        
        // Force PL reset inactive (active low logic usually handled by CIPS, but forcing helps sim)
        force dut.rstn_pl = 1'b1; 
        
        $display("[%t] INFO: CIPS VIP initialized", $time);
    end

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    integer i;
    integer file_handle;
    
    initial begin
        $display("================================================================================");
        $display("NoC Intermediate Layer (MM + GELU) End-to-End Test");
        $display("================================================================================");
        $display("Dimensions: A[%0d x %0d] * K[%0d x %0d] = G[%0d x %0d]", 
                 INPUT_SIZE, HIDDEN_SIZE, HIDDEN_SIZE, EXP_SIZE, INPUT_SIZE, EXP_SIZE);

        // 1. Initialize Control Signals
        start = 0;
        addr_A_r = ADDR_A;
        addr_K_r = ADDR_K;
        addr_G_r = ADDR_G;
        requant_m_mult_r = REQUANT_M_MULT;
        requant_e_mult_r = REQUANT_E_MULT;
        requant_m_G_r    = REQUANT_M_G;
        requant_e_G_r    = REQUANT_E_G;

        // Wait for VIP initialization
        repeat(300) @(posedge sim_clk);
        
        // Configure NoC Routing via VIP
        dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.set_routing_config(
            "NOC_API", "FPD_CCI_NOC", 1
        );

        // 2. Generate Test Data
        $display("[%t] INFO: Step 1 - Generating Test Matrices", $time);
        
        // Matrix A: All 1s
        for (i = 0; i < INPUT_SIZE*HIDDEN_SIZE; i++) begin
            matrix_A[i] = 8'd1;
        end
        
        // Matrix K: All 2s
        for (i = 0; i < HIDDEN_SIZE*EXP_SIZE; i++) begin
            matrix_K[i] = 8'd2; 
        end

        // 3. Write Data Files
        file_handle = $fopen("matrix_A.txt", "w");
        for (i = 0; i < INPUT_SIZE*HIDDEN_SIZE; i++) 
            $fwrite(file_handle, "%08h\n", {24'b0, matrix_A[i]});
        $fclose(file_handle);

        file_handle = $fopen("matrix_K.txt", "w");
        for (i = 0; i < HIDDEN_SIZE*EXP_SIZE; i++) 
            $fwrite(file_handle, "%08h\n", {24'b0, matrix_K[i]});
        $fclose(file_handle);

        // 4. Load DDR via VIP
        $display("[%t] INFO: Step 2 - Loading DDR", $time);
        write_ddr_from_file(ADDR_A, "matrix_A.txt", INPUT_SIZE*HIDDEN_SIZE*4);
        write_ddr_from_file(ADDR_K, "matrix_K.txt", HIDDEN_SIZE*EXP_SIZE*4);

        repeat(100) @(posedge sim_clk);

        // 5. Run DUT
        $display("[%t] INFO: Step 3 - Starting Processing", $time);
        start = 1;
        repeat(5) @(posedge sim_clk);
        start = 0;

        // 6. Wait for Completion
        fork
            begin
                wait(done == 1);
                $display("[%t] INFO: Processing Done signal received", $time);
            end
            begin
                repeat(TIMEOUT_CYCLES) @(posedge sim_clk);
                if (!done) begin
                    $display("[%t] ERROR: Timeout waiting for DONE", $time);
                    $finish;
                end
            end
        join_any
        disable fork;

        if (error) $display("[%t] ERROR: DUT reported error state", $time);

        repeat(500) @(posedge sim_clk);

        // 7. Read Back Results
        $display("[%t] INFO: Step 4 - Reading Result G", $time);
        // Note: Output is written as 8-bit values zero-extended to 32-bit words in DDR
        read_ddr_to_file(ADDR_G, "result_G.txt", INPUT_SIZE * EXP_SIZE * 4);

        $display("================================================================================");
        $display("[%t] INFO: Test Complete. Check result_G.txt for output.", $time);
        $display("================================================================================");
        $finish;
    end

endmodule
