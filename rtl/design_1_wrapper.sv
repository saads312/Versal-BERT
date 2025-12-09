//
// Top-level wrapper combining Block Design and RTL with XPM NoC
//
// All IBERT parameters are centralized in ibert_params.svh
//

`timescale 1ns / 1ps

`include "ibert_params.svh"

module design_1_wrapper (
    // DDR4 interface
    output wire        CH0_DDR4_0_act_n,
    output wire [16:0] CH0_DDR4_0_adr,
    output wire [1:0]  CH0_DDR4_0_ba,
    output wire [1:0]  CH0_DDR4_0_bg,
    output wire        CH0_DDR4_0_ck_c,
    output wire        CH0_DDR4_0_ck_t,
    output wire        CH0_DDR4_0_cke,
    output wire        CH0_DDR4_0_cs_n,
    inout  wire [7:0]  CH0_DDR4_0_dm_n,
    inout  wire [63:0] CH0_DDR4_0_dq,
    inout  wire [7:0]  CH0_DDR4_0_dqs_c,
    inout  wire [7:0]  CH0_DDR4_0_dqs_t,
    output wire        CH0_DDR4_0_odt,
    output wire        CH0_DDR4_0_reset_n,

    // System clock for DDR
    input  wire        sys_clk0_clk_n,
    input  wire        sys_clk0_clk_p,

    // Attention projection control interface
    input  wire        attn_start,
    output wire        attn_done,
    output wire        attn_error,

    // Input I (reused 3x)
    input  wire [63:0] addr_I,

    // Weights
    input  wire [63:0] addr_W_Q,
    input  wire [63:0] addr_W_K,
    input  wire [63:0] addr_W_V,

    // Outputs
    input  wire [63:0] addr_Q_prime,
    input  wire [63:0] addr_K_prime_T,
    input  wire [63:0] addr_V_prime,

    // Requantization parameters
    input  wire [31:0] requant_m_Q,
    input  wire [7:0]  requant_e_Q,
    input  wire [31:0] requant_m_K,
    input  wire [7:0]  requant_e_K,
    input  wire [31:0] requant_m_V,
    input  wire [7:0]  requant_e_V
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

    // NoC Attention Projection RTL with XPM_NMU instances
    // Performs: I × W^Q → Q', I × W^K → K'^T, I × W^V → V'
    //
    // IBERT dimensions from ibert_params.svh
    noc_attn_proj_top #(
        .TOKENS(TOKENS),
        .EMBED(EMBED),
        .HEAD_DIM(HEAD_DIM),
        .D_W(D_W),
        .D_W_ACC(D_W_ACC),
        .N1(N1),
        .N2(N2),
        .MATRIXSIZE_W(24),
        .MEM_DEPTH_A(TOKENS * EMBED / N1),  // For I
        .MEM_DEPTH_B(EMBED * HEAD_DIM),     // For W
        .MEM_DEPTH_D(TOKENS * HEAD_DIM),    // For output
        .AXI_ADDR_WIDTH(64),
        .AXI_DATA_WIDTH(128),
        .AXI_ID_WIDTH(16)
    ) noc_attn_proj_top_inst (
        .clk(clk_pl),
        .rstn(rstn_pl),
        .start(attn_start),
        .done(attn_done),
        .error(attn_error),

        // Input address
        .addr_I(addr_I),

        // Weight addresses
        .addr_W_Q(addr_W_Q),
        .addr_W_K(addr_W_K),
        .addr_W_V(addr_W_V),

        // Output addresses
        .addr_Q_prime(addr_Q_prime),
        .addr_K_prime_T(addr_K_prime_T),
        .addr_V_prime(addr_V_prime),

        // Requant parameters
        .requant_m_Q(requant_m_Q),
        .requant_e_Q(requant_e_Q),
        .requant_m_K(requant_m_K),
        .requant_e_K(requant_e_K),
        .requant_m_V(requant_m_V),
        .requant_e_V(requant_e_V)
    );

endmodule
