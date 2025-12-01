`timescale 1ps / 1ps

module mem_read
#(
    parameter integer D_W    = 8,
    parameter integer N      = 4,
    parameter integer ADDR_W = 12
)
(
    input  wire              clk,
    input  wire              rd_en,
    input  wire [ADDR_W-1:0] rd_addr,
    output wire [ADDR_W-1:0] rd_addr_bram [N-1:0],
    output wire [N-1:0]      rd_en_bram
);

assign rd_addr_bram[0] = rd_addr;
assign rd_en_bram[0]   = rd_en;

// Debug logging
reg prev_rd_en = 0;
always @(posedge clk) begin
    prev_rd_en <= rd_en;
    if (rd_en && !prev_rd_en) begin
        $display("[%t] MEM_READ: rd_en asserted, rd_addr=%d", $time, rd_addr);
    end
    if (!rd_en && prev_rd_en) begin
        $display("[%t] MEM_READ: rd_en deasserted", $time);
    end
end

reg [ADDR_W-1:0] rd_addr_bram_reg [N-1:0];
reg [N-1:0]      rd_en_bram_reg;

genvar x;
for (x = 1; x < N; x = x + 1) begin
    always @(posedge clk) begin
        rd_addr_bram_reg[x] <= rd_addr_bram[x-1];
        rd_en_bram_reg[x]   <= rd_en_bram[x-1];
    end
    assign rd_addr_bram[x] = rd_addr_bram_reg[x];
    assign rd_en_bram[x]   = rd_en_bram_reg[x];
end

endmodule
