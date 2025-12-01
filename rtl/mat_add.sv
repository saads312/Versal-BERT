`default_nettype none
`timescale 1ps / 1ps

module mat_add
#(
    parameter integer D_W     = 8,
    parameter integer OUT_BITS = 22
)
(
    input  wire clk,
    input  wire rst,

    input  wire signed [D_W-1:0]      in_tdata_R,
    input  wire                       in_tlast_R,
    output wire                       in_tready_R,
    input  wire                       in_tvalid_R,

    input  wire signed [D_W-1:0]      in_tdata_Y,
    input  wire                       in_tlast_Y,
    output wire                       in_tready_Y,
    input  wire                       in_tvalid_Y,

    output wire signed [OUT_BITS-1:0] out_tdata_Z,
    output wire                       out_tvalid_Z,
    input  wire                       out_tready_Z,
    output wire                       out_tlast_Z
);

localparam signed [D_W-1:0] UPPER_BOUND = (1 << (OUT_BITS - 1)) - 1;
localparam signed [D_W-1:0] LOWER_BOUND = - UPPER_BOUND - 1;

reg  signed [D_W-1:0] in_data_R_reg = 0;
reg  signed [D_W-1:0] in_data_Y_reg = 0;
reg  signed [D_W-1:0] out_data_Z_reg = 0;
wire signed [D_W-1:0] result;

reg in_tvalid_R_reg = 0;
reg in_tvalid_Y_reg = 0;
reg out_tvalid_Z_reg = 0;

reg in_tlast_R_reg = 0;
reg in_tlast_Y_reg = 0;
reg out_tlast_Z_reg = 0;

wire in_tvalid_s0;
wire in_tlast_s0;
wire in_tready_s0;
wire in_tready_s1;

assign out_tvalid_Z = out_tvalid_Z_reg;
assign out_tdata_Z = out_data_Z_reg;
assign out_tlast_Z = out_tlast_Z_reg;

// pass everyone once - src
assign in_tready_R = in_tready_s0 | ~in_tvalid_R_reg;
assign in_tready_Y = in_tready_s0 | ~in_tvalid_Y_reg;

// now need everyone - s0 stage
assign in_tvalid_s0 = in_tvalid_R_reg & in_tvalid_Y_reg;
assign in_tlast_s0 = in_tlast_R_reg & in_tlast_Y_reg;
assign in_tready_s0 = in_tready_s1 & in_tvalid_s0;

// output s1 stage
assign in_tready_s1 = out_tready_Z | ~out_tvalid_Z;

always @(posedge clk) begin
    if (rst) begin
        in_tvalid_R_reg <= 0;
        in_tvalid_Y_reg <= 0;
        in_tlast_R_reg <= 0;
        in_tlast_Y_reg <= 0;
        in_data_R_reg <= 0;
        in_data_Y_reg <= 0;
    end else begin
        if (in_tready_R) begin
            in_tvalid_R_reg <= in_tvalid_R;
            in_tlast_R_reg <= in_tlast_R;
            in_data_R_reg <= in_tdata_R;
        end

        if (in_tready_Y) begin
            in_tvalid_Y_reg <= in_tvalid_Y;
            in_tlast_Y_reg <= in_tlast_Y;
            in_data_Y_reg <= in_tdata_Y;
        end
    end
end

assign result = in_data_R_reg + in_data_Y_reg;

always @(posedge clk) begin
    if (rst) begin
        out_tvalid_Z_reg <= 0;
        out_tlast_Z_reg <= 0;
        out_data_Z_reg <= 0;
    end else begin
        if (in_tready_s1) begin
            out_tvalid_Z_reg <= in_tvalid_s0;
            out_tlast_Z_reg <= in_tlast_s0;
            out_data_Z_reg <= (result < LOWER_BOUND) ? LOWER_BOUND :
                              (result > UPPER_BOUND) ? UPPER_BOUND : result;
        end
    end
end

endmodule
