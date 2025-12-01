`default_nettype none
`timescale 1ps / 1ps

module requant
#(
    parameter integer D_W = 8,
    parameter integer D_W_ACC = 32,
    parameter integer OUT_BITS = 8,
    parameter integer CLIP = 0
)
(
    input  wire                       clk,
    input  wire                       rst,

    input  wire signed [D_W_ACC-1:0]  in_tdata,
    input  wire                       in_tlast,
    output wire                       in_tready,
    input  wire                       in_tvalid,

    input  wire signed [D_W_ACC-1:0]  in_tdata_bias,
    input  wire                       in_tlast_bias,
    output wire                       in_tready_bias,
    input  wire                       in_tvalid_bias,

    input  wire signed [D_W_ACC-1:0]  in_tdata_m,
    input  wire                       in_tlast_m,
    output wire                       in_tready_m,
    input  wire                       in_tvalid_m,

    input  wire signed [D_W-1:0]      in_tdata_e,
    input  wire                       in_tlast_e,
    output wire                       in_tready_e,
    input  wire                       in_tvalid_e,

    output wire signed [OUT_BITS-1:0] out_tdata,
    output wire                       out_tlast,
    input  wire                       out_tready,
    output wire                       out_tvalid
);

localparam signed [D_W_ACC-1:0] UPPER_BOUND = (1 << (OUT_BITS - 1)) - 1;
localparam signed [D_W_ACC-1:0] LOWER_BOUND = - UPPER_BOUND - 1;

localparam SHAMT_SZ  = $clog2(2*D_W_ACC);
localparam MAX_SHAMT = 1 << SHAMT_SZ;

reg signed [D_W_ACC-1:0]   in_tdata_r0;
reg signed [D_W_ACC-1:0]   in_tdata_bias_r0;
reg signed [D_W_ACC-1:0]   in_tdata_m_r[1:0];
reg signed [D_W-1:0]       in_tdata_e_r[4:0];

reg in_tvalid_r0 = 0;
reg in_tvalid_bias_r0 = 0;
reg in_tvalid_m_r0 = 0;
reg in_tvalid_e_r0 = 0;
reg in_tlast_r0 = 0;
reg in_tlast_bias_r0 = 0;
reg in_tlast_m_r0 = 0;
reg in_tlast_e_r0 = 0;

reg signed [6:0]           result_tvalid = 0;
reg signed [6:0]           result_tlast = 0;
reg signed [D_W_ACC-1:0]   result_add = 0;
reg signed [2*D_W_ACC-1:0] result_mul = 0;
reg signed [2*D_W_ACC-1:0] result_mul_p1 = 0;
reg signed [2*D_W_ACC-1:0] result_mul_p2 = 0;
reg signed [2*D_W_ACC-1:0] result_shift_int = 0;
reg signed [2*D_W_ACC-1:0] result_shift_frac = 0;
reg signed [D_W_ACC-1:0]   result = 0;

wire in_tvalid_s0;
wire in_tlast_s0;
wire in_tready_s0;
wire in_tready_s1;

assign out_tvalid = result_tvalid[6];
assign out_tlast = result_tlast[6];
assign out_tdata = (CLIP && result < LOWER_BOUND) ? LOWER_BOUND :
                   (CLIP && result > UPPER_BOUND) ? UPPER_BOUND : result;

// register everyone at least once when in_tready_s0 is low
assign in_tready = in_tready_s0 | ~in_tvalid_r0;
assign in_tready_bias = in_tready_s0 | ~in_tvalid_bias_r0;
assign in_tready_m = in_tready_s0 | ~in_tvalid_m_r0;
assign in_tready_e = in_tready_s0 | ~in_tvalid_e_r0;

// now I need everyone to be valid after first pass
assign in_tvalid_s0 = in_tvalid_r0 & in_tvalid_bias_r0 & in_tvalid_m_r0 & in_tvalid_e_r0;
assign in_tlast_s0 = in_tlast_r0 & in_tlast_bias_r0 & in_tlast_m_r0 & in_tlast_e_r0;
assign in_tready_s0 = in_tready_s1 & in_tvalid_s0;

