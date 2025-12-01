`timescale 1ps / 1ps

module rom 
#(
    parameter integer D_W  = 32,
    parameter integer DEPTH = 768,
    parameter         INIT = "NONE"
)
(
    input  wire                     clk,
    input  wire [$clog2(DEPTH)-1:0] rdaddr,
    output reg signed     [D_W-1:0] rddata
);

(* rom_style = "distributed" *) reg [D_W-1:0] mem[0:DEPTH-1];
// reg [D_W-1:0] mem[DEPTH-1:0];

initial begin
    if (INIT != "NONE")
        $readmemh(INIT, mem);
end

always @(posedge clk) begin
    rddata <= mem[rdaddr];
end

endmodule
