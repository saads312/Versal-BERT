`ifndef XIL_TIMING
`default_nettype none
`endif
`timescale 1ps / 1ps
import dims::*;

// out = req(gelu(X * W + W_bias))

module mm_gelu
#(
    parameter integer D_W           = 8,
    parameter integer D_W_ACC       = 32,
    parameter integer X_W           = 32,
    parameter integer Y_W           = 32,
    parameter integer LAYERS        = 12,
    parameter integer BATCHES       = 1,
    parameter integer N1            = 4,
    parameter integer N2            = 4,
    parameter integer MATRIXSIZE_W  = 16,
    parameter         BLOCKED_D     = 0,
    parameter integer P_B           = 1,
    parameter integer MEM_DEPTH_A   = 4096,
    parameter integer MEM_DEPTH_B   = 4096,
    parameter integer MEM_DEPTH_D   = 4096,
    parameter integer MAT_MEM_DEPTH = 6144,
    parameter integer REQ_MEM_DEPTH = 768
)
(
    input  wire                      clk,
    input  wire                      fclk,
    input  wire                      rst,

    input  wire signed [D_W-1:0]     s_axis_s2mm_tdata_A,
    input  wire                      s_axis_s2mm_tlast_A,
    output wire                      s_axis_s2mm_tready_A,
    input  wire                      s_axis_s2mm_tvalid_A,

    input  wire signed [X_W-1:0]     s_axis_s2mm_tdata_W,
    input  wire                      s_axis_s2mm_tlast_W,
    output wire                      s_axis_s2mm_tready_W,
    input  wire                      s_axis_s2mm_tvalid_W,

    input  wire signed [X_W-1:0]     s_axis_s2mm_tdata_W_bias,
    input  wire                      s_axis_s2mm_tlast_W_bias,
    output wire                      s_axis_s2mm_tready_W_bias,
    input  wire                      s_axis_s2mm_tvalid_W_bias,

    input  wire signed [X_W-1:0]     s_axis_s2mm_tdata_out_m,
    input  wire                      s_axis_s2mm_tlast_out_m,
    output wire                      s_axis_s2mm_tready_out_m,
    input  wire                      s_axis_s2mm_tvalid_out_m,

    input  wire signed [X_W-1:0]     s_axis_s2mm_tdata_out_e,
    input  wire                      s_axis_s2mm_tlast_out_e,
    output wire                      s_axis_s2mm_tready_out_e,
    input  wire                      s_axis_s2mm_tvalid_out_e,

    `ifdef READ_A
    output wire signed [D_W-1:0]     m_axis_mm2s_tdata_A,
    output wire                      m_axis_mm2s_tlast_A,
    input  wire                      m_axis_mm2s_tready_A,
    output wire                      m_axis_mm2s_tvalid_A,
    `endif

    output wire signed [D_W-1:0]     out_tdata,
    output wire                      out_tlast,
    input  wire                      out_tready,
    output wire                      out_tvalid,

    input  dimensions                mm_dimensions
);

wire signed [D_W_ACC-1:0] tdata_G;
wire tlast_G;
wire tready_G;
wire tvalid_G;

wire signed [D_W_ACC-1:0] tdata_W_bias;
wire tlast_W_bias;
wire tready_W_bias;
wire tvalid_W_bias;

wire signed [D_W_ACC-1:0] tdata_W_m = 1;
wire tlast_W_m = 1'b1;
wire tready_W_m;
wire tvalid_W_m = 1'b1;

