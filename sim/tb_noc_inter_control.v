`timescale 1ns / 1ps

// Define a macro to handle the pulsing. 
// "sig" is the signal to drive, "dly" is the cycles to wait before driving.
`define PULSE(sig, dly) \
    repeat(dly) @(posedge clk); \
    sig = 1; \
    @(posedge clk); \
    sig = 0;

module tb_noc_inter_control;

    // ========================================================================
    // Signal Declarations
    // ========================================================================
    reg clk;
    reg rstn;
    reg start;

    // Outputs from DUT
    wire done;
    wire error;
    wire start_dma_a;
    wire start_dma_k;
    wire start_dma_g;
    wire start_requant_mm;
    wire start_requant_gelu;
    wire start_gelu;

    // Inputs to DUT
    reg dma_a_done, dma_a_error;
    reg dma_k_done, dma_k_error;
    reg dma_g_done, dma_g_error;
    reg mm_done;
    reg requant_mm_done;
    reg gelu_done;
    reg requant_gelu_done;

    integer error_count = 0;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    noc_inter_control DUT (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .done(done),
        .error(error),
        .start_dma_a(start_dma_a),
        .start_dma_k(start_dma_k),
        .start_dma_g(start_dma_g),
        .start_requant_mm(start_requant_mm),
        .requant_mm_done(requant_mm_done),
        .start_requant_gelu(start_requant_gelu),
        .requant_gelu_done(requant_gelu_done),
        .dma_a_done(dma_a_done),
        .dma_k_done(dma_k_done),
        .dma_g_done(dma_g_done), 
        .dma_a_error(dma_a_error),
        .dma_k_error(dma_k_error),
        .dma_g_error(dma_g_error),
        .mm_done(mm_done),
        .start_gelu(start_gelu),
        .gelu_done(gelu_done)
    );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================================================
    // Helper Tasks
    // ========================================================================
    task clear_inputs;
    begin
        dma_a_done = 0; dma_a_error = 0;
        dma_k_done = 0; dma_k_error = 0;
        dma_g_done = 0; dma_g_error = 0;
        mm_done = 0;
        requant_mm_done = 0;
        gelu_done = 0;
        requant_gelu_done = 0;
    end
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        $display("\n=== [TB] Starting Simulation ===");
        start = 0;
        clear_inputs();
        rstn = 0;
        repeat(5) @(posedge clk);
        rstn = 1;
        @(posedge clk);

        // ------------------------------------------------------------
        // CASE 1: Normal Operation
        // ------------------------------------------------------------
        $display("\n=== [TB] Case 1: Normal Operation ===");
        
        start = 1;
        @(posedge clk);
        start = 0; 

        // Wait for LOAD_A start
        wait(start_dma_a); 
        $display("[TB] Saw Start DMA A");
        `PULSE(dma_a_done, 4) // Replaced task call with Macro

        // Wait for LOAD_K start
        wait(start_dma_k);
        $display("[TB] Saw Start DMA K");
        `PULSE(dma_k_done, 4)

        // Wait for MM start
        // Note: start_dma_g pulses AT THE SAME TIME as state entry.
        // If we wait too long, we might miss it. 
        // We use 'wait' here because the previous PULSE command finishes 
        // exactly when the FSM transitions.
        wait(start_dma_g); 
        $display("[TB] Saw Start DMA G (Pipeline Started)");
        
        // MM Done
        `PULSE(mm_done, 10)
        $display("[TB] MM Processing Finished");

        // Requant MM
        wait(start_requant_mm);
        `PULSE(requant_mm_done, 2)
        
        // GELU
        wait(start_gelu);
        `PULSE(gelu_done, 5)

        // Requant GELU
        wait(start_requant_gelu);
        `PULSE(requant_gelu_done, 2)

        // Write DMA
        $display("[TB] FSM Waiting for Write DMA completion...");
        // Wait a moment to ensure we are in the WRITE state
        repeat(2) @(posedge clk);
        `PULSE(dma_g_done, 2)

        // Check Done
        wait(done);
        $display("[TB] SUCCESS: Operation Done detected");
        @(posedge clk);

        if (error) begin
            $display("[TB] FAILURE: Error flag asserted unexpectedly.");
            error_count = error_count + 1;
        end

        // ------------------------------------------------------------
        // CASE 2: Error Handling
        // ------------------------------------------------------------
        $display("\n=== [TB] Case 2: DMA Error Handling ===");
        
        wait(DUT.state == 0); // Ensure IDLE
        clear_inputs();
        
        start = 1;
        @(posedge clk);
        start = 0;

        wait(start_dma_a);
        
        // Inject Error
        repeat(2) @(posedge clk);
        dma_a_error = 1;
        @(posedge clk);
        dma_a_error = 0;

        wait(error);
        $display("[TB] SUCCESS: Error state detected correctly");
        
        // ------------------------------------------------------------
        // End Simulation
        // ------------------------------------------------------------
        repeat(10) @(posedge clk);
        if (error_count == 0)
            $display("\n=== [TB] SIMULATION PASSED ===");
        else
            $display("\n=== [TB] SIMULATION FAILED with %d errors ===", error_count);
        
        $finish;
    end

endmodule