`timescale 1ns / 1ps

module tb_noc_inter_control;

    // ========================================================================
    // Signal Declarations
    // ========================================================================
    reg clk;
    reg rstn;
    reg start;

    // Outputs from DUT (to be monitored)
    wire done;
    wire error;
    wire start_dma_a;
    wire start_dma_k;
    wire start_dma_g;
    wire start_requant_mm;
    wire start_requant_gelu;
    wire start_gelu;

    // Inputs to DUT (driven by TB)
    reg dma_a_done, dma_a_error;
    reg dma_k_done, dma_k_error;
    reg dma_g_done, dma_g_error;
    reg mm_done;
    reg requant_mm_done;
    reg gelu_done;
    reg requant_gelu_done;

    // Internal TB variables
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

        // DMA Controls
        .start_dma_a(start_dma_a),
        .start_dma_k(start_dma_k),
        .start_dma_g(start_dma_g),

        // Requant Controls
        .start_requant_mm(start_requant_mm),
        .requant_mm_done(requant_mm_done),
        .start_requant_gelu(start_requant_gelu),
        .requant_gelu_done(requant_gelu_done),

        // DMA Status
        .dma_a_done(dma_a_done),
        .dma_k_done(dma_k_done),
        .dma_g_done(dma_g_done), // Assumes you fixed the typo in DUT (dma_out_done -> dma_g_done)
        .dma_a_error(dma_a_error),
        .dma_k_error(dma_k_error),
        .dma_g_error(dma_g_error),

        // Core Status
        .mm_done(mm_done),
        .start_gelu(start_gelu),
        .gelu_done(gelu_done)
    );

    // ========================================================================
    // Clock Generation (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================================================
    // Helper Tasks
    // ========================================================================
    
    // Task to clear all submodule done/error flags
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

    // Task to pulse a done signal after a delay (simulating hardware latency)
    task pulse_signal;
        output reg signal_to_pulse;
        input integer delay_cycles;
    begin
        repeat(delay_cycles) @(posedge clk);
        signal_to_pulse = 1;
        @(posedge clk);
        signal_to_pulse = 0;
    end
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        // 1. Initialization
        $display("\n=== [TB] Starting Simulation ===");
        start = 0;
        clear_inputs();
        rstn = 0; // Assert Reset
        repeat(5) @(posedge clk);
        rstn = 1; // Release Reset
        @(posedge clk);

        // ------------------------------------------------------------
        // CASE 1: Normal Operation (The Happy Path)
        // ------------------------------------------------------------
        $display("\n=== [TB] Case 1: Normal Operation ===");
        
        // Start the FSM
        start = 1;
        @(posedge clk);
        // We can lower start, or keep it high. 
        // If we keep it high, it will restart immediately after done.
        // Let's keep it high to test loopback, or toggle it. 
        // Let's toggle it off to stop at IDLE later.
        start = 0; 

        // -- Wait for LOAD_A start --
        wait(start_dma_a); 
        $display("[TB] Saw Start DMA A");
        pulse_signal(dma_a_done, 4); // Simulate 4 cycle read latency
        $display("Pulsed signal dma_a_done");

        // -- Wait for LOAD_K start --
        wait(start_dma_k);
        $display("[TB] Saw Start DMA K");
        pulse_signal(dma_k_done, 4); // Simulate 4 cycle read latency

        // -- Wait for MM start --
        // Note: The DUT pulses start_dma_g AS SOON AS it enters MM state
        // We need to verify this happens now.
        wait(start_dma_g); 
        $display("[TB] Saw Start DMA G (Pipeline Started)");
        
        // Simulate MM Processing time
        pulse_signal(mm_done, 10); 
        $display("[TB] MM Processing Finished");

        // -- Wait for Requant MM --
        wait(start_requant_mm);
        pulse_signal(requant_mm_done, 2);
        
        // -- Wait for GELU --
        wait(start_gelu);
        pulse_signal(gelu_done, 5);

        // -- Wait for Requant GELU --
        wait(start_requant_gelu);
        pulse_signal(requant_gelu_done, 2);

        // -- FSM is now in WRITE_G state --
        // It is waiting for the Write DMA (started way back in MM state) to finish
        $display("[TB] FSM Waiting for Write DMA completion...");
        pulse_signal(dma_g_done, 2);

        // -- Check Done --
        wait(done);
        $display("[TB] SUCCESS: Operation Done detected");
        @(posedge clk);

        if (error) begin
            $display("[TB] FAILURE: Error flag asserted unexpectedly.");
            error_count = error_count + 1;
        end

        // ------------------------------------------------------------
        // CASE 2: Error Handling (DMA A Failure)
        // ------------------------------------------------------------
        $display("\n=== [TB] Case 2: DMA Error Handling ===");
        
        // Ensure we are back in IDLE
        wait(DUT.state == 0); // IDLE
        clear_inputs();
        
        start = 1;
        @(posedge clk);
        start = 0;

        wait(start_dma_a);
        $display("[TB] Saw Start DMA A");
        
        // Inject Error instead of Done
        repeat(2) @(posedge clk);
        dma_a_error = 1;
        @(posedge clk);
        dma_a_error = 0;

        // Check if FSM went to ERROR state (9)
        wait(error);
        $display("[TB] SUCCESS: Error state detected correctly");
        
        if (DUT.state !== 9) begin
            $display("[TB] FAILURE: State is %d, expected 9 (ERROR)", DUT.state);
            error_count = error_count + 1;
        end

        // Reset FSM from Error state
        // Logic says: if (!start) state <= IDLE.
        // Start is already 0, so it should go to IDLE next clock.
        @(posedge clk);
        if (DUT.state == 0) 
            $display("[TB] Recovered to IDLE");
        else 
            $display("[TB] Failed to recover to IDLE");

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
