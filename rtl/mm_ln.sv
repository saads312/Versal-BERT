`ifndef XIL_TIMING
`default_nettype none
`endif
`timescale 1ps / 1ps
import dims::*;

// out = req(layer_norm(req(X * W + W_bias) + req(R)))

module mm_ln
#(
    parameter integer D_W           = 8,
    parameter integer D_W_ACC       = 32,
    parameter integer X_W           = 32,
    parameter integer Y_W           = 32,
    parameter integer LN_BITS       = 22,
    parameter integer N1            = 4,
    parameter integer N2            = 4,
    parameter integer P_B           = 1,
    parameter integer MATRIXSIZE_W  = 24,
    parameter         BLOCKED_A     = 0,
    parameter integer MEM_DEPTH_A   = 6144,
    parameter integer MEM_DEPTH_B   = 147456,
    parameter integer MEM_DEPTH_D   = 6144,
    parameter integer MAT_MEM_DEPTH = 6144,
    parameter integer REQ_MEM_DEPTH = 768
)
(
    input wire                      clk,
    input wire                      fclk,
    input wire                      rst,

    input  wire signed [D_W-1:0]    s_axis_s2mm_tdata_X,
    input  wire                     s_axis_s2mm_tlast_X,
    output wire                     s_axis_s2mm_tready_X,
    input  wire                     s_axis_s2mm_tvalid_X,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_W,
    input  wire                     s_axis_s2mm_tlast_W,
    output wire                     s_axis_s2mm_tready_W,
    input  wire                     s_axis_s2mm_tvalid_W,

    input  wire signed [D_W-1:0]    s_axis_s2mm_tdata_R,
    input  wire                     s_axis_s2mm_tlast_R,
    output wire                     s_axis_s2mm_tready_R,
    input  wire                     s_axis_s2mm_tvalid_R,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_W_bias,
    input  wire                     s_axis_s2mm_tlast_W_bias,
    output wire                     s_axis_s2mm_tready_W_bias,
    input  wire                     s_axis_s2mm_tvalid_W_bias,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_W_m,
    input  wire                     s_axis_s2mm_tlast_W_m,
    output wire                     s_axis_s2mm_tready_W_m,
    input  wire                     s_axis_s2mm_tvalid_W_m,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_W_e,
    input  wire                     s_axis_s2mm_tlast_W_e,
    output wire                     s_axis_s2mm_tready_W_e,
    input  wire                     s_axis_s2mm_tvalid_W_e,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_R_m,
    input  wire                     s_axis_s2mm_tlast_R_m,
    output wire                     s_axis_s2mm_tready_R_m,
    input  wire                     s_axis_s2mm_tvalid_R_m,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_R_e,
    input  wire                     s_axis_s2mm_tlast_R_e,
    output wire                     s_axis_s2mm_tready_R_e,
    input  wire                     s_axis_s2mm_tvalid_R_e,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_ln_bias,
    input  wire                     s_axis_s2mm_tlast_ln_bias,
    output wire                     s_axis_s2mm_tready_ln_bias,
    input  wire                     s_axis_s2mm_tvalid_ln_bias,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_out_m,
    input  wire                     s_axis_s2mm_tlast_out_m,
    output wire                     s_axis_s2mm_tready_out_m,
    input  wire                     s_axis_s2mm_tvalid_out_m,

    input  wire signed [X_W-1:0]    s_axis_s2mm_tdata_out_e,
    input  wire                     s_axis_s2mm_tlast_out_e,
    output wire                     s_axis_s2mm_tready_out_e,
    input  wire                     s_axis_s2mm_tvalid_out_e,

    output wire signed [D_W-1:0]    out_tdata,
    output wire                     out_tlast,
    input  wire                     out_tready,
    output wire                     out_tvalid,

    input  dimensions               mm_dimensions
);

wire signed [D_W_ACC-1:0] tdata_Y;
wire tlast_Y;
wire tready_Y;
wire tvalid_Y;

