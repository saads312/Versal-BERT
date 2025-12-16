`timescale 1ns / 1ps
//
// NoC Self-Attention End-to-End Testbench
// Tests complete self-attention:
//   Phase 1: Q/K/V projections (I × W^Q/K/V → Q'/K'^T/V')
//   Phase 2: Attention scores (Q' × K'^T → S)
//   Phase 3: Softmax (S → P)
//   Phase 4: Context (P × V' → C → C')
//
// Uses CIPS VIP API for memory access
// All parameters are centralized in ibert_params.svh
//

`include "ibert_params.svh"

module noc_self_attn_tb;

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

    // DDR4 interface
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

    // Self-attention control
    reg         attn_start;
    wire        attn_done;
    wire        attn_error;

    // Input and weight addresses
    reg  [63:0] addr_I_r;
    reg  [63:0] addr_W_Q_r;
    reg  [63:0] addr_W_K_r;
    reg  [63:0] addr_W_V_r;

    // Q/K/V projection output addresses
    reg  [63:0] addr_Q_prime_r;
    reg  [63:0] addr_K_prime_T_r;
    reg  [63:0] addr_V_prime_r;

    // Self-attention intermediate addresses
    reg  [63:0] addr_S_r;
    reg  [63:0] addr_P_r;
    reg  [63:0] addr_C_prime_r;

    // Requantization parameters for Q/K/V
    reg  [31:0] requant_m_Q_r;
    reg  [7:0]  requant_e_Q_r;
    reg  [31:0] requant_m_K_r;
    reg  [7:0]  requant_e_K_r;
    reg  [31:0] requant_m_V_r;
    reg  [7:0]  requant_e_V_r;

    // Requantization parameters for context
    reg  [31:0] requant_m_C_r;
    reg  [7:0]  requant_e_C_r;

    // Softmax coefficients
    reg signed [31:0] softmax_qb_r;
    reg signed [31:0] softmax_qc_r;
    reg signed [31:0] softmax_qln2_r;
    reg signed [31:0] softmax_qln2_inv_r;
    reg        [31:0] softmax_sreq_r;

    //==========================================================================
    // DUT Instantiation - Use Vivado's sim_wrapper for proper clock infrastructure
    //==========================================================================

    design_1_wrapper_sim_wrapper dut (
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

        // Control
        .attn_start(attn_start),
        .attn_done(attn_done),
        .attn_error(attn_error),

        // Input and weight addresses
        .addr_I(addr_I_r),
        .addr_W_Q(addr_W_Q_r),
        .addr_W_K(addr_W_K_r),
        .addr_W_V(addr_W_V_r),

        // Q/K/V projection outputs
        .addr_Q_prime(addr_Q_prime_r),
        .addr_K_prime_T(addr_K_prime_T_r),
        .addr_V_prime(addr_V_prime_r),

        // Self-attention intermediates
        .addr_S(addr_S_r),
        .addr_P(addr_P_r),
        .addr_C_prime(addr_C_prime_r),

        // Requant parameters for Q/K/V
        .requant_m_Q(requant_m_Q_r),
        .requant_e_Q(requant_e_Q_r),
        .requant_m_K(requant_m_K_r),
        .requant_e_K(requant_e_K_r),
        .requant_m_V(requant_m_V_r),
        .requant_e_V(requant_e_V_r),

        // Requant parameters for context
        .requant_m_C(requant_m_C_r),
        .requant_e_C(requant_e_C_r),

        // Softmax coefficients
        .softmax_qb(softmax_qb_r),
        .softmax_qc(softmax_qc_r),
        .softmax_qln2(softmax_qln2_r),
        .softmax_qln2_inv(softmax_qln2_inv_r),
        .softmax_sreq(softmax_sreq_r)
    );

    //==========================================================================
    // Test Data: Define Matrices
    //==========================================================================

    // Input I (TOKENS x EMBED)
    reg [7:0] matrix_I [0:TOKENS*EMBED-1];

    // Weight matrices (EMBED x HEAD_DIM)
    reg [7:0] matrix_W_Q [0:EMBED*HEAD_DIM-1];
    reg [7:0] matrix_W_K [0:EMBED*HEAD_DIM-1];
    reg [7:0] matrix_W_V [0:EMBED*HEAD_DIM-1];

    // Expected intermediate values (for reference)
    reg [31:0] matrix_Q_expected [0:TOKENS*HEAD_DIM-1];
    reg [31:0] matrix_K_expected [0:TOKENS*HEAD_DIM-1];
    reg [31:0] matrix_V_expected [0:TOKENS*HEAD_DIM-1];
    reg [31:0] matrix_S_expected [0:TOKENS*TOKENS-1];  // Attention scores

    //==========================================================================
    // DDR Memory Access via CIPS VIP
    //==========================================================================

    task write_ddr_via_noc(
        input [63:0] addr,
        input [31:0] data_word
    );
        automatic bit [1:0] resp;
        begin
            dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.write_data_32(
                "NOC_API", addr, data_word, resp
            );
            if (resp != 0)
                $display("[%t] ERROR: NoC write to 0x%h failed resp=%0d", $time, addr, resp);
        end
    endtask

    task read_ddr_via_noc(
        input  [63:0] addr,
        output [31:0] data_word
    );
        automatic bit [1:0] resp;
        begin
            dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.read_data_32(
                "NOC_API", addr, data_word, resp
            );
            if (resp != 0)
                $display("[%t] ERROR: NoC read from 0x%h failed resp=%0d", $time, addr, resp);
        end
    endtask

    // Bulk write from file
    task write_ddr_from_file(
        input [63:0] addr,
        input [1023:0] filename,
        input [31:0] num_bytes
    );
        automatic bit [1:0] resp;
        begin
            dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.write_from_file(
                "NOC_API", filename, addr, num_bytes, resp
            );
            if (resp != 0)
                $display("[%t] ERROR: NoC write_from_file to 0x%h failed resp=%0d", $time, addr, resp);
        end
    endtask

    // Bulk read to file
    task read_ddr_to_file(
        input [63:0] addr,
        input [1023:0] filename,
        input [31:0] num_bytes
    );
        automatic bit [1:0] resp;
        begin
            dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.read_to_file(
                "NOC_API", filename, addr, num_bytes, resp
            );
            if (resp != 0)
                $display("[%t] ERROR: NoC read_to_file from 0x%h failed resp=%0d", $time, addr, resp);
            else
                $display("[%t] INFO: Read %d bytes from 0x%h to file %s", $time, num_bytes, addr, filename);
        end
    endtask

    integer file_handle;

    //==========================================================================
    // CIPS VIP Initialization
    //==========================================================================

    initial begin
        repeat(10) @(posedge sim_clk);
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.pl_gen_clock(0, 300);
        force dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.versal_cips_ps_vip_clk = sim_clk;
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.por_reset(0);
        repeat(20) @(posedge sim_clk);
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.por_reset(1);
        repeat(50) @(posedge sim_clk);
        force dut.design_1_wrapper_i.rstn_pl = 1'b1;
        $display("[%t] INFO: CIPS VIP initialized", $time);
    end

    //==========================================================================
    // Main Test Sequence
    //==========================================================================

    integer i, j, k;
    integer errors;
    reg [31:0] expected_val, actual_val;
    reg [31:0] temp_read_data;

    initial begin
        $display("================================================================================");
        $display("NoC Self-Attention End-to-End Test");
        $display("================================================================================");
        $display("[%t] INFO: Test configuration:", $time);
        $display("  Input I: %0d x %0d", TOKENS, EMBED);
        $display("  Weights W^Q/K/V: %0d x %0d", EMBED, HEAD_DIM);
        $display("  Q'/K'^T/V': %0d x %0d", TOKENS, HEAD_DIM);
        $display("  Attention scores S: %0d x %0d", TOKENS, TOKENS);
        $display("  Softmax output P: %0d x %0d", TOKENS, TOKENS);
        $display("  Context output C': %0d x %0d", TOKENS, HEAD_DIM);
        $display("================================================================================");

        // Initialize control signals
        attn_start = 0;

        // Set addresses from parameters
        addr_I_r = ADDR_I;
        addr_W_Q_r = ADDR_W_Q;
        addr_W_K_r = ADDR_W_K;
        addr_W_V_r = ADDR_W_V;
        addr_Q_prime_r = ADDR_Q_PRIME;
        addr_K_prime_T_r = ADDR_K_PRIME_T;
        addr_V_prime_r = ADDR_V_PRIME;
        addr_S_r = ADDR_S;
        addr_P_r = ADDR_P;
        addr_C_prime_r = ADDR_C_PRIME;

        // Requant parameters (same for all projections and context)
        requant_m_Q_r = REQUANT_M;
        requant_e_Q_r = REQUANT_E;
        requant_m_K_r = REQUANT_M;
        requant_e_K_r = REQUANT_E;
        requant_m_V_r = REQUANT_M;
        requant_e_V_r = REQUANT_E;
        requant_m_C_r = REQUANT_M;
        requant_e_C_r = REQUANT_E;

        // Softmax coefficients from parameters
        softmax_qb_r = SOFTMAX_QB;
        softmax_qc_r = SOFTMAX_QC;
        softmax_qln2_r = SOFTMAX_QLN2;
        softmax_qln2_inv_r = SOFTMAX_QLN2_INV;
        softmax_sreq_r = SOFTMAX_SREQ;

        // Wait for initialization
        repeat(300) @(posedge sim_clk);
        $display("[%t] INFO: CIPS VIP ready", $time);

        //======================================================================
        // Step 1: Initialize Test Matrices
        //======================================================================
        $display("[%t] INFO: Step 1 - Initializing test matrices", $time);

        // Matrix I: Simple identity-like pattern for predictable results
        for (i = 0; i < TOKENS; i = i + 1) begin
            for (j = 0; j < EMBED; j = j + 1) begin
                matrix_I[i*EMBED + j] = (i == j % TOKENS) ? 8'd1 : 8'd0;
            end
        end

        // Weight matrices: Different patterns for Q, K, V
        for (i = 0; i < EMBED; i = i + 1) begin
            for (j = 0; j < HEAD_DIM; j = j + 1) begin
                matrix_W_Q[i*HEAD_DIM + j] = 8'd2;  // All 2s for W^Q
                matrix_W_K[i*HEAD_DIM + j] = 8'd3;  // All 3s for W^K
                matrix_W_V[i*HEAD_DIM + j] = 8'd4;  // All 4s for W^V
            end
        end

        // Calculate expected Q/K/V projections for reference
        for (i = 0; i < TOKENS; i = i + 1) begin
            for (j = 0; j < HEAD_DIM; j = j + 1) begin
                // Q = I × W^Q
                expected_val = 0;
                for (k = 0; k < EMBED; k = k + 1)
                    expected_val = expected_val + matrix_I[i*EMBED + k] * matrix_W_Q[k*HEAD_DIM + j];
                matrix_Q_expected[i*HEAD_DIM + j] = expected_val;

                // K = I × W^K
                expected_val = 0;
                for (k = 0; k < EMBED; k = k + 1)
                    expected_val = expected_val + matrix_I[i*EMBED + k] * matrix_W_K[k*HEAD_DIM + j];
                matrix_K_expected[i*HEAD_DIM + j] = expected_val;

                // V = I × W^V
                expected_val = 0;
                for (k = 0; k < EMBED; k = k + 1)
                    expected_val = expected_val + matrix_I[i*EMBED + k] * matrix_W_V[k*HEAD_DIM + j];
                matrix_V_expected[i*HEAD_DIM + j] = expected_val;
            end
        end

        $display("[%t] INFO: Test matrices initialized", $time);

        // Configure NoC routing
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.set_routing_config(
            "NOC_API", "FPD_CCI_NOC", 1
        );

        //======================================================================
        // Step 2: Generate data files and write to DDR via bulk transfer
        //======================================================================
        $display("[%t] INFO: Step 2 - Generating data files for bulk DDR write", $time);

        // Generate Input I file (32-bit per line)
        file_handle = $fopen("matrix_I.txt", "w");
        for (i = 0; i < TOKENS*EMBED; i = i + 1)
            $fwrite(file_handle, "%08h\n", {24'b0, matrix_I[i]});
        $fclose(file_handle);

        // Generate W^Q file
        file_handle = $fopen("matrix_W_Q.txt", "w");
        for (i = 0; i < EMBED*HEAD_DIM; i = i + 1)
            $fwrite(file_handle, "%08h\n", {24'b0, matrix_W_Q[i]});
        $fclose(file_handle);

        // Generate W^K file
        file_handle = $fopen("matrix_W_K.txt", "w");
        for (i = 0; i < EMBED*HEAD_DIM; i = i + 1)
            $fwrite(file_handle, "%08h\n", {24'b0, matrix_W_K[i]});
        $fclose(file_handle);

        // Generate W^V file
        file_handle = $fopen("matrix_W_V.txt", "w");
        for (i = 0; i < EMBED*HEAD_DIM; i = i + 1)
            $fwrite(file_handle, "%08h\n", {24'b0, matrix_W_V[i]});
        $fclose(file_handle);

        $display("[%t] INFO: Data files generated", $time);

        //======================================================================
        // Step 3: Bulk write matrices to DDR
        //======================================================================
        $display("[%t] INFO: Step 3 - Bulk writing matrices to DDR", $time);

        $display("[%t] INFO: Writing Input I to DDR at 0x%h (%0d bytes)", $time, ADDR_I, TOKENS*EMBED*4);
        write_ddr_from_file(ADDR_I, "matrix_I.txt", TOKENS*EMBED*4);

        $display("[%t] INFO: Writing W^Q to DDR at 0x%h", $time, ADDR_W_Q);
        write_ddr_from_file(ADDR_W_Q, "matrix_W_Q.txt", EMBED*HEAD_DIM*4);

        $display("[%t] INFO: Writing W^K to DDR at 0x%h", $time, ADDR_W_K);
        write_ddr_from_file(ADDR_W_K, "matrix_W_K.txt", EMBED*HEAD_DIM*4);

        $display("[%t] INFO: Writing W^V to DDR at 0x%h", $time, ADDR_W_V);
        write_ddr_from_file(ADDR_W_V, "matrix_W_V.txt", EMBED*HEAD_DIM*4);

        $display("[%t] INFO: All input matrices written to DDR", $time);

        repeat(100) @(posedge sim_clk);

        //======================================================================
        // Step 4: Start Self-Attention
        //======================================================================
        $display("[%t] INFO: Step 4 - Starting self-attention computation", $time);
        $display("[%t] INFO: This will perform:", $time);
        $display("  1. Q/K/V projections: I × W^Q/K/V → Q'/K'^T/V'", $time);
        $display("  2. Attention scores: Q' × K'^T → S", $time);
        $display("  3. Softmax: S → P", $time);
        $display("  4. Context: P × V' → C → C'", $time);

        @(posedge sim_clk);
        attn_start = 1;
        repeat(10) @(posedge sim_clk);
        attn_start = 0;

        //======================================================================
        // Step 5: Wait for Completion
        //======================================================================
        fork
            begin
                wait(attn_done == 1);
                $display("[%t] INFO: Step 5 - Self-attention completed!", $time);
            end
            begin
                repeat(TIMEOUT_CYCLES) @(posedge sim_clk);
                if (!attn_done) begin
                    $display("[%t] ERROR: Timeout after %0d cycles!", $time, TIMEOUT_CYCLES);
                    $finish;
                end
            end
        join_any
        disable fork;

        if (attn_error) begin
            $display("[%t] ERROR: Self-attention reported error!", $time);
            $finish;
        end

        repeat(500) @(posedge sim_clk);

        //======================================================================
        // Step 6: Read Back All Results
        //======================================================================
        $display("[%t] INFO: Step 6 - Reading all results from DDR", $time);

        // Read Q' output
        read_ddr_to_file(ADDR_Q_PRIME, "result_Q_prime.txt", TOKENS * HEAD_DIM * 4);

        // Read K'^T output
        read_ddr_to_file(ADDR_K_PRIME_T, "result_K_prime_T.txt", TOKENS * HEAD_DIM * 4);

        // Read V' output
        read_ddr_to_file(ADDR_V_PRIME, "result_V_prime.txt", TOKENS * HEAD_DIM * 4);

        // Note: Attention scores S are NOT stored in DDR
        // S values (32-bit) stream directly from MM output to softmax
        // This avoids DDR round-trip for 32-bit data through 8-bit DMA
        $display("[%t] INFO: Note - Attention scores S stream directly to softmax (not in DDR)", $time);

        // Read softmax output P (8-bit values, stored as 32-bit)
        read_ddr_to_file(ADDR_P, "result_P.txt", TOKENS * TOKENS * 4);

        // Read final context output C' (8-bit values, stored as 32-bit)
        read_ddr_to_file(ADDR_C_PRIME, "result_C_prime.txt", TOKENS * HEAD_DIM * 4);

        $display("[%t] INFO: All results written to result_*.txt files", $time);

        //======================================================================
        // Step 7: Summary
        //======================================================================
        $display("================================================================================");
        $display("[%t] INFO: Self-attention computation complete!", $time);
        $display("================================================================================");
        $display("Results dumped to files:");
        $display("  Q' projection: result_Q_prime.txt (%0d x %0d)", TOKENS, HEAD_DIM);
        $display("  K'^T projection: result_K_prime_T.txt (%0d x %0d)", TOKENS, HEAD_DIM);
        $display("  V' projection: result_V_prime.txt (%0d x %0d)", TOKENS, HEAD_DIM);
        $display("  Attention scores S: (streamed directly to softmax - not in DDR)");
        $display("  Softmax output P: result_P.txt (%0d x %0d, 8-bit)", TOKENS, TOKENS);
        $display("  Context output C': result_C_prime.txt (%0d x %0d, 8-bit)", TOKENS, HEAD_DIM);
        $display("================================================================================");
        $display("Data flow completed:");
        $display("  I (%0dx%0d) × W^Q (%0dx%0d) → Q' (%0dx%0d) [DDR]", TOKENS, EMBED, EMBED, HEAD_DIM, TOKENS, HEAD_DIM);
        $display("  I (%0dx%0d) × W^K (%0dx%0d) → K'^T (%0dx%0d) [DDR]", TOKENS, EMBED, EMBED, HEAD_DIM, TOKENS, HEAD_DIM);
        $display("  I (%0dx%0d) × W^V (%0dx%0d) → V' (%0dx%0d) [DDR]", TOKENS, EMBED, EMBED, HEAD_DIM, TOKENS, HEAD_DIM);
        $display("  Q' (%0dx%0d) × K'^T^T (%0dx%0d) → S (%0dx%0d) [streaming]", TOKENS, HEAD_DIM, HEAD_DIM, TOKENS, TOKENS, TOKENS);
        $display("  Softmax(S) → P (%0dx%0d) [DDR]", TOKENS, TOKENS);
        $display("  P (%0dx%0d) × V' (%0dx%0d) → C' (%0dx%0d) [DDR]", TOKENS, TOKENS, TOKENS, HEAD_DIM, TOKENS, HEAD_DIM);
        $display("================================================================================");

        $finish;
    end

    //==========================================================================
    // Debug Monitors
    //==========================================================================

    always @(posedge attn_start or negedge attn_start)
        $display("[%t] TB: attn_start = %b", $time, attn_start);

    always @(posedge attn_done or negedge attn_done)
        $display("[%t] TB: attn_done = %b", $time, attn_done);

    always @(posedge attn_error or negedge attn_error)
        $display("[%t] TB: attn_error = %b", $time, attn_error);

    //==========================================================================
    // Timeout
    //==========================================================================

    initial begin
        #(TIMEOUT_CYCLES * 10); // 10ns per cycle at 100MHz
        $display("[%t] ERROR: Simulation timeout after %0d cycles!", $time, TIMEOUT_CYCLES);
        $finish;
    end

endmodule
