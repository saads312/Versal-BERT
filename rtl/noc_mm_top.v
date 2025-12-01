//
// NoC-based Matrix Multiply Top Level
// Minimal scalable design using llm_rtl mm.sv with XPM NoC macros
//
// Architecture:
//   DDR (Matrix A) -> XPM_NMU -> Read DMA -> AXI-Stream ->
//   DDR (Matrix B) -> XPM_NMU -> Read DMA -> AXI-Stream -> MM (Systolic Array) -> AXI-Stream ->
//   Write DMA -> XPM_NSU -> DDR (Matrix D)
//

`timescale 1ns / 1ps

module noc_mm_top #(
    // Matrix dimensions - Start small and scalable
    parameter D_W = 8,                    // Data width (8-bit for efficiency)
    parameter D_W_ACC = 32,               // Accumulator width
    parameter N1 = 2,                     // Systolic array rows
    parameter N2 = 2,                     // Systolic array columns
    parameter MATRIXSIZE_W = 24,          // Matrix size register width

    // Memory parameters
    parameter MEM_DEPTH_A = 1024,
    parameter MEM_DEPTH_B = 2048,
    parameter MEM_DEPTH_D = 512,

    // NoC/AXI parameters
    parameter AXI_ADDR_WIDTH = 64,
    parameter AXI_DATA_WIDTH = 128,
    parameter AXI_ID_WIDTH = 16
)(
    input wire clk,
    input wire rstn,

    // Control interface (would connect to VIO or AXI-Lite slave)
    input wire start,
    output wire done,
    output wire error,

    // Matrix dimension inputs
    input wire [MATRIXSIZE_W-1:0] M1,    // Rows of A
    input wire [MATRIXSIZE_W-1:0] M2,    // Cols of A / Rows of B
    input wire [MATRIXSIZE_W-1:0] M3,    // Cols of B

    // DDR base addresses
    input wire [AXI_ADDR_WIDTH-1:0] addr_matrix_a,
    input wire [AXI_ADDR_WIDTH-1:0] addr_matrix_b,
    input wire [AXI_ADDR_WIDTH-1:0] addr_matrix_d
);

// Internal signals
wire mm_clk, mm_rst_n;
assign mm_clk = clk;
assign mm_rst_n = rstn;

// Calculated sizes
wire [31:0] size_a = M1 * M2;  // bytes for matrix A
wire [31:0] size_b = M2 * M3;  // bytes for matrix B
wire [31:0] size_d = M1 * M3 * (D_W_ACC/8);  // bytes for matrix D

wire [MATRIXSIZE_W-1:0] M1dN1 = M1 / N1;
wire [MATRIXSIZE_W-1:0] M3dN2 = M3 / N2;
wire [MATRIXSIZE_W-1:0] M1xM3dN1 = (M1 * M3) / N1;
wire [MATRIXSIZE_W-1:0] M1xM3dN1xN2 = (M1 * M3) / (N1 * N2);

//============================================================================
// AXI4 Signals for Matrix A Read Path (NoC Master)
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
// AXI4 Signals for Matrix B Read Path (NoC Master)
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_b_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_b_araddr;
wire [7:0]                 axi_b_arlen;
wire [2:0]                 axi_b_arsize;
wire [1:0]                 axi_b_arburst;
wire                       axi_b_arlock;
wire [3:0]                 axi_b_arcache;
wire [2:0]                 axi_b_arprot;
wire [3:0]                 axi_b_arqos;
wire                       axi_b_arvalid;
wire                       axi_b_arready;
wire [AXI_ID_WIDTH-1:0]    axi_b_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_b_rdata;
wire [1:0]                 axi_b_rresp;
wire                       axi_b_rlast;
wire                       axi_b_rvalid;
wire                       axi_b_rready;

//============================================================================
// AXI4 Signals for Matrix D Write Path (NoC Master)
//============================================================================
wire [AXI_ID_WIDTH-1:0]      axi_d_awid;
wire [AXI_ADDR_WIDTH-1:0]    axi_d_awaddr;
wire [7:0]                   axi_d_awlen;
wire [2:0]                   axi_d_awsize;
wire [1:0]                   axi_d_awburst;
wire                         axi_d_awlock;
wire [3:0]                   axi_d_awcache;
wire [2:0]                   axi_d_awprot;
wire [3:0]                   axi_d_awqos;
wire                         axi_d_awvalid;
wire                         axi_d_awready;
wire [AXI_DATA_WIDTH-1:0]    axi_d_wdata;
wire [AXI_DATA_WIDTH/8-1:0]  axi_d_wstrb;
wire                         axi_d_wlast;
wire                         axi_d_wvalid;
wire                         axi_d_wready;
wire [AXI_ID_WIDTH-1:0]      axi_d_bid;
wire [1:0]                   axi_d_bresp;
wire                         axi_d_bvalid;
wire                         axi_d_bready;

//============================================================================
// AXI-Stream Signals between DMAs and Matrix Multiply
//============================================================================
wire [D_W-1:0]     axis_a_tdata;
wire               axis_a_tvalid;
wire               axis_a_tlast;
wire               axis_a_tready;

wire [D_W-1:0]     axis_b_tdata;
wire               axis_b_tvalid;
wire               axis_b_tlast;
wire               axis_b_tready;

wire [D_W_ACC-1:0] axis_d_tdata;
wire               axis_d_tvalid;
wire               axis_d_tlast;
wire               axis_d_tready;

// DMA control signals
wire dma_a_done, dma_a_error;
wire dma_b_done, dma_b_error;
wire dma_d_done, dma_d_error;

// Control FSM signals
wire start_dma_a, start_dma_b, start_dma_d;

// Control FSM instance
noc_mm_control control_fsm (
    .clk(clk),
    .rstn(rstn),
    .start(start),
    .done(done),
    .error(error),
    .start_dma_a(start_dma_a),
    .start_dma_b(start_dma_b),
    .start_dma_d(start_dma_d),
    .dma_a_done(dma_a_done),
    .dma_b_done(dma_b_done),
    .dma_d_done(dma_d_done),
    .dma_a_error(dma_a_error),
    .dma_b_error(dma_b_error),
    .dma_d_error(dma_d_error)
);

//============================================================================
// XPM_NMU for Matrix A Read (PL to DDR via NoC)
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
) xpm_nmu_matrix_a (
    .s_axi_aclk(clk),

    // Write channel (unused for read-only)
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
// XPM_NMU for Matrix B Read (PL to DDR via NoC)
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
) xpm_nmu_matrix_b (
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
    .s_axi_arid(axi_b_arid),
    .s_axi_araddr(axi_b_araddr),
    .s_axi_arlen(axi_b_arlen),
    .s_axi_arsize(axi_b_arsize),
    .s_axi_arburst(axi_b_arburst),
    .s_axi_arlock(axi_b_arlock),
    .s_axi_arcache(axi_b_arcache),
    .s_axi_arprot(axi_b_arprot),
    .s_axi_arregion(4'h0),
    .s_axi_arqos(axi_b_arqos),
    .s_axi_aruser(16'h0),
    .s_axi_arvalid(axi_b_arvalid),
    .s_axi_arready(axi_b_arready),

    .s_axi_rid(axi_b_rid),
    .s_axi_rdata(axi_b_rdata),
    .s_axi_rresp(axi_b_rresp),
    .s_axi_rlast(axi_b_rlast),
    .s_axi_ruser(),
    .s_axi_rvalid(axi_b_rvalid),
    .s_axi_rready(axi_b_rready),

    .nmu_usr_interrupt_in(4'b0)
);

//============================================================================
// XPM_NMU for Matrix D Write (PL to DDR via NoC)
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
) xpm_nmu_matrix_d (
    .s_axi_aclk(clk),

    // Write channel (active)
    .s_axi_awid(axi_d_awid),
    .s_axi_awaddr(axi_d_awaddr),
    .s_axi_awlen(axi_d_awlen),
    .s_axi_awsize(axi_d_awsize),
    .s_axi_awburst(axi_d_awburst),
    .s_axi_awlock(axi_d_awlock),
    .s_axi_awcache(axi_d_awcache),
    .s_axi_awprot(axi_d_awprot),
    .s_axi_awregion(4'h0),
    .s_axi_awqos(axi_d_awqos),
    .s_axi_awuser(16'h0),
    .s_axi_awvalid(axi_d_awvalid),
    .s_axi_awready(axi_d_awready),

    .s_axi_wid(),
    .s_axi_wdata(axi_d_wdata),
    .s_axi_wstrb(axi_d_wstrb),
    .s_axi_wlast(axi_d_wlast),
    .s_axi_wuser(16'h0),
    .s_axi_wvalid(axi_d_wvalid),
    .s_axi_wready(axi_d_wready),

    .s_axi_bid(axi_d_bid),
    .s_axi_bresp(axi_d_bresp),
    .s_axi_buser(),
    .s_axi_bvalid(axi_d_bvalid),
    .s_axi_bready(axi_d_bready),

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
// Read DMA for Matrix A
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

    .start_addr(addr_matrix_a),
    .transfer_length(size_a),
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
// Read DMA for Matrix B
//============================================================================
axi4_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_read_b (
    .aclk(clk),
    .aresetn(rstn),

    .start_addr(addr_matrix_b),
    .transfer_length(size_b),
    .start(start_dma_b),
    .done(dma_b_done),
    .error(dma_b_error),

    .m_axi_arid(axi_b_arid),
    .m_axi_araddr(axi_b_araddr),
    .m_axi_arlen(axi_b_arlen),
    .m_axi_arsize(axi_b_arsize),
    .m_axi_arburst(axi_b_arburst),
    .m_axi_arlock(axi_b_arlock),
    .m_axi_arcache(axi_b_arcache),
    .m_axi_arprot(axi_b_arprot),
    .m_axi_arqos(axi_b_arqos),
    .m_axi_arvalid(axi_b_arvalid),
    .m_axi_arready(axi_b_arready),

    .m_axi_rid(axi_b_rid),
    .m_axi_rdata(axi_b_rdata),
    .m_axi_rresp(axi_b_rresp),
    .m_axi_rlast(axi_b_rlast),
    .m_axi_rvalid(axi_b_rvalid),
    .m_axi_rready(axi_b_rready),

    .m_axis_tdata(axis_b_tdata),
    .m_axis_tvalid(axis_b_tvalid),
    .m_axis_tlast(axis_b_tlast),
    .m_axis_tready(axis_b_tready)
);

//============================================================================
// Matrix Multiply Core (from llm_rtl)
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
    .TRANSPOSE_B(0)
) mm_core (
    .mm_clk(mm_clk),
    .mm_fclk(mm_clk),
    .mm_rst_n(mm_rst_n),

    .s_axis_s2mm_tdata_A(axis_a_tdata),
    .s_axis_s2mm_tlast_A(axis_a_tlast),
    .s_axis_s2mm_tready_A(axis_a_tready),
    .s_axis_s2mm_tvalid_A(axis_a_tvalid),

    .s_axis_s2mm_tdata_B(axis_b_tdata),
    .s_axis_s2mm_tlast_B(axis_b_tlast),
    .s_axis_s2mm_tready_B(axis_b_tready),
    .s_axis_s2mm_tvalid_B(axis_b_tvalid),

    .m_axis_mm2s_tdata(axis_d_tdata),
    .m_axis_mm2s_tvalid(axis_d_tvalid),
    .m_axis_mm2s_tready(axis_d_tready),
    .m_axis_mm2s_tlast(axis_d_tlast),

    .M2(M2),
    .M3(M3),
    .M1xM3dN1(M1xM3dN1),
    .M1dN1(M1dN1),
    .M3dN2(M3dN2),
    .M1xM3dN1xN2(M1xM3dN1xN2)
);

//============================================================================
// Write DMA for Matrix D
//============================================================================
axi4_write_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W_ACC),
    .MAX_BURST_LEN(256)
) dma_write_d (
    .aclk(clk),
    .aresetn(rstn),

    .start_addr(addr_matrix_d),
    .transfer_length(size_d),
    .start(start_dma_d),
    .done(dma_d_done),
    .error(dma_d_error),

    .s_axis_tdata(axis_d_tdata),
    .s_axis_tvalid(axis_d_tvalid),
    .s_axis_tlast(axis_d_tlast),
    .s_axis_tready(axis_d_tready),

    .m_axi_awid(axi_d_awid),
    .m_axi_awaddr(axi_d_awaddr),
    .m_axi_awlen(axi_d_awlen),
    .m_axi_awsize(axi_d_awsize),
    .m_axi_awburst(axi_d_awburst),
    .m_axi_awlock(axi_d_awlock),
    .m_axi_awcache(axi_d_awcache),
    .m_axi_awprot(axi_d_awprot),
    .m_axi_awqos(axi_d_awqos),
    .m_axi_awvalid(axi_d_awvalid),
    .m_axi_awready(axi_d_awready),

    .m_axi_wdata(axi_d_wdata),
    .m_axi_wstrb(axi_d_wstrb),
    .m_axi_wlast(axi_d_wlast),
    .m_axi_wvalid(axi_d_wvalid),
    .m_axi_wready(axi_d_wready),

    .m_axi_bid(axi_d_bid),
    .m_axi_bresp(axi_d_bresp),
    .m_axi_bvalid(axi_d_bvalid),
    .m_axi_bready(axi_d_bready)
);

endmodule
