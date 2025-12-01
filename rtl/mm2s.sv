`timescale 1ps / 1ps

module mm2s
#(
    parameter integer D_W_ACC      = 32,
    parameter integer N1           = 4,
    parameter integer N2           = 4,
    parameter integer MATRIXSIZE_W = 16,
    parameter integer ADDR_W_D     = 12,
    parameter integer MEM_DEPTH_D  = 4096
)
(
    input  wire                           clk,
    input  wire                           fclk,
    input  wire                           rst,
    output wire signed [D_W_ACC-1:0]      m_axis_mm2s_tdata,
    output wire                           m_axis_mm2s_tlast,
    input  wire                           m_axis_mm2s_tready,
    output wire                           m_axis_mm2s_tvalid,
    
    input  wire        [N1-1:0]           valid_D,
    input  wire signed [D_W_ACC-1:0]      data_D [N1-1:0],

    input  wire        [MATRIXSIZE_W-1:0] M3,
    input  wire	       [MATRIXSIZE_W-1:0] M1dN1,
    input  wire        [MATRIXSIZE_W-1:0] M1xM3dN1,

    output reg                            done_multiply
);

wire done_read;
wire last_read_addr;  // Detect when we're issuing the last read
reg start_read = 0;
reg rd_addr_D_valid = 0;
reg reg_rd_addr_D_valid = 0;
reg rd_data_bram_valid = 0;
reg [1:0] done_read_sync = 0;
reg [1:0] done_multiply_sync = 0;
reg done_multiply_sync_wait = 0;
wire out_tready;

// Pipeline for tlast signal (mirrors the data/valid pipeline)
reg reg_rd_last_D = 0;
reg rd_data_bram_last = 0;
reg reg_banked_last_D [N1-1:0];
reg [MATRIXSIZE_W-1:0] addr_count = 0;  // Count addresses issued

wire        [ADDR_W_D-1:0] wr_addr_D_bram         [N1-1:0];
wire        [ADDR_W_D-1:0] rd_addr_D;

wire        [N1-1:0]       wr_en_D_bram;
wire signed [D_W_ACC-1:0]  wr_data_D_bram         [N1-1:0];
wire signed [D_W_ACC-1:0]  rd_data_D_bram         [N1-1:0];

reg         [N1-1:0]       reg_banked_valid_D;
reg  signed [D_W_ACC-1:0]  reg_banked_data_D      [N1-1:0];
reg         [ADDR_W_D-1:0] reg_banked_read_addr_D [N1-1:0];
reg         [N1-1:0]       reg_banked_activate_D  [N1-1:0];

wire        [N1-1:0]       activate_D;
reg         [N1-1:0]       activate_D_reg;

assign out_tready = m_axis_mm2s_tready | ~m_axis_mm2s_tvalid;

// D management
genvar x;
for (x = 0; x < N1; x = x + 1) begin: ram_D
    mem_top #(
        .WIDTH ( D_W_ACC     ),
        .DEPTH ( MEM_DEPTH_D )
    )
    write_ram_D (
        .rst   ( rst                         ),
        .clkA  ( fclk                        ),
        .clkB  ( clk                         ),
        .weA   ( 1'b1                        ),
        .enA   ( wr_en_D_bram[x]             ),
        .enB   ( reg_banked_activate_D[x][x] & out_tready ),
        .addrA ( wr_addr_D_bram[x]           ),
        .addrB ( reg_banked_read_addr_D[x]   ),
        .dinA  ( wr_data_D_bram[x]           ),
        .doutB ( rd_data_D_bram[x]           )
    );

    always @(posedge clk) begin
        if (out_tready) begin
            activate_D_reg[x] <= reg_banked_activate_D[x][x];
        end
    end

    if (x == N1-1) begin
        always @(posedge clk) begin
            if (rst) begin
                reg_banked_valid_D[x] <= 0;
                reg_banked_last_D[x] <= 0;
            end else if (out_tready) begin
                // Clear pipeline after TLAST has been output AND keep it cleared
                if ((m_axis_mm2s_tlast && m_axis_mm2s_tvalid && m_axis_mm2s_tready) || tlast_seen) begin
                    reg_banked_valid_D[x] <= 0;
                    reg_banked_last_D[x] <= 0;
                    if (m_axis_mm2s_tlast && m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
                        $display("[%t] MM2S PIPELINE: Clearing bank[%d] valid after TLAST output", $time, x);
                    end
                end else begin
                    reg_banked_data_D[x]      <= rd_data_D_bram[x];
                    reg_banked_read_addr_D[x] <= rd_addr_D;
                    reg_banked_valid_D[x]     <= rd_data_bram_valid;
                    reg_banked_activate_D[x]  <= activate_D;
                    reg_banked_last_D[x]      <= rd_data_bram_last;

                    // Debug tlast pipeline
                    if (rd_data_bram_last) begin
                        $display("[%t] MM2S PIPELINE: tlast entering bank[%d] (last stage)", $time, x);
                    end
                end
            end
        end
    end else begin
        always @(posedge clk) begin
            if (rst) begin
                reg_banked_valid_D[x] <= 0;
                reg_banked_last_D[x] <= 0;
            end else if (out_tready) begin
                // Clear pipeline after TLAST has been output AND keep it cleared
                if ((m_axis_mm2s_tlast && m_axis_mm2s_tvalid && m_axis_mm2s_tready) || tlast_seen) begin
                    reg_banked_valid_D[x] <= 0;
                    reg_banked_last_D[x] <= 0;
                    if (m_axis_mm2s_tlast && m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
                        $display("[%t] MM2S PIPELINE: Clearing bank[%d] valid after TLAST output", $time, x);
                    end
                end else begin
                    reg_banked_data_D[x]      <= (activate_D_reg[x] == 1) ? rd_data_D_bram[x] : reg_banked_data_D[x+1];
                    reg_banked_read_addr_D[x] <= reg_banked_read_addr_D[x+1];
                    reg_banked_valid_D[x]     <= reg_banked_valid_D[x+1];
                    reg_banked_activate_D[x]  <= reg_banked_activate_D[x+1];
                    reg_banked_last_D[x]      <= reg_banked_last_D[x+1];

                    // Debug tlast pipeline
                    if (reg_banked_last_D[x+1]) begin
                        $display("[%t] MM2S PIPELINE: tlast shifting from bank[%d] to bank[%d]", $time, x+1, x);
                    end
                end
            end
        end
    end
end

// AXI Signals management
// mem_read_D produces M1*M3 total output beats by cycling through phases and banks
// Total beats = M1xM3dN1 * N1 (e.g., 8 * 2 = 16 for M1=4, M3=4, N1=2)
// We detect the last read by counting total reads issued (addr_count)
// The last read occurs when addr_count reaches the total number of beats minus 1 (0-indexed)
// Original condition using address was triggering too early (at end of first phase, not last phase)
assign last_read_addr = (addr_count == (M1xM3dN1 * N1 - 1)) & (out_tready & start_read);

reg done_read_r = 0;
reg tlast_seen = 0;

// Track when TLAST has been output and acknowledged
always @(posedge clk) begin
    if (rst) begin
        tlast_seen <= 0;
    end else begin
        if (m_axis_mm2s_tvalid && m_axis_mm2s_tready && m_axis_mm2s_tlast) begin
            tlast_seen <= 1;
            $display("[%t] MM2S RTL: TLAST output acknowledged, setting tlast_seen", $time);
        end else if (!start_read) begin
            tlast_seen <= 0;
        end
    end
end

// done_read should only assert AFTER tlast has been output
always @(posedge clk) begin
    if (rst) begin
        done_read_r <= 0;
    end else begin
        // Assert done_read only after TLAST has been sent and acknowledged
        if (tlast_seen) begin
            done_read_r <= 1;
            $display("[%t] MM2S RTL: done_read asserted after TLAST acknowledged", $time);
        end else begin
            done_read_r <= 0;
        end
    end
end
assign done_read = done_read_r;

always @(posedge fclk) begin
    done_read_sync <= {done_read_sync[0], done_read};
end

always @(posedge fclk) begin
    if (rst) begin
        done_multiply <= 0;
    end else begin
        if (done_read_sync[1]) begin
            // axi finished reading out D
            done_multiply <= 0;
        end else  if (wr_addr_D_bram[N1-1] == M1xM3dN1-1) begin
            // systolic finished writing
            done_multiply <= 1;
        end
    end
end

always @(posedge clk) begin
    done_multiply_sync <= {done_multiply_sync[0], done_multiply};
end

always @(posedge clk) begin
    if (rst) begin
        done_multiply_sync_wait <= 0;
    end else begin
        if (out_tready) begin
            if (done_read) begin
                done_multiply_sync_wait <= 1;
            end else if (~done_multiply_sync[1]) begin
                done_multiply_sync_wait <= 0;
            end
        end
    end
end

// Hex dump file for cycle-by-cycle analysis
integer hex_file;
initial begin
    hex_file = $fopen("mm2s_state_dump.hex", "w");
    $fwrite(hex_file, "# MM2S State Dump - Cycle by Cycle\n");
    $fwrite(hex_file, "# Format: time,clk,rst,out_tready,start_read,done_read,addr_count,valid_D,rd_addr_D,activate_D,reg_rd_last_D,rd_data_bram_last,reg_banked_last_D[1],reg_banked_last_D[0],m_axis_mm2s_tvalid,m_axis_mm2s_tlast,m_axis_mm2s_tready,rd_addr_D_valid,reg_rd_addr_D_valid,rd_data_bram_valid\n");
end

always @(posedge clk) begin
    if (!rst) begin
        $fwrite(hex_file, "%0d,%b,%b,%b,%b,%b,%0d,%b,%0d,%h,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b\n",
                $time,
                clk,
                rst,
                out_tready,
                start_read,
                done_read,
                addr_count,
                (out_tready & start_read),
                rd_addr_D,
                activate_D,
                reg_rd_last_D,
                rd_data_bram_last,
                reg_banked_last_D[1],
                reg_banked_last_D[0],
                m_axis_mm2s_tvalid,
                m_axis_mm2s_tlast,
                m_axis_mm2s_tready,
                rd_addr_D_valid,
                reg_rd_addr_D_valid,
                rd_data_bram_valid);
    end
end

final begin
    $fclose(hex_file);
end

// ========== COMPREHENSIVE DIAGNOSTIC LOGGING ==========

// Counter for valid address generations
reg [MATRIXSIZE_W-1:0] valid_addr_count = 0;
reg [MATRIXSIZE_W-1:0] output_beat_count = 0;

// Track valid address generation
always @(posedge clk) begin
    if (rst || !start_read) begin
        valid_addr_count <= 0;
    end else if (out_tready && start_read && !done_read && (activate_D != 0)) begin
        valid_addr_count <= valid_addr_count + 1;
        $display("[%t] MM2S ADDR_GEN: Valid address #%d generated | addr=%d activate_D=0x%h bank_active=%b",
                 $time, valid_addr_count + 1, rd_addr_D, activate_D,
                 (activate_D == 2'b01) ? 0 : (activate_D == 2'b10) ? 1 : -1);
    end else if (out_tready && start_read && !done_read && (activate_D == 0)) begin
        $display("[%t] MM2S ADDR_GEN: WARNING! activate_D is 0 at addr_count=%d (no bank active)",
                 $time, addr_count);
    end
end

// Track output beats
always @(posedge clk) begin
    if (rst) begin
        output_beat_count <= 0;
    end else if (m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
        output_beat_count <= output_beat_count + 1;
        $display("[%t] MM2S OUTPUT: Beat #%d output | data=0x%h tlast=%b (expected total: %d)",
                 $time, output_beat_count + 1, m_axis_mm2s_tdata, m_axis_mm2s_tlast, M1xM3dN1 * N1);
    end
end

// Track pipeline stages status
always @(posedge clk) begin
    if (!rst && out_tready && start_read) begin
        $display("[%t] MM2S PIPELINE: addr_count=%d | rd_addr_D_valid=%b reg_rd_addr_D_valid=%b rd_data_bram_valid=%b | bank[1]_valid=%b bank[0]_valid=%b",
                 $time, addr_count, rd_addr_D_valid, reg_rd_addr_D_valid, rd_data_bram_valid,
                 reg_banked_valid_D[1], reg_banked_valid_D[0]);
    end
end

// Track when activate_D changes
reg [N1-1:0] prev_activate_D = 0;
always @(posedge clk) begin
    if (!rst) begin
        prev_activate_D <= activate_D;
        if (activate_D != prev_activate_D) begin
            $display("[%t] MM2S ACTIVATE: activate_D changed from 0x%h to 0x%h | addr_count=%d rd_addr_D=%d",
                     $time, prev_activate_D, activate_D, addr_count, rd_addr_D);
            if (activate_D == 0 && start_read) begin
                $display("[%t] MM2S ACTIVATE: ERROR! activate_D went to 0 while start_read=1", $time);
            end
        end
    end
end

// Debug counter increment (simplified)
always @(posedge clk) begin
    if (!rst && out_tready) begin
        if (start_read) begin
            $display("[%t] MM2S CONTROL: out_tready=%b start_read=%b done_read=%b addr_count=%d valid_addr_gen=%b",
                     $time, out_tready, start_read, done_read, addr_count, (out_tready & start_read && !done_read));
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        start_read <= 0;
        rd_addr_D_valid <= 0;
        reg_rd_addr_D_valid <= 0;
        rd_data_bram_valid <= 0;
        reg_rd_last_D <= 0;
        rd_data_bram_last <= 0;
        addr_count <= 0;
    end else begin
        // Clear pipeline valid signals when done_read asserts to prevent garbage outputs
        if (done_read) begin
            rd_addr_D_valid <= 0;
            reg_rd_addr_D_valid <= 0;
            rd_data_bram_valid <= 0;
            start_read <= 0;
            $display("[%t] MM2S RTL: Clearing pipeline valid signals due to done_read", $time);
        end else if (out_tready) begin
            start_read <= done_multiply_sync[1];
            // Keep start_read active until the entire pipeline has drained (after tlast is output)
            if (done_multiply_sync_wait) begin
                start_read <= 0;
            end

            // addr_count increments with each address generation
            // The TB shows addr_count AFTER it's been incremented from previous cycle
            // So when TB shows addr_count=7, that means 7 addresses have been issued
            // We want tlast on address #8, which means when addr_count will become 8
            // Check when addr_count is currently 7 (meaning 7 addresses issued, about to issue #8)

            // Generate tlast marker when we're about to issue the 8th address
            // addr_count shows how many addresses have ALREADY been issued in previous cycles
            // When addr_count==6, we've issued 6 in previous cycles, so THIS cycle is #7
            // NO WAIT - when addr_count==7, we're CURRENTLY issuing #7 (the 7th address)
            // So we want tlast on #8, which means when addr_count==7 and we're about to go to 8
            // Actually from debug: at 5513ns addr_count=7 is during issue of address #7
            // So we want the check when addr_count==M1xM3dN1-2 (which is 6)
            // When addr_count=6, the NEXT increment will make it 7, and we're issuing address #7
            // CORRECTED LOGIC:
            // The total number of output beats = M1 * M3 (one per result element)
            // With banking N1, we have: M1xM3dN1 = (M1 * M3) / N1
            // Therefore: Total beats = M1xM3dN1 * N1
            // For M1=4, M3=4, N1=2: Total beats = 8 * 2 = 16
            // The TLAST should appear on the LAST beat (beat #16)
            // Set TLAST when addr_count equals the total number of beats
            // At addr_count=N, we're generating the Nth valid address
            // So at addr_count=16, we're generating valid address #16 (the last one)
            if ((out_tready & start_read) && !done_read && (addr_count == (M1xM3dN1 * N1))) begin
                reg_rd_last_D <= 1;
                $display("[%t] MM2S RTL: TLAST MARKER! addr_count=%d, generating last address #%d (addr=%d, bank=0x%h)",
                         $time, addr_count, addr_count, rd_addr_D, activate_D);
            end else begin
                reg_rd_last_D <= 0;
            end

            rd_data_bram_last <= reg_rd_last_D;

            // Increment address counter after checking
            if ((out_tready & start_read) && !done_read) begin
                addr_count <= addr_count + 1;
            end else if (!start_read) begin
                addr_count <= 0;
            end

            rd_addr_D_valid <= start_read;
            reg_rd_addr_D_valid <= rd_addr_D_valid;
            rd_data_bram_valid <= reg_rd_addr_D_valid;

            if (rd_data_bram_last) begin
                $display("[%t] MM2S RTL: tlast marker reached BRAM output stage", $time);
            end
        end
    end
end

// AXI-Stream output assignments
// tlast is pipelined alongside data - when the last data value reaches output, tlast arrives with it
assign m_axis_mm2s_tdata = reg_banked_data_D[0];
assign m_axis_mm2s_tvalid = reg_banked_valid_D[0];
assign m_axis_mm2s_tlast = reg_banked_last_D[0];

// Debug: Monitor tlast reaching output
always @(posedge clk) begin
    if (reg_banked_last_D[0] && reg_banked_valid_D[0]) begin
        $display("[%t] MM2S RTL: tlast asserted at output (tdata=0x%h, tvalid=%b, tready=%b)",
                 $time, reg_banked_data_D[0], reg_banked_valid_D[0], m_axis_mm2s_tready);
    end
end

mem_write_D #(
    .D_W          ( D_W_ACC      ),
    .N1           ( N1           ),
    .MATRIXSIZE_W ( MATRIXSIZE_W ),
    .ADDR_W       ( ADDR_W_D     )
)
mem_write_D (
    .clk          ( fclk                ),
    .rst          ( rst                 ),
    .M1xM3dN1     ( M1xM3dN1            ),
    .in_valid     ( valid_D             ),
    .in_data      ( data_D              ),
    .wr_addr_bram ( wr_addr_D_bram      ),
    .wr_data_bram ( wr_data_D_bram      ),
    .wr_en_bram   ( wr_en_D_bram        )
);

mem_read_D #(
    .N1           ( N1           ),
    .N2           ( N2           ),
    .MATRIXSIZE_W ( MATRIXSIZE_W ),
    .ADDR_W       ( ADDR_W_D     )
)
mem_read_D_inst (
    .clk        ( clk         ),
    .rst        ( rst | ~start_read ),
    .M3         ( M3          ),
    .M1dN1      ( M1dN1       ),
    .valid_D    ( out_tready & start_read ),
    .rd_addr_D  ( rd_addr_D   ),
    .activate_D ( activate_D  )
);

endmodule
