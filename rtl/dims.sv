`timescale 1ps / 1ps
package dims;
parameter integer P_MATRIXSIZE_W = 24;

typedef struct packed {
    logic [P_MATRIXSIZE_W-1:0] M1;
    logic [P_MATRIXSIZE_W-1:0] M2;
    logic [P_MATRIXSIZE_W-1:0] M3;
    logic [P_MATRIXSIZE_W-1:0] M1xM3dN1;
    logic [P_MATRIXSIZE_W-1:0] M1dN1;
    logic [P_MATRIXSIZE_W-1:0] M3dN2;
    logic [P_MATRIXSIZE_W-1:0] M1xM3dN1xN2;
    logic [P_MATRIXSIZE_W-1:0] M1xM2;
    logic [P_MATRIXSIZE_W-1:0] M1xM3;
    logic [P_MATRIXSIZE_W-1:0] M1xM1dN1;
    logic [P_MATRIXSIZE_W-1:0] M1dN2;
    logic [P_MATRIXSIZE_W-1:0] M1xM1dN1xN1;
    logic [P_MATRIXSIZE_W-1:0] BLOCKS;
    logic [P_MATRIXSIZE_W-1:0] BLOCK_WIDTH;
    logic [P_MATRIXSIZE_W-1:0] BLOCK_WIDTHdN2;
    logic [P_MATRIXSIZE_W-1:0] BLOCK_SIZEdN2;
    logic [P_MATRIXSIZE_W-1:0] M1xBLOCK_WIDTHdN1xN2;
    logic [P_MATRIXSIZE_W-1:0] M1xBLOCK_WIDTHdN1;
    logic [P_MATRIXSIZE_W-1:0] BLOCKS_A;
    logic [P_MATRIXSIZE_W-1:0] BLOCK_WIDTH_A;
} dimensions;

endpackage
