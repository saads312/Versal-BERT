//
// AXI4 Read DMA - Reads from DDR and outputs AXI-Stream
// Scalable design for matrix data loading
//

`timescale 1ns / 1ps

module axi4_read_dma #(
    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_DATA_WIDTH = 128,
    parameter AXI_ID_WIDTH = 1,
    parameter AXIS_DATA_WIDTH = 32,
    parameter MAX_BURST_LEN = 256
)(
    input wire aclk,
    input wire aresetn,

    // Control interface
    input wire [AXI_ADDR_WIDTH-1:0] start_addr,
    input wire [31:0] transfer_length,  // in bytes
    input wire start,
    output reg done,
    output reg error,

    // AXI4 Read Master (connects to XPM_NMU)
    output reg [AXI_ID_WIDTH-1:0] m_axi_arid,
    output reg [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output reg [7:0] m_axi_arlen,
    output reg [2:0] m_axi_arsize,
    output reg [1:0] m_axi_arburst,
    output reg m_axi_arlock,
    output reg [3:0] m_axi_arcache,
    output reg [2:0] m_axi_arprot,
    output reg [3:0] m_axi_arqos,
    output reg m_axi_arvalid,
    input wire m_axi_arready,

    input wire [AXI_ID_WIDTH-1:0] m_axi_rid,
    input wire [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output reg m_axi_rready,

    // AXI-Stream Output
    output reg [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output reg m_axis_tvalid,
    output reg m_axis_tlast,
    input wire m_axis_tready
);

localparam AXI_BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
localparam AXIS_BYTES_PER_BEAT = AXIS_DATA_WIDTH / 8;
localparam WORDS_PER_AXI_BEAT = AXI_DATA_WIDTH / AXIS_DATA_WIDTH;

// State machine
localparam IDLE = 3'd0;
localparam ISSUE_READ = 3'd1;
localparam RECEIVE_DATA = 3'd2;
localparam STREAM_DATA = 3'd3;
localparam DONE_STATE = 3'd4;

reg [2:0] state;
reg [2:0] prev_state;
reg [31:0] bytes_remaining;
reg [AXI_ADDR_WIDTH-1:0] current_addr;
reg [7:0] current_burst_len;
reg [31:0] total_axis_beats;
reg [31:0] axis_beat_count;

// Data width conversion buffer
reg [AXI_DATA_WIDTH-1:0] data_buffer;
reg [7:0] word_index;
reg buffer_valid;
reg rlast_received;  // Track if current burst received rlast
reg [8:0] beats_in_burst;  // Track actual beats received in current burst

// Debug counters
reg [31:0] total_axi_beats_received = 0;
reg [31:0] total_axis_beats_sent = 0;

// State change logging
always @(posedge aclk) begin
    if (aresetn) begin
        prev_state <= state;
        if (state != prev_state) begin
            $display("[%t] READ_DMA: State change %d -> %d", $time, prev_state, state);
        end
    end
end

always @(posedge aclk) begin
    if (!aresetn) begin
        state <= IDLE;
        done <= 1'b0;
        error <= 1'b0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
        m_axis_tvalid <= 1'b0;
        bytes_remaining <= 32'h0;
        current_addr <= {AXI_ADDR_WIDTH{1'b0}};
        axis_beat_count <= 32'h0;
        buffer_valid <= 1'b0;
        rlast_received <= 1'b0;
        beats_in_burst <= 0;
        total_axi_beats_received <= 0;
        total_axis_beats_sent <= 0;
    end else begin
        case (state)
            IDLE: begin
                done <= 1'b0;
                error <= 1'b0;
                m_axis_tvalid <= 1'b0;
                buffer_valid <= 1'b0;
                rlast_received <= 1'b0;
                if (start) begin
                    $display("[%t] READ_DMA: START received! start_addr=0x%h, transfer_length=%d bytes (%d AXIS beats)",
                             $time, start_addr, transfer_length, transfer_length / AXIS_BYTES_PER_BEAT);
                    current_addr <= start_addr;
                    bytes_remaining <= transfer_length;
                    total_axis_beats <= transfer_length / AXIS_BYTES_PER_BEAT;
                    axis_beat_count <= 32'h0;
                    state <= ISSUE_READ;
                    $display("[%t] READ_DMA: Transitioning to ISSUE_READ", $time);
                end
            end

            ISSUE_READ: begin
                if (!m_axi_arvalid) begin
                    // Calculate burst length and set up AR channel
                    if (bytes_remaining >= (MAX_BURST_LEN * AXI_BYTES_PER_BEAT)) begin
                        current_burst_len <= MAX_BURST_LEN - 1;
                    end else begin
                        current_burst_len <= (bytes_remaining / AXI_BYTES_PER_BEAT) - 1;
                    end

                    $display("[%t] READ_DMA: Issuing AXI4 AR - araddr=0x%h, bytes_remaining=%d",
                             $time, current_addr, bytes_remaining);

                    m_axi_arid <= {AXI_ID_WIDTH{1'b0}};
                    m_axi_araddr <= current_addr;
                    m_axi_arlen <= (bytes_remaining >= (MAX_BURST_LEN * AXI_BYTES_PER_BEAT)) ?
                                   (MAX_BURST_LEN - 1) : ((bytes_remaining / AXI_BYTES_PER_BEAT) - 1);
                    m_axi_arsize <= $clog2(AXI_BYTES_PER_BEAT);
                    m_axi_arburst <= 2'b01;  // INCR
                    m_axi_arlock <= 1'b0;
                    m_axi_arcache <= 4'b0011;  // Modifiable, bufferable
                    m_axi_arprot <= 3'b000;
                    m_axi_arqos <= 4'b0000;
                    m_axi_arvalid <= 1'b1;

                    word_index <= 0;
                    rlast_received <= 1'b0;  // Clear for new burst
                    beats_in_burst <= 0;     // Reset beat counter for new burst
                    $display("[%t] READ_DMA: arvalid asserted, waiting for arready", $time);
                end else if (m_axi_arready) begin
                    // AR handshake complete
                    $display("[%t] READ_DMA: AR handshake complete (arlen=%d), transitioning to RECEIVE_DATA",
                             $time, m_axi_arlen);
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b1;
                    state <= RECEIVE_DATA;
                end
            end

            RECEIVE_DATA: begin
                m_axi_arvalid <= 1'b0;

                if (m_axi_rvalid && m_axi_rready) begin
                    total_axi_beats_received <= total_axi_beats_received + 1;
                    beats_in_burst <= beats_in_burst + 1;  // Track actual beats received
                    $display("[%t] READ_DMA: Received AXI beat #%d (burst beat %d) | rdata=0x%h rlast=%b rresp=%b",
                             $time, total_axi_beats_received + 1, beats_in_burst + 1, m_axi_rdata, m_axi_rlast, m_axi_rresp);

                    data_buffer <= m_axi_rdata;
                    buffer_valid <= 1'b1;
                    word_index <= 0;

                    if (m_axi_rresp != 2'b00) begin
                        $display("[%t] READ_DMA: ERROR response on R channel! rresp=%b", $time, m_axi_rresp);
                        error <= 1'b1;
                        state <= DONE_STATE;
                    end else begin
                        // Deassert rready while streaming to avoid missing data
                        m_axi_rready <= 1'b0;
                        state <= STREAM_DATA;
                    end

                    if (m_axi_rlast) begin
                        // Use actual beats received (beats_in_burst + 1), not requested burst length
                        $display("[%t] READ_DMA: RLAST received after %d beats (requested %d), burst complete",
                                 $time, beats_in_burst + 1, current_burst_len + 1);
                        m_axi_rready <= 1'b0;
                        rlast_received <= 1'b1;  // Mark burst as complete
                        // Update address and remaining bytes based on ACTUAL beats received
                        current_addr <= current_addr + ((beats_in_burst + 1) * AXI_BYTES_PER_BEAT);
                        bytes_remaining <= bytes_remaining - ((beats_in_burst + 1) * AXI_BYTES_PER_BEAT);
                    end
                end
            end

            STREAM_DATA: begin
                if (buffer_valid) begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tdata <= data_buffer[word_index * AXIS_DATA_WIDTH +: AXIS_DATA_WIDTH];
                    m_axis_tlast <= (axis_beat_count == total_axis_beats - 1);

                    if (m_axis_tready) begin
                        total_axis_beats_sent <= total_axis_beats_sent + 1;
                        $display("[%t] READ_DMA: Sent AXIS beat #%d/%d | tdata=0x%h tlast=%b word_index=%d",
                                 $time, total_axis_beats_sent + 1, total_axis_beats,
                                 data_buffer[word_index * AXIS_DATA_WIDTH +: AXIS_DATA_WIDTH],
                                 (axis_beat_count == total_axis_beats - 1), word_index);

                        axis_beat_count <= axis_beat_count + 1;
                        word_index <= word_index + 1;

                        if (word_index == WORDS_PER_AXI_BEAT - 1) begin
                            buffer_valid <= 1'b0;
                            // Don't deassert tvalid if this is the last beat - need to keep it high
                            // for the tlast handshake to complete properly
                            if (axis_beat_count != total_axis_beats - 1) begin
                                m_axis_tvalid <= 1'b0;
                            end

                            if (axis_beat_count == total_axis_beats - 1) begin
                                $display("[%t] READ_DMA: All beats sent, transitioning to DONE", $time);
                                state <= DONE_STATE;
                            end else if (rlast_received) begin
                                // Current burst is done, need new burst
                                if (bytes_remaining > 0) begin
                                    $display("[%t] READ_DMA: Burst done, more data needed (%d bytes), issuing new burst", $time, bytes_remaining);
                                    state <= ISSUE_READ;
                                end else begin
                                    $display("[%t] READ_DMA: Burst done, no bytes remaining, to DONE", $time);
                                    state <= DONE_STATE;
                                end
                            end else begin
                                // More data expected from current burst
                                $display("[%t] READ_DMA: Waiting for more data from current burst", $time);
                                m_axi_rready <= 1'b1;
                                state <= RECEIVE_DATA;
                            end
                        end
                    end
                end
            end

            DONE_STATE: begin
                m_axis_tvalid <= 1'b0;
                done <= 1'b1;
                $display("[%t] READ_DMA: In DONE state, asserting done signal", $time);
                if (!start) begin
                    $display("[%t] READ_DMA: Start deasserted, returning to IDLE", $time);
                    state <= IDLE;
                end
            end
        endcase
    end
end

endmodule
