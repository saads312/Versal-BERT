`timescale 1ns / 1ps

module noc_inter_control (
    input wire clk,
    input wire rstn,

    // External control
    input wire start,
    output reg done,
    output reg error,

    // DMA control outputs
    output reg start_dma_a,         // Read input A~
    output reg start_dma_k,         // Read weight K'^T
    output reg start_dma_g,         // Write output G

    // Requant control
    output reg start_requant_mm,
    input wire requant_mm_done,
    output reg start_requant_gelu,
    input wire requant_gelu_done,

    // DMA status inputs
    input wire dma_a_done,
    input wire dma_k_done,
    input wire dma_g_done,
    input wire dma_a_error,
    input wire dma_k_error,
    input wire dma_g_error,

    // MM core status
    input wire mm_done,

    // GELU core control
    output reg start_gelu,
    input wire gelu_done
);

// State encoding
localparam IDLE             = 4'd0;
// Processing states
localparam LOAD_A           = 4'd1;
localparam LOAD_K           = 4'd2;
localparam MM               = 4'd3;
localparam REQUANT_MM       = 4'd4;
localparam GELU             = 4'd5;
localparam REQUANT_GELU     = 4'd6;
localparam WRITE_G          = 4'd7;
// Terminal states
localparam DONE_STATE       = 4'd8;
localparam ERROR_STATE      = 4'd9;

reg [3:0] state, prev_state;

// State register
reg reset_logged;
always @(posedge clk) begin
    if (!rstn) begin
        state <= IDLE;
        prev_state <= IDLE;
        if (!reset_logged) begin
            $display("[%t] INTER FSM RESET", $time);
            reset_logged <= 1'b1;
        end
    end else begin
        reset_logged <= 1'b0;
        prev_state <= state;
        case (state)
            IDLE: begin
                if (start) begin
                    state <= LOAD_A;
                    $display("[%t] INTER FSM: IDLE->LOAD_A", $time);
                end
            end

            //=================================================================
            // PROCESSING STATES
            //=================================================================
            LOAD_A: begin
                if (dma_a_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] INTER FSM: LOAD_A->ERROR", $time);
                end else if (dma_a_done) begin
                    state <= LOAD_K;
                    $display("[%t] INTER FSM: LOAD_A->LOAD_K", $time);
                end
            end

            LOAD_K: begin
                if (dma_k_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] INTER FSM: LOAD_K->ERROR", $time);
                end else if (dma_k_done) begin
                    state <= MM;
                    $display("[%t] INTER FSM: LOAD_K->MM", $time);
                end
            end

            MM: begin
                if (mm_done) begin
                    state <= REQUANT_MM;
                    $display("[%t] INTER FSM: MM->REQUANT_MM", $time);
                end
            end

            REQUANT_MM: begin
                if (requant_mm_done) begin
                    state <= GELU;
                    $display("[%t] INTER FSM: REQUANT_MM->GELU", $time);
                end
            end

            GELU: begin
                if (gelu_done) begin
                    state <= REQUANT_GELU;
                    $display("[%t] INTER FSM: GELU->REQUANT_GELU", $time);
                end
            end

            REQUANT_GELU: begin
                if (requant_gelu_done) begin
                    state <= WRITE_G;
                    $display("[%t] INTER FSM: REQUANT_GELU->WRITE_G", $time);
                end
            end

            WRITE_G: begin
                if (dma_g_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] INTER FSM: WRITE_G->ERROR", $time);
                end else if (dma_g_done) begin
                    state <= DONE_STATE;
                    $display("[%t] INTER FSM: WRITE_G->DONE", $time);
                end
            end

            //=================================================================
            // TERMINAL STATES
            //=================================================================
            DONE_STATE: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] INTER FSM: DONE->IDLE", $time);
                end
            end

            ERROR_STATE: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] INTER FSM: ERROR->IDLE", $time);
                end
            end

            default: begin
                state <= IDLE;
                $display("[%t] INTER FSM: UNKNOWN->IDLE", $time);
            end
        endcase
    end
end

// Output logic - pulse DMA/requant starts on state transitions
always @(posedge clk) begin
    if (!rstn) begin
        start_dma_a <= 1'b0;
        start_dma_k <= 1'b0;
        start_dma_g <= 1'b0;
        start_requant_mm <= 1'b0;
        start_requant_gelu <= 1'b0;
        start_gelu <= 1'b0;
        done <= 1'b0;
        error <= 1'b0;
    end else begin
        // Default - pulses are one clock cycle
        start_dma_a <= 1'b0;
        start_dma_k <= 1'b0;
        start_dma_g <= 1'b0;
        start_requant_mm <= 1'b0;
        start_requant_gelu <= 1'b0;
        start_gelu <= 1'b0;

        // Pulse start signals on state entry
        // Load A
        if (state == LOAD_A && prev_state != LOAD_A) begin
            start_dma_a <= 1'b1;
            $display("[%t] INTER FSM: Pulsing start_dma_a", $time);
        end

        // Load W
        if (state == LOAD_K && prev_state != LOAD_K) begin
            start_dma_k <= 1'b1;
            $display("[%t] INTER FSM: Pulsing start_dma_k", $time);
        end

        // Start write DMA when entering MM state (before MM output starts)
        // The MM->requant->GELU->requant->writeDMA is a streaming pipeline, so write DMA must be ready first
        if (state == MM && prev_state != MM) begin
            start_dma_g <= 1'b1;
            $display("[%t] INTER FSM: Pulsing start_dma_g at MM entry", $time);
        end

        // Requant MM
        if (state == REQUANT_MM && prev_state != REQUANT_MM) begin
            start_requant_mm <= 1'b1;
            $display("[%t] INTER FSM: Pulsing start_requant_mm", $time);
        end

        // GELU
        if (state == GELU && prev_state != GELU) begin
            start_gelu <= 1'b1;
            $display("[%t] INTER FSM: Pulsing start_gelu", $time);
        end

        // Requant GELU
        if (state == REQUANT_GELU && prev_state != REQUANT_GELU) begin
            start_requant_gelu <= 1'b1;
            $display("[%t] INTER FSM: Pulsing start_requant_gelu", $time);
        end

        // Status outputs
        done <= (state == DONE_STATE);
        error <= (state == ERROR_STATE);
    end
end

// Debug: Monitor state for waveform analysis
`ifdef SIMULATION
always @(posedge clk) begin
    if (state != prev_state) begin
        $display("[%t] INTER FSM: State %d -> %d", $time, prev_state, state);
    end
end
`endif

endmodule