wire [D_W-1:0] tdata_W_e = {D_W{1'b0}};
wire tlast_W_e = 1'b1;
wire tready_W_e;
wire tvalid_W_e = 1'b1;

wire signed [D_W_ACC-1:0] tdata_G_req;
wire tlast_G_req;
wire tready_G_req;
wire tvalid_G_req;

wire signed [D_W_ACC-1:0] tdata_gelu_out;
wire tlast_gelu_out;
wire tready_gelu_out;
wire tvalid_gelu_out;

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
`ifdef READ_A
mm_pp_res #(
`else
mm_pp #(
`endif
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .N1(N1),
    .N2(N2),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH_A(MEM_DEPTH_A),
    .MEM_DEPTH_B(MEM_DEPTH_B),
    .MEM_DEPTH_D(MEM_DEPTH_D),
    .BLOCKED_D(BLOCKED_D),
    .P_B(P_B),
    .TRANSPOSE_B(0)
)
mm_G (
    .mm_clk(clk),
    .mm_fclk(fclk),
    .mm_rst_n(~rst),

    .s_axis_s2mm_tdata_A(s_axis_s2mm_tdata_A),
    .s_axis_s2mm_tlast_A(s_axis_s2mm_tlast_A),
    .s_axis_s2mm_tready_A(s_axis_s2mm_tready_A),
    .s_axis_s2mm_tvalid_A(s_axis_s2mm_tvalid_A),

    .s_axis_s2mm_tdata_B(s_axis_s2mm_tdata_W),
    .s_axis_s2mm_tlast_B(s_axis_s2mm_tlast_W),
    .s_axis_s2mm_tready_B(s_axis_s2mm_tready_W),
    .s_axis_s2mm_tvalid_B(s_axis_s2mm_tvalid_W),

    `ifdef READ_A
    .m_axis_mm2s_tdata_A(m_axis_mm2s_tdata_A),
    .m_axis_mm2s_tlast_A(m_axis_mm2s_tlast_A),
    .m_axis_mm2s_tready_A(m_axis_mm2s_tready_A),
    .m_axis_mm2s_tvalid_A(m_axis_mm2s_tvalid_A),
    `endif

    .m_axis_mm2s_tdata(tdata_G),
    .m_axis_mm2s_tlast(tlast_G),
    .m_axis_mm2s_tready(tready_G),
    .m_axis_mm2s_tvalid(tvalid_G),

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
    .P_B(P_B),
    .TRANSPOSE_B(0)
)
mm_G (
    .mm_clk(clk),
    .mm_fclk(fclk),
    .mm_rst_n(~rst),

    .s_axis_s2mm_tdata_A(s_axis_s2mm_tdata_A),
    .s_axis_s2mm_tlast_A(s_axis_s2mm_tlast_A),
    .s_axis_s2mm_tready_A(s_axis_s2mm_tready_A),
    .s_axis_s2mm_tvalid_A(s_axis_s2mm_tvalid_A),

    .s_axis_s2mm_tdata_B(s_axis_s2mm_tdata_W),
    .s_axis_s2mm_tlast_B(s_axis_s2mm_tlast_W),
    .s_axis_s2mm_tready_B(s_axis_s2mm_tready_W),
    .s_axis_s2mm_tvalid_B(s_axis_s2mm_tvalid_W),

    .m_axis_mm2s_tdata(tdata_G),
    .m_axis_mm2s_tlast(tlast_G),
    .m_axis_mm2s_tready(tready_G),
    .m_axis_mm2s_tvalid(tvalid_G),

    .M2(mm_dimensions.M2),
    .M3(mm_dimensions.M3),
    .M1xM3dN1(mm_dimensions.M1xM3dN1),
    .M1dN1(mm_dimensions.M1dN1),
    .M3dN2(mm_dimensions.M3dN2),
    .M1xM3dN1xN2(mm_dimensions.M1xM3dN1xN2)
);
`endif

generate
    if (BLOCKED_D) begin: blocked_stream_vector_mem
        stream_vector_mem_blocked #(
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
            .DIM2(mm_dimensions.M3),
            .BLOCKS(mm_dimensions.BLOCKS),
            .BLOCK_WIDTH(mm_dimensions.BLOCK_WIDTH)
        );
    end else begin: simple_stream_vector_mem
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
    end
endgenerate

requant #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .OUT_BITS(D_W_ACC),
    .CLIP(0)
)
requant_G (
    .clk(clk),
    .rst(rst),

    .in_tdata(tdata_G),
    .in_tlast(tlast_G),
    .in_tready(tready_G),
    .in_tvalid(tvalid_G),

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

    .out_tdata(tdata_G_req),
    .out_tlast(tlast_G_req),
    .out_tready(tready_G_req),
    .out_tvalid(tvalid_G_req)
);

gelu_top #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .LAYERS(LAYERS),
    .BATCHES(BATCHES)
)
gelu_top_unit (
    .clk(clk),
    .rst(rst),

    .qin_tdata(tdata_G_req),
    .qin_tlast(tlast_G_req),
    .qin_tready(tready_G_req),
    .qin_tvalid(tvalid_G_req),

    .qout_tdata(tdata_gelu_out),
    .qout_tlast(tlast_gelu_out),
    .qout_tready(tready_gelu_out),
    .qout_tvalid(tvalid_gelu_out),

    .DIM1(mm_dimensions.M1),
    .DIM2(mm_dimensions.M3)
);

stream_scalar_mem #(
    .X_W(X_W),
    .Y_W(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W)
)
sca_mem_out_m (
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

stream_scalar_mem #(
    .X_W(X_W),
    .Y_W(D_W),
    .MATRIXSIZE_W(MATRIXSIZE_W)
)
sca_mem_out_e (
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

    .in_tdata(tdata_gelu_out),
    .in_tlast(tlast_gelu_out),
    .in_tready(tready_gelu_out),
    .in_tvalid(tvalid_gelu_out),

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
