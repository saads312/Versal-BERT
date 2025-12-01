`default_nettype none
`timescale 1ps / 1ps

module layer_norm
#(
    parameter integer D_W      = 8,
    parameter integer D_W_ACC  = 32,
    parameter integer N        = 768,
    parameter integer FP_BITS  = 30,
    parameter integer MAX_BITS = 31,
    parameter integer LN_BITS  = 22,
    parameter integer SHIFT    = 6,
    parameter signed [21:0] N_INV = 1398101
)
(
    input  wire                       clk,
    input  wire                       rst,
    input  wire                       enable,
    input  wire                       in_valid,
    input  wire signed  [LN_BITS-1:0] qin,
    input  wire signed  [D_W_ACC-1:0] bias,
    output wire                       out_valid,
    output wire signed  [D_W_ACC-1:0] qout
);

localparam integer SHIFT_W = LN_BITS - SHIFT;
localparam integer W = D_W_ACC >> 1;
localparam [D_W_ACC-1:0] DIVIDENT = 1 << MAX_BITS;

reg                          in_v_r, in_v_r1;
reg  signed  [LN_BITS-1:0]   qin_r, qin_r1;
reg  signed  [SHIFT_W-1:0]   qin_shifted;
reg  signed  [D_W_ACC-1:0]   bias_r, bias_r1;
reg                          qout_v_r, qout_v_r1, qout_v_r2;
reg  signed  [D_W_ACC-1:0]   qout_r, qout_r1;
wire signed  [D_W_ACC-1:0]   qout_shift;

reg                          qacc_out_v;
wire signed [D_W_ACC-1:0]    qacc_out;
wire                         qacc_init;
wire        [D_W_ACC-1:0]    qacc_sq_out;
reg  signed [D_W_ACC-1:0]    qacc_out_r, qacc_out_r1, qacc_out_r1_c1;
reg         [D_W_ACC-1:0]    qacc_sq_out_r, qacc_sq_out_r1, qacc_sq_out_r1_c1, qacc_sq_out_r2, qacc_sq_out_r3;

wire signed [D_W_ACC+22-1:0] qsum_mul;
reg  signed [2*D_W_ACC-1:0]  qmean_mul_r2;
reg  signed [D_W_ACC-1:0]    qmean, qmean_c1, qmean_r2;
reg         [D_W_ACC-1:0]    qmean_sq;
reg  signed [D_W_ACC-1:0]    qsub;
reg         [D_W_ACC-1:0]    qvar;

reg                          qsqrt_in_v_r, qsqrt_in_v_r1, qsqrt_in_v_r1_c1, qsqrt_in_v_r2, qsqrt_in_v_r3, qsqrt_in_v_r4;
wire                         qsqrt_out_v;
wire        [W-1:0]          qsqrt_out;
reg         [D_W_ACC-1:0]    qstd;

reg                          qdiv_in_v;
wire                         qdiv_out_v;
reg                          qdiv_out_v_r, qdiv_out_v_r_c1;
wire        [D_W_ACC-1:0]    qdiv_out;
reg         [D_W_ACC-1:0]    qdiv_out_r, qdiv_out_r_c1, qdiv_out_r1, qdiv_out_r2;

reg         [$clog2(N):0]    qacc_cntr;
reg         [$clog2(N):0]    qsub_cntr;
reg         [$clog2(N):0]    qout_cntr;

reg                          acc_buf_write;
reg                          acc_buf_read, acc_buf_read_r1, acc_buf_read_r1_c1, acc_buf_read_r2, acc_buf_read_r3;
reg  signed   [D_W_ACC-1:0]  acc_buf_wrdata;
wire signed   [D_W_ACC-1:0]  acc_buf_rddata;
reg  signed   [D_W_ACC-1:0]  acc_buf_rddata_r1, acc_buf_rddata_r1_c1, acc_buf_rddata_r2;

reg                          sdiv_buf_write;
reg                          sdiv_buf_read;
reg  signed   [D_W_ACC-1:0]  sdiv_buf_wrdata;
wire signed   [D_W_ACC-1:0]  sdiv_buf_rddata;