wire signed [D_W_ACC-1:0] tdata_R;
wire tlast_R;
wire tready_R;
wire tvalid_R;

wire signed [D_W_ACC-1:0] tdata_W_bias;
wire tlast_W_bias;
wire tready_W_bias;
wire tvalid_W_bias;

wire signed [D_W_ACC-1:0] tdata_W_m;
wire tlast_W_m;
wire tready_W_m;
wire tvalid_W_m;

wire [D_W-1:0] tdata_W_e;
wire tlast_W_e;
wire tready_W_e;
wire tvalid_W_e;

wire signed [D_W_ACC-1:0] tdata_R_bias = {D_W_ACC{1'b0}};
wire tlast_R_bias = 1'b1;
wire tready_R_bias;
wire tvalid_R_bias = 1'b1;

wire signed [D_W_ACC-1:0] tdata_R_m;
wire tlast_R_m;
wire tready_R_m;
wire tvalid_R_m;

wire [D_W-1:0] tdata_R_e;
wire tlast_R_e;
wire tready_R_e;
wire tvalid_R_e;

wire signed [D_W_ACC-1:0] tdata_Y_req;
wire tlast_Y_req;
wire tready_Y_req;
wire tvalid_Y_req;

wire signed [D_W_ACC-1:0] tdata_R_req;
wire tlast_R_req;
wire tready_R_req;
wire tvalid_R_req;

wire signed [LN_BITS-1:0] tdata_Z;
wire tlast_Z;
wire tready_Z;
wire tvalid_Z;

wire signed [D_W_ACC-1:0] tdata_ln_out;
wire tlast_ln_out;
wire tready_ln_out;
wire tvalid_ln_out;

wire [D_W_ACC-1:0] tdata_out_bias = {D_W_ACC{1'b0}};
wire tlast_out_bias = 1'b1;
wire tready_out_bias;
wire tvalid_out_bias = 1'b1;

wire [D_W_ACC-1:0] tdata_out_m;
wire tlast_out_m;
wire tready_out_m;
wire tvalid_out_m;

wire [D_W-1:0] tdata_out_e;
wire tlast_out_e;
wire tready_out_e;
wire tvalid_out_e;

wire signed [D_W-1:0] tdata_out_req;
wire tlast_out_req;
wire tready_out_req;
wire tvalid_out_req;

`ifdef PING_PONG
generate
    if (BLOCKED_A) begin: mm_Y_blocked_A
        mm_pp_blocked_A #(
            .D_W(D_W),
            .D_W_ACC(D_W_ACC),
            .N1(N1),
            .N2(N2),
            .MATRIXSIZE_W(MATRIXSIZE_W),
            .MEM_DEPTH_A(MEM_DEPTH_A),
            .MEM_DEPTH_B(MEM_DEPTH_B),
            .MEM_DEPTH_D(MEM_DEPTH_D),
            .P_B(P_B),
            .TRANSPOSE_B(0)
        )
        mm_Y (
            .mm_clk(clk),
            .mm_fclk(clk),
            .mm_rst_n(~rst),

            .s_axis_s2mm_tdata_A(s_axis_s2mm_tdata_X),
            .s_axis_s2mm_tlast_A(s_axis_s2mm_tlast_X),
            .s_axis_s2mm_tready_A(s_axis_s2mm_tready_X),
            .s_axis_s2mm_tvalid_A(s_axis_s2mm_tvalid_X),

            .s_axis_s2mm_tdata_B(s_axis_s2mm_tdata_W),
            .s_axis_s2mm_tlast_B(s_axis_s2mm_tlast_W),
            .s_axis_s2mm_tready_B(s_axis_s2mm_tready_W),
            .s_axis_s2mm_tvalid_B(s_axis_s2mm_tvalid_W),

            .m_axis_mm2s_tdata(tdata_Y),
            .m_axis_mm2s_tlast(tlast_Y),
            .m_axis_mm2s_tready(tready_Y),
            .m_axis_mm2s_tvalid(tvalid_Y),

            .BLOCKS(mm_dimensions.BLOCKS),
            .BLOCK_WIDTH(mm_dimensions.BLOCK_WIDTH),
            .BLOCK_WIDTHdN2(mm_dimensions.BLOCK_WIDTHdN2),
            .BLOCK_SIZEdN2(mm_dimensions.BLOCK_SIZEdN2),
            .M1xBLOCK_WIDTHdN1xN2(mm_dimensions.M1xBLOCK_WIDTHdN1xN2),
            .M1xBLOCK_WIDTHdN1(mm_dimensions.M1xBLOCK_WIDTHdN1),
            .BLOCKS_A(mm_dimensions.BLOCKS_A),
            .BLOCK_WIDTH_A(mm_dimensions.BLOCK_WIDTH_A),
            .M2(mm_dimensions.M2),
            .M3dN2(mm_dimensions.M3dN2),
            .M1xM3dN1(mm_dimensions.M1xM3dN1),
            .M1dN1(mm_dimensions.M1dN1)
        );
    end else begin: mm_Y_simple
        mm_pp #(
            .D_W(D_W),
            .D_W_ACC(D_W_ACC),
            .N1(N1),
            .N2(N2),
            .MATRIXSIZE_W(MATRIXSIZE_W),
            .MEM_DEPTH_A(MEM_DEPTH_A),
            .MEM_DEPTH_B(MEM_DEPTH_B),
            .MEM_DEPTH_D(MEM_DEPTH_D),
            .P_B(P_B),
            .TRANSPOSE_B(0)
        )
        mm_Y (
            .mm_clk(clk),
            .mm_fclk(clk),
            .mm_rst_n(~rst),

            .s_axis_s2mm_tdata_A(s_axis_s2mm_tdata_X),
            .s_axis_s2mm_tlast_A(s_axis_s2mm_tlast_X),
            .s_axis_s2mm_tready_A(s_axis_s2mm_tready_X),
            .s_axis_s2mm_tvalid_A(s_axis_s2mm_tvalid_X),

            .s_axis_s2mm_tdata_B(s_axis_s2mm_tdata_W),
            .s_axis_s2mm_tlast_B(s_axis_s2mm_tlast_W),
            .s_axis_s2mm_tready_B(s_axis_s2mm_tready_W),
            .s_axis_s2mm_tvalid_B(s_axis_s2mm_tvalid_W),

            .m_axis_mm2s_tdata(tdata_Y),
            .m_axis_mm2s_tlast(tlast_Y),
            .m_axis_mm2s_tready(tready_Y),
            .m_axis_mm2s_tvalid(tvalid_Y),

            .BLOCKS(mm_dimensions.BLOCKS),
            .BLOCK_WIDTH(mm_dimensions.BLOCK_WIDTH),
            .BLOCK_WIDTHdN2(mm_dimensions.BLOCK_WIDTHdN2),
            .BLOCK_SIZEdN2(mm_dimensions.BLOCK_SIZEdN2),
            .M1xBLOCK_WIDTHdN1xN2(mm_dimensions.M1xBLOCK_WIDTHdN1xN2),
            .M1xBLOCK_WIDTHdN1(mm_dimensions.M1xBLOCK_WIDTHdN1),
            .M2(mm_dimensions.M2),
            .M3dN2(mm_dimensions.M3dN2),
            .M1xM3dN1(mm_dimensions.M1xM3dN1),
            .M1dN1(mm_dimensions.M1dN1)
        );
    end
endgenerate
`else
mm #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .N1(N1),
    .N2(N2),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH_A(MEM_DEPTH_A),
    .MEM_DEPTH_B(MEM_DEPTH_B),
    .MEM_DEPTH_D(MEM_DEPTH_D),
    .TRANSPOSE_B(0)
)
mm_Y (
    .mm_clk(clk),
    .mm_fclk(fclk),
    .mm_rst_n(~rst),

    .s_axis_s2mm_tdata_A(s_axis_s2mm_tdata_X),
    .s_axis_s2mm_tlast_A(s_axis_s2mm_tlast_X),
    .s_axis_s2mm_tready_A(s_axis_s2mm_tready_X),
    .s_axis_s2mm_tvalid_A(s_axis_s2mm_tvalid_X),

    .s_axis_s2mm_tdata_B(s_axis_s2mm_tdata_W),
    .s_axis_s2mm_tlast_B(s_axis_s2mm_tlast_W),
    .s_axis_s2mm_tready_B(s_axis_s2mm_tready_W),
    .s_axis_s2mm_tvalid_B(s_axis_s2mm_tvalid_W),

    .m_axis_mm2s_tdata(tdata_Y),
    .m_axis_mm2s_tlast(tlast_Y),
    .m_axis_mm2s_tready(tready_Y),
    .m_axis_mm2s_tvalid(tvalid_Y),

    .M2(mm_dimensions.M2),
    .M3(mm_dimensions.M3),
    .M1xM3dN1(mm_dimensions.M1xM3dN1),
    .M1dN1(mm_dimensions.M1dN1),
    .M3dN2(mm_dimensions.M3dN2),
    .M1xM3dN1xN2(mm_dimensions.M1xM3dN1xN2)
);
`endif

stream_vector_mem #(
    .X_W(X_W),
    .Y_W(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(REQ_MEM_DEPTH)
)
vec_mem_W_bias (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_W_bias),
    .in_tlast(s_axis_s2mm_tlast_W_bias),
    .in_tready(s_axis_s2mm_tready_W_bias),
    .in_tvalid(s_axis_s2mm_tvalid_W_bias),

    .out_tdata(tdata_W_bias),
    .out_tlast(tlast_W_bias),
    .out_tready(tready_W_bias),
    .out_tvalid(tvalid_W_bias),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

stream_vector_mem #(
    .X_W(X_W),
    .Y_W(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(REQ_MEM_DEPTH)
)
vec_mem_W_m (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_W_m),
    .in_tlast(s_axis_s2mm_tlast_W_m),
    .in_tready(s_axis_s2mm_tready_W_m),
    .in_tvalid(s_axis_s2mm_tvalid_W_m),

    .out_tdata(tdata_W_m),
    .out_tlast(tlast_W_m),
    .out_tready(tready_W_m),
    .out_tvalid(tvalid_W_m),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

stream_vector_mem #(
    .X_W(X_W),
    .Y_W(D_W),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(REQ_MEM_DEPTH)
)
vec_mem_W_e (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_W_e),
    .in_tlast(s_axis_s2mm_tlast_W_e),
    .in_tready(s_axis_s2mm_tready_W_e),
    .in_tvalid(s_axis_s2mm_tvalid_W_e),

    .out_tdata(tdata_W_e),
    .out_tlast(tlast_W_e),
    .out_tready(tready_W_e),
    .out_tvalid(tvalid_W_e),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

requant #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .OUT_BITS(D_W_ACC),
    .CLIP(0)
)
requant_Y (
    .clk(clk),
    .rst(rst),

    .in_tdata(tdata_Y),
    .in_tlast(tlast_Y),
    .in_tready(tready_Y),
    .in_tvalid(tvalid_Y),

    .in_tdata_bias(tdata_W_bias),
    .in_tlast_bias(tlast_W_bias),
    .in_tready_bias(tready_W_bias),
    .in_tvalid_bias(tvalid_W_bias),

    .in_tdata_m(tdata_W_m),
    .in_tlast_m(tlast_W_m),
    .in_tready_m(tready_W_m),
    .in_tvalid_m(tvalid_W_m),

    .in_tdata_e(tdata_W_e),
    .in_tlast_e(tlast_W_e),
    .in_tready_e(tready_W_e),
    .in_tvalid_e(tvalid_W_e),

    .out_tdata(tdata_Y_req),
    .out_tlast(tlast_Y_req),
    .out_tready(tready_Y_req),
    .out_tvalid(tvalid_Y_req)
);

`ifdef RES_MEM
stream_matrix_mem #(
    .X_W(D_W),
    .Y_W(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(MAT_MEM_DEPTH)
)
mat_mem_R (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_R),
    .in_tlast(s_axis_s2mm_tlast_R),
    .in_tready(s_axis_s2mm_tready_R),
    .in_tvalid(s_axis_s2mm_tvalid_R),

    .out_tdata(tdata_R),
    .out_tlast(tlast_R),
    .out_tready(tready_R),
    .out_tvalid(tvalid_R),

    .DEPTH(mm_dimensions.M1xM3)
);
`else
assign tdata_R = s_axis_s2mm_tdata_R;
assign tlast_R = s_axis_s2mm_tlast_R;
assign tvalid_R = s_axis_s2mm_tvalid_R;
assign s_axis_s2mm_tready_R = tready_R;
`endif

stream_scalar_mem #(
    .X_W(X_W),
    .Y_W(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W)
)
sca_mem_R_m (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_R_m),
    .in_tlast(s_axis_s2mm_tlast_R_m),
    .in_tready(s_axis_s2mm_tready_R_m),
    .in_tvalid(s_axis_s2mm_tvalid_R_m),

    .out_tdata(tdata_R_m),
    .out_tlast(tlast_R_m),
    .out_tready(tready_R_m),
    .out_tvalid(tvalid_R_m),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

stream_scalar_mem #(
    .X_W(X_W),
    .Y_W(D_W),
    .MATRIXSIZE_W(MATRIXSIZE_W)
)
sca_mem_R_e (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_R_e),
    .in_tlast(s_axis_s2mm_tlast_R_e),
    .in_tready(s_axis_s2mm_tready_R_e),
    .in_tvalid(s_axis_s2mm_tvalid_R_e),

    .out_tdata(tdata_R_e),
    .out_tlast(tlast_R_e),
    .out_tready(tready_R_e),
    .out_tvalid(tvalid_R_e),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

