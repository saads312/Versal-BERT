`timescale 1ns / 1ps
//
// NoC Self-Output Layer End-to-End Testbench
// Tests: LayerNorm(Linear(attention_output) + residual)
//        where Linear = attention_output × W_self_output + bias
// Uses CIPS VIP API for memory access
//

`include "ibert_params.svh"

module noc_self_output_tb;

    //==========================================================================
    // Parameters (override from ibert_params.svh if needed)
    //==========================================================================
    localparam TOKENS = 32;
    localparam EMBED = 768;

    // DDR addresses
    localparam [63:0] ADDR_ATTN_OUTPUT = 64'h0001_0000;
    localparam [63:0] ADDR_WEIGHT      = 64'h0002_0000;
    localparam [63:0] ADDR_RESIDUAL    = 64'h0003_0000;
    localparam [63:0] ADDR_OUTPUT      = 64'h0004_0000;

    // Requantization parameters
    localparam [31:0] REQUANT_M_MM = 32'h0000_0100;  // Scale for matmul output
    localparam [7:0]  REQUANT_E_MM = 8'd8;           // Shift for matmul output
    localparam [31:0] REQUANT_M_LN = 32'h0000_0100;  // Scale for layernorm output
    localparam [7:0]  REQUANT_E_LN = 8'd8;           // Shift for layernorm output

    //==========================================================================
    // Clock Generation
    //==========================================================================
    reg sim_clk;
    initial begin
        sim_clk = 0;
        forever #5 sim_clk = ~sim_clk; // 100 MHz
    end

    // DDR4 system clock (200 MHz differential)
    reg sys_clk_p;
    wire sys_clk_n;
    assign sys_clk_n = !sys_clk_p;
    initial begin
        sys_clk_p = 0;
        forever #2.5 sys_clk_p = !sys_clk_p; // 200 MHz
    end

    //==========================================================================
    // DUT Interface Signals
    //==========================================================================
    wire        ch0_ddr4_0_act_n;
    wire [16:0] ch0_ddr4_0_adr;
    wire [1:0]  ch0_ddr4_0_ba;
    wire [1:0]  ch0_ddr4_0_bg;
    wire        ch0_ddr4_0_ck_c;
    wire        ch0_ddr4_0_ck_t;
    wire        ch0_ddr4_0_cke;
    wire        ch0_ddr4_0_cs_n;
    wire [7:0]  ch0_ddr4_0_dm_n;
    wire [63:0] ch0_ddr4_0_dq;
    wire [7:0]  ch0_ddr4_0_dqs_c;
    wire [7:0]  ch0_ddr4_0_dqs_t;
    wire        ch0_ddr4_0_odt;
    wire        ch0_ddr4_0_reset_n;

    // Control Signals
    reg         start;
    wire        done;
    wire        error;

    // Configuration Registers
    reg [63:0] addr_attn_output_r;
    reg [63:0] addr_weight_r;
    reg [63:0] addr_residual_r;
    reg [63:0] addr_output_r;

    reg [31:0] requant_m_mm_r;
    reg [7:0]  requant_e_mm_r;
    reg [31:0] requant_m_ln_r;
    reg [7:0]  requant_e_ln_r;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================

    // Instantiate the self-output wrapper
    design_1_wrapper_self_output dut (
        .CH0_DDR4_0_act_n(ch0_ddr4_0_act_n),
        .CH0_DDR4_0_adr(ch0_ddr4_0_adr),
        .CH0_DDR4_0_ba(ch0_ddr4_0_ba),
        .CH0_DDR4_0_bg(ch0_ddr4_0_bg),
        .CH0_DDR4_0_ck_c(ch0_ddr4_0_ck_c),
        .CH0_DDR4_0_ck_t(ch0_ddr4_0_ck_t),
        .CH0_DDR4_0_cke(ch0_ddr4_0_cke),
        .CH0_DDR4_0_cs_n(ch0_ddr4_0_cs_n),
        .CH0_DDR4_0_dm_n(ch0_ddr4_0_dm_n),
        .CH0_DDR4_0_dq(ch0_ddr4_0_dq),
        .CH0_DDR4_0_dqs_c(ch0_ddr4_0_dqs_c),
        .CH0_DDR4_0_dqs_t(ch0_ddr4_0_dqs_t),
        .CH0_DDR4_0_odt(ch0_ddr4_0_odt),
        .CH0_DDR4_0_reset_n(ch0_ddr4_0_reset_n),
        .sys_clk0_clk_n(sys_clk_n),
        .sys_clk0_clk_p(sys_clk_p),

        // DUT Control & Config
        .start(start),
        .done(done),
        .error(error),
        .addr_attn_output(addr_attn_output_r),
        .addr_weight(addr_weight_r),
        .addr_residual(addr_residual_r),
        .addr_output(addr_output_r),
        .requant_m_mm(requant_m_mm_r),
        .requant_e_mm(requant_e_mm_r),
        .requant_m_ln(requant_m_ln_r),
        .requant_e_ln(requant_e_ln_r)
    );

    //==========================================================================
    // Test Data Arrays
    //==========================================================================
    // Arrays for generating data files
    reg [7:0] matrix_attn_output [0:TOKENS*EMBED-1];
    reg [7:0] matrix_weight [0:EMBED*EMBED-1];
    reg [7:0] matrix_residual [0:TOKENS*EMBED-1];
    reg [7:0] matrix_output_expected [0:TOKENS*EMBED-1];
    reg [7:0] matrix_output_actual [0:TOKENS*EMBED-1];


endmodule