// s1 stage
assign in_tready_s1 = out_tready | ~out_tvalid;

// pipelines: src | s0 | s1 | s2 | s3 | s4

always @(posedge clk) begin
    if (rst) begin
        in_tdata_r0 <= 0;
        in_tlast_r0 <= 0;
        in_tvalid_r0 <= 0;

        in_tdata_bias_r0 <= 0;
        in_tlast_bias_r0 <= 0;
        in_tvalid_bias_r0 <= 0;

        in_tdata_m_r[0] <= 0;
        in_tlast_m_r0 <= 0;
        in_tvalid_m_r0 <= 0;

        in_tdata_e_r[0] <= 0;
        in_tlast_e_r0 <= 0;
        in_tvalid_e_r0 <= 0;
    end else begin
        // stage 0
        if (in_tready) begin
            in_tdata_r0 <= in_tdata;
            in_tlast_r0 <= in_tlast;
            in_tvalid_r0 <= in_tvalid;
        end
        // stage 0
        if (in_tready_bias) begin
            in_tdata_bias_r0 <= in_tdata_bias;
            in_tlast_bias_r0 <= in_tlast_bias;
            in_tvalid_bias_r0 <= in_tvalid_bias;
        end
        // stage 0
        if (in_tready_m) begin
            in_tdata_m_r[0] <= in_tdata_m;
            in_tlast_m_r0 <= in_tlast_m;
            in_tvalid_m_r0 <= in_tvalid_m;
        end
        // stage 0
        if (in_tready_e) begin
            in_tdata_e_r[0] <= in_tdata_e;
            in_tlast_e_r0 <= in_tlast_e;
            in_tvalid_e_r0 <= in_tvalid_e;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        result_add <= 0;
        in_tdata_m_r[1] <= 0;
        in_tdata_e_r[1] <= 0;
        result_tvalid[1] <= 0;
        result_tlast[1] <= 0;

        result_mul <= 0;
        in_tdata_e_r[2] <= 0;
        result_tvalid[2] <= 0;
        result_tlast[2] <= 0;

        result_shift_int <= 0;
        result_shift_frac <= 0;
        result_tvalid[3] <= 0;
        result_tlast[3] <= 0;

        result <= 0;
        result_tvalid[4] <= 0;
        result_tlast[4] <= 0;
    end else begin
        if (in_tready_s1) begin
            // stage 1
            result_add <= in_tdata_r0 + in_tdata_bias_r0;
            in_tdata_m_r[1] <= in_tdata_m_r[0];
            in_tdata_e_r[1] <= in_tdata_e_r[0];
            result_tvalid[1] <= in_tvalid_s0;
            result_tlast[1] <= in_tlast_s0;
            // stage 2
            result_mul <= result_add * in_tdata_m_r[1];
            in_tdata_e_r[2] <= in_tdata_e_r[1];
            result_tvalid[2] <= result_tvalid[1];
            result_tlast[2] <= result_tlast[1];
            // stage 2-p1
            result_mul_p1 <= result_mul;
            in_tdata_e_r[3] <= in_tdata_e_r[2];
            result_tvalid[3] <= result_tvalid[2];
            result_tlast[3] <= result_tlast[2];
            // stage 2-p2
            result_mul_p2 <= result_mul_p1;
            in_tdata_e_r[4] <= in_tdata_e_r[3];
            result_tvalid[4] <= result_tvalid[3];
            result_tlast[4] <= result_tlast[3];
            // stage 3
            result_shift_int <= result_mul_p2 >>> in_tdata_e_r[4];
            result_shift_frac <= result_mul_p2 << (MAX_SHAMT - in_tdata_e_r[4]);
            result_tvalid[5] <= result_tvalid[4];
            result_tlast[5] <= result_tlast[4];
            // stage 4
            result <= result_shift_int + result_shift_frac[2*D_W_ACC-1];
            result_tvalid[6] <= result_tvalid[5];
            result_tlast[6] <= result_tlast[5];
        end
    end
end

endmodule
