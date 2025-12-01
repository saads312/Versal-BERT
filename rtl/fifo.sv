module fifo 
#(
    parameter integer D_W = 32,
    parameter integer DEPTH = 8
)
(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  write,
    input  wire                  read,
    input  wire signed [D_W-1:0] data_in,
    output wire                  full,
    output wire                  empty,
    output reg  signed [D_W-1:0] data_out
);

reg [$clog2(DEPTH)-1:0] rdaddr;
reg [$clog2(DEPTH)-1:0] wraddr;
reg [$clog2(DEPTH)-1:0] occup;

reg [D_W-1:0]           mem [DEPTH-1:0];

assign full = occup == (DEPTH-1) ? 1 : 0;
assign empty = occup == 0 ? 1 : 0;

always @(posedge clk) begin
    data_out <= mem[rdaddr];
    if (write)
        mem[wraddr] <= data_in;
end

always @(posedge clk) begin
    if (rst) begin
        rdaddr <= 0;
        wraddr <= 0;
        occup  <= 0;
    end else begin
        if (write) begin
            wraddr <= wraddr + 1;
        end
        if (read) begin
            rdaddr <= rdaddr + 1;
        end
        if (read && !write) begin
            occup <= occup - 1;
        end
        else if (!read && write) begin
            occup <= occup + 1;
        end
    end
end

endmodule
