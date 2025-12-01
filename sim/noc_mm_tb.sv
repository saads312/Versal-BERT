`timescale 1ns / 1ps
//
// NoC Matrix Multiply End-to-End Testbench
// Tests full matrix multiply operation with DDR memory via NoC
// Uses CIPS VIP API for memory access
//

module noc_mm_tb;

    //==========================================================================
    // Test Configuration
    //==========================================================================

    // Matrix dimensions for test (must be divisible by N1=2, N2=2)
    localparam M1 = 4;  // Rows of A
    localparam M2 = 4;  // Cols of A / Rows of B
    localparam M3 = 4;  // Cols of B

    // Systolic array parameters (must match RTL)
    localparam N1 = 2;  // Number of PE rows
    localparam N2 = 2;  // Number of PE columns

    // DDR addresses - MUST be in actual DDR region (starts ~6GB in Versal address map)
    // Reference: Xilinx Versal NoC/DDRMC Tutorial uses 0x0600_0000_0100 for DDR
    // The lower 2GB (0x0-0x8000_0000) is PS/PMC registers, NOT DDR!
    localparam ADDR_MATRIX_A = 64'h0000_0600_0000; // Base address in DDR region
    localparam ADDR_MATRIX_B = 64'h0000_0600_1000; // +4KB offset
    localparam ADDR_MATRIX_D = 64'h0000_0600_2000; // +8KB offset

    //==========================================================================
    // Clock Generation
    //==========================================================================

    // Base clock for simulation control (100 MHz)
    reg sim_clk;
    initial begin
        sim_clk = 0;
        forever #5 sim_clk = ~sim_clk; // 100 MHz = 10ns period
    end

    // DDR4 system clock (200 MHz differential)
    reg sys_clk_p;
    wire sys_clk_n;
    assign sys_clk_n = !sys_clk_p;

    initial begin
        sys_clk_p = 0;
        forever #2.5 sys_clk_p = !sys_clk_p; // 200 MHz = 5ns period
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

    // Matrix multiply control
    reg         mm_start;
    wire        mm_done;
    wire        mm_error;
    reg  [23:0] mm_M1;
    reg  [23:0] mm_M2;
    reg  [23:0] mm_M3;
    reg  [63:0] mm_addr_a;
    reg  [63:0] mm_addr_b;
    reg  [63:0] mm_addr_d;

    //==========================================================================
    // DUT Instantiation
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
        .mm_start(mm_start),
        .mm_done(mm_done),
        .mm_error(mm_error),
        .mm_M1(mm_M1),
        .mm_M2(mm_M2),
        .mm_M3(mm_M3),
        .mm_addr_matrix_a(mm_addr_a),
        .mm_addr_matrix_b(mm_addr_b),
        .mm_addr_matrix_d(mm_addr_d)
    );

    //==========================================================================
    // Test Data: Define Matrices
    //==========================================================================

    // Matrix A (M1 x M2) = (4 x 4)
    // Simple identity-like pattern for easy verification
    reg [7:0] matrix_a [0:M1*M2-1];

    // Matrix B (M2 x M3) = (4 x 4)
    reg [7:0] matrix_b [0:M2*M3-1];

    // Expected result D = A * B (M1 x M3) = (4 x 4)
    // Results are 32-bit accumulators
    reg [31:0] matrix_d_expected [0:M1*M3-1];

    // Read back result
    reg [31:0] matrix_d_result [0:M1*M3-1];

    //==========================================================================
    // DDR Memory Access via CIPS VIP NOC_API
    //==========================================================================
    // Use CIPS VIP's NOC_API master to write/read DDR through the NoC
    // This properly tests the full NoC path and initializes the DDR model

    task write_ddr_via_noc(
        input [63:0] addr,
        input [31:0] data_word
    );
        automatic bit [1:0] resp;
        begin
            // Use CIPS VIP's write_data_32 task to write through NoC to DDR
            dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.write_data_32(
                "NOC_API",  // master_name
                addr,       // start_addr
                data_word,  // w_data
                resp        // response
            );
            if (resp != 0) begin
                $display("[%t] ERROR: NoC write to addr=0x%h failed with resp=%0d", $time, addr, resp);
            end
        end
    endtask

    // Task to read data from DDR via CIPS VIP NOC_API (goes through the NoC!)
    task read_ddr_via_noc(
        input  [63:0] addr,
        output [31:0] data_word
    );
        automatic bit [1:0] resp;
        begin
            // Use CIPS VIP's read_data_32 task to read from DDR through NoC
            dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.read_data_32(
                "NOC_API",  // master_name
                addr,       // start_addr
                data_word,  // rd_data_32
                resp        // response
            );
            if (resp != 0) begin
                $display("[%t] ERROR: NoC read from addr=0x%h failed with resp=%0d", $time, addr, resp);
            end
        end
    endtask

    //==========================================================================
    // CIPS VIP and DDR Initialization
    //==========================================================================

    initial begin
        // Wait for design to settle
        repeat(10) @(posedge sim_clk);

        // Configure CIPS VIP: Set PL clock to 300 MHz
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.pl_gen_clock(0, 300);

        // Force CIPS VIP clock to our simulation clock
        force dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.versal_cips_ps_vip_clk = sim_clk;

        // Apply reset to PS VIP
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.por_reset(0);
        repeat(20) @(posedge sim_clk);

        // Release POR reset
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.por_reset(1);

        // Wait for CIPS to initialize, then force PL reset to be released
        // (CIPS VIP may not automatically release PL reset in simulation)
        repeat(50) @(posedge sim_clk);
        force dut.design_1_wrapper_i.rstn_pl = 1'b1;

        $display("[%t] INFO: CIPS VIP initialized and PL reset released", $time);
    end

    //==========================================================================
    // Main Test Sequence
    //==========================================================================

    integer i, j, k;
    integer errors;
    reg [31:0] expected_val, actual_val;

    initial begin
        $display("================================================================================");
        $display("NoC Matrix Multiply End-to-End Test");
        $display("================================================================================");
        $display("[%t] INFO: Test configuration:", $time);
        $display("  Matrix A: %0d x %0d", M1, M2);
        $display("  Matrix B: %0d x %0d", M2, M3);
        $display("  Matrix D: %0d x %0d", M1, M3);
        $display("================================================================================");

        // Initialize control signals
        mm_start = 0;
        mm_M1 = M1;
        mm_M2 = M2;
        mm_M3 = M3;
        mm_addr_a = ADDR_MATRIX_A;
        mm_addr_b = ADDR_MATRIX_B;
        mm_addr_d = ADDR_MATRIX_D;

        // Wait for CIPS VIP initialization
        repeat(300) @(posedge sim_clk);
        $display("[%t] INFO: CIPS VIP ready", $time);

        //======================================================================
        // Step 1: Initialize Test Matrices
        //======================================================================
        $display("[%t] INFO: Step 1 - Initializing test matrices", $time);

        // Matrix A: Simple values for easy calculation
        // A = [[1, 0, 0, 0],
        //      [0, 1, 0, 0],
        //      [0, 0, 1, 0],
        //      [0, 0, 0, 1]]
        for (i = 0; i < M1*M2; i = i + 1) begin
            if (i % (M2 + 1) == 0)
                matrix_a[i] = 1;  // Diagonal elements
            else
                matrix_a[i] = 0;
        end

        // Matrix B: Simple pattern
        // B = [[2, 0, 0, 0],
        //      [0, 3, 0, 0],
        //      [0, 0, 4, 0],
        //      [0, 0, 0, 5]]
        for (i = 0; i < M2*M3; i = i + 1) begin
            if (i % (M3 + 1) == 0)
                matrix_b[i] = 2 + (i / (M3 + 1));
            else
                matrix_b[i] = 0;
        end

        // Calculate expected result: D = A * B
        for (i = 0; i < M1; i = i + 1) begin
            for (j = 0; j < M3; j = j + 1) begin
                expected_val = 0;
                for (k = 0; k < M2; k = k + 1) begin
                    expected_val = expected_val + (matrix_a[i*M2 + k] * matrix_b[k*M3 + j]);
                end
                matrix_d_expected[i*M3 + j] = expected_val;
            end
        end

        // Display initialized matrices
        $display("[%t] TB: Matrix A initialized:", $time);
        for (i = 0; i < M1; i = i + 1) begin
            $write("  Row %0d: ", i);
            for (j = 0; j < M2; j = j + 1) begin
                $write("%3d ", matrix_a[i*M2 + j]);
            end
            $write("\n");
        end

        $display("[%t] TB: Matrix B initialized:", $time);
        for (i = 0; i < M2; i = i + 1) begin
            $write("  Row %0d: ", i);
            for (j = 0; j < M3; j = j + 1) begin
                $write("%3d ", matrix_b[i*M3 + j]);
            end
            $write("\n");
        end

        $display("[%t] INFO: Test matrices initialized", $time);

        // Configure NoC routing: NOC_API (slave) -> FPD_CCI_NOC (master)
        // The wrapper API takes (slave_port_name, master_port_name, routing_en)
        $display("[%t] INFO: Configuring NoC routing: NOC_API -> FPD_CCI_NOC", $time);
        dut.design_1_wrapper_i.design_1_i.versal_cips_0.inst.pspmc_0.inst.PS9_VIP_inst.inst.set_routing_config(
            "NOC_API",      // slave_port_name (source)
            "FPD_CCI_NOC",  // master_port_name (destination)
            1               // routing_en (enable)
        );

        //======================================================================
        // Step 2: Write Matrix A to DDR via CIPS VIP NOC_API
        //======================================================================
        $display("[%t] INFO: Step 2 - Writing Matrix A to DDR via NoC at 0x%h", $time, ADDR_MATRIX_A);

        // Write each 32-bit element of matrix A to DDR through the NoC (4-byte aligned)
        for (i = 0; i < M1*M2; i = i + 1) begin
            write_ddr_via_noc(ADDR_MATRIX_A + (i * 4), matrix_a[i]);
        end
        $display("[%t] INFO: Matrix A written via NoC (%0d elements, %0d bytes)", $time, M1*M2, M1*M2*4);

        //======================================================================
        // Step 3: Write Matrix B to DDR via CIPS VIP NOC_API
        //======================================================================
        $display("[%t] INFO: Step 3 - Writing Matrix B to DDR via NoC at 0x%h", $time, ADDR_MATRIX_B);

        // Write each 32-bit element of matrix B to DDR through the NoC (4-byte aligned)
        for (i = 0; i < M2*M3; i = i + 1) begin
            write_ddr_via_noc(ADDR_MATRIX_B + (i * 4), matrix_b[i]);
        end
        $display("[%t] INFO: Matrix B written via NoC (%0d elements, %0d bytes)", $time, M2*M3, M2*M3*4);

        // Wait for memory writes to complete
        repeat(100) @(posedge sim_clk);

        //======================================================================
        // Step 4: Start Matrix Multiply Operation
        //======================================================================
        $display("[%t] INFO: Step 4 - Starting matrix multiply operation", $time);

        // Hold mm_start high for 100ns to ensure it's sampled by FSM clock domain
        // (FSM runs on CIPS PL clock which may be different frequency/phase than sim_clk)
        @(posedge sim_clk);
        mm_start = 1;
        repeat(10) @(posedge sim_clk);  // Hold for 100ns
        mm_start = 0;

        $display("[%t] INFO: Matrix multiply started, waiting for completion...", $time);

        //======================================================================
        // Step 5: Wait for Completion
        //======================================================================
        fork
            begin
                // Wait for done signal
                wait(mm_done == 1);
                $display("[%t] INFO: Step 5 - Matrix multiply completed!", $time);
            end
            begin
                // Timeout after 50000 cycles
                repeat(50000) @(posedge sim_clk);
                if (mm_done == 0) begin
                    $display("[%t] ERROR: Matrix multiply timeout!", $time);
                    $finish;
                end
            end
        join_any
        disable fork;

        if (mm_error) begin
            $display("[%t] ERROR: Matrix multiply reported error!", $time);
            $finish;
        end

        // Wait for write-back to DDR to complete
        repeat(500) @(posedge sim_clk);

        //======================================================================
        // Step 6: Read Back Result Matrix D from DDR via CIPS VIP NOC_API
        //======================================================================
        $display("[%t] INFO: Step 6 - Reading result matrix from DDR at 0x%h via NoC", $time, ADDR_MATRIX_D);

        // Read result matrix from DDR through the NoC
        for (i = 0; i < M1*M3; i = i + 1) begin
            // Read each 32-bit element from DDR (4-byte aligned addresses)
            read_ddr_via_noc(ADDR_MATRIX_D + (i * 4), matrix_d_result[i]);
        end
        $display("[%t] INFO: Result matrix read back via NoC (%0d elements)", $time, M1*M3);

        //======================================================================
        // Step 7: Verify Results
        //======================================================================
        $display("[%t] INFO: Step 7 - Verifying results", $time);
        $display("================================================================================");

        errors = 0;
        for (i = 0; i < M1; i = i + 1) begin
            for (j = 0; j < M3; j = j + 1) begin
                expected_val = matrix_d_expected[i*M3 + j];
                actual_val = matrix_d_result[i*M3 + j];

                if (actual_val !== expected_val) begin
                    $display("  [%0d,%0d] MISMATCH: Expected=0x%h, Got=0x%h",
                             i, j, expected_val, actual_val);
                    errors = errors + 1;
                end else begin
                    $display("  [%0d,%0d] PASS: Value=0x%h", i, j, actual_val);
                end
            end
        end

        $display("================================================================================");
        if (errors == 0) begin
            $display("[%t] SUCCESS: All %0d matrix elements verified correctly!", $time, M1*M3);
            $display("================================================================================");
            $display("PASS: NoC Matrix Multiply End-to-End Test");
            $display("================================================================================");
        end else begin
            $display("[%t] FAILURE: %0d mismatches found!", $time, errors);
            $display("================================================================================");
            $display("FAIL: NoC Matrix Multiply End-to-End Test");
            $display("================================================================================");
        end

        $finish;
    end

    //==========================================================================
    // Debug: Monitor top-level control signals
    //==========================================================================

    // Monitor mm_start and mm_done
    always @(posedge mm_start or negedge mm_start) begin
        $display("[%t] TB: mm_start = %b", $time, mm_start);
    end

    always @(posedge mm_done or negedge mm_done) begin
        $display("[%t] TB: mm_done = %b", $time, mm_done);
    end

    always @(posedge mm_error or negedge mm_error) begin
        $display("[%t] TB: mm_error = %b", $time, mm_error);
    end

    // Monitor AXI-Stream signals to MM core in detail
    reg axis_a_activity_logged = 0;
    reg axis_b_activity_logged = 0;

    always @(posedge sim_clk) begin
        // Log first valid for each stream
        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tvalid && !axis_a_activity_logged) begin
            $display("[%t] TB: axis_a stream started (tvalid=1, tready=%b)", $time,
                     dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tready);
            axis_a_activity_logged = 1;
        end

        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tvalid && !axis_b_activity_logged) begin
            $display("[%t] TB: axis_b stream started (tvalid=1, tready=%b)", $time,
                     dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tready);
            axis_b_activity_logged = 1;
        end

        // Log tlast events
        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tvalid && dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tready && dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tlast) begin
            $display("[%t] TB: axis_a_tlast asserted (DMA A transfer complete)", $time);
        end
        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tvalid && dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tready && dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tlast) begin
            $display("[%t] TB: axis_b_tlast asserted (DMA B transfer complete)", $time);
        end

        // If we see tlast without handshake, report it
        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tlast && dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tvalid && !dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tready) begin
            $display("[%t] TB: WARNING: axis_a tlast=1 but tready=0 (handshake blocked)", $time);
        end
        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tlast && dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tvalid && !dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tready) begin
            $display("[%t] TB: WARNING: axis_b tlast=1 but tready=0 (handshake blocked)", $time);
        end
    end

    // Monitor tlast signals directly (any edge)
    always @(posedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tlast or negedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tlast) begin
        $display("[%t] TB: axis_a_tlast changed to %b (tvalid=%b, tready=%b)", $time,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tlast,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tvalid,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_a_tready);
    end

    always @(posedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tlast or negedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tlast) begin
        $display("[%t] TB: axis_b_tlast changed to %b (tvalid=%b, tready=%b)", $time,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tlast,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tvalid,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_b_tready);
    end

    // Monitor MM core internal start_multiply signal
    always @(posedge dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.start_multiply or negedge dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.start_multiply) begin
        $display("[%t] TB: MM core start_multiply = %b", $time, dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.start_multiply);
    end

    // Monitor MM core output valid
    always @(posedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tvalid or negedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tvalid) begin
        $display("[%t] TB: MM core axis_d_tvalid = %b", $time, dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tvalid);
    end

    // Monitor axis_d tlast signal
    always @(posedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tlast or negedge dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tlast) begin
        $display("[%t] TB: axis_d_tlast = %b (tvalid=%b, tready=%b)", $time,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tlast,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tvalid,
                 dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tready);
    end

    // Monitor write DMA done
    always @(posedge dut.design_1_wrapper_i.noc_mm_top_inst.dma_d_done or negedge dut.design_1_wrapper_i.noc_mm_top_inst.dma_d_done) begin
        $display("[%t] TB: Write DMA done = %b", $time, dut.design_1_wrapper_i.noc_mm_top_inst.dma_d_done);
    end

    // Monitor MM2S module internal signals to debug early termination
    initial begin
        // Wait for reset to complete
        wait(dut.design_1_wrapper_i.rstn_pl == 1'b1);
        repeat(10) @(posedge sim_clk);

        $display("================================================================================");
        $display("[%t] MM2S DEBUG: Parameter Values", $time);
        $display("  M1xM3dN1 = %d (beats per bank)", dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.M1xM3dN1);
        $display("  M3 = %d", dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.M3);
        $display("  M1dN1 = %d (number of phases)", dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.M1dN1);
        $display("  N1 = %d (number of banks)", dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.N1);
        $display("  N2 = %d (systolic cols)", dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.N2);
        $display("  TLAST address check = (M1xM3dN1 * N1) = (%d * %d) = %d",
                 dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.M1xM3dN1,
                 dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.N1,
                 (dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.M1xM3dN1 *
                  dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.N1));
        $display("  Expected last bank = 1 << (N1-1) = %d",
                 1 << (dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.N1 - 1));
        $display("  done_read triggers after TLAST is output and acknowledged");
        $display("  Expected output beats = M1xM3dN1 * N1 = %d * %d = %d",
                 dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.M1xM3dN1,
                 dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.N1,
                 dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.M1xM3dN1 *
                 dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.N1);
        $display("================================================================================");
    end

    // Monitor rd_addr_D to see read progression
    always @(posedge dut.design_1_wrapper_i.clk_pl) begin
        if (dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.rd_addr_D_valid) begin
            $display("[%t] MM2S TB: rd_addr_D = %d, activate_D = 0x%h, start_read=%b, out_tready=%b, valid_D=%b, addr_count=%d",
                     $time,
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.rd_addr_D,
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.activate_D,
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.start_read,
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.out_tready,
                     (dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.out_tready &
                      dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.start_read),
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.addr_count);
        end
    end

    // Monitor last_read_addr and done_read signals
    always @(posedge dut.design_1_wrapper_i.clk_pl) begin
        if (dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.last_read_addr) begin
            $display("[%t] MM2S: last_read_addr detected (last address issued)! rd_addr_D=%d, activate_D=0x%h",
                     $time,
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.rd_addr_D,
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.activate_D);
        end
        if (dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.done_read) begin
            $display("[%t] MM2S: done_read asserted (after TLAST output)!",
                     $time);
        end
    end

    // Count actual output beats on axis_d
    integer axis_d_beat_count = 0;
    always @(posedge sim_clk) begin
        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tvalid && dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tready) begin
            axis_d_beat_count = axis_d_beat_count + 1;
            $display("[%t] MM2S: Output beat #%d (tdata=0x%h, tlast=%b)",
                     $time,
                     axis_d_beat_count,
                     dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tdata,
                     dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tlast);
        end

        if (dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tlast &&
            dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tvalid &&
            dut.design_1_wrapper_i.noc_mm_top_inst.axis_d_tready) begin
            $display("[%t] MM2S: Total beats output = %d (expected 16 for 4x4 matrix)", $time, axis_d_beat_count);
            axis_d_beat_count = 0;
        end
    end

    //==========================================================================
    // Final Summary Report
    //==========================================================================

    always @(posedge sim_clk) begin
        if (dut.design_1_wrapper_i.noc_mm_top_inst.done) begin
            #100; // Wait a bit to ensure all counters updated
            $display("================================================================================");
            $display("SIMULATION COMPLETED - FINAL SUMMARY");
            $display("================================================================================");
            $display("Matrix dimensions: M1=%d M2=%d M3=%d N1=%d N2=%d",
                     M1, M2, M3, N1, N2);
            $display("Expected output beats: M1 * M3 = %d * %d = %d",
                     M1, M3, M1 * M3);
            $display("Actual output beats: %d", axis_d_beat_count);
            $display("");
            $display("MEM_READ_D Statistics:");
            $display("  Valid addresses generated: %d",
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.mem_read_D_inst.addr_gen_count);
            $display("");
            $display("MM2S Statistics:");
            $display("  Valid address count: %d",
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.valid_addr_count);
            $display("  Output beat count: %d",
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.output_beat_count);
            $display("  Final addr_count: %d",
                     dut.design_1_wrapper_i.noc_mm_top_inst.mm_core.mm2s_inst.addr_count);
            $display("");
            if (axis_d_beat_count == M1 * M3) begin
                $display("STATUS: SUCCESS - Correct number of beats output!");
            end else begin
                $display("STATUS: FAILURE - Expected %d beats, got %d (missing %d beats)",
                         M1 * M3, axis_d_beat_count, M1 * M3 - axis_d_beat_count);
            end
            $display("================================================================================");
        end
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================

    initial begin
        #5000000; // 5ms timeout
        $display("================================================================================");
        $display("[%t] ERROR: Simulation timeout!", $time);
        $display("================================================================================");
        $finish;
    end

endmodule
