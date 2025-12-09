`timescale 1ns / 1ps

module noc_attn_proj_control (
    input wire clk,
    input wire rstn,

    // External control
    input wire start,
    output reg done,
    output reg error,

    // Current projection indicator (for address selection)
    output reg [1:0] current_proj,  // 0=Q, 1=K, 2=V

    // DMA control outputs
    output reg start_dma_i,         // Read input I
    output reg start_dma_w,         // Read weight W^Q/K/V
    output reg start_dma_out,       // Write output Q'/K'^T/V'

    // Requant control
    output reg start_requant,
    input wire requant_done,

    // DMA status inputs
    input wire dma_i_done,
    input wire dma_w_done,
    input wire dma_out_done,
    input wire dma_i_error,
    input wire dma_w_error,
    input wire dma_out_error,

    // MM core status
    input wire mm_done
);

// State encoding
localparam IDLE           = 5'd0;
// Q projection states
localparam LOAD_I_Q       = 5'd1;
localparam LOAD_W_Q       = 5'd2;
localparam COMPUTE_Q      = 5'd3;
localparam REQUANT_Q      = 5'd4;
localparam WRITE_Q_PRIME  = 5'd5;
// K projection states
localparam LOAD_I_K       = 5'd6;
localparam LOAD_W_K       = 5'd7;
localparam COMPUTE_K      = 5'd8;
localparam REQUANT_K      = 5'd9;
localparam WRITE_K_PRIME  = 5'd10;
// V projection states
localparam LOAD_I_V       = 5'd11;
localparam LOAD_W_V       = 5'd12;
localparam COMPUTE_V      = 5'd13;
localparam REQUANT_V      = 5'd14;
localparam WRITE_V_PRIME  = 5'd15;
// Terminal states
localparam DONE_STATE     = 5'd16;
localparam ERROR_STATE    = 5'd17;

reg [4:0] state, prev_state;

// Current projection encoding
localparam PROJ_Q = 2'd0;
localparam PROJ_K = 2'd1;
localparam PROJ_V = 2'd2;

// State register
reg reset_logged;
always @(posedge clk) begin
    if (!rstn) begin
        state <= IDLE;
        prev_state <= IDLE;
        current_proj <= PROJ_Q;
        if (!reset_logged) begin
            $display("[%t] ATTN_PROJ FSM RESET", $time);
            reset_logged <= 1'b1;
        end
    end else begin
        reset_logged <= 1'b0;
        prev_state <= state;
        case (state)
            IDLE: begin
                current_proj <= PROJ_Q;
                if (start) begin
                    state <= LOAD_I_Q;
                    $display("[%t] ATTN_PROJ FSM: IDLE->LOAD_I_Q (starting Q projection)", $time);
                end
            end

            //=================================================================
            // Q PROJECTION
            //=================================================================
            LOAD_I_Q: begin
                current_proj <= PROJ_Q;
                if (dma_i_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: LOAD_I_Q->ERROR", $time);
                end else if (dma_i_done) begin
                    state <= LOAD_W_Q;
                    $display("[%t] ATTN_PROJ FSM: LOAD_I_Q->LOAD_W_Q", $time);
                end
            end

            LOAD_W_Q: begin
                if (dma_w_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: LOAD_W_Q->ERROR", $time);
                end else if (dma_w_done) begin
                    state <= COMPUTE_Q;
                    $display("[%t] ATTN_PROJ FSM: LOAD_W_Q->COMPUTE_Q", $time);
                end
            end

            COMPUTE_Q: begin
                if (mm_done) begin
                    state <= REQUANT_Q;
                    $display("[%t] ATTN_PROJ FSM: COMPUTE_Q->REQUANT_Q", $time);
                end
            end

            REQUANT_Q: begin
                if (requant_done) begin
                    state <= WRITE_Q_PRIME;
                    $display("[%t] ATTN_PROJ FSM: REQUANT_Q->WRITE_Q_PRIME", $time);
                end
            end

            WRITE_Q_PRIME: begin
                if (dma_out_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: WRITE_Q_PRIME->ERROR", $time);
                end else if (dma_out_done) begin
                    state <= LOAD_I_K;
                    $display("[%t] ATTN_PROJ FSM: WRITE_Q_PRIME->LOAD_I_K (starting K projection)", $time);
                end
            end

            //=================================================================
            // K PROJECTION
            //=================================================================
            LOAD_I_K: begin
                current_proj <= PROJ_K;
                if (dma_i_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: LOAD_I_K->ERROR", $time);
                end else if (dma_i_done) begin
                    state <= LOAD_W_K;
                    $display("[%t] ATTN_PROJ FSM: LOAD_I_K->LOAD_W_K", $time);
                end
            end

            LOAD_W_K: begin
                if (dma_w_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: LOAD_W_K->ERROR", $time);
                end else if (dma_w_done) begin
                    state <= COMPUTE_K;
                    $display("[%t] ATTN_PROJ FSM: LOAD_W_K->COMPUTE_K", $time);
                end
            end

            COMPUTE_K: begin
                if (mm_done) begin
                    state <= REQUANT_K;
                    $display("[%t] ATTN_PROJ FSM: COMPUTE_K->REQUANT_K", $time);
                end
            end

            REQUANT_K: begin
                if (requant_done) begin
                    state <= WRITE_K_PRIME;
                    $display("[%t] ATTN_PROJ FSM: REQUANT_K->WRITE_K_PRIME", $time);
                end
            end

            WRITE_K_PRIME: begin
                if (dma_out_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: WRITE_K_PRIME->ERROR", $time);
                end else if (dma_out_done) begin
                    state <= LOAD_I_V;
                    $display("[%t] ATTN_PROJ FSM: WRITE_K_PRIME->LOAD_I_V (starting V projection)", $time);
                end
            end

            //=================================================================
            // V PROJECTION
            //=================================================================
            LOAD_I_V: begin
                current_proj <= PROJ_V;
                if (dma_i_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: LOAD_I_V->ERROR", $time);
                end else if (dma_i_done) begin
                    state <= LOAD_W_V;
                    $display("[%t] ATTN_PROJ FSM: LOAD_I_V->LOAD_W_V", $time);
                end
            end

            LOAD_W_V: begin
                if (dma_w_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: LOAD_W_V->ERROR", $time);
                end else if (dma_w_done) begin
                    state <= COMPUTE_V;
                    $display("[%t] ATTN_PROJ FSM: LOAD_W_V->COMPUTE_V", $time);
                end
            end

            COMPUTE_V: begin
                if (mm_done) begin
                    state <= REQUANT_V;
                    $display("[%t] ATTN_PROJ FSM: COMPUTE_V->REQUANT_V", $time);
                end
            end

            REQUANT_V: begin
                if (requant_done) begin
                    state <= WRITE_V_PRIME;
                    $display("[%t] ATTN_PROJ FSM: REQUANT_V->WRITE_V_PRIME", $time);
                end
            end

            WRITE_V_PRIME: begin
                if (dma_out_error) begin
                    state <= ERROR_STATE;
                    $display("[%t] ATTN_PROJ FSM: WRITE_V_PRIME->ERROR", $time);
                end else if (dma_out_done) begin
                    state <= DONE_STATE;
                    $display("[%t] ATTN_PROJ FSM: WRITE_V_PRIME->DONE (all projections complete)", $time);
                end
            end

            //=================================================================
            // TERMINAL STATES
            //=================================================================
            DONE_STATE: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] ATTN_PROJ FSM: DONE->IDLE", $time);
                end
            end

            ERROR_STATE: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] ATTN_PROJ FSM: ERROR->IDLE", $time);
                end
            end

            default: begin
                state <= IDLE;
                $display("[%t] ATTN_PROJ FSM: UNKNOWN->IDLE", $time);
            end
        endcase
    end
end

// Output logic - pulse DMA/requant starts on state transitions
always @(posedge clk) begin
    if (!rstn) begin
        start_dma_i <= 1'b0;
        start_dma_w <= 1'b0;
        start_dma_out <= 1'b0;
        start_requant <= 1'b0;
        done <= 1'b0;
        error <= 1'b0;
    end else begin
        // Default - pulses are one clock cycle
        start_dma_i <= 1'b0;
        start_dma_w <= 1'b0;
        start_dma_out <= 1'b0;
        start_requant <= 1'b0;

        // Pulse start signals on state entry
        // Load I for each projection
        if ((state == LOAD_I_Q && prev_state != LOAD_I_Q) ||
            (state == LOAD_I_K && prev_state != LOAD_I_K) ||
            (state == LOAD_I_V && prev_state != LOAD_I_V)) begin
            start_dma_i <= 1'b1;
            $display("[%t] ATTN_PROJ FSM: Pulsing start_dma_i (proj=%d)", $time, current_proj);
        end

        // Load W for each projection
        if ((state == LOAD_W_Q && prev_state != LOAD_W_Q) ||
            (state == LOAD_W_K && prev_state != LOAD_W_K) ||
            (state == LOAD_W_V && prev_state != LOAD_W_V)) begin
            start_dma_w <= 1'b1;
            $display("[%t] ATTN_PROJ FSM: Pulsing start_dma_w (proj=%d)", $time, current_proj);
        end

        // Start write DMA when entering COMPUTE states (before MM output starts)
        // The MM->requant->writeDMA is a streaming pipeline, so write DMA must be ready first
        if ((state == COMPUTE_Q && prev_state != COMPUTE_Q) ||
            (state == COMPUTE_K && prev_state != COMPUTE_K) ||
            (state == COMPUTE_V && prev_state != COMPUTE_V)) begin
            start_dma_out <= 1'b1;
            $display("[%t] ATTN_PROJ FSM: Pulsing start_dma_out at COMPUTE entry (proj=%d)", $time, current_proj);
        end

        // Start requant when entering REQUANT states (for tracking/status purposes)
        if ((state == REQUANT_Q && prev_state != REQUANT_Q) ||
            (state == REQUANT_K && prev_state != REQUANT_K) ||
            (state == REQUANT_V && prev_state != REQUANT_V)) begin
            start_requant <= 1'b1;
            $display("[%t] ATTN_PROJ FSM: Pulsing start_requant (proj=%d)", $time, current_proj);
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
        $display("[%t] ATTN_PROJ FSM: State %d -> %d, proj=%d", $time, prev_state, state, current_proj);
    end
end
`endif

endmodule
