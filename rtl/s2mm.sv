`ifndef XIL_TIMING
`default_nettype none
`endif
`timescale 1ps / 1ps

module s2mm
#(
    parameter integer D_W          = 8,
    parameter integer N1           = 4,
    parameter integer N2           = 4,
    parameter integer MATRIXSIZE_W = 16,
    parameter integer KEEP_A       = 1,
    parameter integer MEM_DEPTH_A  = 4096,
    parameter integer MEM_DEPTH_B  = 4096,
    parameter integer ADDR_W_A     = 12,
    parameter integer ADDR_W_B     = 12,
    parameter integer P_B          = 1,
    parameter         TRANSPOSE_B  = 0
)
(
    input  wire                      clk,
    input  wire                      fclk,
    input  wire                      rst,

    input  wire signed [D_W-1:0]     s_axis_s2mm_tdata_A,
    input  wire                      s_axis_s2mm_tlast_A,
    output wire                      s_axis_s2mm_tready_A,
    input  wire                      s_axis_s2mm_tvalid_A,

    input  wire signed [D_W*P_B-1:0] s_axis_s2mm_tdata_B,
    input  wire                      s_axis_s2mm_tlast_B,
    output wire                      s_axis_s2mm_tready_B,
    input  wire                      s_axis_s2mm_tvalid_B,

    input  wire [ADDR_W_A-1:0]       rd_addr_A,
    input  wire [ADDR_W_B-1:0]       rd_addr_B,

    output wire signed [D_W-1:0]     A_bram [N1-1:0],
    output wire signed [D_W-1:0]     B_bram [N2-1:0],

    input  wire [MATRIXSIZE_W-1:0]   M2,
    input  wire [MATRIXSIZE_W-1:0]   M1dN1,
    input  wire [MATRIXSIZE_W-1:0]   M3dN2,

    input  wire                      done_multiply,
    output wire                      start_multiply
);

reg start_multiply_r = 0;
reg tlast_A_flag = 0;
reg tlast_B_flag = 0;
reg write_done_A = 0;
reg write_done_B = 0;
reg write_done = 0;
reg [1:0] write_done_sync = 0;
reg [1:0] start_multiply_sync = 0;
reg [1:0] done_multiply_sync = 0;

// A signals
reg             [N1-1:0]   reg_banked_valid_A;
reg  signed    [D_W-1:0]   reg_banked_data_A       [N1-1:0];
reg       [ADDR_W_A-1:0]   reg_banked_write_addr_A [N1-1:0];
reg             [N1-1:0]   reg_banked_activate_A   [N1-1:0];
wire signed    [D_W-1:0]   A_bram_data             [N1-1:0];

wire        [N1-1:0]       activate_A;
wire        [ADDR_W_A-1:0] wr_addr_A;
wire        [ADDR_W_A-1:0] rd_addr_A_bram          [N1-1:0];
wire        [N1-1:0]       rd_en_A_bram;
reg         [N1-1:0]       rd_data_valid_A;

// B signals
reg         [N2-1:0]       reg_banked_valid_B;
reg  signed [D_W*P_B-1:0]  reg_banked_data_B       [N2-1:0];
reg         [ADDR_W_B-1:0] reg_banked_write_addr_B [N2-1:0];
reg         [N2-1:0]       reg_banked_activate_B   [N2-1:0];
wire signed [D_W-1:0]      B_bram_data             [N2-1:0];

wire        [N2-1:0]       activate_B;
wire        [ADDR_W_B-1:0] wr_addr_B;
wire        [ADDR_W_B-1:0] rd_addr_B_bram          [N2-1:0];
wire        [N2-1:0]       rd_en_B_bram;
reg         [N2-1:0]       rd_data_valid_B;

reg                      s_axis_s2mm_tready_A_r = 1;
reg                      s_axis_s2mm_tready_B_r = 1;
reg signed [D_W-1:0]     s_axis_s2mm_tdata_A_r = 0;
reg                      s_axis_s2mm_tvalid_A_r = 0;
reg signed [D_W*P_B-1:0] s_axis_s2mm_tdata_B_r = 0;
reg                      s_axis_s2mm_tvalid_B_r = 0;
reg [$clog2(KEEP_A):0]   keep_A_cntr = 0;

