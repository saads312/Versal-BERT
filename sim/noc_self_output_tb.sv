`timescale 1ns / 1ps
//
// NoC Self-Output Layer End-to-End Testbench
// Tests: LayerNorm(Linear(attention_output) + residual)
//        where Linear = attention_output × W_self_output + bias
// Uses CIPS VIP API for memory access
//

`include "ibert_params.svh"

module noc_self_output_tb;

    
    // Parameters (override from ibert_params.svh if needed)
    
    localparam TOKENS = 32;
    localparam EMBED = 768;

    // DDR addresses
    localparam [63:0] ADDR_ATTN_OUTPUT = 64'h0001_0000;
    localparam [63:0] ADDR_WEIGHT      = 64'h0002_0000;
    localparam [63:0] ADDR_RESIDUAL    = 64'h0003_0000;
    localparam [63:0] ADDR_OUTPUT      = 64'h0004_0000;

    // Requantization parameters
    localparam [31:0] REQUANT_M_MM = 32'h0000_0100;  // Scale for matmul output
    localparam [7:0]  REQUANT_E_MM = 8'd8;           // Shift for matmul output
    localparam [31:0] REQUANT_M_LN = 32'h0000_0100;  // Scale for layernorm output
    localparam [7:0]  REQUANT_E_LN = 8'd8;           // Shift for layernorm output

    
    // Clock Generation
    
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

    
    // DUT Interface Signals
    
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
    reg [63:0] addr_attn_output_r;
    reg [63:0] addr_weight_r;
    reg [63:0] addr_residual_r;
    reg [63:0] addr_output_r;

    reg [31:0] requant_m_mm_r;
    reg [7:0]  requant_e_mm_r;
    reg [31:0] requant_m_ln_r;
    reg [7:0]  requant_e_ln_r;

    
    // DUT Instantiation
    

    // Instantiate the self-output wrapper
    design_1_wrapper_self_output dut (
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
        .addr_attn_output(addr_attn_output_r),
        .addr_weight(addr_weight_r),
        .addr_residual(addr_residual_r),
        .addr_output(addr_output_r),
        .requant_m_mm(requant_m_mm_r),
        .requant_e_mm(requant_e_mm_r),
        .requant_m_ln(requant_m_ln_r),
        .requant_e_ln(requant_e_ln_r)
    );

    
    // Test Data Arrays
    
    // Arrays for generating data files
    reg [7:0] matrix_attn_output [0:TOKENS*EMBED-1];
    reg [7:0] matrix_weight [0:EMBED*EMBED-1];
    reg [7:0] matrix_residual [0:TOKENS*EMBED-1];
    reg [7:0] matrix_output_expected [0:TOKENS*EMBED-1];
    reg [7:0] matrix_output_actual [0:TOKENS*EMBED-1];

    
    // CIPS VIP Memory Tasks
    
    // NOTE: Hierarchy path to VIP must match the instantiated design_1 instance
    // Inside design_1_wrapper_self_output, the BD instance is named "design_1_i"

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
            else
                $display("[%t] INFO: Wrote %d bytes from file %s to 0x%h", $time, num_bytes, filename, addr);
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

    
    // CIPS Initialization
    
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

    
    // Main Test Sequence
    
    integer i, j;
    integer file_handle;
    integer mismatches;

    initial begin
        $display("================================================================================");
        $display("NoC Self-Output Layer End-to-End Test");
        $display("================================================================================");
        $display("Dimensions:");
        $display("  Attention Output: [%0d x %0d]", TOKENS, EMBED);
        $display("  Weight (W_self_output): [%0d x %0d]", EMBED, EMBED);
        $display("  Residual: [%0d x %0d]", TOKENS, EMBED);
        $display("  Output: [%0d x %0d]", TOKENS, EMBED);
        $display("Operation: LayerNorm(attn_output × weight + residual)");
        $display("================================================================================");

        // 1. Initialize Control Signals
        start = 0;
        addr_attn_output_r = ADDR_ATTN_OUTPUT;
        addr_weight_r = ADDR_WEIGHT;
        addr_residual_r = ADDR_RESIDUAL;
        addr_output_r = ADDR_OUTPUT;
        requant_m_mm_r = REQUANT_M_MM;
        requant_e_mm_r = REQUANT_E_MM;
        requant_m_ln_r = REQUANT_M_LN;
        requant_e_ln_r = REQUANT_E_LN;

        // Wait for VIP initialization
        repeat(300) @(posedge sim_clk);

        // Configure NoC Routing via VIP
        dut.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.set_routing_config(
            "NOC_API", "FPD_CCI_NOC", 1
        );

        // 2. Generate Test Data
        $display("[%t] INFO: Step 1 - Generating Test Matrices", $time);

        // Attention output: All 1s
        for (i = 0; i < TOKENS*EMBED; i++) begin
            matrix_attn_output[i] = 8'd1;
        end

        // Weight: Identity-like (simplified for testing)
        for (i = 0; i < EMBED*EMBED; i++) begin
            matrix_weight[i] = 8'd1;  // Simplified - could use identity matrix
        end

        // Residual: All 2s
        for (i = 0; i < TOKENS*EMBED; i++) begin
            matrix_residual[i] = 8'd2;
        end

        // Write test data to binary files
        file_handle = $fopen("attn_output.bin", "wb");
        for (i = 0; i < TOKENS*EMBED; i++) begin
            $fwrite(file_handle, "%c", matrix_attn_output[i]);
        end
        $fclose(file_handle);

        file_handle = $fopen("weight.bin", "wb");
        for (i = 0; i < EMBED*EMBED; i++) begin
            $fwrite(file_handle, "%c", matrix_weight[i]);
        end
        $fclose(file_handle);

        file_handle = $fopen("residual.bin", "wb");
        for (i = 0; i < TOKENS*EMBED; i++) begin
            $fwrite(file_handle, "%c", matrix_residual[i]);
        end
        $fclose(file_handle);

        $display("[%t] INFO: Test matrices generated and written to files", $time);

        // 3. Write Test Data to DDR
        $display("[%t] INFO: Step 2 - Writing test data to DDR", $time);

        write_ddr_from_file(ADDR_ATTN_OUTPUT, "attn_output.bin", TOKENS*EMBED);
        repeat(10) @(posedge sim_clk);

        write_ddr_from_file(ADDR_WEIGHT, "weight.bin", EMBED*EMBED);
        repeat(10) @(posedge sim_clk);

        write_ddr_from_file(ADDR_RESIDUAL, "residual.bin", TOKENS*EMBED);
        repeat(10) @(posedge sim_clk);

        $display("[%t] INFO: All input data written to DDR", $time);

        // 4. Start Computation
        $display("[%t] INFO: Step 3 - Starting computation", $time);
        repeat(10) @(posedge sim_clk);
        start = 1;
        @(posedge sim_clk);
        start = 0;

        $display("[%t] INFO: Waiting for done signal...", $time);

        // 5. Wait for Completion
        fork
            begin
                // Timeout after 50ms
                #50_000_000;
                if (!done) begin
                    $display("[%t] ERROR: Timeout waiting for done signal!", $time);
                    $finish;
                end
            end
            begin
                // Wait for done
                wait(done);
                $display("[%t] INFO: Computation completed", $time);
            end
            begin
                // Monitor for errors
                wait(error);
                $display("[%t] ERROR: Error signal asserted during computation!", $time);
                $finish;
            end
        join_any
        disable fork;

        // Check if we got an error
        if (error) begin
            $display("[%t] FAIL: Design reported an error", $time);
            $finish;
        end

        // 6. Read Results from DDR
        $display("[%t] INFO: Step 4 - Reading results from DDR", $time);
        repeat(50) @(posedge sim_clk);

        read_ddr_to_file(ADDR_OUTPUT, "output_actual.bin", TOKENS*EMBED);
        repeat(10) @(posedge sim_clk);

        // 7. Load and verify results
        $display("[%t] INFO: Step 5 - Verifying results", $time);

        file_handle = $fopen("output_actual.bin", "rb");
        if (file_handle == 0) begin
            $display("[%t] ERROR: Could not open output_actual.bin", $time);
            $finish;
        end
        for (i = 0; i < TOKENS*EMBED; i++) begin
            matrix_output_actual[i] = $fgetc(file_handle);
        end
        $fclose(file_handle);

        // Simple verification - check that output is non-zero
        mismatches = 0;
        for (i = 0; i < TOKENS*EMBED; i++) begin
            if (matrix_output_actual[i] == 8'd0) begin
                mismatches = mismatches + 1;
            end
        end

        // Display results
        $display("[%t] INFO: Verification complete", $time);
        $display("================================================================================");
        $display("RESULTS:");
        $display("  Total elements: %0d", TOKENS*EMBED);
        $display("  Zero elements: %0d", mismatches);
        $display("  Non-zero elements: %0d", (TOKENS*EMBED) - mismatches);

        // Show first few output values
        $display("\nFirst 16 output values:");
        for (i = 0; i < 16; i++) begin
            $display("  output[%0d] = %d (0x%h)", i, $signed(matrix_output_actual[i]), matrix_output_actual[i]);
        end

        if (mismatches < TOKENS*EMBED) begin
            $display("\n*** TEST PASSED ***");
            $display("Output contains valid data (non-zero values detected)");
        end else begin
            $display("\n*** TEST FAILED ***");
            $display("All output values are zero - likely computation error");
        end

        $display("================================================================================");
        $finish;
    end

    // Waveform Dump
    initial begin
        $dumpfile("noc_self_output_tb.vcd");
        $dumpvars(0, noc_self_output_tb);
    end


    // Timeout
    initial begin
        #100_000_000; // 100ms absolute timeout
        $display("[%t] ERROR: Absolute simulation timeout!", $time);
        $finish;
    end

endmodule
