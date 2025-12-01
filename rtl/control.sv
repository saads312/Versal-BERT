`timescale 1ps / 1ps

module control
#(
    parameter integer N1 = 4,
    parameter integer N2 = 4,
    parameter integer MATRIXSIZE_W = 16,
    parameter integer ADDR_W_A = 12,
    parameter integer ADDR_W_B = 12
)
(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [MATRIXSIZE_W-1:0] M2,
    input  wire [MATRIXSIZE_W-1:0] M1dN1,
    input  wire [MATRIXSIZE_W-1:0] M3dN2,
    input  wire [MATRIXSIZE_W-1:0] M1xM3dN1xN2,
    output wire [ADDR_W_A-1:0]     rd_addr_A,
    output wire [ADDR_W_B-1:0]     rd_addr_B,
    output wire [N2-1:0]           init [N1-1:0]
);

wire [MATRIXSIZE_W-1:0] pixel_cntr_A;
wire [MATRIXSIZE_W-1:0] slice_cntr_A;
wire [MATRIXSIZE_W-1:0] pixel_cntr_B;
wire [MATRIXSIZE_W-1:0] slice_cntr_B;

assign rd_addr_A = (slice_cntr_A * M2 + pixel_cntr_A);
assign rd_addr_B = (pixel_cntr_B * M2 + slice_cntr_B);

// Debug logging for addresses
reg [31:0] addr_cycle_count = 0;
always @(posedge clk) begin
    if (rst) begin
        addr_cycle_count <= 0;
    end else begin
        addr_cycle_count <= addr_cycle_count + 1;
        if (addr_cycle_count < 20) begin
            $display("[%t] CONTROL ADDR cycle %d: rd_addr_A=%d (slice=%d pix=%d) rd_addr_B=%d (slice=%d pix=%d)",
                     $time, addr_cycle_count, rd_addr_A, slice_cntr_A, pixel_cntr_A,
                     rd_addr_B, slice_cntr_B, pixel_cntr_B);
        end
    end
end

reg [MATRIXSIZE_W-1:0] e_patch_cntr = 1;
reg                    enable_row_count_A = 0;

always @(posedge clk) begin
    if (rst) begin
        e_patch_cntr       <= 1;
        enable_row_count_A <= 0;
    end else begin
        if (enable_row_count_A == 1'b1) begin
            enable_row_count_A <= 0;
        end else if (pixel_cntr_A == M2-2 && e_patch_cntr == M3dN2) begin
            e_patch_cntr <= 1;
            enable_row_count_A <= ~enable_row_count_A;
        end else if (pixel_cntr_A == M2-2) begin
            e_patch_cntr <= e_patch_cntr + 1;
        end
    end
end

reg [N1+N2-1:0] shift = 0;
reg [MATRIXSIZE_W-1:0] i_patch_cntr = 0;
reg prev_rst = 1;

integer r;
always @(posedge clk) begin
    if (rst) begin
        shift <= 0;
        i_patch_cntr <= 0;
        prev_rst <= 1;
    end else begin
        if (prev_rst) begin
            $display("[%t] CONTROL: Released from reset, starting address generation", $time);
        end
        prev_rst <= 0;

        if (pixel_cntr_A == M2-1 && i_patch_cntr < M1xM3dN1xN2) begin
            i_patch_cntr <= i_patch_cntr + 1;
            shift[0]     <= 1'b1;
            $display("[%t] CONTROL: Init pulse starting (i_patch_cntr=%d, shift=0x%h)",
                     $time, i_patch_cntr, {shift[N1+N2-1:1], 1'b1});
        end else begin
            shift[0] <= 0;
        end

        for (r = 1; r < N1+N2; r = r+1) begin
            shift[r] <= shift[r-1];
        end
    end
end

genvar i, j;
generate 
    for (i = 0; i < N1; i = i + 1) begin
        for (j = 0; j < N2; j = j + 1) begin
            assign init[i][j] = shift[i+j+1];
        end
    end
endgenerate

counter #(
    .MATRIXSIZE_W (MATRIXSIZE_W)
)
counter_A (
    .clk                (clk),
    .rst                (rst),
    .enable_pixel_count (1'b1),
    .enable_slice_count (enable_row_count_A),
    .WIDTH              (M2),
    .HEIGHT             (M1dN1),
    .pixel_cntr         (pixel_cntr_A),
    .slice_cntr         (slice_cntr_A)
);

counter #(
    .MATRIXSIZE_W (MATRIXSIZE_W)
)
counter_B (
    .clk                (clk),
    .rst                (rst),
    .enable_pixel_count (1'b1),
    .enable_slice_count (1'b1),
    .WIDTH              (M2),
    .HEIGHT             (M3dN2),
    .pixel_cntr         (slice_cntr_B),
    .slice_cntr         (pixel_cntr_B)
);

endmodule
