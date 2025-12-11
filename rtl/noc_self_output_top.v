//
// Self Output Layer top file
// Performs: LayerNorm(Linear(attention_output) + residual)
//   where Linear = attention_output × W_self_output + bias
//
// Architecture:
//   DDR (attn_output) -> XPM_NMU -> Read DMA -> AXI-Stream --
//   DDR (weight)      -> XPM_NMU -> Read DMA -> AXI-Stream ---> mm_ln -> AXI-Stream ->
//   DDR (residual)    -> XPM_NMU -> Read DMA -> AXI-Stream --/   Write DMA -> XPM_NMU -> DDR (output)
// 

`timescale 1ns / 1ps

module noc_self_output_top #(
// Matrix dimensions
parameter TOKENS = 32,                 // Sequence length
parameter EMBED = 768,                 // Embedding dimension


  // Data widths
  parameter D_W = 8,                     // Data width (8-bit quantized)
  parameter D_W_ACC = 32,                // Accumulator width

  // Systolic array dimensions
  parameter N1 = 2,                      // Systolic array rows
  parameter N2 = 2,                      // Systolic array columns
  parameter MATRIXSIZE_W = 24,           // Matrix size register width

  // Memory parameters (for mm_ln internal memories)
  parameter MEM_DEPTH_A = 4096,          // For input: TOKENS * EMBED / N1
  parameter MEM_DEPTH_B = 8192,          // For weight: EMBED * EMBED
  parameter MEM_DEPTH_D = 4096,          // For output

  // NoC/AXI parameters
  parameter AXI_ADDR_WIDTH = 64,
  parameter AXI_DATA_WIDTH = 128,
  parameter AXI_ID_WIDTH = 16


)(
input wire clk,
input wire rstn,


  // Control interface
  input wire start,
  output wire done,
  output wire error,

  // DDR base addresses
  input wire [AXI_ADDR_WIDTH-1:0] addr_attn_output,  // Attention output (TOKENS × EMBED)
  input wire [AXI_ADDR_WIDTH-1:0] addr_weight,       // W_self_output (EMBED × EMBED)
  input wire [AXI_ADDR_WIDTH-1:0] addr_residual,     // Residual connection (TOKENS × EMBED)
  input wire [AXI_ADDR_WIDTH-1:0] addr_output,       // Output (TOKENS × EMBED)

  // Requantization parameters for mm_ln
  input wire [D_W_ACC-1:0] requant_m_mm,   // For matmul output requantization
  input wire [D_W-1:0]     requant_e_mm,
  input wire [D_W_ACC-1:0] requant_m_ln,   // For layernorm output requantization
  input wire [D_W-1:0]     requant_e_ln


);

// Internal clocks
wire compute_clk, compute_rst_n;
assign compute_clk = clk;
assign compute_rst_n = rstn;

// Matrix dimension calculations
localparam [MATRIXSIZE_W-1:0] M1 = TOKENS;           // 32
localparam [MATRIXSIZE_W-1:0] M2 = EMBED;            // 768
localparam [MATRIXSIZE_W-1:0] M3 = EMBED;            // 768 (output dimension same as input)

wire [MATRIXSIZE_W-1:0] M1dN1 = M1 / N1;
wire [MATRIXSIZE_W-1:0] M3dN2 = M3 / N2;
wire [MATRIXSIZE_W-1:0] M1xM3dN1 = (M1  *M3) / N1;
wire [MATRIXSIZE_W-1:0] M1xM3dN1xN2 = (M1*  M3) / (N1 * N2);

// Transfer sizes in bytes
wire [31:0] size_attn_output = M1  *M2;     // 32*  768 = 24576 bytes
wire [31:0] size_weight = M2  *M3;          // 768*  768 = 589824 bytes
wire [31:0] size_residual = M1  *M2;        // 32*  768 = 24576 bytes
wire [31:0] size_output = M1  *M3;          // 32*  768 = 24576 bytes (8-bit quantized)

// Control signals from FSM
wire start_dma_attn, start_dma_weight, start_dma_residual, start_dma_out;
wire start_compute;
wire dma_attn_done, dma_weight_done, dma_residual_done, dma_out_done;
wire dma_attn_error, dma_weight_error, dma_residual_error, dma_out_error;
wire compute_done;

//============================================================================
// Control FSM
//============================================================================
noc_self_output_control control_fsm (
.clk(clk),
.rstn(rstn),
.start(start),
.done(done),
.error(error),


  // DMA control
  .start_dma_attn(start_dma_attn),
  .start_dma_weight(start_dma_weight),
  .start_dma_residual(start_dma_residual),
  .start_dma_out(start_dma_out),

  // DMA status
  .dma_attn_done(dma_attn_done),
  .dma_weight_done(dma_weight_done),
  .dma_residual_done(dma_residual_done),
  .dma_out_done(dma_out_done),
  .dma_attn_error(dma_attn_error),
  .dma_weight_error(dma_weight_error),
  .dma_residual_error(dma_residual_error),
  .dma_out_error(dma_out_error),

  // Compute control
  .start_compute(start_compute),
  .compute_done(compute_done)


);

//============================================================================
// AXI4 Signals for Attention Output Read Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_attn_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_attn_araddr;
wire [7:0]                 axi_attn_arlen;
wire [2:0]                 axi_attn_arsize;
wire [1:0]                 axi_attn_arburst;
wire                       axi_attn_arlock;
wire [3:0]                 axi_attn_arcache;
wire [2:0]                 axi_attn_arprot;
wire [3:0]                 axi_attn_arqos;
wire                       axi_attn_arvalid;
wire                       axi_attn_arready;
wire [AXI_ID_WIDTH-1:0]    axi_attn_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_attn_rdata;
wire [1:0]                 axi_attn_rresp;
wire                       axi_attn_rlast;
wire                       axi_attn_rvalid;
wire                       axi_attn_rready;

//============================================================================
// AXI4 Signals for Weight Read Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_weight_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_weight_araddr;
wire [7:0]                 axi_weight_arlen;
wire [2:0]                 axi_weight_arsize;
wire [1:0]                 axi_weight_arburst;
wire                       axi_weight_arlock;
wire [3:0]                 axi_weight_arcache;
wire [2:0]                 axi_weight_arprot;
wire [3:0]                 axi_weight_arqos;
wire                       axi_weight_arvalid;
wire                       axi_weight_arready;
wire [AXI_ID_WIDTH-1:0]    axi_weight_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_weight_rdata;
wire [1:0]                 axi_weight_rresp;
wire                       axi_weight_rlast;
wire                       axi_weight_rvalid;
wire                       axi_weight_rready;

//============================================================================
// AXI4 Signals for Residual Read Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_residual_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_residual_araddr;
wire [7:0]                 axi_residual_arlen;
wire [2:0]                 axi_residual_arsize;
wire [1:0]                 axi_residual_arburst;
wire                       axi_residual_arlock;
wire [3:0]                 axi_residual_arcache;
wire [2:0]                 axi_residual_arprot;
wire [3:0]                 axi_residual_arqos;
wire                       axi_residual_arvalid;
wire                       axi_residual_arready;
wire [AXI_ID_WIDTH-1:0]    axi_residual_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_residual_rdata;
wire [1:0]                 axi_residual_rresp;
wire                       axi_residual_rlast;
wire                       axi_residual_rvalid;
wire                       axi_residual_rready;

//============================================================================
// AXI4 Signals for Output Write Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]      axi_out_awid;
wire [AXI_ADDR_WIDTH-1:0]    axi_out_awaddr;
wire [7:0]                   axi_out_awlen;
wire [2:0]                   axi_out_awsize;
wire [1:0]                   axi_out_awburst;
wire                         axi_out_awlock;
wire [3:0]                   axi_out_awcache;
wire [2:0]                   axi_out_awprot;
wire [3:0]                   axi_out_awqos;
wire                         axi_out_awvalid;
wire                         axi_out_awready;
wire [AXI_DATA_WIDTH-1:0]    axi_out_wdata;
wire [AXI_DATA_WIDTH/8-1:0]  axi_out_wstrb;
wire                         axi_out_wlast;
wire                         axi_out_wvalid;
wire                         axi_out_wready;
wire [AXI_ID_WIDTH-1:0]      axi_out_bid;
wire [1:0]                   axi_out_bresp;
wire                         axi_out_bvalid;
wire                         axi_out_bready;


endmodule
