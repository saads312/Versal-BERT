`timescale 1ps / 1ps

module systolic
#(
    parameter integer D_W     = 8,      // operand data width
    parameter integer D_W_ACC = 32,     // accumulator data width
    parameter integer N1      = 8,
    parameter integer N2      = 4
)
(
    input  wire                      clk,
    input  wire                      rst,
    input  wire        [N2-1:0]      init [N1-1:0],
    input  wire signed [D_W-1:0]     A    [N1-1:0],
    input  wire signed [D_W-1:0]     B    [N2-1:0],
    output wire signed [D_W_ACC-1:0] D    [N1-1:0],
    output wire        [N1-1:0]      valid_D
);

wire signed [D_W-1:0]     a_wire     [N1-1:0][N2:0];
wire signed [D_W-1:0]     b_wire     [N1:0][N2-1:0];
wire signed [D_W_ACC-1:0] data_wire  [N1-1:0][N2:0];
wire        [N2:0]        valid_wire [N1-1:0];

reg  signed [D_W-1:0]     A_reg      [N1-1:0];
reg  signed [D_W-1:0]     B_reg      [N2-1:0];
reg         [N2-1:0]      init_reg   [N1-1:0];

integer x;
reg [31:0] systolic_cycle_count = 0;
reg prev_rst = 1;

always @(posedge clk) begin
    if (rst) begin
        for (x = 0; x < N1; x = x + 1) begin
            A_reg[x]    <= 0;
            init_reg[x] <= 0;
        end
        for (x = 0; x < N2; x = x + 1) begin
            B_reg[x] <= 0;
        end
        systolic_cycle_count <= 0;
        prev_rst <= 1;
    end else begin
        // Log when coming out of reset
        if (prev_rst) begin
            $display("[%t] SYSTOLIC: Released from reset, starting computation", $time);
        end
        prev_rst <= 0;

        systolic_cycle_count <= systolic_cycle_count + 1;

        for (x = 0; x < N1; x = x + 1) begin
            A_reg[x]    <= A[x];
            init_reg[x] <= init[x];
        end
        for (x = 0; x < N2; x = x + 1) begin
            B_reg[x] <= B[x];
        end

        // Log first few cycles with data
        if (systolic_cycle_count < 10 || (A[0] != 0 || A[1] != 0 || B[0] != 0 || B[1] != 0)) begin
            $display("[%t] SYSTOLIC cycle %d: A[0]=%d A[1]=%d | B[0]=%d B[1]=%d | init[0]=0x%h init[1]=0x%h",
                     $time, systolic_cycle_count, $signed(A[0]), $signed(A[1]),
                     $signed(B[0]), $signed(B[1]), init[0], init[1]);
        end
    end
end

genvar i, j;
generate
    `ifdef DSP_HPACK
    for (i = 0; i < N1; i = i + 1) begin
        assign data_wire[i][0]  = {D_W{1'b0}};
        assign valid_wire[i][0] = 1'b0;

        for (j = 0; j < N2; j = j + 2) begin
            pe_hp #(
                .D_W     (D_W),
                .D_W_ACC (D_W_ACC)
            )
            pe_inst (
                .clk        (clk),
                .rst        (rst),
                .init       (init_reg[i][j]),
                .in_a       (j == 0 ? A_reg[i] : a_wire[i][j]),
                .in_b1      (i == 0 ? B_reg[j] : b_wire[i][j]),
                .in_b2      (i == 0 ? B_reg[j+1] : b_wire[i][j+1]),
                .in_data    (data_wire[i][j]),
                .in_valid   (valid_wire[i][j]),
                .out_a      (a_wire[i][j+2]),
                .out_b1     (b_wire[i+1][j]),
                .out_b2     (b_wire[i+1][j+1]),
                .out_data   (data_wire[i][j+2]),
                .out_valid  (valid_wire[i][j+2])
            );
        end

        assign D[i]       = data_wire[i][N2];
        assign valid_D[i] = valid_wire[i][N2];
    end
    `elsif DSP_VPACK
    for (i = 0; i < N1; i = i + 2) begin
        assign data_wire[i][0]    = {D_W{1'b0}};
        assign valid_wire[i][0]   = 1'b0;
        assign data_wire[i+1][0]  = {D_W{1'b0}};
        assign valid_wire[i+1][0] = 1'b0;

        for (j = 0; j < N2; j = j + 1) begin
            pe_vp #(
                .D_W     (D_W),
                .D_W_ACC (D_W_ACC)
            )
            pe_inst (
                .clk        (clk),
                .rst        (rst),
                .init       (init_reg[i][j]),
                .in_a1      (j == 0 ? A_reg[i] : a_wire[i][j]),
                .in_a2      (j == 0 ? A_reg[i+1] : a_wire[i+1][j]),
                .in_b       (i == 0 ? B_reg[j] : b_wire[i][j]),
                .in_data1   (data_wire[i][j]),
                .in_valid1  (valid_wire[i][j]),
                .in_data2   (data_wire[i+1][j]),
                .in_valid2  (valid_wire[i+1][j]),
                .out_a1     (a_wire[i][j+1]),
                .out_a2     (a_wire[i+1][j+1]),
                .out_b      (b_wire[i+2][j]),
                .out_data1  (data_wire[i][j+1]),
                .out_valid1 (valid_wire[i][j+1]),
                .out_data2  (data_wire[i+1][j+1]),
                .out_valid2 (valid_wire[i+1][j+1])
            );
        end

        assign D[i]         = data_wire[i][N2];
        assign valid_D[i]   = valid_wire[i][N2];
        assign D[i+1]       = data_wire[i+1][N2];
        assign valid_D[i+1] = valid_wire[i+1][N2];
    end
    `else
    for (i = 0; i < N1; i = i + 1) begin
        assign data_wire[i][0]  = {D_W{1'b0}};
        assign valid_wire[i][0] = 1'b0;

        for (j = 0; j < N2; j = j + 1) begin
            pe #(
                .D_W     (D_W),
                .D_W_ACC (D_W_ACC)
            )
            pe_inst (
                .clk       (clk),
                .rst       (rst),
                .init      (init_reg[i][j]),
                .in_a      (j == 0 ? A_reg[i] : a_wire[i][j]),
                .in_b      (i == 0 ? B_reg[j] : b_wire[i][j]),
                .in_data   (data_wire[i][j]),
                .in_valid  (valid_wire[i][j]),
                .out_a     (a_wire[i][j+1]),
                .out_b     (b_wire[i+1][j]),
                .out_data  (data_wire[i][j+1]),
                .out_valid (valid_wire[i][j+1])
            );
        end

        assign D[i]       = data_wire[i][N2];
        assign valid_D[i] = valid_wire[i][N2];
    end
    `endif
endgenerate

// Log valid_D outputs
reg [N1-1:0] prev_valid_D = 0;
integer v;
always @(posedge clk) begin
    prev_valid_D <= valid_D;
    for (v = 0; v < N1; v = v + 1) begin
        if (valid_D[v] && !prev_valid_D[v]) begin
            $display("[%t] SYSTOLIC: valid_D[%d] asserted, D[%d]=0x%h (%d)",
                     $time, v, v, D[v], $signed(D[v]));
        end
    end
end

endmodule
