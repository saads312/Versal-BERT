`timescale 1ns / 1ps

//
// Self-Attention Control FSM
// Extends noc_attn_proj_control to complete self-attention:
//   Q/K/V projections → Q' × K'^T → Softmax → P × V' → C'
//

module noc_self_attn_control (
    input wire clk,
    input wire rstn,

    // External control
    input wire start,
    output reg done,
    output reg error,

    // Current operation indicator
    output reg [3:0] current_op,

    // DMA control outputs for Q/K/V projections (reuse existing)
    output reg start_dma_i,         // Read input I
    output reg start_dma_w,         // Read weight W^Q/K/V
    output reg start_dma_proj_out,  // Write Q'/K'^T/V'

    // DMA control for attention computation
    output reg start_dma_qprime,    // Read Q'
    output reg start_dma_kprime_t,  // Read K'^T
    output reg start_dma_vprime,    // Read V'
    output reg start_dma_s,         // Write attention scores S
    output reg start_dma_p,         // Write/Read softmax output P
    output reg start_dma_cprime,    // Write context C'

    // Softmax control
    output reg start_softmax,
    input wire softmax_done,

    // Requant control
    output reg start_requant,
    input wire requant_done,

    // DMA status inputs
    input wire dma_i_done,
    input wire dma_w_done,
    input wire dma_proj_out_done,
    input wire dma_qprime_done,
    input wire dma_kprime_t_done,
    input wire dma_vprime_done,
    input wire dma_s_done,
    input wire dma_p_done,
    input wire dma_cprime_done,
    input wire dma_error,

    // MM core status
    input wire mm_done
);

// State encoding - 6 bits for up to 64 states
localparam [5:0] IDLE              = 6'd0;

// Q projection states
localparam [5:0] LOAD_I_Q          = 6'd1;
localparam [5:0] LOAD_W_Q          = 6'd2;
localparam [5:0] COMPUTE_Q         = 6'd3;
localparam [5:0] REQUANT_Q         = 6'd4;
localparam [5:0] WRITE_Q_PRIME     = 6'd5;

// K projection states
localparam [5:0] LOAD_I_K          = 6'd6;
localparam [5:0] LOAD_W_K          = 6'd7;
localparam [5:0] COMPUTE_K         = 6'd8;
localparam [5:0] REQUANT_K         = 6'd9;
localparam [5:0] WRITE_K_PRIME     = 6'd10;

// V projection states
localparam [5:0] LOAD_I_V          = 6'd11;
localparam [5:0] LOAD_W_V          = 6'd12;
localparam [5:0] COMPUTE_V         = 6'd13;
localparam [5:0] REQUANT_V         = 6'd14;
localparam [5:0] WRITE_V_PRIME     = 6'd15;

// Attention score states: S = Q' × K'^T
localparam [5:0] LOAD_Q_PRIME      = 6'd16;
localparam [5:0] LOAD_K_PRIME_T    = 6'd17;
localparam [5:0] COMPUTE_S         = 6'd18;
localparam [5:0] WRITE_S           = 6'd19;

// Softmax states: P = Softmax(S)
localparam [5:0] LOAD_S            = 6'd20;
localparam [5:0] SOFTMAX           = 6'd21;
localparam [5:0] WRITE_P           = 6'd22;

// Context states: C = P × V'
localparam [5:0] LOAD_P            = 6'd23;
localparam [5:0] LOAD_V_PRIME      = 6'd24;
localparam [5:0] COMPUTE_C         = 6'd25;
localparam [5:0] REQUANT_C         = 6'd26;
localparam [5:0] WRITE_C_PRIME     = 6'd27;

// Terminal states
localparam [5:0] DONE_STATE        = 6'd28;
localparam [5:0] ERROR_STATE       = 6'd29;

reg [5:0] state, prev_state;

// Operation encoding for address/dimension selection
localparam [3:0] OP_PROJ_Q    = 4'd0;
localparam [3:0] OP_PROJ_K    = 4'd1;
localparam [3:0] OP_PROJ_V    = 4'd2;
localparam [3:0] OP_ATTN_S    = 4'd3;  // Q' × K'^T
localparam [3:0] OP_SOFTMAX   = 4'd4;
localparam [3:0] OP_CONTEXT   = 4'd5;  // P × V'

// State register
reg reset_logged;
always @(posedge clk) begin
    if (!rstn) begin
        state <= IDLE;
        prev_state <= IDLE;
        current_op <= OP_PROJ_Q;
        reset_logged <= 1'b0;
    end else begin
        prev_state <= state;
        case (state)
            IDLE: begin
                current_op <= OP_PROJ_Q;
                if (start) begin
                    state <= LOAD_I_Q;
                    $display("[%t] SELF_ATTN FSM: IDLE->LOAD_I_Q", $time);
                end
            end

            //=================================================================
            // Q PROJECTION: I × W^Q → Q → Requant → Q'
            //=================================================================
            LOAD_I_Q: begin
                current_op <= OP_PROJ_Q;
                if (dma_error) state <= ERROR_STATE;
                else if (dma_i_done) begin
                    state <= LOAD_W_Q;
                    $display("[%t] SELF_ATTN FSM: LOAD_I_Q->LOAD_W_Q", $time);
                end
            end

            LOAD_W_Q: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_w_done) begin
                    state <= COMPUTE_Q;
                    $display("[%t] SELF_ATTN FSM: LOAD_W_Q->COMPUTE_Q", $time);
                end
            end

            COMPUTE_Q: begin
                if (mm_done) begin
                    state <= REQUANT_Q;
                    $display("[%t] SELF_ATTN FSM: COMPUTE_Q->REQUANT_Q", $time);
                end
            end

            REQUANT_Q: begin
                if (requant_done) begin
                    state <= WRITE_Q_PRIME;
                    $display("[%t] SELF_ATTN FSM: REQUANT_Q->WRITE_Q_PRIME", $time);
                end
            end

            WRITE_Q_PRIME: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_proj_out_done) begin
                    state <= LOAD_I_K;
                    $display("[%t] SELF_ATTN FSM: WRITE_Q_PRIME->LOAD_I_K", $time);
                end
            end

            //=================================================================
            // K PROJECTION: I × W^K → K → Requant → K'^T
            //=================================================================
            LOAD_I_K: begin
                current_op <= OP_PROJ_K;
                if (dma_error) state <= ERROR_STATE;
                else if (dma_i_done) begin
                    state <= LOAD_W_K;
                    $display("[%t] SELF_ATTN FSM: LOAD_I_K->LOAD_W_K", $time);
                end
            end

            LOAD_W_K: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_w_done) begin
                    state <= COMPUTE_K;
                    $display("[%t] SELF_ATTN FSM: LOAD_W_K->COMPUTE_K", $time);
                end
            end

            COMPUTE_K: begin
                if (mm_done) begin
                    state <= REQUANT_K;
                    $display("[%t] SELF_ATTN FSM: COMPUTE_K->REQUANT_K", $time);
                end
            end

            REQUANT_K: begin
                if (requant_done) begin
                    state <= WRITE_K_PRIME;
                    $display("[%t] SELF_ATTN FSM: REQUANT_K->WRITE_K_PRIME", $time);
                end
            end

            WRITE_K_PRIME: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_proj_out_done) begin
                    state <= LOAD_I_V;
                    $display("[%t] SELF_ATTN FSM: WRITE_K_PRIME->LOAD_I_V", $time);
                end
            end

            //=================================================================
            // V PROJECTION: I × W^V → V → Requant → V'
            //=================================================================
            LOAD_I_V: begin
                current_op <= OP_PROJ_V;
                if (dma_error) state <= ERROR_STATE;
                else if (dma_i_done) begin
                    state <= LOAD_W_V;
                    $display("[%t] SELF_ATTN FSM: LOAD_I_V->LOAD_W_V", $time);
                end
            end

            LOAD_W_V: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_w_done) begin
                    state <= COMPUTE_V;
                    $display("[%t] SELF_ATTN FSM: LOAD_W_V->COMPUTE_V", $time);
                end
            end

            COMPUTE_V: begin
                if (mm_done) begin
                    state <= REQUANT_V;
                    $display("[%t] SELF_ATTN FSM: COMPUTE_V->REQUANT_V", $time);
                end
            end

            REQUANT_V: begin
                if (requant_done) begin
                    state <= WRITE_V_PRIME;
                    $display("[%t] SELF_ATTN FSM: REQUANT_V->WRITE_V_PRIME", $time);
                end
            end

            WRITE_V_PRIME: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_proj_out_done) begin
                    state <= LOAD_Q_PRIME;
                    $display("[%t] SELF_ATTN FSM: WRITE_V_PRIME->LOAD_Q_PRIME (starting attention scores)", $time);
                end
            end

            //=================================================================
            // ATTENTION SCORES: S = Q' × K'^T
            //=================================================================
            LOAD_Q_PRIME: begin
                current_op <= OP_ATTN_S;
                if (dma_error) state <= ERROR_STATE;
                else if (dma_qprime_done) begin
                    state <= LOAD_K_PRIME_T;
                    $display("[%t] SELF_ATTN FSM: LOAD_Q_PRIME->LOAD_K_PRIME_T", $time);
                end
            end

            LOAD_K_PRIME_T: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_kprime_t_done) begin
                    state <= COMPUTE_S;
                    $display("[%t] SELF_ATTN FSM: LOAD_K_PRIME_T->COMPUTE_S", $time);
                end
            end

            COMPUTE_S: begin
                // MM outputs 32-bit S values, stream directly to softmax
                // (no DDR round-trip since DMA is 8-bit and S is 32-bit)
                current_op <= OP_SOFTMAX;  // Switch to softmax mode for data path
                if (mm_done) begin
                    state <= SOFTMAX;
                    $display("[%t] SELF_ATTN FSM: COMPUTE_S->SOFTMAX (streaming 32-bit S to softmax)", $time);
                end
            end

            //=================================================================
            // SOFTMAX: P = Softmax(S)
            // Note: S values stream directly from MM output (32-bit)
            // Softmax output P is 8-bit
            //=================================================================
            SOFTMAX: begin
                if (softmax_done) begin
                    state <= WRITE_P;
                    $display("[%t] SELF_ATTN FSM: SOFTMAX->WRITE_P", $time);
                end
            end

            WRITE_P: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_p_done) begin
                    state <= LOAD_P;
                    $display("[%t] SELF_ATTN FSM: WRITE_P->LOAD_P (starting context)", $time);
                end
            end

            //=================================================================
            // CONTEXT: C = P × V' → Requant → C'
            //=================================================================
            LOAD_P: begin
                current_op <= OP_CONTEXT;
                if (dma_error) state <= ERROR_STATE;
                else if (dma_p_done) begin
                    state <= LOAD_V_PRIME;
                    $display("[%t] SELF_ATTN FSM: LOAD_P->LOAD_V_PRIME", $time);
                end
            end

            LOAD_V_PRIME: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_vprime_done) begin
                    state <= COMPUTE_C;
                    $display("[%t] SELF_ATTN FSM: LOAD_V_PRIME->COMPUTE_C", $time);
                end
            end

            COMPUTE_C: begin
                if (mm_done) begin
                    state <= REQUANT_C;
                    $display("[%t] SELF_ATTN FSM: COMPUTE_C->REQUANT_C", $time);
                end
            end

            REQUANT_C: begin
                if (requant_done) begin
                    state <= WRITE_C_PRIME;
                    $display("[%t] SELF_ATTN FSM: REQUANT_C->WRITE_C_PRIME", $time);
                end
            end

            WRITE_C_PRIME: begin
                if (dma_error) state <= ERROR_STATE;
                else if (dma_cprime_done) begin
                    state <= DONE_STATE;
                    $display("[%t] SELF_ATTN FSM: WRITE_C_PRIME->DONE (self-attention complete)", $time);
                end
            end

            //=================================================================
            // TERMINAL STATES
            //=================================================================
            DONE_STATE: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] SELF_ATTN FSM: DONE->IDLE", $time);
                end
            end

            ERROR_STATE: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] SELF_ATTN FSM: ERROR->IDLE", $time);
                end
            end

            default: begin
                state <= IDLE;
                $display("[%t] SELF_ATTN FSM: UNKNOWN->IDLE", $time);
            end
        endcase
    end
end

// Output logic - pulse signals on state transitions
always @(posedge clk) begin
    if (!rstn) begin
        start_dma_i <= 1'b0;
        start_dma_w <= 1'b0;
        start_dma_proj_out <= 1'b0;
        start_dma_qprime <= 1'b0;
        start_dma_kprime_t <= 1'b0;
        start_dma_vprime <= 1'b0;
        start_dma_s <= 1'b0;
        start_dma_p <= 1'b0;
        start_dma_cprime <= 1'b0;
        start_softmax <= 1'b0;
        start_requant <= 1'b0;
        done <= 1'b0;
        error <= 1'b0;
    end else begin
        // Default - all pulses are one clock cycle
        start_dma_i <= 1'b0;
        start_dma_w <= 1'b0;
        start_dma_proj_out <= 1'b0;
        start_dma_qprime <= 1'b0;
        start_dma_kprime_t <= 1'b0;
        start_dma_vprime <= 1'b0;
        start_dma_s <= 1'b0;
        start_dma_p <= 1'b0;
        start_dma_cprime <= 1'b0;
        start_softmax <= 1'b0;
        start_requant <= 1'b0;

        // Q/K/V Projection DMA pulses
        if ((state == LOAD_I_Q && prev_state != LOAD_I_Q) ||
            (state == LOAD_I_K && prev_state != LOAD_I_K) ||
            (state == LOAD_I_V && prev_state != LOAD_I_V)) begin
            start_dma_i <= 1'b1;
        end

        if ((state == LOAD_W_Q && prev_state != LOAD_W_Q) ||
            (state == LOAD_W_K && prev_state != LOAD_W_K) ||
            (state == LOAD_W_V && prev_state != LOAD_W_V)) begin
            start_dma_w <= 1'b1;
        end

        // Start write DMA at COMPUTE entry (streaming pipeline)
        if ((state == COMPUTE_Q && prev_state != COMPUTE_Q) ||
            (state == COMPUTE_K && prev_state != COMPUTE_K) ||
            (state == COMPUTE_V && prev_state != COMPUTE_V)) begin
            start_dma_proj_out <= 1'b1;
        end

        // Requant pulses for Q/K/V and C
        if ((state == REQUANT_Q && prev_state != REQUANT_Q) ||
            (state == REQUANT_K && prev_state != REQUANT_K) ||
            (state == REQUANT_V && prev_state != REQUANT_V) ||
            (state == REQUANT_C && prev_state != REQUANT_C)) begin
            start_requant <= 1'b1;
        end

        // Attention score DMA pulses
        if (state == LOAD_Q_PRIME && prev_state != LOAD_Q_PRIME)
            start_dma_qprime <= 1'b1;

        if (state == LOAD_K_PRIME_T && prev_state != LOAD_K_PRIME_T)
            start_dma_kprime_t <= 1'b1;

        // Softmax control pulse and P write DMA
        // Note: S values stream directly from MM output to softmax (no DDR round-trip)
        if (state == SOFTMAX && prev_state != SOFTMAX) begin
            start_softmax <= 1'b1;
            start_dma_p <= 1'b1;  // Start P write DMA for softmax output
        end

        // Context computation DMA pulses
        if (state == LOAD_P && prev_state != LOAD_P)
            start_dma_p <= 1'b1;  // Reading P for context

        if (state == LOAD_V_PRIME && prev_state != LOAD_V_PRIME)
            start_dma_vprime <= 1'b1;

        // Start C' write DMA at COMPUTE_C entry
        if (state == COMPUTE_C && prev_state != COMPUTE_C)
            start_dma_cprime <= 1'b1;

        // Status outputs
        done <= (state == DONE_STATE);
        error <= (state == ERROR_STATE);
    end
end

endmodule