reg  signed   [D_W_ACC-1:0]  bias1_buf_wrdata, bias2_buf_wrdata;
wire signed   [D_W_ACC-1:0]  bias1_buf_rddata, bias2_buf_rddata;
reg  signed   [D_W_ACC-1:0]  bias1_buf_rddata_r1, bias1_buf_rddata_r1_c1, bias1_buf_rddata_r2, bias1_buf_rddata_r3, bias2_buf_rddata_r;

assign qacc_init = in_v_r & (qacc_cntr == 0);
assign qsum_mul = (qacc_out_r * N_INV); // 32bits * 22bits = 54bits
assign qout_shift = (qout_r >>> 1);
assign out_valid = qout_v_r2;
assign qout = qout_r1;

always @(posedge clk) begin
    if (rst) begin
        qin_r    <= 0;
        in_v_r   <= 0;
        bias_r   <= 0;

        qin_shifted <= 0;
        qin_r1   <= 0;
        in_v_r1  <= 0;
        bias_r1  <= 0;

        acc_buf_write  <= 0;
        acc_buf_wrdata <= 0;
        bias1_buf_wrdata <= 0;
        
        qacc_out_v    <= 0;
        qacc_cntr     <= 0;
        qacc_out_r    <= 0;
        qacc_sq_out_r <= 0;
    end else if (enable) begin
        qin_r   <= qin;
        in_v_r  <= in_valid;
        bias_r  <= bias;

        qin_shifted <= qin_r >>> SHIFT;
        qin_r1 <= qin_r;
        in_v_r1 <= in_v_r;
        bias_r1  <= bias_r;

        qacc_out_v <= 0;
        if (in_v_r1) begin
            qacc_cntr <= qacc_cntr + 1;
            if (qacc_cntr == N-1) begin
                qacc_cntr <= 0;
                qacc_out_v <= 1;
            end
        end

        acc_buf_wrdata <= qin_r1;
        acc_buf_write  <= in_v_r1;
        bias1_buf_wrdata <= bias_r1;

        if (qacc_out_v) begin
            qacc_out_r    <= qacc_out;  //c0
            qacc_sq_out_r <= qacc_sq_out;   //c0
            // $display("#time=%0d,sum=%0d,sum_sq=%0d",$time,qacc_out,qacc_sq_out);
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        acc_buf_read <= 0;
        acc_buf_read_r1 <= 0;
        acc_buf_read_r1_c1 <= 0;
        acc_buf_read_r2 <= 0;
        acc_buf_read_r3 <= 0;

        acc_buf_rddata_r1 <= 0;
        acc_buf_rddata_r1_c1 <= 0;
        acc_buf_rddata_r2 <= 0;
        bias1_buf_rddata_r1 <= 0;
        bias1_buf_rddata_r1_c1 <= 0;
        bias1_buf_rddata_r2 <= 0;
        bias1_buf_rddata_r3 <= 0;

        qacc_out_r1 <= 0;
        qacc_out_r1_c1 <= 0;
        qacc_sq_out_r1 <= 0;
        qacc_sq_out_r1_c1 <= 0;
        qacc_sq_out_r2 <= 0;
        qacc_sq_out_r3 <= 0;

        sdiv_buf_write  <= 0;
        sdiv_buf_wrdata <= 0;
        bias2_buf_wrdata <= 0;

        qsub_cntr <= 0;
        qmean <= 0;
        qmean_c1 <= 0;
        qmean_r2 <= 0;
        qmean_mul_r2 <= 0;
        qmean_sq <= 0;
        qsub <= 0;
        qvar <= 0;

        qsqrt_in_v_r <= 0;
        qsqrt_in_v_r1 <= 0;
        qsqrt_in_v_r1_c1 <= 0;
        qsqrt_in_v_r2 <= 0;
        qsqrt_in_v_r3 <= 0;
        qsqrt_in_v_r4 <= 0;
        
        qstd <= 0;
        qdiv_in_v <= 0;
        qdiv_out_r <= 0;
        qdiv_out_r_c1 <= 0;
        qdiv_out_v_r <= 0;
        qdiv_out_v_r_c1 <= 0;
    end else if (enable) begin
        //c0
        qsqrt_in_v_r <= qacc_out_v;
        if (qacc_out_v) begin
            acc_buf_read <= 1;
        end else if (acc_buf_read && qsub_cntr == N-1) begin
            acc_buf_read <= 0;
        end

        //c1
        qdiv_out_v_r <= 0;
        if (acc_buf_read) begin
            qsub_cntr <= qsub_cntr + 1;
            if (qsub_cntr == N-1) begin
                qsub_cntr <= 0;
            end
            if (qsub_cntr == 65) begin
                qdiv_out_v_r <= 1;
            end
        end

        qsqrt_in_v_r1 <= qsqrt_in_v_r;
        acc_buf_read_r1 <= acc_buf_read;
        acc_buf_rddata_r1 <= acc_buf_rddata;
        bias1_buf_rddata_r1 <= bias1_buf_rddata;
        qmean <= qsum_mul[D_W_ACC+22-1:FP_BITS];    // qacc_out_r * N_INV
        qacc_out_r1 <= qacc_out_r;
        qacc_sq_out_r1 <= qacc_sq_out_r;

        // if (qsqrt_in_v_r)
        //     $display("#time=%0d,qsum_mul=%0d",$time,qsum_mul);

        // if (qsqrt_in_v_r1)
        //     $display("#time=%0d,qmean=%0d",$time,qmean);

        // if (qsqrt_in_v_r1)
        //     $display("#time=%0d,qmean*qacc=%0d",$time,qmean_mul);

        //c1-1
        qdiv_out_v_r_c1 <= qdiv_out_v_r;
        qsqrt_in_v_r1_c1 <= qsqrt_in_v_r1;
        acc_buf_read_r1_c1 <= acc_buf_read_r1;
        acc_buf_rddata_r1_c1 <= acc_buf_rddata_r1;
        bias1_buf_rddata_r1_c1 <= bias1_buf_rddata_r1;
        qmean_c1 <= qmean;
        qacc_out_r1_c1 <= qacc_out_r1;
        qacc_sq_out_r1_c1 <= qacc_sq_out_r1;

        //c2
        qsqrt_in_v_r2 <= qsqrt_in_v_r1_c1;
        acc_buf_read_r2 <= acc_buf_read_r1_c1;
        acc_buf_rddata_r2 <= acc_buf_rddata_r1_c1;
        bias1_buf_rddata_r2 <= bias1_buf_rddata_r1_c1;
        qmean_mul_r2 <= qmean_c1 * qacc_out_r1_c1;
        qacc_sq_out_r2 <= qacc_sq_out_r1_c1;
        qmean_r2 <= qmean_c1;

        //c3
        qsqrt_in_v_r3 <= qsqrt_in_v_r2;
        acc_buf_read_r3 <= acc_buf_read_r2;
        qsub <= acc_buf_rddata_r2 - qmean_r2;
        bias1_buf_rddata_r3 <= bias1_buf_rddata_r2;
        qmean_sq <= qmean_mul_r2 >> (SHIFT << 1);
        qacc_sq_out_r3 <= qacc_sq_out_r2;

        // if (acc_buf_read_r3)
        //     $display("#time=%0d,qsub=%0d",$time,qsub);

        // if (qsqrt_in_v_r3)
        //     $display("#time=%0d,qmean_sq=%0d",$time,qmean_sq);

        //c4
        qsqrt_in_v_r4 <= qsqrt_in_v_r3;
        qvar <= qacc_sq_out_r3 - qmean_sq;
        sdiv_buf_wrdata <= qsub;
        sdiv_buf_write <= acc_buf_read_r3;
        bias2_buf_wrdata <= bias1_buf_rddata_r3;

        // if (qsqrt_in_v_r4)
        //     $display("#time=%0d,qvar=%0d",$time,qvar);

        //lc0
        qdiv_in_v <= qsqrt_out_v;
        qstd <= qsqrt_out << SHIFT;

        if (qdiv_out_v) begin
            qdiv_out_r <= qdiv_out;
            // $display("#time=%0d,factor=%0d",$time,qdiv_out);
        end
        qdiv_out_r_c1 <= qdiv_out_r;
    end
