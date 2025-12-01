`timescale 1ps / 1ps

module sqrt
#(
    parameter integer D_W = 32
)
(
    input  wire                clk,
    input  wire                rst,
    input  wire                enable,
    input  wire                in_valid,
    input  wire [D_W-1:0]      qin,
    output wire                out_valid,
    output wire [(D_W>>1)-1:0] qout
);

localparam integer P = D_W >> 1;    //pipeline stages
localparam integer W = D_W >> 1;    //output width
integer p;

reg         [P-1:0]   in_v_r;
reg                   out_v_r;
reg         [W-1:0]   qout_r;

reg         [W-1:0]   root_r [P-1:0];
reg         [D_W+1:0] acc_r  [P-1:0];
reg         [D_W-1:0] x_r    [P-1:0];
reg  signed [D_W+1:0] test   [P-1:0];

assign out_valid = out_v_r;
assign qout      = qout_r;

always @(*) begin
    for (p = 0; p < P; p = p + 1) begin
        test[p] = acc_r[p] - {root_r[p], 2'b01};
    end
end

always @(posedge clk) begin
    if (rst) begin
        for (p = 0; p < P; p = p + 1) begin
            in_v_r[p] <= 0;
            acc_r[p]  <= 0;
            x_r[p]    <= 0;
            root_r[p] <= 0;
        end
        out_v_r <= 0;
        qout_r  <= 0;
    end else if (enable) begin
        in_v_r[0]          <= in_valid;
        {acc_r[0], x_r[0]} <= {{D_W{1'b0}}, qin, 2'b00};
        root_r[0]          <= 0;

        for (p = 1; p < P; p = p + 1) begin
            in_v_r[p]         <= in_v_r[p-1];
            acc_r[p][D_W+1:2] <= test[p-1][D_W+1] ? acc_r[p-1][D_W-1:0] : test[p-1][D_W-1:0];
            acc_r[p][1:0]     <= x_r[p-1][D_W-1:D_W-2];
            x_r[p]            <= x_r[p-1] << 2;
            root_r[p]         <= {root_r[p-1][W-2:0], ~test[p-1][D_W+1]};
        end

        out_v_r <= in_v_r[P-1];
        qout_r  <= {root_r[P-1][W-2:0], ~test[P-1][D_W+1]};
    end
    
end


endmodule
