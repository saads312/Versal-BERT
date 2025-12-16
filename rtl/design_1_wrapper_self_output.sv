//
// Top-level wrapper combining Block Design and RTL with XPM NoC
// Specifically for the Self-Output Stage
// Performs: LayerNorm(Linear(attention_output) + residual)
//
// All parameters should be defined in ibert_params.svh
//

`timescale 1ns / 1ps

`include "ibert_params.svh"

module design_1_wrapper_self_output (
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

    // Control interface
    input  wire        start,
    output wire        done,
    output wire        error,

    // DDR base addresses
    input  wire [63:0] addr_attn_output,  // Attention output (TOKENS × EMBED)
    input  wire [63:0] addr_weight,       // W_self_output (EMBED × EMBED)
    input  wire [63:0] addr_residual,     // Residual connection (TOKENS × EMBED)
    input  wire [63:0] addr_output,       // Output (TOKENS × EMBED)

    // Requantization parameters
    input  wire [31:0] requant_m_mm,      // Multiplier for matmul output requantization
    input  wire [7:0]  requant_e_mm,      // Exponent for matmul output requantization
    input  wire [31:0] requant_m_ln,      // Multiplier for layernorm output requantization
    input  wire [7:0]  requant_e_ln       // Exponent for layernorm output requantization
);

    // Internal signals from Block Design
    wire clk_pl;
    wire rstn_pl;

    // Block Design instance
    // Provides CIPS, NoC, and DDR4 controller
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

    // NoC Self-Output Stage RTL
    // Performs: LayerNorm(attn_output × W_self_output + residual)
    noc_self_output_top #(
        .TOKENS(TOKENS),               // Defined in ibert_params.svh
        .EMBED(EMBED),                 // Defined in ibert_params.svh
        .D_W(D_W),
        .D_W_ACC(D_W_ACC),
        .N1(N1),
        .N2(N2),
        .MATRIXSIZE_W(24),
        .MEM_DEPTH_A(4096),            // For input: TOKENS * EMBED / N1
        .MEM_DEPTH_B(8192),            // For weight: EMBED * EMBED
        .MEM_DEPTH_D(4096),            // For output
        .AXI_ADDR_WIDTH(64),
        .AXI_DATA_WIDTH(128),
        .AXI_ID_WIDTH(16)
    ) noc_self_output_top_inst (
        .clk(clk_pl),
        .rstn(rstn_pl),

        // Control
        .start(start),
        .done(done),
        .error(error),

        // DDR Addresses
        .addr_attn_output(addr_attn_output),
        .addr_weight(addr_weight),
        .addr_residual(addr_residual),
        .addr_output(addr_output),

        // Requantization Parameters
        .requant_m_mm(requant_m_mm),
        .requant_e_mm(requant_e_mm),
        .requant_m_ln(requant_m_ln),
        .requant_e_ln(requant_e_ln)
    );

endmodule
