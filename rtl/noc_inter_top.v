// NoC-based Intermediate Stage Top Level
// Performs a matrix multiply and GELU with requantization:
//      A~ x K'^T --> requant --> G --> GELU --> G~
//
// Architecture:
//      DDR (A~)    --> XPM_NMU     --> Read DMA    --> AXI Stream  --\
//      DDR (K'^T)  --> XPM_NMU     --> Read DMA    --> AXI Stream  --> MM --> Requant --> GELU -->
//      Requant     --> AXI Stream  --> Write DMA   --> XPM_NMU     --> DDR (G~)
//

`timescale 1ns / 1ps

module noc_inter_top #(
    // Matrix dimensions
    parameter INPUT_SIZE = 32,          // Input size (rows of A~)
    parameter HIDDEN_SIZE = 768,        // Hidden size (cols of A~, rows of K'^T)
    parameter EXP_SIZE = 3072,          // Per-head dimension (cols of K'^T)

    // Data widths
    parameter D_W = 8,                  // Data width (8-bit quantized)
    parameter D_W_ACC = 32,             // Accumulator width

    // Systolic array dimensions
    parameter N1 = 2,                   // Systolic array rows
    parameter N2 = 2,                   // Systolic array columns
    parameter MATRIXSIZE_W = 24,        // Matrix size register width

    // Memory parameters
    parameter MEM_DEPTH_A = INPUT_SIZE * HIDDEN_SIZE / N1,      // For A~
    parameter MEM_DEPTH_B = HIDDEN_SIZE * EXP_SIZE / N1,        // For K'T
    parameter MEM_DEPTH_D = INPUT_SIZE * EXP_SIZE / N1,         // For G

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
    input wire [AXI_ADDR_WIDTH-1:0] addr_A,
    input wire [AXI_ADDR_WIDTH-1:0] addr_K,
    input wire [AXI_ADDR_WIDTH-1:0] addr_G,

    // Requantization parameters (could also be loaded from DDR)
    input wire [D_W_ACC-1:0] requant_m_mult,
    input wire [D_W-1:0]     requant_e_mult,
    input wire [D_W_ACC-1:0] requant_m_G,
    input wire [D_W-1:0]     requant_e_G,
);

// Internal clocks
wire mm_clk, mm_rst_n;
assign mm_clk = clk;
assign mm_rst_n = rstn;

// Matrix dimension calculations
localparam [MATRIXSIZE_W-1:0] M1 = INPUT_SIZE;
localparam [MATRIXSIZE_W-1:0] M2 = HIDDEN_SIZE;
localparam [MATRIXSIZE_W-1:0] M3 = EXP_SIZE;

wire [MATRIXSIZE_W-1:0] M1dN1 = M1 / N1;
wire [MATRIXSIZE_W-1:0] M3dN2 = M3 / N2;
wire [MATRIXSIZE_W-1:0] M1xM3dN1 = (M1 * M3) / N1;
wire [MATRIXSIZE_W-1:0] M1xM3dN1xN2 = (M1 * M3) / (N1 * N2);

// Transfer sizes in bytes
wire [31:0] size_A = M1 * M2;
wire [31:0] size_K = M2 * M3;
wire [31:0] size_G_acc = M1 * M3 * (D_W_ACC/8);
wire [31:0] size_G_req = M1 * M3;

// Control signals
wire start_dma_a, start_dma_k, start_dma_g;
wire start_requant_mm, requant_mm_done;
wire start_requant_gelu, requant_gelu_done;
wire dma_a_done, dma_k_done, dma_g_done;
wire dma_a_error, dma_k_error, dma_g_error;
wire mm_done;
wire start_gelu, gelu_done;

//============================================================================
// Control FSM
//============================================================================

//============================================================================
// AXI4 Signals for Input A Read Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_a_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_a_araddr;
wire [7:0]                 axi_a_arlen;
wire [2:0]                 axi_a_arsize;
wire [1:0]                 axi_a_arburst;
wire                       axi_a_arlock;
wire [3:0]                 axi_a_arcache;
wire [2:0]                 axi_a_arprot;
wire [3:0]                 axi_a_arqos;
wire                       axi_a_arvalid;
wire                       axi_a_arready;
wire [AXI_ID_WIDTH-1:0]    axi_a_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_a_rdata;
wire [1:0]                 axi_a_rresp;
wire                       axi_a_rlast;
wire                       axi_a_rvalid;
wire                       axi_a_rready;

//============================================================================
// AXI4 Signals for Weight K'^T Read Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_k_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_k_araddr;
wire [7:0]                 axi_k_arlen;
wire [2:0]                 axi_k_arsize;
wire [1:0]                 axi_k_arburst;
wire                       axi_k_arlock;
wire [3:0]                 axi_k_arcache;
wire [2:0]                 axi_k_arprot;
wire [3:0]                 axi_k_arqos;
wire                       axi_k_arvalid;
wire                       axi_k_arready;
wire [AXI_ID_WIDTH-1:0]    axi_k_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_k_rdata;
wire [1:0]                 axi_k_rresp;
wire                       axi_k_rlast;
wire                       axi_k_rvalid;
wire                       axi_k_rready;

//============================================================================
// AXI4 Signals for Output G Write Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]      axi_g_awid;
wire [AXI_ADDR_WIDTH-1:0]    axi_g_awaddr;
wire [7:0]                   axi_g_awlen;
wire [2:0]                   axi_g_awsize;
wire [1:0]                   axi_g_awburst;
wire                         axi_g_awlock;
wire [3:0]                   axi_g_awcache;
wire [2:0]                   axi_g_awprot;
wire [3:0]                   axi_g_awqos;
wire                         axi_g_awvalid;
wire                         axi_g_awready;
wire [AXI_DATA_WIDTH-1:0]    axi_g_wdata;
wire [AXI_DATA_WIDTH/8-1:0]  axi_g_wstrb;
wire                         axi_g_wlast;
wire                         axi_g_wvalid;
wire                         axi_g_wready;
wire [AXI_ID_WIDTH-1:0]      axi_g_bid;
wire [1:0]                   axi_g_bresp;
wire                         axi_g_bvalid;
wire                         axi_g_bready;

//============================================================================
// AXI-Stream Signals between DMAs and MM/Requant/GELU
//============================================================================
// Input A stream to MM
wire [D_W-1:0]     axis_a_tdata;
wire               axis_a_tvalid;
wire               axis_a_tlast;
wire               axis_a_tready;

// Weight K'T stream to MM
wire [D_W-1:0]     axis_k_tdata;
wire               axis_k_tvalid;
wire               axis_k_tlast;
wire               axis_k_tready;

// MM output (32-bit accumulator)
wire [D_W_ACC-1:0] axis_mm_out_tdata;
wire               axis_mm_out_tvalid;
wire               axis_mm_out_tlast;
wire               axis_mm_out_tready;

// Requant MM output (8-bit)
wire [D_W-1:0]     axis_req_mm_out_tdata;
wire               axis_req_mm_out_tvalid;
wire               axis_req_mm_out_tlast;
wire               axis_req_mm_out_tready;

// GELU output (32-bit accumulator)
wire [D_W_ACC-1:0] axis_gelu_out_tdata;
wire               axis_gelu_out_tvalid;
wire               axis_gelu_out_tlast;
wire               axis_gelu_out_tready;

// Requant GELU output (8-bit)
wire [D_W-1:0]     axis_req_gelu_out_tdata;
wire               axis_req_gelu_out_tvalid;
wire               axis_req_gelu_out_tlast;
wire               axis_req_gelu_out_tready;

//============================================================================
// XPM_NMU for Input A Read
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
) xpm_nmu_input_a (
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
    .s_axi_arid(axi_a_arid),
    .s_axi_araddr(axi_a_araddr),
    .s_axi_arlen(axi_a_arlen),
    .s_axi_arsize(axi_a_arsize),
    .s_axi_arburst(axi_a_arburst),
    .s_axi_arlock(axi_a_arlock),
    .s_axi_arcache(axi_a_arcache),
    .s_axi_arprot(axi_a_arprot),
    .s_axi_arregion(4'h0),
    .s_axi_arqos(axi_a_arqos),
    .s_axi_aruser(16'h0),
    .s_axi_arvalid(axi_a_arvalid),
    .s_axi_arready(axi_a_arready),
    .s_axi_rid(axi_a_rid),
    .s_axi_rdata(axi_a_rdata),
    .s_axi_rresp(axi_a_rresp),
    .s_axi_rlast(axi_a_rlast),
    .s_axi_ruser(),
    .s_axi_rvalid(axi_a_rvalid),
    .s_axi_rready(axi_a_rready),

    .nmu_usr_interrupt_in(4'b0)
);

//============================================================================
// XPM_NMU for Weight K'^T Read
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
) xpm_nmu_weight_k (
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
    .s_axi_arid(axi_k_arid),
    .s_axi_araddr(axi_k_araddr),
    .s_axi_arlen(axi_k_arlen),
    .s_axi_arsize(axi_k_arsize),
    .s_axi_arburst(axi_k_arburst),
    .s_axi_arlock(axi_k_arlock),
    .s_axi_arcache(axi_k_arcache),
    .s_axi_arprot(axi_k_arprot),
    .s_axi_arregion(4'h0),
    .s_axi_arqos(axi_k_arqos),
    .s_axi_aruser(16'h0),
    .s_axi_arvalid(axi_k_arvalid),
    .s_axi_arready(axi_k_arready),
    .s_axi_rid(axi_k_rid),
    .s_axi_rdata(axi_k_rdata),
    .s_axi_rresp(axi_k_rresp),
    .s_axi_rlast(axi_k_rlast),
    .s_axi_ruser(),
    .s_axi_rvalid(axi_k_rvalid),
    .s_axi_rready(axi_k_rready),

    .nmu_usr_interrupt_in(4'b0)
);

//============================================================================
// XPM_NMU for Output G Write
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
) xpm_nmu_out_g (
    .s_axi_aclk(clk),

    // Write channel (active)
    .s_axi_awid(axi_g_awid),
    .s_axi_awaddr(axi_g_awaddr),
    .s_axi_awlen(axi_g_awlen),
    .s_axi_awsize(axi_g_awsize),
    .s_axi_awburst(axi_g_awburst),
    .s_axi_awlock(axi_g_awlock),
    .s_axi_awcache(axi_g_awcache),
    .s_axi_awprot(axi_g_awprot),
    .s_axi_awregion(4'h0),
    .s_axi_awqos(axi_g_awqos),
    .s_axi_awuser(16'h0),
    .s_axi_awvalid(axi_g_awvalid),
    .s_axi_awready(axi_g_awready),
    .s_axi_wid(),
    .s_axi_wdata(axi_g_wdata),
    .s_axi_wstrb(axi_g_wstrb),
    .s_axi_wlast(axi_g_wlast),
    .s_axi_wuser(16'h0),
    .s_axi_wvalid(axi_g_wvalid),
    .s_axi_wready(axi_g_wready),
    .s_axi_bid(axi_g_bid),
    .s_axi_bresp(axi_g_bresp),
    .s_axi_buser(),
    .s_axi_bvalid(axi_g_bvalid),
    .s_axi_bready(axi_g_bready),

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
// Read DMA for Input A
//============================================================================
axi4_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_read_a (
    .aclk(clk),
    .aresetn(rstn),

    .start_addr(addr_A),
    .transfer_length(size_A),
    .start(start_dma_a),
    .done(dma_a_done),
    .error(dma_a_error),

    .m_axi_arid(axi_a_arid),
    .m_axi_araddr(axi_a_araddr),
    .m_axi_arlen(axi_a_arlen),
    .m_axi_arsize(axi_a_arsize),
    .m_axi_arburst(axi_a_arburst),
    .m_axi_arlock(axi_a_arlock),
    .m_axi_arcache(axi_a_arcache),
    .m_axi_arprot(axi_a_arprot),
    .m_axi_arqos(axi_a_arqos),
    .m_axi_arvalid(axi_a_arvalid),
    .m_axi_arready(axi_a_arready),

    .m_axi_rid(axi_a_rid),
    .m_axi_rdata(axi_a_rdata),
    .m_axi_rresp(axi_a_rresp),
    .m_axi_rlast(axi_a_rlast),
    .m_axi_rvalid(axi_a_rvalid),
    .m_axi_rready(axi_a_rready),

    .m_axis_tdata(axis_a_tdata),
    .m_axis_tvalid(axis_a_tvalid),
    .m_axis_tlast(axis_a_tlast),
    .m_axis_tready(axis_a_tready)
);

//============================================================================
// Read DMA for Weight K'^T
//============================================================================
axi4_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_read_k (
    .aclk(clk),
    .aresetn(rstn),

    .start_addr(addr_K),
    .transfer_length(size_K),
    .start(start_dma_k),
    .done(dma_k_done),
    .error(dma_k_error),

    .m_axi_arid(axi_k_arid),
    .m_axi_araddr(axi_k_araddr),
    .m_axi_arlen(axi_k_arlen),
    .m_axi_arsize(axi_k_arsize),
    .m_axi_arburst(axi_k_arburst),
    .m_axi_arlock(axi_k_arlock),
    .m_axi_arcache(axi_k_arcache),
    .m_axi_arprot(axi_k_arprot),
    .m_axi_arqos(axi_k_arqos),
    .m_axi_arvalid(axi_k_arvalid),
    .m_axi_arready(axi_k_arready),

    .m_axi_rid(axi_k_rid),
    .m_axi_rdata(axi_k_rdata),
    .m_axi_rresp(axi_k_rresp),
    .m_axi_rlast(axi_k_rlast),
    .m_axi_rvalid(axi_k_rvalid),
    .m_axi_rready(axi_k_rready),

    .m_axis_tdata(axis_k_tdata),
    .m_axis_tvalid(axis_k_tvalid),
    .m_axis_tlast(axis_k_tlast),
    .m_axis_tready(axis_k_tready)
);

//============================================================================
// Matrix Multiply Core
//============================================================================
mm #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .N1(N1),
    .N2(N2),
    .MATRIXSIZE_W(MATRIXSIZE_W),
    .KEEP_A(1),
    .MEM_DEPTH_A(MEM_DEPTH_A),
    .MEM_DEPTH_B(MEM_DEPTH_B),
    .MEM_DEPTH_D(MEM_DEPTH_D),
    .P_B(1),
    .TRANSPOSE_B(0)                 // might need to use for K'^T
) mm_core (
    .mm_clk(mm_clk),
    .mm_fclk(mm_clk),
    .mm_rst_n(mm_rst_n),

    .s_axis_s2mm_tdata_A(axis_a_tdata),
    .s_axis_s2mm_tlast_A(axis_a_tlast),
    .s_axis_s2mm_tready_A(axis_a_tready),
    .s_axis_s2mm_tvalid_A(axis_a_tvalid),

    .s_axis_s2mm_tdata_B(axis_k_tdata),
    .s_axis_s2mm_tlast_B(axis_k_tlast),
    .s_axis_s2mm_tready_B(axis_k_tready),
    .s_axis_s2mm_tvalid_B(axis_k_tvalid),

    .m_axis_mm2s_tdata(axis_mm_out_tdata),
    .m_axis_mm2s_tvalid(axis_mm_out_tvalid),
    .m_axis_mm2s_tready(axis_mm_out_tready),
    .m_axis_mm2s_tlast(axis_mm_out_tlast),

    .M2(M2),
    .M3(M3),
    .M1xM3dN1(M1xM3dN1),
    .M1dN1(M1dN1),
    .M3dN2(M3dN2),
    .M1xM3dN1xN2(M1xM3dN1xN2)
);

// MM done detection (based on output tlast)
reg mm_output_complete;
always @(posedge clk) begin
    if (!rstn) begin
        mm_output_complete <= 1'b0;
    end else begin
        if (start_dma_a) begin
            mm_output_complete <= 1'b0;
        end else if (axis_mm_out_tvalid && axis_mm_out_tready && axis_mm_out_tlast) begin
            mm_output_complete <= 1'b1;
        end
    end
end
assign mm_done = mm_output_complete;

//============================================================================
// Requantization Module for MM
// out = clip((in + bias) × m >> e)
// For now, bias = 0 for simplicity
//
// The requant module expects streaming interfaces for bias, m, e.
// We provide constant values by keeping tvalid high and matching tlast.
//============================================================================

// Generate constant parameter streams that match input data stream
wire req_mm_bias_tready, req_mm_m_tready, req_mm_e_tready;

requant #(
    .D_W_ACC(D_W_ACC),
    .D_W(D_W),
    .OUT_BITS(D_W),
    .CLIP(1)
) requant_mm (
    .clk(clk),
    .rst(~rstn),

    // Input data stream from MM
    .in_tdata(axis_mm_out_tdata),
    .in_tvalid(axis_mm_out_tvalid),
    .in_tready(axis_mm_out_tready),
    .in_tlast(axis_mm_out_tlast),

    // Bias stream (constant = 0)
    .in_tdata_bias({D_W_ACC{1'b0}}),
    .in_tvalid_bias(axis_mm_out_tvalid),  // Match data stream valid
    .in_tready_bias(req_mm_bias_tready),
    .in_tlast_bias(axis_mm_out_tlast),    // Match data stream last

    // Multiplier stream
    .in_tdata_m(requant_m_mult),
    .in_tvalid_m(axis_mm_out_tvalid),     // Match data stream valid
    .in_tready_m(req_mm_m_tready),
    .in_tlast_m(axis_mm_out_tlast),       // Match data stream last

    // Exponent stream (from current_requant_e)
    .in_tdata_e(requant_e_mult),
    .in_tvalid_e(axis_mm_out_tvalid),     // Match data stream valid
    .in_tready_e(req_mm_e_tready),
    .in_tlast_e(axis_mm_out_tlast),       // Match data stream last

    // Output stream
    .out_tdata(axis_req_mm_out_tdata),
    .out_tvalid(axis_req_mm_out_tvalid),
    .out_tready(axis_req_mm_out_tready),
    .out_tlast(axis_req_mm_out_tlast)
);

// Requant done detection
reg requant_mm_output_complete;
always @(posedge clk) begin
    if (!rstn) begin
        requant_mm_output_complete <= 1'b0;
    end else begin
        if (start_requant_mm) begin
            requant_mm_output_complete <= 1'b0;
        end else if (axis_req_mm_out_tvalid && axis_req_mm_out_tready && axis_req_mm_out_tlast) begin
            requant_mm_output_complete <= 1'b1;
        end
    end
end
assign requant_gelu_done = requant_mm_output_complete;

//============================================================================
// GELU core
//============================================================================
gelu_top #(
    .D_W(D_W),
    .D_W_ACC(D_W),
    .MATRIXSIZE_W(MATRIXSIZE_W)
) gelu_core (
    .clk(clk),
    .rst(~rstn),

    // Input stream from requant_mm
    .qin_tdata(axis_req_mm_out_tdata),
    .qin_tlast(axis_req_mm_out_tlast),
    .qin_tready(axis_req_mm_out_tready),
    .qin_tvalid(axis_req_mm_out_tvalid),

    // Output stream
    .qout_tdata(axis_gelu_out_tdata),
    .qout_tlast(axis_gelu_out_tlast),
    .qout_tready(axis_gelu_out_tready),
    .qout_tvalid(axis_gelu_out_tvalid),

    // Matrix dimensions
    .DIM1(INPUT_SIZE),
    .DIM2(EXP_SIZE)
);

reg gelu_output_complete;
always @(posedge clk) begin
    if (!rstn) begin
        gelu_output_complete <= 1'b0;
    end else begin
        if (start_gelu) begin
            gelu_output_complete <= 1'b0;
        end else if (axis_gelu_out_tvalid && axis_gelu_out_tready && axis_gelu_out_tlast) begin
            gelu_output_complete <= 1'b1;
        end
end
assign gelu_done = gelu_output_complete;

//============================================================================
// Requantization Module for GELU
// out = clip((in + bias) × m >> e)
// For now, bias = 0 for simplicity
//
// The requant module expects streaming interfaces for bias, m, e.
// We provide constant values by keeping tvalid high and matching tlast.
//============================================================================

// Generate constant parameter streams that match input data stream
wire req_gelu_bias_tready, req_gelu_m_tready, req_gelu_e_tready;

requant #(
    .D_W_ACC(D_W_ACC),
    .D_W(D_W),
    .OUT_BITS(D_W),
    .CLIP(1)
) requant_mm (
    .clk(clk),
    .rst(~rstn),

    // Input data stream from MM
    .in_tdata(axis_gelu_out_tdata),
    .in_tvalid(axis_gelu_out_tvalid),
    .in_tready(axis_gelu_out_tready),
    .in_tlast(axis_gelu_out_tlast),

    // Bias stream (constant = 0)
    .in_tdata_bias({D_W_ACC{1'b0}}),
    .in_tvalid_bias(axis_gelu_out_tvalid),  // Match data stream valid
    .in_tready_bias(req_gelu_bias_tready),
    .in_tlast_bias(axis_gelu_out_tlast),    // Match data stream last

    // Multiplier stream
    .in_tdata_m(requant_m_G),
    .in_tvalid_m(axis_gelu_out_tvalid),     // Match data stream valid
    .in_tready_m(req_gelu_m_tready),
    .in_tlast_m(axis_gelu_out_tlast),       // Match data stream last

    // Exponent stream (from current_requant_e)
    .in_tdata_e(requant_e_G),
    .in_tvalid_e(axis_gelu_out_tvalid),     // Match data stream valid
    .in_tready_e(req_gelu_e_tready),
    .in_tlast_e(axis_gelu_out_tlast),       // Match data stream last

    // Output stream
    .out_tdata(axis_req_gelu_out_tdata),
    .out_tvalid(axis_req_gelu_out_tvalid),
    .out_tready(axis_req_gelu_out_tready),
    .out_tlast(axis_req_gelu_out_tlast)
);

// Requant done detection
reg requant_gelu_output_complete;
always @(posedge clk) begin
    if (!rstn) begin
        requant_gelu_output_complete <= 1'b0;
    end else begin
        if (start_requant_gelu) begin
            requant_gelu_output_complete <= 1'b0;
        end else if (axis_req_gelu_out_tvalid && axis_req_gelu_out_tready && axis_req_gelu_out_tlast) begin
            requant_gelu_output_complete <= 1'b1;
        end
    end
end
assign requant_gelu_done = requant_gelu_output_complete;

//============================================================================
// Write DMA for Output G
//============================================================================
axi4_write_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_write_out (
    .aclk(clk),
    .aresetn(rstn),

    .start_addr(addr_G),
    .transfer_length(size_G_req),
    .start(start_dma_g),
    .done(dma_g_done),
    .error(dma_g_error),

    .s_axis_tdata(axis_req_gelu_out_tdata),
    .s_axis_tvalid(axis_req_gelu_out_tvalid),
    .s_axis_tlast(axis_req_gelu_out_tlast),
    .s_axis_tready(axis_req_gelu_out_tready),

    .m_axi_awid(axi_g_awid),
    .m_axi_awaddr(axi_g_awaddr),
    .m_axi_awlen(axi_g_awlen),
    .m_axi_awsize(axi_g_awsize),
    .m_axi_awburst(axi_g_awburst),
    .m_axi_awlock(axi_g_awlock),
    .m_axi_awcache(axi_g_awcache),
    .m_axi_awprot(axi_g_awprot),
    .m_axi_awqos(axi_g_awqos),
    .m_axi_awvalid(axi_g_awvalid),
    .m_axi_awready(axi_g_awready),

    .m_axi_wdata(axi_g_wdata),
    .m_axi_wstrb(axi_g_wstrb),
    .m_axi_wlast(axi_g_wlast),
    .m_axi_wvalid(axi_g_wvalid),
    .m_axi_wready(axi_g_wready),

    .m_axi_bid(axi_g_bid),
    .m_axi_bresp(axi_g_bresp),
    .m_axi_bvalid(axi_g_bvalid),
    .m_axi_bready(axi_g_bready)
);

endmodule