end

always @(posedge clk) begin
    if (rst) begin
        qout_cntr  <= 0;
        qout_v_r   <= 0;
        qout_v_r1  <= 0;
        qout_v_r2  <= 0;
        qout_r     <= 0;
        qout_r1    <= 0;
        sdiv_buf_read <= 0;
        qdiv_out_r1 <= 0;
        qdiv_out_r2 <= 0;
        bias2_buf_rddata_r <= 0;
    end else if (enable) begin
        //c0
        if (qdiv_out_v_r_c1) begin
            sdiv_buf_read <= 1;
            qdiv_out_r1 <= qdiv_out_r_c1;
        end else if (sdiv_buf_read && qout_cntr == N-1) begin
            sdiv_buf_read <= 0;
        end
        
        //c1
        qout_v_r <= sdiv_buf_read;
        qdiv_out_r2 <= qdiv_out_r1;
        if (sdiv_buf_read) begin
            qout_cntr <= qout_cntr + 1;
            if (qout_cntr == N-1) begin
                qout_cntr <= 0;
            end
        end

        // if (qout_v_r)
        //     $display("#time=%0d,sdiv_buf_rddata=%0d,qdiv_out_r1=%0d",$time,sdiv_buf_rddata,qdiv_out_r2);

        qout_v_r1 <= qout_v_r;
        qout_r <= sdiv_buf_rddata * qdiv_out_r2;
        bias2_buf_rddata_r <= bias2_buf_rddata;

        //c2
        qout_r1 <= qout_shift + bias2_buf_rddata_r;
        qout_v_r2 <= qout_v_r1;
    end
