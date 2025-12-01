//
// NoC Matrix Multiply Wrapper
// Connects to Block Design (CIPS, DDR, NoC)
//

`timescale 1ns / 1ps

module noc_mm_wrapper #(
    parameter D_W = 8,
    parameter D_W_ACC = 32,
    parameter N1 = 2,
    parameter N2 = 2,
    parameter MATRIXSIZE_W = 24,
    parameter MEM_DEPTH_A = 1024,
    parameter MEM_DEPTH_B = 2048,
    parameter MEM_DEPTH_D = 512,
    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_DATA_WIDTH = 128,
    parameter AXI_ID_WIDTH = 16
)(
    input wire clk_pl,
    input wire rstn_pl,

    // Control signals (from VIO or AXI-Lite)
    input wire start,
    output wire done,
    output wire error,

    // Configuration
    input wire [MATRIXSIZE_W-1:0] M1,
    input wire [MATRIXSIZE_W-1:0] M2,
    input wire [MATRIXSIZE_W-1:0] M3,
    input wire [AXI_ADDR_WIDTH-1:0] addr_matrix_a,
    input wire [AXI_ADDR_WIDTH-1:0] addr_matrix_b,
    input wire [AXI_ADDR_WIDTH-1:0] addr_matrix_d
);

noc_mm_top #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .N1(N1),
    .N2(N2),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .MEM_DEPTH_A(MEM_DEPTH_A),
    .MEM_DEPTH_B(MEM_DEPTH_B),
    .MEM_DEPTH_D(MEM_DEPTH_D),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH)
) noc_mm_top_inst (
    .clk(clk_pl),
    .rstn(rstn_pl),
    .start(start),
    .done(done),
    .error(error),
    .M1(M1),
    .M2(M2),
    .M3(M3),
    .addr_matrix_a(addr_matrix_a),
    .addr_matrix_b(addr_matrix_b),
    .addr_matrix_d(addr_matrix_d)
);

endmodule
