//
// Simple control FSM for NoC Matrix Multiply
// Sequences: Read A -> Read B -> Compute -> Write D -> Done
//

`timescale 1ns / 1ps

module noc_mm_control (
    input wire clk,
    input wire rstn,

    // External control
    input wire start,
    output reg done,
    output reg error,

    // DMA control outputs
    output reg start_dma_a,
    output reg start_dma_b,
    output reg start_dma_d,

    // DMA status inputs
    input wire dma_a_done,
    input wire dma_b_done,
    input wire dma_d_done,
    input wire dma_a_error,
    input wire dma_b_error,
    input wire dma_d_error
);

// State machine
localparam IDLE      = 3'd0;
localparam READ_A    = 3'd1;
localparam READ_B    = 3'd2;
localparam COMPUTE   = 3'd3;
localparam WRITE_D   = 3'd4;
localparam DONE      = 3'd5;
localparam ERROR     = 3'd6;

reg [2:0] state, prev_state;

// State register
always @(posedge clk) begin
    if (!rstn) begin
        state <= IDLE;
        prev_state <= IDLE;
        $display("[%t] FSM RESET", $time);
    end else begin
        prev_state <= state;
        case (state)
            IDLE: begin
                if (start) begin
                    state <= READ_A;
                    $display("[%t] FSM: IDLE->READ_A", $time);
                end
            end

            READ_A: begin
                if (dma_a_error) begin
                    state <= ERROR;
                    $display("[%t] FSM: READ_A->ERROR", $time);
                end else if (dma_a_done) begin
                    state <= READ_B;
                    $display("[%t] FSM: READ_A->READ_B (dma_a_done)", $time);
                end
            end

            READ_B: begin
                if (dma_b_error) begin
                    state <= ERROR;
                    $display("[%t] FSM: READ_B->ERROR", $time);
                end else if (dma_b_done) begin
                    state <= COMPUTE;
                    $display("[%t] FSM: READ_B->COMPUTE (dma_b_done)", $time);
                end
            end

            COMPUTE: begin
                // Simple delay for compute (in real design, wait for MM done signal)
                state <= WRITE_D;
                $display("[%t] FSM: COMPUTE->WRITE_D", $time);
            end

            WRITE_D: begin
                if (dma_d_error) begin
                    state <= ERROR;
                    $display("[%t] FSM: WRITE_D->ERROR", $time);
                end else if (dma_d_done) begin
                    state <= DONE;
                    $display("[%t] FSM: WRITE_D->DONE (dma_d_done)", $time);
                end
            end

            DONE: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] FSM: DONE->IDLE", $time);
                end
            end

            ERROR: begin
                if (!start) begin
                    state <= IDLE;
                    $display("[%t] FSM: ERROR->IDLE", $time);
                end
            end

            default: begin
                state <= IDLE;
                $display("[%t] FSM: UNKNOWN->IDLE", $time);
            end
        endcase
    end
end

// Output logic - pulse DMA starts on state transitions
always @(posedge clk) begin
    if (!rstn) begin
        start_dma_a <= 1'b0;
        start_dma_b <= 1'b0;
        start_dma_d <= 1'b0;
        done <= 1'b0;
        error <= 1'b0;
    end else begin
        // Default - pulses are one clock cycle
        start_dma_a <= 1'b0;
        start_dma_b <= 1'b0;
        start_dma_d <= 1'b0;

        // Pulse start signals on state entry
        if (state == READ_A && prev_state != READ_A) begin
            start_dma_a <= 1'b1;
            $display("[%t] FSM: Pulsing start_dma_a", $time);
        end

        if (state == READ_B && prev_state != READ_B) begin
            start_dma_b <= 1'b1;
            $display("[%t] FSM: Pulsing start_dma_b", $time);
        end

        if (state == WRITE_D && prev_state != WRITE_D) begin
            start_dma_d <= 1'b1;
            $display("[%t] FSM: Pulsing start_dma_d", $time);
        end

        // Status outputs
        done <= (state == DONE);
        error <= (state == ERROR);
    end
end

// Monitor dma_d_done signal while in WRITE_D state
reg prev_dma_d_done = 0;
always @(posedge clk) begin
    if (state == WRITE_D) begin
        if (dma_d_done != prev_dma_d_done) begin
            $display("[%t] FSM: dma_d_done changed %b -> %b while in WRITE_D", $time, prev_dma_d_done, dma_d_done);
        end
        prev_dma_d_done <= dma_d_done;
    end
end

endmodule