always @(posedge clk) begin
    if (rst) begin
        s_axis_s2mm_tdata_A_r <= 0;
        s_axis_s2mm_tvalid_A_r <= 0;

        s_axis_s2mm_tdata_B_r <= 0;
        s_axis_s2mm_tvalid_B_r <= 0;
    end else begin
        s_axis_s2mm_tdata_A_r <= s_axis_s2mm_tdata_A;
        s_axis_s2mm_tvalid_A_r <= s_axis_s2mm_tvalid_A;

        s_axis_s2mm_tdata_B_r <= s_axis_s2mm_tdata_B;
        s_axis_s2mm_tvalid_B_r <= s_axis_s2mm_tvalid_B;
    end
end

// A management
genvar x;
for (x = 0; x < N1; x = x + 1) begin: ram_A
    assign A_bram[x] = rd_data_valid_A[x] ? A_bram_data[x] : 0;

    mem_top #(
        .WIDTH ( D_W         ),
        .DEPTH ( MEM_DEPTH_A )
    )
    read_ram_A (
        .rst   ( rst                         ),
        .clkA  ( clk                         ),
        .clkB  ( fclk                        ),
        .weA   ( reg_banked_valid_A[x]       ),
        .enA   ( reg_banked_activate_A[x][x] ),
        .enB   ( rd_en_A_bram[x]             ),
        .addrA ( reg_banked_write_addr_A[x]  ),
        .addrB ( rd_addr_A_bram[x]           ),
        .dinA  ( reg_banked_data_A[x]        ),
        .doutB ( A_bram_data[x]              )
    );

    always @(posedge fclk) begin
        rd_data_valid_A[x] <= rd_en_A_bram[x];
        if (rd_en_A_bram[x] || rd_data_valid_A[x]) begin
            $display("[%t] S2MM BRAM_A[%d]: rd_en=%b rd_addr=%d | rd_data_valid=%b data=0x%h (%d) | A_bram=%d",
                     $time, x, rd_en_A_bram[x], rd_addr_A_bram[x], rd_data_valid_A[x],
                     A_bram_data[x], $signed(A_bram_data[x]), $signed(A_bram[x]));
        end
    end

    if (x==0) begin
        always @(posedge clk) begin
            reg_banked_valid_A[x]      <= s_axis_s2mm_tvalid_A_r;
            reg_banked_data_A[x]       <= s_axis_s2mm_tdata_A_r;
            reg_banked_write_addr_A[x] <= wr_addr_A;
            reg_banked_activate_A[x]   <= activate_A;
            if (s_axis_s2mm_tvalid_A_r && activate_A[x]) begin
                $display("[%t] S2MM WRITE_A[%d]: addr=%d data=0x%h (%d) activate=0x%h",
                         $time, x, wr_addr_A, s_axis_s2mm_tdata_A_r, $signed(s_axis_s2mm_tdata_A_r), activate_A);
            end
        end
    end else begin
        always @(posedge clk) begin
            reg_banked_valid_A[x]      <= reg_banked_valid_A[x-1];
            reg_banked_data_A[x]       <= reg_banked_data_A[x-1];
            reg_banked_write_addr_A[x] <= reg_banked_write_addr_A[x-1];
            reg_banked_activate_A[x]   <= reg_banked_activate_A[x-1];
        end
    end
end

