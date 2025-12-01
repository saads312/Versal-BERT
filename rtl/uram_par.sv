`timescale 1ps / 1ps

/*
uram_par
*/

module uram_par
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

localparam int MEM_DEPTH = 4096;                        // URAM: 4Kx64b, total 256Kb
localparam real MEM_SIZE = (WIDTH * DEPTH) / 1024.0;    // total Kbits of memory
localparam int N_URAMS = int'($ceil(MEM_SIZE / 256.0)); // number of URAMs
localparam int URAM_WIDTH = WIDTH;
localparam int URAM_DEPTH = (DEPTH < MEM_DEPTH) ? DEPTH : MEM_DEPTH;

wire [N_URAMS-1:0]            uram_weA;
wire [N_URAMS-1:0]            uram_enA;
wire [N_URAMS-1:0]            uram_enB;
wire [URAM_WIDTH-1:0]         uram_dinA  [N_URAMS-1:0];
wire [URAM_WIDTH-1:0]         uram_doutB [N_URAMS-1:0];
wire [$clog2(N_URAMS):0]      uram_indexA;
wire [$clog2(N_URAMS):0]      uram_indexB;
reg  [$clog2(N_URAMS):0]      uram_indexB_r = 0;
wire [$clog2(URAM_DEPTH)-1:0] uram_addrA [N_URAMS-1:0];
wire [$clog2(URAM_DEPTH)-1:0] uram_addrB [N_URAMS-1:0];

/* verilator lint_off SELRANGE */
assign uram_indexA = (DEPTH <= URAM_DEPTH) ? 0 : addrA[$clog2(DEPTH)-1:$clog2(URAM_DEPTH)];
assign uram_indexB = (DEPTH <= URAM_DEPTH) ? 0 : addrB[$clog2(DEPTH)-1:$clog2(URAM_DEPTH)];
/* verilator lint_on SELRANGE */

assign doutB = uram_doutB[uram_indexB_r];

always @(posedge clkB) begin
    if (rst) begin
        uram_indexB_r <= 0;
    end else if (enB) begin
        uram_indexB_r <= uram_indexB;
    end
end

genvar x;
for (x = 0; x < N_URAMS; x = x + 1) begin : urams
    assign uram_weA[x] = weA & (uram_indexA == x);
    assign uram_enA[x] = enA & (uram_indexA == x);
    assign uram_enB[x] = enB & (uram_indexB == x);
    assign uram_addrA[x] = addrA[$clog2(URAM_DEPTH)-1:0];
    assign uram_addrB[x] = addrB[$clog2(URAM_DEPTH)-1:0];
    assign uram_dinA[x] = dinA;

    uram #(
        .WIDTH(URAM_WIDTH),
        .DEPTH(URAM_DEPTH)
    )
    uram_inst (
        .rst(rst),
        .clkA(clkA),
        .clkB(clkB),
        .weA(uram_weA[x]),
        .enA(uram_enA[x]),
        .enB(uram_enB[x]),
        .addrA(uram_addrA[x]),
        .addrB(uram_addrB[x]),
        .dinA(uram_dinA[x]),
        .doutB(uram_doutB[x])
    );
end

endmodule