end

sreg #(.D_W(D_W_ACC), .DEPTH(N))
acc_sreg (
    .clk      ( clk            ),
    .rst      ( rst            ),
    .shift_en ( enable & (acc_buf_write | acc_buf_read) ),
    .data_in  ( acc_buf_wrdata ),
    .data_out ( acc_buf_rddata )
);

sreg #(.D_W(D_W_ACC), .DEPTH(64))
sdiv_sreg (
    .clk      ( clk            ),
    .rst      ( rst            ),
    .shift_en ( enable & (sdiv_buf_write | sdiv_buf_read) ),
    .data_in  ( sdiv_buf_wrdata ),
    .data_out ( sdiv_buf_rddata )
);

sreg #(.D_W(D_W_ACC), .DEPTH(N))
bias1_sreg (
    .clk      ( clk            ),
    .rst      ( rst            ),
    .shift_en ( enable & (acc_buf_write | acc_buf_read) ),
    .data_in  ( bias1_buf_wrdata ),
    .data_out ( bias1_buf_rddata )
);

sreg #(.D_W(D_W_ACC), .DEPTH(64))
bias2_sreg (
    .clk      ( clk            ),
    .rst      ( rst            ),
    .shift_en ( enable & (sdiv_buf_write | sdiv_buf_read) ),
    .data_in  ( bias2_buf_wrdata ),
    .data_out ( bias2_buf_rddata )
);

acc #(.D_W(D_W_ACC))
qacc (
    .clk        ( clk       ),
    .rst        ( rst       ),
    .enable     ( enable    ),
    .initialize ( qacc_init ),
    .in_data    ( qin_r1    ),
    .result     ( qacc_out  )
);

mac #(.D_W(SHIFT_W))
qacc_sq (
    .clk        ( clk          ),
    .rst        ( rst          ),
    .enable     ( enable       ),
    .initialize ( qacc_init    ),
    .a          ( qin_shifted  ),
    .b          ( qin_shifted  ),
    .result     ( qacc_sq_out  )
);

sqrt #(.D_W(D_W_ACC))
qsqrt (
    .clk        ( clk         ),
    .rst        ( rst         ),
    .enable     ( enable      ),
    .in_valid   ( qsqrt_in_v_r4 ),
    .qin        ( qvar        ),
    .out_valid  ( qsqrt_out_v ),
    .qout       ( qsqrt_out   )
);

div #(.D_W(D_W_ACC))
qdiv (
    .clk       ( clk        ),
    .rst       ( rst        ),
    .enable    ( enable     ),
    .in_valid  ( qdiv_in_v  ),
    .divisor   ( qstd       ),
    .divident  ( DIVIDENT   ),
    .out_valid ( qdiv_out_v ),
    .quotient  ( qdiv_out   )
);

endmodule
