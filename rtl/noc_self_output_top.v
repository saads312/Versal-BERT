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

//============================================================================
// AXI-Stream Signals between DMAs and mm_ln
//============================================================================
// Attention output stream
wire [D_W-1:0]     axis_attn_tdata;
wire               axis_attn_tvalid;
wire               axis_attn_tlast;
wire               axis_attn_tready;

// Weight stream
wire [D_W-1:0]     axis_weight_tdata;
wire               axis_weight_tvalid;
wire               axis_weight_tlast;
wire               axis_weight_tready;

// Residual stream
wire [D_W-1:0]     axis_residual_tdata;
wire               axis_residual_tvalid;
wire               axis_residual_tlast;
wire               axis_residual_tready;

// mm_ln output stream (8-bit quantized)
wire [D_W-1:0]     axis_output_tdata;
wire               axis_output_tvalid;
wire               axis_output_tlast;
wire               axis_output_tready;

//============================================================================
// XPM_NMU for Attention Output Read
//============================================================================
xpm_nmu_mm # (
.NOC_FABRIC("VNOC"),
.DATA_WIDTH(AXI_DATA_WIDTH),
.ADDR_WIDTH(AXI_ADDR_WIDTH),
.ID_WIDTH(AXI_ID_WIDTH),
.AUSER_WIDTH(16),
.DUSER_WIDTH(0),
.ENABLE_USR_INTERRUPT("false"),
.SIDEBAND_PINS("false")
) xpm_nmu_attn_read (
  .s_axi_aclk(clk),
  // Write channel (unused)
  .s_axi_awid({AXI_ID_WIDTH{1'b0}}),
  .s_axi_awaddr({AXI_ADDR_WIDTH{1'b0}}),
  .s_axi_awlen(8'h0),
  .s_axi_awsize(3'h0),
  .s_axi_awburst(2'b01),
  .s_axi_awlock(1'b0),
  .s_axi_awcache(4'h0),
  .s_axi_awprot(3'h0),
  .s_axi_awregion(4'h0),
  .s_axi_awqos(4'h0),
  .s_axi_awuser(16'h0),
  .s_axi_awvalid(1'b0),
  .s_axi_awready(),
  .s_axi_wid(),
  .s_axi_wdata({AXI_DATA_WIDTH{1'b0}}),
  .s_axi_wstrb({(AXI_DATA_WIDTH/8){1'b0}}),
  .s_axi_wlast(1'b0),
  .s_axi_wuser(16'h0),
  .s_axi_wvalid(1'b0),
  .s_axi_wready(),
  .s_axi_bid(),
  .s_axi_bresp(),
  .s_axi_buser(),
  .s_axi_bvalid(),
  .s_axi_bready(1'b0),

  // Read channel (active)
  .s_axi_arid(axi_attn_arid),
  .s_axi_araddr(axi_attn_araddr),
  .s_axi_arlen(axi_attn_arlen),
  .s_axi_arsize(axi_attn_arsize),
  .s_axi_arburst(axi_attn_arburst),
  .s_axi_arlock(axi_attn_arlock),
  .s_axi_arcache(axi_attn_arcache),
  .s_axi_arprot(axi_attn_arprot),
  .s_axi_arregion(4'h0),
  .s_axi_arqos(axi_attn_arqos),
  .s_axi_aruser(16'h0),
  .s_axi_arvalid(axi_attn_arvalid),
  .s_axi_arready(axi_attn_arready),
  .s_axi_rid(axi_attn_rid),
  .s_axi_rdata(axi_attn_rdata),
  .s_axi_rresp(axi_attn_rresp),
  .s_axi_rlast(axi_attn_rlast),
  .s_axi_ruser(),
  .s_axi_rvalid(axi_attn_rvalid),
  .s_axi_rready(axi_attn_rready),

  .nmu_usr_interrupt_in(4'b0)


);

//============================================================================
// XPM_NMU for Weight Read
//============================================================================
xpm_nmu_mm # (
  .NOC_FABRIC("VNOC"),
  .DATA_WIDTH(AXI_DATA_WIDTH),
  .ADDR_WIDTH(AXI_ADDR_WIDTH),
  .ID_WIDTH(AXI_ID_WIDTH),
  .AUSER_WIDTH(16),
  .DUSER_WIDTH(0),
  .ENABLE_USR_INTERRUPT("false"),
  .SIDEBAND_PINS("false")
) xpm_nmu_weight_read (
  .s_axi_aclk(clk),
  // Write channel (unused)
  .s_axi_awid({AXI_ID_WIDTH{1'b0}}),
  .s_axi_awaddr({AXI_ADDR_WIDTH{1'b0}}),
  .s_axi_awlen(8'h0),
  .s_axi_awsize(3'h0),
  .s_axi_awburst(2'b01),
  .s_axi_awlock(1'b0),
  .s_axi_awcache(4'h0),
  .s_axi_awprot(3'h0),
  .s_axi_awregion(4'h0),
  .s_axi_awqos(4'h0),
  .s_axi_awuser(16'h0),
  .s_axi_awvalid(1'b0),
  .s_axi_awready(),
  .s_axi_wid(),
  .s_axi_wdata({AXI_DATA_WIDTH{1'b0}}),
  .s_axi_wstrb({(AXI_DATA_WIDTH/8){1'b0}}),
  .s_axi_wlast(1'b0),
  .s_axi_wuser(16'h0),
  .s_axi_wvalid(1'b0),
  .s_axi_wready(),
  .s_axi_bid(),
  .s_axi_bresp(),
  .s_axi_buser(),
  .s_axi_bvalid(),
  .s_axi_bready(1'b0),

  // Read channel (active)
  .s_axi_arid(axi_weight_arid),
  .s_axi_araddr(axi_weight_araddr),
  .s_axi_arlen(axi_weight_arlen),
  .s_axi_arsize(axi_weight_arsize),
  .s_axi_arburst(axi_weight_arburst),
  .s_axi_arlock(axi_weight_arlock),
  .s_axi_arcache(axi_weight_arcache),
  .s_axi_arprot(axi_weight_arprot),
  .s_axi_arregion(4'h0),
  .s_axi_arqos(axi_weight_arqos),
  .s_axi_aruser(16'h0),
  .s_axi_arvalid(axi_weight_arvalid),
  .s_axi_arready(axi_weight_arready),
  .s_axi_rid(axi_weight_rid),
  .s_axi_rdata(axi_weight_rdata),
  .s_axi_rresp(axi_weight_rresp),
  .s_axi_rlast(axi_weight_rlast),
  .s_axi_ruser(),
  .s_axi_rvalid(axi_weight_rvalid),
  .s_axi_rready(axi_weight_rready),
  .nmu_usr_interrupt_in(4'b0)

);

//============================================================================
// XPM_NMU for Residual Read
//============================================================================
xpm_nmu_mm # (
  .NOC_FABRIC("VNOC"),
  .DATA_WIDTH(AXI_DATA_WIDTH),
  .ADDR_WIDTH(AXI_ADDR_WIDTH),
  .ID_WIDTH(AXI_ID_WIDTH),
  .AUSER_WIDTH(16),
  .DUSER_WIDTH(0),
  .ENABLE_USR_INTERRUPT("false"),
  .SIDEBAND_PINS("false")
) xpm_nmu_residual_read (
  .s_axi_aclk(clk),
  // Write channel (unused)
  .s_axi_awid({AXI_ID_WIDTH{1'b0}}),
  .s_axi_awaddr({AXI_ADDR_WIDTH{1'b0}}),
  .s_axi_awlen(8'h0),
  .s_axi_awsize(3'h0),
  .s_axi_awburst(2'b01),
  .s_axi_awlock(1'b0),
  .s_axi_awcache(4'h0),
  .s_axi_awprot(3'h0),
  .s_axi_awregion(4'h0),
  .s_axi_awqos(4'h0),
  .s_axi_awuser(16'h0),
  .s_axi_awvalid(1'b0),
  .s_axi_awready(),
  .s_axi_wid(),
  .s_axi_wdata({AXI_DATA_WIDTH{1'b0}}),
  .s_axi_wstrb({(AXI_DATA_WIDTH/8){1'b0}}),
  .s_axi_wlast(1'b0),
  .s_axi_wuser(16'h0),
  .s_axi_wvalid(1'b0),
  .s_axi_wready(),
  .s_axi_bid(),
  .s_axi_bresp(),
  .s_axi_buser(),
  .s_axi_bvalid(),
  .s_axi_bready(1'b0),

  // Read channel (active)
  .s_axi_arid(axi_residual_arid),
  .s_axi_araddr(axi_residual_araddr),
  .s_axi_arlen(axi_residual_arlen),
  .s_axi_arsize(axi_residual_arsize),
  .s_axi_arburst(axi_residual_arburst),
  .s_axi_arlock(axi_residual_arlock),
  .s_axi_arcache(axi_residual_arcache),
  .s_axi_arprot(axi_residual_arprot),
  .s_axi_arregion(4'h0),
  .s_axi_arqos(axi_residual_arqos),
  .s_axi_aruser(16'h0),
  .s_axi_arvalid(axi_residual_arvalid),
  .s_axi_arready(axi_residual_arready),
  .s_axi_rid(axi_residual_rid),
  .s_axi_rdata(axi_residual_rdata),
  .s_axi_rresp(axi_residual_rresp),
  .s_axi_rlast(axi_residual_rlast),
  .s_axi_ruser(),
  .s_axi_rvalid(axi_residual_rvalid),
  .s_axi_rready(axi_residual_rready),

  .nmu_usr_interrupt_in(4'b0)
);

//============================================================================
// XPM_NMU for Output Write
//============================================================================
xpm_nmu_mm # (
 .NOC_FABRIC("VNOC"),
 .DATA_WIDTH(AXI_DATA_WIDTH),
 .ADDR_WIDTH(AXI_ADDR_WIDTH),
 .ID_WIDTH(AXI_ID_WIDTH),
 .AUSER_WIDTH(16),
 .DUSER_WIDTH(0),
 .ENABLE_USR_INTERRUPT("false"),
 .SIDEBAND_PINS("false")
) xpm_nmu_output_write (
  .s_axi_aclk(clk),
  // Write channel (active)
  .s_axi_awid(axi_out_awid),
  .s_axi_awaddr(axi_out_awaddr),
  .s_axi_awlen(axi_out_awlen),
  .s_axi_awsize(axi_out_awsize),
  .s_axi_awburst(axi_out_awburst),
  .s_axi_awlock(axi_out_awlock),
  .s_axi_awcache(axi_out_awcache),
  .s_axi_awprot(axi_out_awprot),
  .s_axi_awregion(4'h0),
  .s_axi_awqos(axi_out_awqos),
  .s_axi_awuser(16'h0),
  .s_axi_awvalid(axi_out_awvalid),
  .s_axi_awready(axi_out_awready),
  .s_axi_wid(),
  .s_axi_wdata(axi_out_wdata),
  .s_axi_wstrb(axi_out_wstrb),
  .s_axi_wlast(axi_out_wlast),
  .s_axi_wuser(16'h0),
  .s_axi_wvalid(axi_out_wvalid),
  .s_axi_wready(axi_out_wready),
  .s_axi_bid(axi_out_bid),
  .s_axi_bresp(axi_out_bresp),
  .s_axi_buser(),
  .s_axi_bvalid(axi_out_bvalid),
  .s_axi_bready(axi_out_bready),

  // Read channel (unused)
  .s_axi_arid({AXI_ID_WIDTH{1'b0}}),
  .s_axi_araddr({AXI_ADDR_WIDTH{1'b0}}),
  .s_axi_arlen(8'h0),
  .s_axi_arsize(3'h0),
  .s_axi_arburst(2'b01),
  .s_axi_arlock(1'b0),
  .s_axi_arcache(4'h0),
  .s_axi_arprot(3'h0),
  .s_axi_arregion(4'h0),
  .s_axi_arqos(4'h0),
  .s_axi_aruser(16'h0),
  .s_axi_arvalid(1'b0),
  .s_axi_arready(),
  .s_axi_rid(),
  .s_axi_rdata(),
  .s_axi_rresp(),
  .s_axi_rlast(),
  .s_axi_ruser(),
  .s_axi_rvalid(),
  .s_axi_rready(1'b0),

  .nmu_usr_interrupt_in(4'b0)
);

//============================================================================
// Read DMA for Attention Output
//============================================================================
axi4_read_dma #(
.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
.AXI_ID_WIDTH(AXI_ID_WIDTH),
.AXIS_DATA_WIDTH(D_W),
.MAX_BURST_LEN(256)
) dma_read_attn (
.aclk(clk),
.aresetn(rstn),


  .start_addr(addr_attn_output),
  .transfer_length(size_attn_output),
  .start(start_dma_attn),
  .done(dma_attn_done),
  .error(dma_attn_error),

  .m_axi_arid(axi_attn_arid),
  .m_axi_araddr(axi_attn_araddr),
  .m_axi_arlen(axi_attn_arlen),
  .m_axi_arsize(axi_attn_arsize),
  .m_axi_arburst(axi_attn_arburst),
  .m_axi_arlock(axi_attn_arlock),
  .m_axi_arcache(axi_attn_arcache),
  .m_axi_arprot(axi_attn_arprot),
  .m_axi_arqos(axi_attn_arqos),
  .m_axi_arvalid(axi_attn_arvalid),
  .m_axi_arready(axi_attn_arready),

  .m_axi_rid(axi_attn_rid),
  .m_axi_rdata(axi_attn_rdata),
  .m_axi_rresp(axi_attn_rresp),
  .m_axi_rlast(axi_attn_rlast),
  .m_axi_rvalid(axi_attn_rvalid),
  .m_axi_rready(axi_attn_rready),

  .m_axis_tdata(axis_attn_tdata),
  .m_axis_tvalid(axis_attn_tvalid),
  .m_axis_tlast(axis_attn_tlast),
  .m_axis_tready(axis_attn_tready)
);

//============================================================================
// Read DMA for Weight
//============================================================================
axi4_read_dma #(
.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
.AXI_ID_WIDTH(AXI_ID_WIDTH),
.AXIS_DATA_WIDTH(D_W),
.MAX_BURST_LEN(256)
) dma_read_weight (
  .aclk(clk),
  .aresetn(rstn),
  .start_addr(addr_weight),
  .transfer_length(size_weight),
  .start(start_dma_weight),
  .done(dma_weight_done),
  .error(dma_weight_error),

  .m_axi_arid(axi_weight_arid),
  .m_axi_araddr(axi_weight_araddr),
  .m_axi_arlen(axi_weight_arlen),
  .m_axi_arsize(axi_weight_arsize),
  .m_axi_arburst(axi_weight_arburst),
  .m_axi_arlock(axi_weight_arlock),
  .m_axi_arcache(axi_weight_arcache),
  .m_axi_arprot(axi_weight_arprot),
  .m_axi_arqos(axi_weight_arqos),
  .m_axi_arvalid(axi_weight_arvalid),
  .m_axi_arready(axi_weight_arready),

  .m_axi_rid(axi_weight_rid),
  .m_axi_rdata(axi_weight_rdata),
  .m_axi_rresp(axi_weight_rresp),
  .m_axi_rlast(axi_weight_rlast),
  .m_axi_rvalid(axi_weight_rvalid),
  .m_axi_rready(axi_weight_rready),

  .m_axis_tdata(axis_weight_tdata),
  .m_axis_tvalid(axis_weight_tvalid),
  .m_axis_tlast(axis_weight_tlast),
  .m_axis_tready(axis_weight_tready)
);

//============================================================================
// Read DMA for Residual
//============================================================================
axi4_read_dma #(
.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
.AXI_ID_WIDTH(AXI_ID_WIDTH),
.AXIS_DATA_WIDTH(D_W),
.MAX_BURST_LEN(256)
) dma_read_residual (
  .aclk(clk),
  .aresetn(rstn),

  .start_addr(addr_residual),
  .transfer_length(size_residual),
  .start(start_dma_residual),
  .done(dma_residual_done),
  .error(dma_residual_error),

  .m_axi_arid(axi_residual_arid),
  .m_axi_araddr(axi_residual_araddr),
  .m_axi_arlen(axi_residual_arlen),
  .m_axi_arsize(axi_residual_arsize),
  .m_axi_arburst(axi_residual_arburst),
  .m_axi_arlock(axi_residual_arlock),
  .m_axi_arcache(axi_residual_arcache),
  .m_axi_arprot(axi_residual_arprot),
  .m_axi_arqos(axi_residual_arqos),
  .m_axi_arvalid(axi_residual_arvalid),
  .m_axi_arready(axi_residual_arready),

  .m_axi_rid(axi_residual_rid),
  .m_axi_rdata(axi_residual_rdata),
  .m_axi_rresp(axi_residual_rresp),
  .m_axi_rlast(axi_residual_rlast),
  .m_axi_rvalid(axi_residual_rvalid),
  .m_axi_rready(axi_residual_rready),

  .m_axis_tdata(axis_residual_tdata),
  .m_axis_tvalid(axis_residual_tvalid),
  .m_axis_tlast(axis_residual_tlast),
  .m_axis_tready(axis_residual_tready)
);

//============================================================================
// Complete Self-Output Pipeline:
// mm → requant_mm → mat_add (with requant_res) → layer_norm → requant_out
//============================================================================

// Intermediate AXI-Stream signals between pipeline stages
wire [D_W_ACC-1:0] axis_mm_out_tdata;
wire               axis_mm_out_tvalid;
wire               axis_mm_out_tlast;
wire               axis_mm_out_tready;

wire [D_W_ACC-1:0] axis_requant_mm_tdata;
wire               axis_requant_mm_tvalid;
wire               axis_requant_mm_tlast;
wire               axis_requant_mm_tready;

wire [D_W_ACC-1:0] axis_requant_res_tdata;
wire               axis_requant_res_tvalid;
wire               axis_requant_res_tlast;
wire               axis_requant_res_tready;

wire signed [21:0] axis_matadd_tdata;  // LN_BITS = 22
wire               axis_matadd_tvalid;
wire               axis_matadd_tlast;
wire               axis_matadd_tready;

wire [D_W_ACC-1:0] axis_layernorm_tdata;
wire               axis_layernorm_tvalid;
wire               axis_layernorm_tlast;
wire               axis_layernorm_tready;

// Constant stream wires for requant parameters
wire req_mm_bias_tready, req_mm_m_tready, req_mm_e_tready;
wire req_res_bias_tready, req_res_m_tready, req_res_e_tready;
wire req_out_bias_tready, req_out_m_tready, req_out_e_tready;
wire ln_bias_tready;

//============================================================================
// Stage 1: Matrix Multiply (attention_output × weight)
//============================================================================
mm #(
.D_W(D_W),
.D_W_ACC(D_W_ACC),
.N1(N1),
.N2(N2),
.MATRIXSIZE_W(MATRIXSIZE_W),
.KEEP_A(0),                         // Don't keep A (not reusing)
.MEM_DEPTH_A(MEM_DEPTH_A),
.MEM_DEPTH_B(MEM_DEPTH_B),
.MEM_DEPTH_D(MEM_DEPTH_D),
.P_B(1),
.TRANSPOSE_B(0)
) mm_inst (
  .mm_clk(clk),
  .mm_fclk(clk),
  .mm_rst_n(rstn),

  // Input A (attention output)
  .s_axis_s2mm_tdata_A(axis_attn_tdata),
  .s_axis_s2mm_tlast_A(axis_attn_tlast),
  .s_axis_s2mm_tready_A(axis_attn_tready),
  .s_axis_s2mm_tvalid_A(axis_attn_tvalid),

  // Input B (weight)
  .s_axis_s2mm_tdata_B(axis_weight_tdata),
  .s_axis_s2mm_tlast_B(axis_weight_tlast),
  .s_axis_s2mm_tready_B(axis_weight_tready),
  .s_axis_s2mm_tvalid_B(axis_weight_tvalid),

  // Output (32-bit accumulator)
  .m_axis_mm2s_tdata(axis_mm_out_tdata),
  .m_axis_mm2s_tvalid(axis_mm_out_tvalid),
  .m_axis_mm2s_tready(axis_mm_out_tready),
  .m_axis_mm2s_tlast(axis_mm_out_tlast),

  // Matrix dimensions
  .M2(M2),                            // EMBED
  .M3(M3),                            // EMBED
  .M1xM3dN1(M1xM3dN1),
  .M1dN1(M1dN1),
  .M3dN2(M3dN2),
  .M1xM3dN1xN2(M1xM3dN1xN2)


);

//============================================================================
// Stage 2: Requantization after MatMul (32-bit → 32-bit, no clipping)
// Scales the matmul output: out = (in + bias) * m >> e
//============================================================================
requant #(
.D_W_ACC(D_W_ACC),
.D_W(D_W),
.OUT_BITS(D_W_ACC),                 // Keep 32-bit output
.CLIP(0)                            // No clipping
) requant_mm (
  .clk(clk),
  .rst(~rstn),

  // Input from MM
  .in_tdata(axis_mm_out_tdata),
  .in_tvalid(axis_mm_out_tvalid),
  .in_tready(axis_mm_out_tready),
  .in_tlast(axis_mm_out_tlast),

  // Bias stream (constant = 0)
  .in_tdata_bias({D_W_ACC{1'b0}}),
  .in_tvalid_bias(axis_mm_out_tvalid),
  .in_tready_bias(req_mm_bias_tready),
  .in_tlast_bias(axis_mm_out_tlast),

  // Multiplier stream (from top-level input)
  .in_tdata_m(requant_m_mm),
  .in_tvalid_m(axis_mm_out_tvalid),
  .in_tready_m(req_mm_m_tready),
  .in_tlast_m(axis_mm_out_tlast),

  // Exponent stream (from top-level input)
  .in_tdata_e(requant_e_mm),
  .in_tvalid_e(axis_mm_out_tvalid),
  .in_tready_e(req_mm_e_tready),
  .in_tlast_e(axis_mm_out_tlast),

  // Output (32-bit)
  .out_tdata(axis_requant_mm_tdata),
  .out_tvalid(axis_requant_mm_tvalid),
  .out_tready(axis_requant_mm_tready),
  .out_tlast(axis_requant_mm_tlast)


);

//============================================================================
// Stage 3: Requantization for Residual (8-bit → 32-bit, no clipping)
// Converts residual to same precision as matmul output
//============================================================================
requant #(
.D_W_ACC(D_W),                      // Input is 8-bit
.D_W(D_W),
.OUT_BITS(D_W_ACC),                 // Output is 32-bit
.CLIP(0)                            // No clipping
) requant_res (
  .clk(clk),
  .rst(~rstn),

  // Input residual (8-bit)
  .in_tdata({{(D_W_ACC-D_W){axis_residual_tdata[D_W-1]}}, axis_residual_tdata}),  // Sign extend
  .in_tvalid(axis_residual_tvalid),
  .in_tready(axis_residual_tready),
  .in_tlast(axis_residual_tlast),

  // Bias stream (constant = 0)
  .in_tdata_bias({D_W_ACC{1'b0}}),
  .in_tvalid_bias(axis_residual_tvalid),
  .in_tready_bias(req_res_bias_tready),
  .in_tlast_bias(axis_residual_tlast),

  // Multiplier stream (use default 1.0 or provide parameter)
  .in_tdata_m(32'h0000_0100),         // Scale = 1.0 (adjust as needed)
  .in_tvalid_m(axis_residual_tvalid),
  .in_tready_m(req_res_m_tready),
  .in_tlast_m(axis_residual_tlast),

  // Exponent stream
  .in_tdata_e(8'd8),                  // Shift = 8 (adjust as needed)
  .in_tvalid_e(axis_residual_tvalid),
  .in_tready_e(req_res_e_tready),
  .in_tlast_e(axis_residual_tlast),

  // Output (32-bit)
  .out_tdata(axis_requant_res_tdata),
  .out_tvalid(axis_requant_res_tvalid),
  .out_tready(axis_requant_res_tready),
  .out_tlast(axis_requant_res_tlast)


);

//============================================================================
// Stage 4: Matrix Add (matmul_output + residual)
// Two 32-bit inputs → 22-bit output
//============================================================================
mat_add #(
.D_W(D_W_ACC),                      // 32-bit inputs
.OUT_BITS(22)                       // 22-bit output (LN_BITS)
) mat_add_inst (
  .clk(clk),
  .rst(~rstn),

  // Input R (residual, requantized to 32-bit)
  .in_tdata_R(axis_requant_res_tdata),
  .in_tlast_R(axis_requant_res_tlast),
  .in_tready_R(axis_requant_res_tready),
  .in_tvalid_R(axis_requant_res_tvalid),

  // Input Y (matmul output, requantized to 32-bit)
  .in_tdata_Y(axis_requant_mm_tdata),
  .in_tlast_Y(axis_requant_mm_tlast),
  .in_tready_Y(axis_requant_mm_tready),
  .in_tvalid_Y(axis_requant_mm_tvalid),

  // Output Z (22-bit)
  .out_tdata_Z(axis_matadd_tdata),
  .out_tvalid_Z(axis_matadd_tvalid),
  .out_tready_Z(axis_matadd_tready),
  .out_tlast_Z(axis_matadd_tlast)

);

//============================================================================
// Stage 5: Layer Normalization
// 22-bit input → 32-bit output
//============================================================================
layer_norm_top #(
.X_W(32),
.D_W(D_W),
.D_W_ACC(D_W_ACC),
.LN_BITS(22),
.MATRIXSIZE_W(MATRIXSIZE_W)
) layer_norm_inst (
  .clk(clk),
  .rst(~rstn),

  // Bias input (constant = 0 for now, or add DMA later)
  .s_axis_s2mm_tdata_bias({32{1'b0}}),
  .s_axis_s2mm_tlast_bias(axis_matadd_tlast),
  .s_axis_s2mm_tready_bias(ln_bias_tready),
  .s_axis_s2mm_tvalid_bias(axis_matadd_tvalid),

  // Input data (22-bit from mat_add)
  .qin_tdata(axis_matadd_tdata),
  .qin_tlast(axis_matadd_tlast),
  .qin_tready(axis_matadd_tready),
  .qin_tvalid(axis_matadd_tvalid),

  // Output (32-bit)
  .qout_tdata(axis_layernorm_tdata),
  .qout_tlast(axis_layernorm_tlast),
  .qout_tready(axis_layernorm_tready),
  .qout_tvalid(axis_layernorm_tvalid),

  // Dimensions
  .DIM1(M1),                          // TOKENS
  .DIM2(M3)                           // EMBED


);

//============================================================================
// Stage 6: Final Requantization (32-bit → 8-bit with clipping)
//============================================================================
requant #(
.D_W_ACC(D_W_ACC),
.D_W(D_W),
.OUT_BITS(D_W),                     // 8-bit output
.CLIP(1)                            // Enable clipping
) requant_out (
  .clk(clk),
  .rst(~rstn),

  // Input from layer norm (32-bit)
  .in_tdata(axis_layernorm_tdata),
  .in_tvalid(axis_layernorm_tvalid),
  .in_tready(axis_layernorm_tready),
  .in_tlast(axis_layernorm_tlast),

  // Bias stream (constant = 0)
  .in_tdata_bias({D_W_ACC{1'b0}}),
  .in_tvalid_bias(axis_layernorm_tvalid),
  .in_tready_bias(req_out_bias_tready),
  .in_tlast_bias(axis_layernorm_tlast),

  // Multiplier stream (from top-level input)
  .in_tdata_m(requant_m_ln),
  .in_tvalid_m(axis_layernorm_tvalid),
  .in_tready_m(req_out_m_tready),
  .in_tlast_m(axis_layernorm_tlast),

  // Exponent stream (from top-level input)
  .in_tdata_e(requant_e_ln),
  .in_tvalid_e(axis_layernorm_tvalid),
  .in_tready_e(req_out_e_tready),
  .in_tlast_e(axis_layernorm_tlast),

  // Output (8-bit)
  .out_tdata(axis_output_tdata),
  .out_tvalid(axis_output_tvalid),
  .out_tready(axis_output_tready),
  .out_tlast(axis_output_tlast)


);

// Compute done detection - based on final output tlast
reg compute_output_complete;
always @(posedge clk) begin
    if (!rstn) begin
        compute_output_complete <= 1'b0;
    end else begin
        if (start_compute) begin
            compute_output_complete <= 1'b0;
        end else if (axis_output_tvalid && axis_output_tready && axis_output_tlast) begin
            compute_output_complete <= 1'b1;
        end
    end
end
assign compute_done = compute_output_complete;

//============================================================================
// Write DMA for Output
//============================================================================
axi4_write_dma #(
.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
.AXI_ID_WIDTH(AXI_ID_WIDTH),
.AXIS_DATA_WIDTH(D_W),
.MAX_BURST_LEN(256)
) dma_write_output (
  .aclk(clk),
  .aresetn(rstn),

  .start_addr(addr_output),
  .transfer_length(size_output),
  .start(start_dma_out),
  .done(dma_out_done),
  .error(dma_out_error),

  .s_axis_tdata(axis_output_tdata),
  .s_axis_tvalid(axis_output_tvalid),
  .s_axis_tlast(axis_output_tlast),
  .s_axis_tready(axis_output_tready),

  .m_axi_awid(axi_out_awid),
  .m_axi_awaddr(axi_out_awaddr),
  .m_axi_awlen(axi_out_awlen),
  .m_axi_awsize(axi_out_awsize),
  .m_axi_awburst(axi_out_awburst),
  .m_axi_awlock(axi_out_awlock),
  .m_axi_awcache(axi_out_awcache),
  .m_axi_awprot(axi_out_awprot),
  .m_axi_awqos(axi_out_awqos),
  .m_axi_awvalid(axi_out_awvalid),
  .m_axi_awready(axi_out_awready),

  .m_axi_wdata(axi_out_wdata),
  .m_axi_wstrb(axi_out_wstrb),
  .m_axi_wlast(axi_out_wlast),
  .m_axi_wvalid(axi_out_wvalid),
  .m_axi_wready(axi_out_wready),

  .m_axi_bid(axi_out_bid),
  .m_axi_bresp(axi_out_bresp),
  .m_axi_bvalid(axi_out_bvalid),
  .m_axi_bready(axi_out_bready)
);

endmodule