// B management
for (x = 0; x < N2 ; x = x +1) begin: ram_B
    assign B_bram[x] = rd_data_valid_B[x] ? B_bram_data[x] : 0;

    mem_top #(
        .WIDTH ( D_W         ),
        .DEPTH ( MEM_DEPTH_B ),
        .PACKS ( P_B         )
    )
    read_ram_B (
        .rst   ( rst                         ),
        .clkA  ( clk                         ),
        .clkB  ( fclk                        ),
        .weA   ( reg_banked_valid_B[x]       ),
        .enA   ( reg_banked_activate_B[x][x] ),
        .enB   ( rd_en_B_bram[x]             ),
        .addrA ( reg_banked_write_addr_B[x]  ),
        .addrB ( rd_addr_B_bram[x]           ),
        .dinA  ( reg_banked_data_B[x]        ),
        .doutB ( B_bram_data[x]              )
    );

    always @(posedge fclk) begin
        rd_data_valid_B[x] <= rd_en_B_bram[x];
        if (rd_en_B_bram[x] || rd_data_valid_B[x]) begin
            $display("[%t] S2MM BRAM_B[%d]: rd_en=%b rd_addr=%d | rd_data_valid=%b data=0x%h (%d) | B_bram=%d",
                     $time, x, rd_en_B_bram[x], rd_addr_B_bram[x], rd_data_valid_B[x],
                     B_bram_data[x], $signed(B_bram_data[x]), $signed(B_bram[x]));
        end
    end

    if (x==0) begin
        always @(posedge clk) begin
            reg_banked_valid_B[x]      <= s_axis_s2mm_tvalid_B_r;
            reg_banked_data_B[x]       <= s_axis_s2mm_tdata_B_r;
            reg_banked_write_addr_B[x] <= wr_addr_B;
            reg_banked_activate_B[x]   <= activate_B;
            if (s_axis_s2mm_tvalid_B_r && activate_B[x]) begin
                $display("[%t] S2MM WRITE_B[%d]: addr=%d data=0x%h (%d) activate=0x%h",
                         $time, x, wr_addr_B, s_axis_s2mm_tdata_B_r, $signed(s_axis_s2mm_tdata_B_r), activate_B);
            end
        end
    end else begin
        always @(posedge clk) begin
            reg_banked_valid_B[x]      <= reg_banked_valid_B[x-1];
            reg_banked_data_B[x]       <= reg_banked_data_B[x-1];
            reg_banked_write_addr_B[x] <= reg_banked_write_addr_B[x-1];
            reg_banked_activate_B[x]   <= reg_banked_activate_B[x-1];
        end
    end
end

// AXI Signals management
reg tready;
always @(posedge clk) begin
    if (rst) begin
        tready <= 0;
    end else begin
        tready <= 1;
    end
end

assign s_axis_s2mm_tready_A = s_axis_s2mm_tready_A_r & tready;
assign s_axis_s2mm_tready_B = s_axis_s2mm_tready_B_r & tready;

always @(posedge clk) begin
    if (rst) begin
        s_axis_s2mm_tready_A_r <= 1;
        s_axis_s2mm_tready_B_r <= 1;
    end else begin
        // need tlast_flag to safeguard ready from jumping when done_multiply is high even after new batch tlast is received 
        if (s_axis_s2mm_tready_A && s_axis_s2mm_tlast_A && s_axis_s2mm_tvalid_A || tlast_A_flag) begin
            s_axis_s2mm_tready_A_r <= 0;
        end else if (done_multiply_sync[1]) begin
            s_axis_s2mm_tready_A_r <= 1;
        end

        if (s_axis_s2mm_tready_B && s_axis_s2mm_tlast_B && s_axis_s2mm_tvalid_B || tlast_B_flag) begin
            s_axis_s2mm_tready_B_r <= 0;
        end else if (done_multiply_sync[1]) begin
            s_axis_s2mm_tready_B_r <= 1;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        tlast_A_flag <= 0;
        tlast_B_flag <= 0;
        write_done_A <= 0;
        write_done_B <= 0;
        write_done <= 0;
        keep_A_cntr <= 0;
    end else begin
        if (s_axis_s2mm_tready_A && s_axis_s2mm_tlast_A && s_axis_s2mm_tvalid_A) begin
            tlast_A_flag <= 1;
            $display("[%t] S2MM: tlast_A_flag set (TLAST_A received)", $time);
        end

        if (s_axis_s2mm_tready_B && s_axis_s2mm_tlast_B && s_axis_s2mm_tvalid_B) begin
            tlast_B_flag <= 1;
            $display("[%t] S2MM: tlast_B_flag set (TLAST_B received)", $time);
        end

        if (~reg_banked_valid_A[N1-1] && tlast_A_flag) begin
            write_done_A <= 1;
            $display("[%t] S2MM: write_done_A asserted (pipeline cleared, tlast_A_flag=%b)", $time, tlast_A_flag);
        end

        if (~reg_banked_valid_B[N2-1] && tlast_B_flag) begin
            write_done_B <= 1;
            $display("[%t] S2MM: write_done_B asserted (pipeline cleared, tlast_B_flag=%b)", $time, tlast_B_flag);
        end

        if (tlast_A_flag && tlast_B_flag && start_multiply_sync[1]) begin
            // last A and B elements were received and synced to start_multiply
            if (KEEP_A > 1) begin
                keep_A_cntr <= keep_A_cntr + 1;
                if (keep_A_cntr == KEEP_A-1) begin
                    keep_A_cntr <= 0;
                    write_done_A <= 0;
                    tlast_A_flag <= 0;
                end
            end else begin
                write_done_A <= 0;
                tlast_A_flag <= 0;
            end
            write_done_B <= 0;
            tlast_B_flag <= 0;
        end

        write_done <= write_done_A && write_done_B;
    end
