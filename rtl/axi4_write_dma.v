//
// AXI4 Write DMA - Takes AXI-Stream and writes to DDR
// Scalable design for matrix result storage
//

`timescale 1ns / 1ps

module axi4_write_dma #(
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

    // AXI-Stream Input
    input wire [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tlast,
    output reg s_axis_tready,

    // AXI4 Write Master (connects to XPM_NMU)
    output reg [AXI_ID_WIDTH-1:0] m_axi_awid,
    output reg [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg [7:0] m_axi_awlen,
    output reg [2:0] m_axi_awsize,
    output reg [1:0] m_axi_awburst,
    output reg m_axi_awlock,
    output reg [3:0] m_axi_awcache,
    output reg [2:0] m_axi_awprot,
    output reg [3:0] m_axi_awqos,
    output reg m_axi_awvalid,
    input wire m_axi_awready,

    output reg [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output reg [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg m_axi_wlast,
    output reg m_axi_wvalid,
    input wire m_axi_wready,

    input wire [AXI_ID_WIDTH-1:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output reg m_axi_bready
);

localparam AXI_BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
localparam AXIS_BYTES_PER_BEAT = AXIS_DATA_WIDTH / 8;
localparam WORDS_PER_AXI_BEAT = AXI_DATA_WIDTH / AXIS_DATA_WIDTH;

// State machine
localparam IDLE = 3'd0;
localparam BUFFER_DATA = 3'd1;
localparam ISSUE_WRITE_ADDR = 3'd2;
localparam WRITE_DATA = 3'd3;
localparam WAIT_BRESP = 3'd4;
localparam DONE_STATE = 3'd5;

reg [2:0] state;
reg [2:0] prev_state;
reg [31:0] bytes_remaining;
reg [AXI_ADDR_WIDTH-1:0] current_addr;
reg [7:0] current_burst_len;
reg [7:0] beats_in_burst;
reg [7:0] beat_count;

// Debug counters
reg [31:0] total_beats_received = 0;
reg tlast_seen_flag = 0;
reg prev_s_axis_tready = 0;

// Track TLAST reception during transaction
reg tlast_received = 0;

// Data width conversion buffer
reg [AXI_DATA_WIDTH-1:0] data_buffer;
reg [7:0] word_index;

// State change logging
always @(posedge aclk) begin
    if (aresetn) begin
        prev_state <= state;
        if (state != prev_state) begin
            $display("[%t] WRITE_DMA: State change %d -> %d", $time, prev_state, state);
        end
    end
end

// Beat reception logging
always @(posedge aclk) begin
    if (!aresetn) begin
        total_beats_received <= 0;
        tlast_seen_flag <= 0;
        prev_s_axis_tready <= 0;
    end else begin
        prev_s_axis_tready <= s_axis_tready;

        // Log tready changes
        if (s_axis_tready != prev_s_axis_tready) begin
            $display("[%t] WRITE_DMA: s_axis_tready changed %b -> %b (state=%d, word_index=%d)",
                     $time, prev_s_axis_tready, s_axis_tready, state, word_index);
        end

        if (s_axis_tvalid && s_axis_tready) begin
            total_beats_received <= total_beats_received + 1;
            $display("[%t] WRITE_DMA: Received beat #%d | tdata=0x%h tlast=%b | word_index=%d state=%d",
                     $time, total_beats_received + 1, s_axis_tdata, s_axis_tlast, word_index, state);

            if (s_axis_tlast) begin
                if (tlast_seen_flag) begin
                    $display("[%t] WRITE_DMA: ERROR! TLAST seen again after previous TLAST!", $time);
                end else begin
                    tlast_seen_flag <= 1;
                    $display("[%t] WRITE_DMA: TLAST received on beat #%d", $time, total_beats_received + 1);
                end
            end else if (tlast_seen_flag) begin
                $display("[%t] WRITE_DMA: ERROR! Received beat AFTER TLAST! (beat #%d)", $time, total_beats_received + 1);
            end
        end

        // Log when tvalid is high but tready is low (backpressure)
        if (s_axis_tvalid && !s_axis_tready) begin
            $display("[%t] WRITE_DMA: Backpressure - tvalid=1 but tready=0 (state=%d)", $time, state);
        end
    end
end

always @(posedge aclk) begin
    if (!aresetn) begin
        state <= IDLE;
        prev_state <= IDLE;
        done <= 1'b0;
        error <= 1'b0;
        m_axi_awvalid <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        s_axis_tready <= 1'b0;
        bytes_remaining <= 32'h0;
        current_addr <= {AXI_ADDR_WIDTH{1'b0}};
        word_index <= 8'h0;
    end else begin
        case (state)
            IDLE: begin
                done <= 1'b0;
                error <= 1'b0;
                m_axi_wvalid <= 1'b0;
                tlast_received <= 1'b0;
                if (start) begin
                    current_addr <= start_addr;
                    bytes_remaining <= transfer_length;
                    word_index <= 0;
                    s_axis_tready <= 1'b1;
                    tlast_received <= 1'b0;
                    state <= BUFFER_DATA;
                    $display("[%t] WRITE_DMA: Starting new transaction (addr=0x%h, len=%d bytes)",
                             $time, start_addr, transfer_length);
                end
            end

            BUFFER_DATA: begin
                if (s_axis_tvalid && s_axis_tready) begin
                    data_buffer[word_index * AXIS_DATA_WIDTH +: AXIS_DATA_WIDTH] <= s_axis_tdata;
                    word_index <= word_index + 1;

                    // Track TLAST reception
                    if (s_axis_tlast) begin
                        tlast_received <= 1'b1;
                        $display("[%t] WRITE_DMA: TLAST detected while buffering (word_index=%d)",
                                 $time, word_index);
                    end

                    if (word_index == WORDS_PER_AXI_BEAT - 1) begin
                        s_axis_tready <= 1'b0;
                        state <= ISSUE_WRITE_ADDR;
                        $display("[%t] WRITE_DMA: Buffer full, transitioning to ISSUE_WRITE_ADDR (tlast_received=%b)",
                                 $time, tlast_received || s_axis_tlast);
                    end
                end
            end

            ISSUE_WRITE_ADDR: begin
                if (!m_axi_awvalid || m_axi_awready) begin
                    // Calculate burst length
                    if (bytes_remaining >= (MAX_BURST_LEN * AXI_BYTES_PER_BEAT)) begin
                        current_burst_len <= MAX_BURST_LEN - 1;
                    end else begin
                        current_burst_len <= (bytes_remaining / AXI_BYTES_PER_BEAT) - 1;
                    end

                    $display("[%t] WRITE_DMA: Issuing write addr=0x%h, len=%d beats, bytes_remaining=%d",
                             $time, current_addr, current_burst_len + 1, bytes_remaining);

                    m_axi_awid <= {AXI_ID_WIDTH{1'b0}};
                    m_axi_awaddr <= current_addr;
                    m_axi_awlen <= current_burst_len;
                    m_axi_awsize <= $clog2(AXI_BYTES_PER_BEAT);
                    m_axi_awburst <= 2'b01;  // INCR
                    m_axi_awlock <= 1'b0;
                    m_axi_awcache <= 4'b0011;  // Modifiable, bufferable
                    m_axi_awprot <= 3'b000;
                    m_axi_awqos <= 4'b0000;
                    m_axi_awvalid <= 1'b1;

                    beat_count <= 0;
                    beats_in_burst <= current_burst_len + 1;
                    state <= WRITE_DATA;
                end
            end

            WRITE_DATA: begin
                m_axi_awvalid <= 1'b0;

                if (!m_axi_wvalid || m_axi_wready) begin
                    // Check if this is the last beat (either end of burst OR tlast received)
                    m_axi_wdata <= data_buffer;
                    m_axi_wstrb <= {(AXI_DATA_WIDTH/8){1'b1}};
                    m_axi_wlast <= (beat_count == beats_in_burst - 1) || tlast_received;
                    m_axi_wvalid <= 1'b1;

                    $display("[%t] WRITE_DMA: Writing AXI beat %d/%d (wdata=0x%h, wlast=%b, tlast_received=%b)",
                             $time, beat_count + 1, beats_in_burst, data_buffer,
                             ((beat_count == beats_in_burst - 1) || tlast_received), tlast_received);

                    beat_count <= beat_count + 1;

                    if ((beat_count == beats_in_burst - 1) || tlast_received) begin
                        $display("[%t] WRITE_DMA: Last beat in burst (beat_count=%d, tlast_received=%b), transitioning to WAIT_BRESP",
                                 $time, beat_count, tlast_received);
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        // Update address and bytes based on actual beats written
                        current_addr <= current_addr + ((beat_count + 1) * AXI_BYTES_PER_BEAT);
                        bytes_remaining <= bytes_remaining - ((beat_count + 1) * AXI_BYTES_PER_BEAT);
                        state <= WAIT_BRESP;
                    end else begin
                        $display("[%t] WRITE_DMA: More beats in burst, back to BUFFER_DATA", $time);
                        // Get next data from stream
                        word_index <= 0;
                        s_axis_tready <= 1'b1;
                        state <= BUFFER_DATA;
                    end
                end
            end

            WAIT_BRESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    $display("[%t] WRITE_DMA: BRESP received (resp=%b, bytes_remaining=%d, tlast_received=%b)",
                             $time, m_axi_bresp, bytes_remaining, tlast_received);
                    m_axi_bready <= 1'b0;

                    if (m_axi_bresp != 2'b00) begin
                        $display("[%t] WRITE_DMA: ERROR response, transitioning to DONE", $time);
                        error <= 1'b1;
                        state <= DONE_STATE;
                    end else if (tlast_received) begin
                        // TLAST was received - transaction complete regardless of bytes_remaining
                        $display("[%t] WRITE_DMA: TLAST was received, transaction complete, transitioning to DONE", $time);
                        state <= DONE_STATE;
                    end else if (bytes_remaining > 0) begin
                        $display("[%t] WRITE_DMA: More data to write (%d bytes), back to BUFFER_DATA",
                                 $time, bytes_remaining);
                        word_index <= 0;
                        s_axis_tready <= 1'b1;
                        state <= BUFFER_DATA;
                    end else begin
                        $display("[%t] WRITE_DMA: All data written (bytes_remaining=0), transitioning to DONE", $time);
                        state <= DONE_STATE;
                    end
                end else begin
                    if (m_axi_bvalid) begin
                        $display("[%t] WRITE_DMA: In WAIT_BRESP, bvalid=1 but bready=%b (waiting for handshake)",
                                 $time, m_axi_bready);
                    end
                end
            end

            DONE_STATE: begin
                s_axis_tready <= 1'b0;
                done <= 1'b1;
                $display("[%t] WRITE_DMA: In DONE_STATE, asserting done signal", $time);
                if (!start) begin
                    state <= IDLE;
                end
            end
        endcase
    end
end

endmodule