requant #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .OUT_BITS(D_W_ACC),
    .CLIP(0)
)
requant_R (
    .clk(clk),
    .rst(rst),

    .in_tdata(tdata_R),
    .in_tlast(tlast_R),
    .in_tready(tready_R),
    .in_tvalid(tvalid_R),

    .in_tdata_bias(tdata_R_bias),
    .in_tlast_bias(tlast_R_bias),
    .in_tready_bias(tready_R_bias),
    .in_tvalid_bias(tvalid_R_bias),

    .in_tdata_m(tdata_R_m),
    .in_tlast_m(tlast_R_m),
    .in_tready_m(tready_R_m),
    .in_tvalid_m(tvalid_R_m),

    .in_tdata_e(tdata_R_e),
    .in_tlast_e(tlast_R_e),
    .in_tready_e(tready_R_e),
    .in_tvalid_e(tvalid_R_e),

    .out_tdata(tdata_R_req),
    .out_tlast(tlast_R_req),
    .out_tready(tready_R_req),
    .out_tvalid(tvalid_R_req)
);

mat_add #(
    .D_W(D_W_ACC),
    .OUT_BITS(LN_BITS)
)
mat_add_Z (
    .clk(clk),
    .rst(rst),

    .in_tdata_R(tdata_R_req),
    .in_tlast_R(tlast_R_req),
    .in_tready_R(tready_R_req),
    .in_tvalid_R(tvalid_R_req),

    .in_tdata_Y(tdata_Y_req),
    .in_tlast_Y(tlast_Y_req),
    .in_tready_Y(tready_Y_req),
    .in_tvalid_Y(tvalid_Y_req),

    .out_tdata_Z(tdata_Z),
    .out_tlast_Z(tlast_Z),
    .out_tready_Z(tready_Z),
    .out_tvalid_Z(tvalid_Z)
);

