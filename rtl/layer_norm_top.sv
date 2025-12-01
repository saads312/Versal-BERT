`default_nettype none
`timescale 1ps / 1ps

module layer_norm_top
#(
    parameter integer X_W = 32,
    parameter integer D_W = 8,
    parameter integer D_W_ACC = 32,
    parameter integer LN_BITS = 22,
    parameter integer MATRIXSIZE_W = 24
)
(
    input  wire                       clk,
    input  wire                       rst,

    input  wire signed [X_W-1:0]      s_axis_s2mm_tdata_bias,
    input  wire                       s_axis_s2mm_tlast_bias,
    output wire                       s_axis_s2mm_tready_bias,
    input  wire                       s_axis_s2mm_tvalid_bias,

    input  wire signed [LN_BITS-1:0]  qin_tdata,
    input  wire                       qin_tlast,
    output wire                       qin_tready,
    input  wire                       qin_tvalid,

    output wire signed [D_W_ACC-1:0]  qout_tdata,
    output wire                       qout_tlast,
    input  wire                       qout_tready,
    output wire                       qout_tvalid,

    input  wire [MATRIXSIZE_W-1:0]    DIM1,
    input  wire [MATRIXSIZE_W-1:0]    DIM2
);

localparam integer               N        = 768;
localparam [D_W_ACC-1:0]         N_INV    = 1398101;
localparam integer               FP_BITS  = 30;
localparam integer               MAX_BITS = 31;
localparam [$clog2(LN_BITS)-1:0] SHIFT    = 6;
localparam integer               ADDR_W   = $clog2(N);

wire [MATRIXSIZE_W-1:0] qout_col_cntr;
wire [MATRIXSIZE_W-1:0] qout_row_cntr;

wire signed [D_W_ACC-1:0] ln_bias_tdata;
wire ln_bias_tlast;
wire ln_bias_tready;
wire ln_bias_tvalid;

reg signed [LN_BITS-1:0] qin_tdata_reg;
reg signed [D_W_ACC-1:0] ln_bias_tdata_reg;

reg qin_tvalid_reg = 0;
reg ln_bias_tvalid_reg = 0;

wire in_tvalid_s0;
wire in_tready_s0;
wire in_tready_s1;

assign qout_tlast = (qout_row_cntr == DIM1-1) && (qout_col_cntr == DIM2-1);

// register everyone at least once when in_tready_s0 is low
assign qin_tready = in_tready_s0 | ~qin_tvalid_reg;
assign ln_bias_tready = in_tready_s0 | ~ln_bias_tvalid_reg;

// now I need everyone to be valid after first pass
assign in_tvalid_s0 = qin_tvalid_reg & ln_bias_tvalid_reg;
assign in_tready_s0 = in_tready_s1 & in_tvalid_s0;

// s1 stage
assign in_tready_s1 = qout_tready | ~qout_tvalid;

always @(posedge clk) begin
    if (rst) begin
        qin_tvalid_reg <= 0;
        ln_bias_tvalid_reg <= 0;
        qin_tdata_reg <= 0;
        ln_bias_tdata_reg <= 0;
    end else begin
        if (qin_tready) begin
            qin_tdata_reg <= qin_tdata;
            qin_tvalid_reg <= qin_tvalid;
        end

        if (ln_bias_tready) begin
            ln_bias_tdata_reg <= ln_bias_tdata;
            ln_bias_tvalid_reg <= ln_bias_tvalid;
        end
    end
end

counter #(
    .MATRIXSIZE_W (MATRIXSIZE_W)
)
counter_ln (
    .clk                (clk),
    .rst                (rst),
    .enable_pixel_count (qout_tvalid & qout_tready),
    .enable_slice_count (1'b1),
    .WIDTH              (DIM2),
    .HEIGHT             (DIM1),
    .pixel_cntr         (qout_col_cntr),
    .slice_cntr         (qout_row_cntr)
);

stream_vector_mem #(
    .X_W(X_W),
    .Y_W(D_W_ACC),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH(N)
)
vec_mem_ln_bias (
    .clk(clk),
    .rst(rst),

    .in_tdata(s_axis_s2mm_tdata_bias),
    .in_tlast(s_axis_s2mm_tlast_bias),
    .in_tready(s_axis_s2mm_tready_bias),
    .in_tvalid(s_axis_s2mm_tvalid_bias),

    .out_tdata(ln_bias_tdata),
    .out_tlast(ln_bias_tlast),
    .out_tready(ln_bias_tready),
    .out_tvalid(ln_bias_tvalid),

    .DIM1(DIM1),
    .DIM2(DIM2)
);

layer_norm #(
    .D_W      ( D_W      ),
    .D_W_ACC  ( D_W_ACC  ),
    .LN_BITS  ( LN_BITS  ),
    .SHIFT    ( SHIFT    ),
    .N        ( N        ),
    .N_INV    ( N_INV    ),
    .FP_BITS  ( FP_BITS  ),
    .MAX_BITS ( MAX_BITS )
)
layer_norm_unit (
    .clk       ( clk           ),
    .rst       ( rst           ),
    .enable    ( in_tready_s1  ),
    .in_valid  ( in_tvalid_s0  ),
    .qin       ( qin_tdata_reg ),
    .bias      ( ln_bias_tdata_reg ),
    .out_valid ( qout_tvalid   ),
    .qout      ( qout_tdata    )
);

endmodule
