//
// NoC-based Attention Projection Top Level (Q/K/V)
// Performs three sequential matrix multiplies with requantization:
//   I × W^Q → Q → Requant → Q'
//   I × W^K → K → Requant → K'^T
//   I × W^V → V → Requant → V'
//
// Architecture:
//   DDR (I)     -> XPM_NMU -> Read DMA -> AXI-Stream --\
//   DDR (W^Q/K/V) -> XPM_NMU -> Read DMA -> AXI-Stream --> MM -> Requant -> AXI-Stream ->
//   Write DMA -> XPM_NMU -> DDR (Q'/K'^T/V')
//

`timescale 1ns / 1ps

module noc_attn_proj_top #(
    // Matrix dimensions for attention head
    parameter TOKENS = 32,                 // Sequence length (rows of I)
    parameter EMBED = 768,                 // Embedding dimension (cols of I, rows of W)
    parameter HEAD_DIM = 64,               // Per-head dimension (cols of W)

    // Data widths
    parameter D_W = 8,                     // Data width (8-bit quantized)
    parameter D_W_ACC = 32,                // Accumulator width

    // Systolic array dimensions
    parameter N1 = 2,                      // Systolic array rows
    parameter N2 = 2,                      // Systolic array columns
    parameter MATRIXSIZE_W = 24,           // Matrix size register width

    // Memory parameters
    parameter MEM_DEPTH_A = 4096,          // For I: TOKENS * EMBED / N1
    parameter MEM_DEPTH_B = 8192,          // For W: EMBED * HEAD_DIM
    parameter MEM_DEPTH_D = 1024,          // For output

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

    // DDR base addresses for I (input - reused 3x)
    input wire [AXI_ADDR_WIDTH-1:0] addr_I,

    // DDR base addresses for weights
    input wire [AXI_ADDR_WIDTH-1:0] addr_W_Q,
    input wire [AXI_ADDR_WIDTH-1:0] addr_W_K,
    input wire [AXI_ADDR_WIDTH-1:0] addr_W_V,

    // DDR base addresses for outputs
    input wire [AXI_ADDR_WIDTH-1:0] addr_Q_prime,
    input wire [AXI_ADDR_WIDTH-1:0] addr_K_prime_T,
    input wire [AXI_ADDR_WIDTH-1:0] addr_V_prime,

    // Requantization parameters (could also be loaded from DDR)
    input wire [D_W_ACC-1:0] requant_m_Q,
    input wire [D_W-1:0]     requant_e_Q,
    input wire [D_W_ACC-1:0] requant_m_K,
    input wire [D_W-1:0]     requant_e_K,
    input wire [D_W_ACC-1:0] requant_m_V,
    input wire [D_W-1:0]     requant_e_V
);

// Internal clocks
wire mm_clk, mm_rst_n;
assign mm_clk = clk;
assign mm_rst_n = rstn;

// Matrix dimension calculations
localparam [MATRIXSIZE_W-1:0] M1 = TOKENS;           // 32
localparam [MATRIXSIZE_W-1:0] M2 = EMBED;            // 768
localparam [MATRIXSIZE_W-1:0] M3 = HEAD_DIM;         // 64

wire [MATRIXSIZE_W-1:0] M1dN1 = M1 / N1;
wire [MATRIXSIZE_W-1:0] M3dN2 = M3 / N2;
wire [MATRIXSIZE_W-1:0] M1xM3dN1 = (M1 * M3) / N1;
wire [MATRIXSIZE_W-1:0] M1xM3dN1xN2 = (M1 * M3) / (N1 * N2);

// Transfer sizes in bytes
wire [31:0] size_I = M1 * M2;           // 32 * 768 = 24576 bytes
wire [31:0] size_W = M2 * M3;           // 768 * 64 = 49152 bytes
wire [31:0] size_out_acc = M1 * M3 * (D_W_ACC/8);  // 32 * 64 * 4 = 8192 bytes
wire [31:0] size_out_req = M1 * M3;     // 32 * 64 = 2048 bytes (after requant)

// Control signals
wire [1:0] current_proj;
wire start_dma_i, start_dma_w, start_dma_out;
wire start_requant, requant_done;
wire dma_i_done, dma_w_done, dma_out_done;
wire dma_i_error, dma_w_error, dma_out_error;
wire mm_done;

// Address multiplexing based on current projection
reg [AXI_ADDR_WIDTH-1:0] current_addr_W;
reg [AXI_ADDR_WIDTH-1:0] current_addr_out;
reg [D_W_ACC-1:0] current_requant_m;
reg [D_W-1:0] current_requant_e;

always @(*) begin
    case (current_proj)
        2'd0: begin // Q projection
            current_addr_W = addr_W_Q;
            current_addr_out = addr_Q_prime;
            current_requant_m = requant_m_Q;
            current_requant_e = requant_e_Q;
        end
        2'd1: begin // K projection
            current_addr_W = addr_W_K;
            current_addr_out = addr_K_prime_T;
            current_requant_m = requant_m_K;
            current_requant_e = requant_e_K;
        end
        2'd2: begin // V projection
            current_addr_W = addr_W_V;
            current_addr_out = addr_V_prime;
            current_requant_m = requant_m_V;
            current_requant_e = requant_e_V;
        end
        default: begin
            current_addr_W = addr_W_Q;
            current_addr_out = addr_Q_prime;
            current_requant_m = requant_m_Q;
            current_requant_e = requant_e_Q;
        end
    endcase
end

//============================================================================
// Control FSM
//============================================================================
noc_attn_proj_control control_fsm (
    .clk(clk),
    .rstn(rstn),
    .start(start),
    .done(done),
    .error(error),
    .current_proj(current_proj),
    .start_dma_i(start_dma_i),
    .start_dma_w(start_dma_w),
    .start_dma_out(start_dma_out),
    .start_requant(start_requant),
    .requant_done(requant_done),
    .dma_i_done(dma_i_done),
    .dma_w_done(dma_w_done),
    .dma_out_done(dma_out_done),
    .dma_i_error(dma_i_error),
    .dma_w_error(dma_w_error),
    .dma_out_error(dma_out_error),
    .mm_done(mm_done)
);

//============================================================================
// AXI4 Signals for Input I Read Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_i_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_i_araddr;
wire [7:0]                 axi_i_arlen;
wire [2:0]                 axi_i_arsize;
wire [1:0]                 axi_i_arburst;
wire                       axi_i_arlock;
wire [3:0]                 axi_i_arcache;
wire [2:0]                 axi_i_arprot;
wire [3:0]                 axi_i_arqos;
wire                       axi_i_arvalid;
wire                       axi_i_arready;
wire [AXI_ID_WIDTH-1:0]    axi_i_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_i_rdata;
wire [1:0]                 axi_i_rresp;
wire                       axi_i_rlast;
wire                       axi_i_rvalid;
wire                       axi_i_rready;

//============================================================================
// AXI4 Signals for Weight W Read Path
//============================================================================
wire [AXI_ID_WIDTH-1:0]    axi_w_arid;
wire [AXI_ADDR_WIDTH-1:0]  axi_w_araddr;
wire [7:0]                 axi_w_arlen;
wire [2:0]                 axi_w_arsize;
wire [1:0]                 axi_w_arburst;
wire                       axi_w_arlock;
wire [3:0]                 axi_w_arcache;
wire [2:0]                 axi_w_arprot;
wire [3:0]                 axi_w_arqos;
wire                       axi_w_arvalid;
wire                       axi_w_arready;
wire [AXI_ID_WIDTH-1:0]    axi_w_rid;
wire [AXI_DATA_WIDTH-1:0]  axi_w_rdata;
wire [1:0]                 axi_w_rresp;
wire                       axi_w_rlast;
wire                       axi_w_rvalid;
wire                       axi_w_rready;

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
// AXI-Stream Signals between DMAs and MM/Requant
//============================================================================
// Input I stream to MM
wire [D_W-1:0]     axis_i_tdata;
wire               axis_i_tvalid;
wire               axis_i_tlast;
wire               axis_i_tready;

// Weight W stream to MM
wire [D_W-1:0]     axis_w_tdata;
wire               axis_w_tvalid;
wire               axis_w_tlast;
wire               axis_w_tready;

// MM output (32-bit accumulator)
wire [D_W_ACC-1:0] axis_mm_out_tdata;
wire               axis_mm_out_tvalid;
wire               axis_mm_out_tlast;
wire               axis_mm_out_tready;

// Requant output (8-bit)
wire [D_W-1:0]     axis_req_out_tdata;
wire               axis_req_out_tvalid;
wire               axis_req_out_tlast;
wire               axis_req_out_tready;

//============================================================================
// XPM_NMU for Input I Read
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
) xpm_nmu_input_i (
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
    .s_axi_arid(axi_i_arid),
    .s_axi_araddr(axi_i_araddr),
    .s_axi_arlen(axi_i_arlen),
    .s_axi_arsize(axi_i_arsize),
    .s_axi_arburst(axi_i_arburst),
    .s_axi_arlock(axi_i_arlock),
    .s_axi_arcache(axi_i_arcache),
    .s_axi_arprot(axi_i_arprot),
    .s_axi_arregion(4'h0),
    .s_axi_arqos(axi_i_arqos),
    .s_axi_aruser(16'h0),
    .s_axi_arvalid(axi_i_arvalid),
    .s_axi_arready(axi_i_arready),
    .s_axi_rid(axi_i_rid),
    .s_axi_rdata(axi_i_rdata),
    .s_axi_rresp(axi_i_rresp),
    .s_axi_rlast(axi_i_rlast),
    .s_axi_ruser(),
    .s_axi_rvalid(axi_i_rvalid),
    .s_axi_rready(axi_i_rready),

    .nmu_usr_interrupt_in(4'b0)
);

//============================================================================
// XPM_NMU for Weight W Read
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
) xpm_nmu_weight_w (
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
    .s_axi_arid(axi_w_arid),
    .s_axi_araddr(axi_w_araddr),
    .s_axi_arlen(axi_w_arlen),
    .s_axi_arsize(axi_w_arsize),
    .s_axi_arburst(axi_w_arburst),
    .s_axi_arlock(axi_w_arlock),
    .s_axi_arcache(axi_w_arcache),
    .s_axi_arprot(axi_w_arprot),
    .s_axi_arregion(4'h0),
    .s_axi_arqos(axi_w_arqos),
    .s_axi_aruser(16'h0),
    .s_axi_arvalid(axi_w_arvalid),
    .s_axi_arready(axi_w_arready),
    .s_axi_rid(axi_w_rid),
    .s_axi_rdata(axi_w_rdata),
    .s_axi_rresp(axi_w_rresp),
    .s_axi_rlast(axi_w_rlast),
    .s_axi_ruser(),
    .s_axi_rvalid(axi_w_rvalid),
    .s_axi_rready(axi_w_rready),

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
) xpm_nmu_output (
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
// Read DMA for Input I
//============================================================================
axi4_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_read_i (
    .aclk(clk),
    .aresetn(rstn),

    .start_addr(addr_I),
    .transfer_length(size_I),
    .start(start_dma_i),
    .done(dma_i_done),
    .error(dma_i_error),

    .m_axi_arid(axi_i_arid),
    .m_axi_araddr(axi_i_araddr),
    .m_axi_arlen(axi_i_arlen),
    .m_axi_arsize(axi_i_arsize),
    .m_axi_arburst(axi_i_arburst),
    .m_axi_arlock(axi_i_arlock),
    .m_axi_arcache(axi_i_arcache),
    .m_axi_arprot(axi_i_arprot),
    .m_axi_arqos(axi_i_arqos),
    .m_axi_arvalid(axi_i_arvalid),
    .m_axi_arready(axi_i_arready),

    .m_axi_rid(axi_i_rid),
    .m_axi_rdata(axi_i_rdata),
    .m_axi_rresp(axi_i_rresp),
    .m_axi_rlast(axi_i_rlast),
    .m_axi_rvalid(axi_i_rvalid),
    .m_axi_rready(axi_i_rready),

    .m_axis_tdata(axis_i_tdata),
    .m_axis_tvalid(axis_i_tvalid),
    .m_axis_tlast(axis_i_tlast),
    .m_axis_tready(axis_i_tready)
);

//============================================================================
// Read DMA for Weight W
//============================================================================
axi4_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_read_w (
    .aclk(clk),
    .aresetn(rstn),

    .start_addr(current_addr_W),
    .transfer_length(size_W),
    .start(start_dma_w),
    .done(dma_w_done),
    .error(dma_w_error),

    .m_axi_arid(axi_w_arid),
    .m_axi_araddr(axi_w_araddr),
    .m_axi_arlen(axi_w_arlen),
    .m_axi_arsize(axi_w_arsize),
    .m_axi_arburst(axi_w_arburst),
    .m_axi_arlock(axi_w_arlock),
    .m_axi_arcache(axi_w_arcache),
    .m_axi_arprot(axi_w_arprot),
    .m_axi_arqos(axi_w_arqos),
    .m_axi_arvalid(axi_w_arvalid),
    .m_axi_arready(axi_w_arready),

    .m_axi_rid(axi_w_rid),
    .m_axi_rdata(axi_w_rdata),
    .m_axi_rresp(axi_w_rresp),
    .m_axi_rlast(axi_w_rlast),
    .m_axi_rvalid(axi_w_rvalid),
    .m_axi_rready(axi_w_rready),

    .m_axis_tdata(axis_w_tdata),
    .m_axis_tvalid(axis_w_tvalid),
    .m_axis_tlast(axis_w_tlast),
    .m_axis_tready(axis_w_tready)
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
    .TRANSPOSE_B(0)
) mm_core (
    .mm_clk(mm_clk),
    .mm_fclk(mm_clk),
    .mm_rst_n(mm_rst_n),

    .s_axis_s2mm_tdata_A(axis_i_tdata),
    .s_axis_s2mm_tlast_A(axis_i_tlast),
    .s_axis_s2mm_tready_A(axis_i_tready),
    .s_axis_s2mm_tvalid_A(axis_i_tvalid),

    .s_axis_s2mm_tdata_B(axis_w_tdata),
    .s_axis_s2mm_tlast_B(axis_w_tlast),
    .s_axis_s2mm_tready_B(axis_w_tready),
    .s_axis_s2mm_tvalid_B(axis_w_tvalid),

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
        if (start_dma_i) begin
            mm_output_complete <= 1'b0;
        end else if (axis_mm_out_tvalid && axis_mm_out_tready && axis_mm_out_tlast) begin
            mm_output_complete <= 1'b1;
        end
    end
end
assign mm_done = mm_output_complete;

//============================================================================
// Requantization Module
// out = clip((in + bias) × m >> e)
// For now, bias = 0 for simplicity
//
// The requant module expects streaming interfaces for bias, m, e.
// We provide constant values by keeping tvalid high and matching tlast.
//============================================================================

// Generate constant parameter streams that match input data stream
wire req_bias_tready, req_m_tready, req_e_tready;

requant #(
    .D_W_ACC(D_W_ACC),
    .D_W(D_W),
    .OUT_BITS(D_W),
    .CLIP(1)
) requant_inst (
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
    .in_tready_bias(req_bias_tready),
    .in_tlast_bias(axis_mm_out_tlast),    // Match data stream last

    // Multiplier stream (from current_requant_m)
    .in_tdata_m(current_requant_m),
    .in_tvalid_m(axis_mm_out_tvalid),     // Match data stream valid
    .in_tready_m(req_m_tready),
    .in_tlast_m(axis_mm_out_tlast),       // Match data stream last

    // Exponent stream (from current_requant_e)
    .in_tdata_e(current_requant_e),
    .in_tvalid_e(axis_mm_out_tvalid),     // Match data stream valid
    .in_tready_e(req_e_tready),
    .in_tlast_e(axis_mm_out_tlast),       // Match data stream last

    // Output stream
    .out_tdata(axis_req_out_tdata),
    .out_tvalid(axis_req_out_tvalid),
    .out_tready(axis_req_out_tready),
    .out_tlast(axis_req_out_tlast)
);

// Requant done detection
reg requant_output_complete;
always @(posedge clk) begin
    if (!rstn) begin
        requant_output_complete <= 1'b0;
    end else begin
        if (start_requant) begin
            requant_output_complete <= 1'b0;
        end else if (axis_req_out_tvalid && axis_req_out_tready && axis_req_out_tlast) begin
            requant_output_complete <= 1'b1;
        end
    end
end
assign requant_done = requant_output_complete;

//============================================================================
// Write DMA for Output (after requant)
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

    .start_addr(current_addr_out),
    .transfer_length(size_out_req),
    .start(start_dma_out),
    .done(dma_out_done),
    .error(dma_out_error),

    .s_axis_tdata(axis_req_out_tdata),
    .s_axis_tvalid(axis_req_out_tvalid),
    .s_axis_tlast(axis_req_out_tlast),
    .s_axis_tready(axis_req_out_tready),

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