layer_norm_top #(
    .X_W(X_W),
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .LN_BITS(LN_BITS),
    .MATRIXSIZE_W(MATRIXSIZE_W)
)
layer_norm_top_unit (
    .clk(clk),
    .rst(rst),

    .s_axis_s2mm_tdata_bias(s_axis_s2mm_tdata_ln_bias),
    .s_axis_s2mm_tlast_bias(s_axis_s2mm_tlast_ln_bias),
    .s_axis_s2mm_tready_bias(s_axis_s2mm_tready_ln_bias),
    .s_axis_s2mm_tvalid_bias(s_axis_s2mm_tvalid_ln_bias),

    .qin_tdata(tdata_Z),
    .qin_tlast(tlast_Z),
    .qin_tready(tready_Z),
    .qin_tvalid(tvalid_Z),

    .qout_tdata(tdata_ln_out),
    .qout_tlast(tlast_ln_out),
    .qout_tready(tready_ln_out),
    .qout_tvalid(tvalid_ln_out),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

stream_vector_mem #(
    .X_W(X_W),
    .Y_W(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(REQ_MEM_DEPTH)
)
vec_mem_out_m (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_out_m),
    .in_tlast(s_axis_s2mm_tlast_out_m),
    .in_tready(s_axis_s2mm_tready_out_m),
    .in_tvalid(s_axis_s2mm_tvalid_out_m),

    .out_tdata(tdata_out_m),
    .out_tlast(tlast_out_m),
    .out_tready(tready_out_m),
    .out_tvalid(tvalid_out_m),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

stream_vector_mem #(
    .X_W(X_W),
    .Y_W(D_W),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(REQ_MEM_DEPTH)
)
vec_mem_out_e (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_out_e),
    .in_tlast(s_axis_s2mm_tlast_out_e),
    .in_tready(s_axis_s2mm_tready_out_e),
    .in_tvalid(s_axis_s2mm_tvalid_out_e),

    .out_tdata(tdata_out_e),
    .out_tlast(tlast_out_e),
    .out_tready(tready_out_e),
    .out_tvalid(tvalid_out_e),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

