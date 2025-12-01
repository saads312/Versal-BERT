`timescale 1ps / 1ps

module mem_read_D
#(
    parameter integer N1           = 4,
    parameter integer N2           = 4,
    parameter integer MATRIXSIZE_W = 16,
    parameter integer ADDR_W       = 12
)
(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [MATRIXSIZE_W-1:0] M3,
    input  wire [MATRIXSIZE_W-1:0] M1dN1,
    input  wire                    valid_D,
    output wire [ADDR_W-1:0]       rd_addr_D,
    output wire [N1-1:0]           activate_D
);

reg [ADDR_W-1:0]       rd_addr_D_r = 0;
reg [N1-1:0]           activate_D_r = 0;
reg [N1-1:0]           activate_D_rr = 1;
reg [MATRIXSIZE_W-1:0] col = 0;
reg [$clog2(N1)-1:0]   sys_row = 0;
reg [MATRIXSIZE_W-1:0] offset = 0;
reg [MATRIXSIZE_W-1:0] phase = 0;
reg [$clog2(N2)-1:0]   mini_col = 0;
reg [MATRIXSIZE_W-1:0] mini_offset = 0;
reg                    done = 0;  // Signal to stop address generation

// Combinational signal to detect when we're generating the last address
// This is used to prevent activate rotation on the same cycle that done is set
wire is_last_address = (phase == M1dN1-1) && (sys_row == N1-1) && (col == M3-1);

assign rd_addr_D = rd_addr_D_r;
assign activate_D = activate_D_r;

// ========== MEM_READ_D DIAGNOSTIC LOGGING ==========
reg [31:0] addr_gen_count = 0;

always @(posedge clk) begin
    if (rst) begin
        col         <= 0;
        sys_row     <= 0;
        offset      <= 0;
        phase       <= 0;
        mini_col    <= 0;
        mini_offset <= 0;
        rd_addr_D_r <= 0;
        addr_gen_count <= 0;
        done        <= 0;
    end else if (valid_D && !done) begin  // Only process if not done
        addr_gen_count <= addr_gen_count + 1;

        $display("[%t] MEM_READ_D: Gen #%d | col=%d sys_row=%d phase=%d | addr=%d | mini_col=%d mini_offset=%d offset=%d",
                 $time, addr_gen_count + 1, col, sys_row, phase, rd_addr_D_r, mini_col, mini_offset, offset);

        // Check if this is the last address: last phase, last row, last column
        if ((phase == M1dN1-1) && (sys_row == N1-1) && (col == M3-1)) begin
            done <= 1;
            $display("[%t] MEM_READ_D:   -> DONE! Last address generated (phase=%d sys_row=%d col=%d)",
                     $time, phase, sys_row, col);
        end

        col <= col + 1;
        mini_col <= mini_col + 1;

        if (mini_col == N2-1) begin
            mini_col    <= 0;
            mini_offset <= mini_offset + N2;
            $display("[%t] MEM_READ_D:   -> mini_col wrapped, mini_offset: %d -> %d", $time, mini_offset, mini_offset + N2);
        end

        if (col == M3-1) begin
            $display("[%t] MEM_READ_D:   -> col wrapped at M3-1=%d, sys_row: %d -> %d", $time, M3-1, sys_row, sys_row + 1);
            col <= 0;
            mini_offset <= 0;
            sys_row <= sys_row + 1;
            if (sys_row == N1-1) begin
                $display("[%t] MEM_READ_D:   -> sys_row wrapped, phase: %d -> %d, offset: %d -> %d",
                         $time, phase, phase + 1, offset, offset + M3);
                sys_row <= 0;
                offset  <= offset + M3;
                phase   <= phase + 1;
                if (phase == M1dN1-1) begin
                    $display("[%t] MEM_READ_D:   -> PHASE WRAP: phase was at M1dN1-1=%d, stopping", $time, M1dN1-1);
                    // Don't wrap phase - we're done
                    // offset <= 0;
                    // phase  <= 0;
                end
            end
        end

        rd_addr_D_r <= (N2 - mini_col - 1) + mini_offset + offset;
    end
end

integer x;
always @(posedge clk) begin
    if (rst) begin
        activate_D_rr <= 1;      // [0,0,...,1]
        activate_D_r  <= 0;
    end else begin
        activate_D_r <= activate_D_rr;
        if (valid_D && !done && !is_last_address) begin  // Don't rotate after done OR on last address
            if (col == M3-1) begin
                $display("[%t] MEM_READ_D ACTIVATE: Rotating activate | col=M3-1 phase=%d M1dN1-1=%d | activate_D_rr before=0x%h",
                         $time, phase, M1dN1-1, activate_D_rr);

                if (phase == M1dN1-1) begin
                    $display("[%t] MEM_READ_D ACTIVATE: STOPPING! phase == M1dN1-1, setting activate_D_rr[0] to 0", $time);
                    activate_D_rr[0] <= 0;
                end else begin
                    activate_D_rr[0] <= activate_D_rr[N1-1];
                end

                for (x = 1; x < N1; x = x + 1) begin
                    activate_D_rr[x] <= activate_D_rr[x-1];
                end

                $display("[%t] MEM_READ_D ACTIVATE: After rotate: activate_D_rr=0x%h", $time,
                         {activate_D_rr[N1-1:1], (phase == M1dN1-1) ? 1'b0 : activate_D_rr[N1-1]});
            end
        end else if (done || is_last_address) begin
            $display("[%t] MEM_READ_D ACTIVATE: DONE/LAST - not rotating activate (activate_D_rr=0x%h, done=%b, is_last=%b)",
                     $time, activate_D_rr, done, is_last_address);
        end
    end
end

endmodule