end

assign start_multiply = start_multiply_r;

always @(posedge fclk) begin
    if (rst) begin
        start_multiply_r <= 0;
    end else begin
        if (done_multiply) begin
            // done_multiply becomes high once systolic finishes writing D
            // and goes low when D is fully read out
            start_multiply_r <= 0;
            $display("[%t] S2MM: start_multiply deasserted (done_multiply received)", $time);
        end else if (write_done_sync[1]) begin
            // write finished, start multiply, keep high until done multiply
            start_multiply_r <= 1;
            $display("[%t] S2MM: start_multiply asserted (write_done_sync[1]=%b)", $time, write_done_sync[1]);
        end
    end
end

always @(posedge clk) begin
    start_multiply_sync <= {start_multiply_sync[0], start_multiply_r};
    done_multiply_sync <= {done_multiply_sync[0], done_multiply};
end

always @(posedge fclk) begin
    write_done_sync <= {write_done_sync[0], write_done};
end

mem_write_A #(
    .N1           ( N1           ),
    .MATRIXSIZE_W ( MATRIXSIZE_W ),
    .ADDR_W       ( ADDR_W_A     )
)
mem_write_A_inst (
    .clk        ( clk        ),
    .rst        ( rst | tlast_A_flag ),
    .M2         ( M2         ),
    .M1dN1      ( M1dN1      ),
    .valid_A    ( s_axis_s2mm_tvalid_A & s_axis_s2mm_tready_A ),
    .wr_addr_A  ( wr_addr_A  ),
    .activate_A ( activate_A )
);

generate
    if (TRANSPOSE_B) begin: transpose
        mem_write_A #(
            .N1           ( N2           ),
            .MATRIXSIZE_W ( MATRIXSIZE_W ),
            .ADDR_W       ( ADDR_W_B     )
        )
        mem_write_B_inst (
            .clk        ( clk        ),
            .rst        ( rst | tlast_B_flag ),
            .M2         ( M2         ),
            .M1dN1      ( M3dN2      ),
            .valid_A    ( s_axis_s2mm_tvalid_B & s_axis_s2mm_tready_B ),
            .wr_addr_A  ( wr_addr_B  ),
            .activate_A ( activate_B )
        );
    end else begin: simple
        mem_write_B #(
            .N2           ( N2           ),
            .MATRIXSIZE_W ( MATRIXSIZE_W ),
            .ADDR_W       ( ADDR_W_B     ),
            .P_B          ( P_B          )
        )
        mem_write_B_inst (
            .clk        ( clk        ),
            .rst        ( rst | tlast_B_flag ),
            .M2         ( M2         ),
            .M3dN2      ( M3dN2      ),
            .valid_B    ( s_axis_s2mm_tvalid_B & s_axis_s2mm_tready_B ),
            .wr_addr_B  ( wr_addr_B  ),
            .activate_B ( activate_B )
        );
    end
endgenerate

mem_read #(
    .D_W    (D_W),
    .N      (N1),
    .ADDR_W (ADDR_W_A)
)
mem_read_A (
    .clk          ( fclk             ),
    .rd_addr      ( rd_addr_A        ),
    .rd_en        ( start_multiply_r ),
    .rd_addr_bram ( rd_addr_A_bram   ),
    .rd_en_bram   ( rd_en_A_bram     )
);

mem_read #(
    .D_W    (D_W),
    .N      (N2),
    .ADDR_W (ADDR_W_B)
)
mem_read_B (
    .clk          ( fclk             ),
    .rd_addr      ( rd_addr_B        ),
    .rd_en        ( start_multiply_r ),
    .rd_addr_bram ( rd_addr_B_bram   ),
    .rd_en_bram   ( rd_en_B_bram     )
);

endmodule
