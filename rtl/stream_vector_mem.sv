`default_nettype none
`timescale 1ps / 1ps

/*
    stream_vector_mem - stores stream of vector data in memory in Y_W bits, and streams it out in Y_W bits
*/

module stream_vector_mem
#(
    parameter integer X_W          = 32,
    parameter integer Y_W          = 8,
    parameter integer MATRIXSIZE_W = 24,
    parameter integer MEM_DEPTH    = 4096
)
(
    input  wire clk,
    input  wire rst,

    input  wire signed [X_W-1:0]    in_tdata,
    input  wire                     in_tlast,
    output wire                     in_tready,
    input  wire                     in_tvalid,

    output wire signed [Y_W-1:0]    out_tdata,
    output wire                     out_tlast,
    input  wire                     out_tready,
    output wire                     out_tvalid,

    input  wire [MATRIXSIZE_W-1:0]  DIM1,
    input  wire [MATRIXSIZE_W-1:0]  DIM2
);

localparam integer ADDR_W = $clog2(MEM_DEPTH);

wire signed [Y_W-1:0] wrdata;
wire signed [Y_W-1:0] rddata;

reg  [ADDR_W-1:0] wraddr = 0;
reg  [ADDR_W-1:0] rdaddr = 0;
wire [ADDR_W-1:0] prerdaddr;

reg [MATRIXSIZE_W-1:0] rdcntr = 0;

wire write_hs;
wire read_hs;

wire write_last;
wire read_last;

wire write_start;
wire read_start;

wire write_stall;
wire read_stall;

typedef enum logic [1:0] {
    WRRESET = 2'b00,
    WRIDLE = 2'b01,
    WRDATA = 2'b10
} wstate_t;

typedef enum logic [1:0] {
    RDRESET = 2'b00,
    RDIDLE = 2'b01,
    RDDATA = 2'b10
} rstate_t;

wstate_t wstate, wnext;
rstate_t rstate, rnext;

// WRITE

assign wrdata = in_tdata[Y_W-1:0];
assign in_tready = (wstate == WRDATA);
assign write_hs = in_tvalid & in_tready;
assign write_last = write_hs & in_tlast;
assign write_start = (rstate == RDIDLE);

always @(posedge clk) begin
    if (rst) begin
        wstate <= WRRESET;
    end else begin
        wstate <= wnext;
    end
end

always @(*) begin
    case (wstate)
        WRIDLE:
            wnext = (write_start) ? WRDATA : WRIDLE;
        WRDATA:
            wnext = (write_last) ? WRIDLE : WRDATA;
        default:
            wnext = WRIDLE;
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        wraddr <= 0;
    end else begin
        if (write_hs) begin
            wraddr <= wraddr + 1;
            if (write_last) begin
                wraddr <= 0;
            end
        end
    end
end

// READ

assign out_tdata = rddata;
assign out_tvalid = (rstate == RDDATA);
assign out_tlast = (rdaddr == DIM2-1) & (rdcntr == DIM1-1);
assign read_hs = out_tvalid & out_tready;
assign read_last = read_hs & out_tlast;
assign read_start = write_last;

always @(posedge clk) begin
    if (rst) begin
        rstate <= RDRESET;
    end else begin
        rstate <= rnext;
    end
end

always @(*) begin
    case (rstate)
        RDIDLE:
            rnext = (read_start) ? RDDATA : RDIDLE;
        RDDATA:
            rnext = (read_last) ? RDIDLE : RDDATA;
        default:
            rnext = RDIDLE;
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        rdaddr <= 0;
        rdcntr <= 0;
    end else begin
        if (read_hs) begin
            rdaddr <= rdaddr + 1;
            if (rdaddr == DIM2-1) begin
                rdaddr <= 0;
                rdcntr <= rdcntr + 1;
                if (rdcntr == DIM1-1) begin
                    rdcntr <= 0;
                end
            end
        end
    end
end

assign prerdaddr = (rdaddr == DIM2-1) ? 0 : rdaddr + 1;

// mem_dist #(
mem_top #(
    .WIDTH ( Y_W       ),
    .DEPTH ( MEM_DEPTH )
)
vector_mem (
    .rst   ( rst ),
    .clkA  ( clk ),
    .clkB  ( clk ),
    .weA   ( write_hs ),
    .enA   ( 1'b1 ),
    .enB   ( 1'b1 ),
    .addrA ( wraddr ),
    .addrB ( read_hs ? prerdaddr : rdaddr ),
    .dinA  ( wrdata ),
    .doutB ( rddata )
);

endmodule
