`timescale 1ps / 1ps

module gelu
#(
    parameter integer D_W   = 32,
    parameter integer SHIFT = 14
)
(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,
    input  wire                  in_valid,
    input  wire signed [D_W-1:0] qin,           // gelu input

    input  wire signed [D_W-1:0] qb,            // coefficient
    input  wire signed [D_W-1:0] qc,            // coefficient
    input  wire signed [D_W-1:0] q1,            // coefficient

    output wire                  out_valid,
    output wire signed [D_W-1:0] qout           // gelu output
);

reg  signed [D_W-1:0] qin_r0, qin_r1, qin_r2, qin_r3, qin_r4, qin_r5, qin_r6;
wire signed [D_W-1:0] qabs;
wire signed [D_W-1:0] qerf;
reg  signed [D_W-1:0] qerf_r5;
reg  signed [D_W-1:0] qmin_r1, qmin_r2;
reg  signed [D_W-1:0] ql_r2, ql_r3, ql_r4;
reg  signed [D_W-1:0] qout_r6, qout_r;

reg  signed [D_W-1:0] qb_r0;
reg  signed [D_W-1:0] qc_r0;
reg  signed [D_W-1:0] q1_r0;

reg in_v_r0, in_v_r1, in_v_r2, in_v_r3, in_v_r4, in_v_r5, in_v_r6;
reg done;

assign qout      = qout_r;
assign out_valid = done;

assign qabs = qin_r0[D_W-1] ? -qin_r0 : qin_r0;     // cycle1
assign qerf = qin_r4[D_W-1] ?   -ql_r4 : ql_r4;     // cycle4

always @(posedge clk) begin
    if (rst) begin
        in_v_r0 <= 0;
        in_v_r1 <= 0;
        in_v_r2 <= 0;
        in_v_r3 <= 0;
        in_v_r4 <= 0;
        in_v_r5 <= 0;
        in_v_r6 <= 0;

        qin_r0  <= 0;
        qin_r1  <= 0;
        qin_r2  <= 0;
        qin_r3  <= 0;
        qin_r4  <= 0;
        qin_r5  <= 0;
        qin_r6  <= 0;

        qb_r0   <= 0;
        qc_r0   <= 0;
        q1_r0   <= 0;

        qmin_r1 <= 0;
        qmin_r2 <= 0;

        ql_r2   <= 0;
        ql_r3   <= 0;
        ql_r4   <= 0;

        qerf_r5 <= 0;
        qout_r6 <= 0;
        qout_r  <= 0;
        done    <= 0;
    end else if (enable) begin
        // cycle 0
        in_v_r0 <= in_valid;
        qin_r0  <= qin;
        qb_r0   <= qb;
        qc_r0   <= qc;
        q1_r0   <= q1;

        // cycle 1
        qmin_r1  <= (qabs < -qb_r0) ? qabs : -qb_r0;
        in_v_r1 <= in_v_r0;
        qin_r1  <= qin_r0;

        // cycle 2
        ql_r2   <= qmin_r1 + (qb_r0 << 1);
        qmin_r2 <= qmin_r1;
        in_v_r2 <= in_v_r1;
        qin_r2  <= qin_r1;

        // cycle 3
        ql_r3   <= ql_r2 * qmin_r2;
        in_v_r3 <= in_v_r2;
        qin_r3  <= qin_r2;

        // cycle 4
        ql_r4   <= ql_r3 + qc_r0;
        in_v_r4 <= in_v_r3;
        qin_r4  <= qin_r3;

        // cycle 5
        qerf_r5 <= qerf >>> SHIFT;
        in_v_r5 <= in_v_r4;
        qin_r5  <= qin_r4;
        
        // cycle 6
        qout_r6 <= qerf_r5 + q1_r0;
        in_v_r6 <= in_v_r5;
        qin_r6  <= qin_r5;

        // cycle 7
        qout_r  <= qin_r6 * qout_r6;
        done    <= in_v_r6;
    end
end


endmodule
