`timescale 1ps / 1ps

/*
mem_A
*/

module mem_A
#(
    parameter WIDTH = 32,
    parameter DEPTH = 512,
    parameter BANKS = 16
)
(
    input  wire                     rst,
    input  wire                     clkA,
    input  wire                     clkB,
    input  wire [BANKS-1:0]         weA,
    input  wire [BANKS-1:0]         enA,
    input  wire [BANKS-1:0]         enB,
    input  wire [$clog2(DEPTH)-1:0] addrA,
    input  wire [$clog2(DEPTH)-1:0] addrB,
    input  wire [WIDTH-1:0]         dinA,
    output wire [WIDTH-1:0]         doutB  [BANKS-1:0]
);

// pipeline doutB

    always @(posedge fclk) begin
        rd_data_valid_A[x] <= rd_en_A_bram[x];
    end

    if (x==0) begin
        always @(posedge clk) begin
            reg_banked_valid_A[x]      <= s_axis_s2mm_tvalid_A_r;
            reg_banked_last_A[x]       <= s_axis_s2mm_tlast_A_r;
            reg_banked_data_A[x]       <= s_axis_s2mm_tdata_A_r;
            reg_banked_write_addr_A[x] <= wr_addr_A;
            reg_banked_activate_A[x]   <= activate_A;
        end
    end else begin
        always @(posedge clk) begin
            reg_banked_valid_A[x]      <= reg_banked_valid_A[x-1];
            reg_banked_last_A[x]       <= reg_banked_last_A[x-1];
            reg_banked_data_A[x]       <= reg_banked_data_A[x-1];
            reg_banked_write_addr_A[x] <= reg_banked_write_addr_A[x-1];
            reg_banked_activate_A[x]   <= reg_banked_activate_A[x-1];
        end
    end
end

wire [WIDTH*BANKS-1:0] mem_dinA;
reg [WIDTH*BANKS-1:0] mem_doutB;

reg enA_r1;
reg weA_r1;
reg [$clog2(DEPTH)-1:0] mem_addrA;
wire [$clog2(DEPTH)-1:0] mem_addrB;

(* ram_style = "ultra" *) reg [WIDTH*BANKS-1:0] mem [0:DEPTH-1];

always @(posedge clkA) begin
    if (rst) begin
        enA_r <= 0;
        weA_r <= 0;
        mem_addrA <= 0;
    end else begin
        enA_r <= enA;
        weA_r <= weA;
        mem_addrA <= addrA;
    end
end

assign mem_addrB = enB ? addrB : addrA;

genvar i;
generate
    for (i = 0; i < BANKS; i = i + 1) begin
        assign doutB[i] = mem_doutB[(i+1)*WIDTH-1-:WIDTH];
    end
endgenerate

generate
    for (i = 0; i < BANKS; i = i + 1) begin
        assign mem_dinA[(i+1)*WIDTH-1-:WIDTH] = (enA_r1[i] && weA_r1[i]) ? dinA_r1 : doutB[i];
    end
endgenerate

`ifndef SYNTHESIS
integer r;
initial begin
    for (r=0; r<=DEPTH-1; r=r+1) begin
        mem[r] = {WIDTH{1'b0}};
    end
end
`endif

always @(posedge clkA) begin
    if (enA_r1) begin
        if (weA_r1) begin
            dinA_r1 <= dinA;
        end
    end
end

always @(posedge clkA) begin
    if (enA_r2) begin
        if (weA_r2) begin
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
