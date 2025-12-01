//
// Top-level wrapper combining Block Design and RTL with XPM NoC
// Based on Vivado Design Tutorial pattern
//

`timescale 1ns / 1ps

module design_1_wrapper (
    // DDR4 interface
    output        CH0_DDR4_0_act_n,
    output [16:0] CH0_DDR4_0_adr,
    output [1:0]  CH0_DDR4_0_ba,
    output [1:0]  CH0_DDR4_0_bg,
    output        CH0_DDR4_0_ck_c,
    output        CH0_DDR4_0_ck_t,
    output        CH0_DDR4_0_cke,
    output        CH0_DDR4_0_cs_n,
    inout  [7:0]  CH0_DDR4_0_dm_n,
    inout  [63:0] CH0_DDR4_0_dq,
    inout  [7:0]  CH0_DDR4_0_dqs_c,
    inout  [7:0]  CH0_DDR4_0_dqs_t,
    output        CH0_DDR4_0_odt,
    output        CH0_DDR4_0_reset_n,

    // System clock for DDR
    input         sys_clk0_clk_n,
    input         sys_clk0_clk_p,

    // Matrix multiply control interface (exposed for testbench)
    input         mm_start,
    output        mm_done,
    output        mm_error,
    input  [23:0] mm_M1,
    input  [23:0] mm_M2,
    input  [23:0] mm_M3,
    input  [63:0] mm_addr_matrix_a,
    input  [63:0] mm_addr_matrix_b,
    input  [63:0] mm_addr_matrix_d
);

    // Internal signals from Block Design
    wire clk_pl;
    wire rstn_pl;

    // Block Design instance
    design_1 design_1_i (
        .CH0_DDR4_0_act_n(CH0_DDR4_0_act_n),
        .CH0_DDR4_0_adr(CH0_DDR4_0_adr),
        .CH0_DDR4_0_ba(CH0_DDR4_0_ba),
        .CH0_DDR4_0_bg(CH0_DDR4_0_bg),
        .CH0_DDR4_0_ck_c(CH0_DDR4_0_ck_c),
        .CH0_DDR4_0_ck_t(CH0_DDR4_0_ck_t),
        .CH0_DDR4_0_cke(CH0_DDR4_0_cke),
        .CH0_DDR4_0_cs_n(CH0_DDR4_0_cs_n),
        .CH0_DDR4_0_dm_n(CH0_DDR4_0_dm_n),
        .CH0_DDR4_0_dq(CH0_DDR4_0_dq),
        .CH0_DDR4_0_dqs_c(CH0_DDR4_0_dqs_c),
        .CH0_DDR4_0_dqs_t(CH0_DDR4_0_dqs_t),
        .CH0_DDR4_0_odt(CH0_DDR4_0_odt),
        .CH0_DDR4_0_reset_n(CH0_DDR4_0_reset_n),
        .sys_clk0_clk_n(sys_clk0_clk_n),
        .sys_clk0_clk_p(sys_clk0_clk_p),
        .clk_pl(clk_pl),
        .rstn_pl(rstn_pl)
    );

    // NoC Matrix Multiply RTL with XPM_NMU instances
    noc_mm_top #(
        .D_W(8),
        .D_W_ACC(32),
        .N1(2),
        .N2(2),
        .MATRIXSIZE_W(24),
        .MEM_DEPTH_A(1024),
        .MEM_DEPTH_B(2048),
        .MEM_DEPTH_D(512),
        .AXI_ADDR_WIDTH(64),
        .AXI_DATA_WIDTH(128),
        .AXI_ID_WIDTH(16)
    ) noc_mm_top_inst (
        .clk(clk_pl),
        .rstn(rstn_pl),
        .start(mm_start),
        .done(mm_done),
        .error(mm_error),
        .M1(mm_M1),
        .M2(mm_M2),
        .M3(mm_M3),
        .addr_matrix_a(mm_addr_matrix_a),
        .addr_matrix_b(mm_addr_matrix_b),
        .addr_matrix_d(mm_addr_matrix_d)
    );

endmodule