requant #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .OUT_BITS(D_W),
    .CLIP(1)
)
requant_out (
    .clk(clk),
    .rst(rst),

    .in_tdata(tdata_ln_out),
    .in_tlast(tlast_ln_out),
    .in_tready(tready_ln_out),
    .in_tvalid(tvalid_ln_out),

    .in_tdata_bias(tdata_out_bias),
    .in_tlast_bias(tlast_out_bias),
    .in_tready_bias(tready_out_bias),
    .in_tvalid_bias(tvalid_out_bias),

    .in_tdata_m(tdata_out_m),
    .in_tlast_m(tlast_out_m),
    .in_tready_m(tready_out_m),
    .in_tvalid_m(tvalid_out_m),

    .in_tdata_e(tdata_out_e),
    .in_tlast_e(tlast_out_e),
    .in_tready_e(tready_out_e),
    .in_tvalid_e(tvalid_out_e),

    .out_tdata(tdata_out_req),
    .out_tlast(tlast_out_req),
    .out_tready(tready_out_req),
    .out_tvalid(tvalid_out_req)
);

`ifdef BUF_MEM
stream_matrix_mem #(
    .X_W(D_W),
    .Y_W(D_W),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(MAT_MEM_DEPTH)
)
mat_mem_out (
    .clk(clk),
    .rst(rst),

    .in_tdata(tdata_out_req),
    .in_tlast(tlast_out_req),
    .in_tready(tready_out_req),
    .in_tvalid(tvalid_out_req),

    .out_tdata(out_tdata),
    .out_tlast(out_tlast),
    .out_tready(out_tready),
    .out_tvalid(out_tvalid),

    .DEPTH(mm_dimensions.M1xM3)
);
`else
assign out_tdata = tdata_out_req;
assign out_tlast = tlast_out_req;
assign tready_out_req = out_tready;
assign out_tvalid = tvalid_out_req;
`endif

endmodule
