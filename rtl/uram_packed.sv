`timescale 1ps / 1ps

/*
uram_packed - writes 8b, reads 8b, stores 64b
*/

module uram_packed
#(
    parameter WIDTH = 32,
    parameter DEPTH = 512
)
(
    input  wire                     rst,
    input  wire                     clkA,
    input  wire                     clkB,
    input  wire                     weA,
    input  wire                     enA,
    input  wire                     enB,
    input  wire [$clog2(DEPTH)-1:0] addrA,
    input  wire [$clog2(DEPTH)-1:0] addrB,
    input  wire [WIDTH-1:0]         dinA,
    output wire [WIDTH-1:0]         doutB
);

localparam integer PACKS = 8;

reg enA_r;
reg weA_r;
reg [$clog2(DEPTH/PACKS)-1:0] mem_addrA;
wire [$clog2(DEPTH/PACKS)-1:0] mem_addrB;
reg [$clog2(PACKS)-1:0] indexB;
reg [WIDTH*PACKS-1:0] mem_dinA;
reg [WIDTH*PACKS-1:0] mem_doutB;
wire [WIDTH-1:0] unp_doutB [PACKS-1:0];

(* ram_style = "ultra" *) reg [WIDTH*PACKS-1:0] mem [0:DEPTH/PACKS-1];

always @(posedge clkA) begin
    if (rst) begin
        enA_r <= 0;
        weA_r <= 0;
        mem_addrA <= 0;
    end else begin
        enA_r <= enA;
        weA_r <= weA;
        mem_addrA <= addrA >> $clog2(PACKS);
    end
end

assign mem_addrB = addrB >> $clog2(PACKS);

genvar i;
generate
    for (i = 0; i < PACKS; i = i + 1) begin: unpacked
        assign unp_doutB[i] = mem_doutB[(i+1)*WIDTH-1-:WIDTH];
    end
endgenerate

assign doutB = unp_doutB[indexB];

always @(posedge clkA) begin
    if (rst) begin
        indexB <= 0;
    end else if (enB) begin
        indexB <= addrB[$clog2(PACKS)-1:0];
    end
end

`ifndef SYNTHESIS
integer r;
initial begin
    for (r=0; r<=DEPTH/PACKS-1; r=r+1) begin
        mem[r] = {WIDTH{1'b0}};
    end
end
`endif

always @(posedge clkA) begin
    if (enA) begin
        if (weA) begin
            mem_dinA <= {dinA, mem_dinA[WIDTH*PACKS-1:WIDTH]};
        end
    end
end

always @(posedge clkA) begin
    if (enA_r) begin
        if (weA_r) begin
            mem[mem_addrA] <= mem_dinA;
        end
    end
end

always @(posedge clkA) begin
    if (rst) begin
        mem_doutB <= 0;
    end else if (enB) begin
        mem_doutB <= mem[mem_addrB];
    end
end

endmodule
