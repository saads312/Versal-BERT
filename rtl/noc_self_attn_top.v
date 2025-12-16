//
// NoC-based Self-Attention Top Level
// Complete self-attention computation:
//   Phase 1: Q/K/V projections (I × W^Q/K/V → Q'/K'^T/V')
//   Phase 2: Attention scores (Q' × K'^T → S)
//   Phase 3: Softmax (S → P)
//   Phase 4: Context (P × V' → C → C')
//

`timescale 1ns / 1ps

module noc_self_attn_top #(
    // Matrix dimensions
    parameter TOKENS = 32,
    parameter EMBED = 768,
    parameter HEAD_DIM = 64,

    // Data widths
    parameter D_W = 8,
    parameter D_W_ACC = 32,

    // Systolic array dimensions
    parameter N1 = 2,
    parameter N2 = 2,
    parameter MATRIXSIZE_W = 24,

    // Memory parameters
    parameter MEM_DEPTH_A = 4096,
    parameter MEM_DEPTH_B = 8192,
    parameter MEM_DEPTH_D = 1024,

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

    // DDR addresses for inputs
    input wire [AXI_ADDR_WIDTH-1:0] addr_I,
    input wire [AXI_ADDR_WIDTH-1:0] addr_W_Q,
    input wire [AXI_ADDR_WIDTH-1:0] addr_W_K,
    input wire [AXI_ADDR_WIDTH-1:0] addr_W_V,

    // DDR addresses for Q/K/V projection outputs
    input wire [AXI_ADDR_WIDTH-1:0] addr_Q_prime,
    input wire [AXI_ADDR_WIDTH-1:0] addr_K_prime_T,
    input wire [AXI_ADDR_WIDTH-1:0] addr_V_prime,

    // DDR addresses for attention intermediates
    input wire [AXI_ADDR_WIDTH-1:0] addr_S,
    input wire [AXI_ADDR_WIDTH-1:0] addr_P,
    input wire [AXI_ADDR_WIDTH-1:0] addr_C_prime,

    // Requantization parameters
    input wire [D_W_ACC-1:0] requant_m_Q,
    input wire [D_W-1:0]     requant_e_Q,
    input wire [D_W_ACC-1:0] requant_m_K,
    input wire [D_W-1:0]     requant_e_K,
    input wire [D_W_ACC-1:0] requant_m_V,
    input wire [D_W-1:0]     requant_e_V,
    input wire [D_W_ACC-1:0] requant_m_C,
    input wire [D_W-1:0]     requant_e_C,

    // Softmax coefficients
    input wire signed [D_W_ACC-1:0] softmax_qb,
    input wire signed [D_W_ACC-1:0] softmax_qc,
    input wire signed [D_W_ACC-1:0] softmax_qln2,
    input wire signed [D_W_ACC-1:0] softmax_qln2_inv,
    input wire        [D_W_ACC-1:0] softmax_sreq
);

//============================================================================
// Internal Clocks and Resets
//============================================================================
wire mm_clk = clk;
wire mm_rst_n = rstn;

//============================================================================
// Matrix Dimension Calculations
//============================================================================

// For Q/K/V projections: I(TOKENS×EMBED) × W(EMBED×HEAD_DIM) = Out(TOKENS×HEAD_DIM)
localparam [MATRIXSIZE_W-1:0] PROJ_M1 = TOKENS;
localparam [MATRIXSIZE_W-1:0] PROJ_M2 = EMBED;
localparam [MATRIXSIZE_W-1:0] PROJ_M3 = HEAD_DIM;

// For attention scores: Q'(TOKENS×HEAD_DIM) × K'^T(HEAD_DIM×TOKENS) = S(TOKENS×TOKENS)
localparam [MATRIXSIZE_W-1:0] ATTN_M1 = TOKENS;
localparam [MATRIXSIZE_W-1:0] ATTN_M2 = HEAD_DIM;
localparam [MATRIXSIZE_W-1:0] ATTN_M3 = TOKENS;

// For context: P(TOKENS×TOKENS) × V'(TOKENS×HEAD_DIM) = C(TOKENS×HEAD_DIM)
localparam [MATRIXSIZE_W-1:0] CTX_M1 = TOKENS;
localparam [MATRIXSIZE_W-1:0] CTX_M2 = TOKENS;
localparam [MATRIXSIZE_W-1:0] CTX_M3 = HEAD_DIM;

// Transfer sizes in bytes
wire [31:0] size_I = TOKENS * EMBED;
wire [31:0] size_W = EMBED * HEAD_DIM;
wire [31:0] size_proj_out = TOKENS * HEAD_DIM;  // 8-bit after requant
wire [31:0] size_S = TOKENS * TOKENS * 4;       // 32-bit before softmax
wire [31:0] size_P = TOKENS * TOKENS;           // 8-bit after softmax
wire [31:0] size_C = TOKENS * HEAD_DIM;         // 8-bit after requant

//============================================================================
// Control FSM Signals
//============================================================================
wire [3:0] current_op;
wire start_dma_i, start_dma_w, start_dma_proj_out;
wire start_dma_qprime, start_dma_kprime_t, start_dma_vprime;
wire start_dma_s, start_dma_p, start_dma_cprime;
wire start_softmax, softmax_done_int;
wire start_requant, requant_done_int;
wire dma_error_any;

// DMA done signals
wire dma_a_done, dma_b_done, dma_out_done;

// Map generic DMA done signals to FSM expectations
wire dma_i_done = dma_a_done;
wire dma_w_done = dma_b_done;
wire dma_proj_out_done = dma_out_done;
wire dma_qprime_done = dma_a_done;
wire dma_kprime_t_done = dma_b_done;
wire dma_vprime_done = dma_b_done;
wire dma_s_done_wr = dma_out_done;
wire dma_s_done_rd = dma_a_done;
wire dma_p_done_wr = dma_out_done;
wire dma_p_done_rd = dma_a_done;
wire dma_cprime_done = dma_out_done;

wire mm_done_int;

//============================================================================
// Address and Size Multiplexing
//============================================================================
reg [AXI_ADDR_WIDTH-1:0] dma_a_addr;
reg [AXI_ADDR_WIDTH-1:0] dma_b_addr;
reg [AXI_ADDR_WIDTH-1:0] dma_out_addr;
reg [31:0] dma_a_size;
reg [31:0] dma_b_size;
reg [31:0] dma_out_size;
reg [D_W_ACC-1:0] current_requant_m;
reg [D_W-1:0] current_requant_e;

// MM dimension signals
reg [MATRIXSIZE_W-1:0] mm_M2, mm_M3;
reg [MATRIXSIZE_W-1:0] mm_M1dN1, mm_M3dN2, mm_M1xM3dN1, mm_M1xM3dN1xN2;
reg mm_transpose_b;

// Operation encoding from FSM
localparam [3:0] OP_PROJ_Q  = 4'd0;
localparam [3:0] OP_PROJ_K  = 4'd1;
localparam [3:0] OP_PROJ_V  = 4'd2;
localparam [3:0] OP_ATTN_S  = 4'd3;
localparam [3:0] OP_SOFTMAX = 4'd4;
localparam [3:0] OP_CONTEXT = 4'd5;

always @(*) begin
    // Defaults
    dma_a_addr = addr_I;
    dma_b_addr = addr_W_Q;
    dma_out_addr = addr_Q_prime;
    dma_a_size = size_I;
    dma_b_size = size_W;
    dma_out_size = size_proj_out;
    current_requant_m = requant_m_Q;
    current_requant_e = requant_e_Q;

    // MM dimensions for projection
    mm_M2 = PROJ_M2;
    mm_M3 = PROJ_M3;
    mm_M1dN1 = PROJ_M1 / N1;
    mm_M3dN2 = PROJ_M3 / N2;
    mm_M1xM3dN1 = (PROJ_M1 * PROJ_M3) / N1;
    mm_M1xM3dN1xN2 = (PROJ_M1 * PROJ_M3) / (N1 * N2);
    mm_transpose_b = 1'b0;

    case (current_op)
        OP_PROJ_Q: begin
            dma_a_addr = addr_I;
            dma_b_addr = addr_W_Q;
            dma_out_addr = addr_Q_prime;
            dma_a_size = size_I;
            dma_b_size = size_W;
            dma_out_size = size_proj_out;
            current_requant_m = requant_m_Q;
            current_requant_e = requant_e_Q;
        end

        OP_PROJ_K: begin
            dma_a_addr = addr_I;
            dma_b_addr = addr_W_K;
            dma_out_addr = addr_K_prime_T;
            dma_a_size = size_I;
            dma_b_size = size_W;
            dma_out_size = size_proj_out;
            current_requant_m = requant_m_K;
            current_requant_e = requant_e_K;
        end

        OP_PROJ_V: begin
            dma_a_addr = addr_I;
            dma_b_addr = addr_W_V;
            dma_out_addr = addr_V_prime;
            dma_a_size = size_I;
            dma_b_size = size_W;
            dma_out_size = size_proj_out;
            current_requant_m = requant_m_V;
            current_requant_e = requant_e_V;
        end

        OP_ATTN_S: begin
            // Q'(TOKENS×HEAD_DIM) × K'^T(HEAD_DIM×TOKENS) = S(TOKENS×TOKENS)
            dma_a_addr = addr_Q_prime;
            dma_b_addr = addr_K_prime_T;
            dma_out_addr = addr_S;
            dma_a_size = size_proj_out;
            dma_b_size = size_proj_out;
            dma_out_size = size_S;
            // No requant for S (goes directly to softmax)
            current_requant_m = 32'h0000_0001;
            current_requant_e = 8'd0;
            // Update MM dimensions for attention
            mm_M2 = ATTN_M2;
            mm_M3 = ATTN_M3;
            mm_M1dN1 = ATTN_M1 / N1;
            mm_M3dN2 = ATTN_M3 / N2;
            mm_M1xM3dN1 = (ATTN_M1 * ATTN_M3) / N1;
            mm_M1xM3dN1xN2 = (ATTN_M1 * ATTN_M3) / (N1 * N2);
            mm_transpose_b = 1'b1;  // K'^T is transposed
        end

        OP_SOFTMAX: begin
            // Softmax reads S, writes P
            dma_a_addr = addr_S;
            dma_out_addr = addr_P;
            dma_a_size = size_S;
            dma_out_size = size_P;
            // CRITICAL: Keep attention dimensions during softmax computation
            // (current_op switches to OP_SOFTMAX in COMPUTE_S state while MM is still running)
            mm_M2 = ATTN_M2;
            mm_M3 = ATTN_M3;
            mm_M1dN1 = ATTN_M1 / N1;
            mm_M3dN2 = ATTN_M3 / N2;
            mm_M1xM3dN1 = (ATTN_M1 * ATTN_M3) / N1;
            mm_M1xM3dN1xN2 = (ATTN_M1 * ATTN_M3) / (N1 * N2);
            mm_transpose_b = 1'b1;
        end

        OP_CONTEXT: begin
            // P(TOKENS×TOKENS) × V'(TOKENS×HEAD_DIM) = C(TOKENS×HEAD_DIM)
            dma_a_addr = addr_P;
            dma_b_addr = addr_V_prime;
            dma_out_addr = addr_C_prime;
            dma_a_size = size_P;
            dma_b_size = size_proj_out;
            dma_out_size = size_C;
            current_requant_m = requant_m_C;
            current_requant_e = requant_e_C;
            // Update MM dimensions for context
            mm_M2 = CTX_M2;
            mm_M3 = CTX_M3;
            mm_M1dN1 = CTX_M1 / N1;
            mm_M3dN2 = CTX_M3 / N2;
            mm_M1xM3dN1 = (CTX_M1 * CTX_M3) / N1;
            mm_M1xM3dN1xN2 = (CTX_M1 * CTX_M3) / (N1 * N2);
            mm_transpose_b = 1'b0;
        end

        default: begin
            // Keep defaults
        end
    endcase
end

//============================================================================
// Control FSM
//============================================================================
noc_self_attn_control control_fsm (
    .clk(clk),
    .rstn(rstn),
    .start(start),
    .done(done),
    .error(error),
    .current_op(current_op),

    // Q/K/V projection DMA control
    .start_dma_i(start_dma_i),
    .start_dma_w(start_dma_w),
    .start_dma_proj_out(start_dma_proj_out),

    // Attention computation DMA control
    .start_dma_qprime(start_dma_qprime),
    .start_dma_kprime_t(start_dma_kprime_t),
    .start_dma_vprime(start_dma_vprime),
    .start_dma_s(start_dma_s),
    .start_dma_p(start_dma_p),
    .start_dma_cprime(start_dma_cprime),

    // Softmax control
    .start_softmax(start_softmax),
    .softmax_done(softmax_done_int),

    // Requant control
    .start_requant(start_requant),
    .requant_done(requant_done_int),

    // DMA status - map from generic DMAs
    .dma_i_done(dma_a_done),
    .dma_w_done(dma_b_done),
    .dma_proj_out_done(dma_out_done),
    .dma_qprime_done(dma_a_done),
    .dma_kprime_t_done(dma_b_done),
    .dma_vprime_done(dma_b_done),
    .dma_s_done(dma_out_done),
    // dma_p_done: write DMA during SOFTMAX (WRITE_P), read DMA A during CONTEXT (LOAD_P)
    .dma_p_done((current_op == OP_CONTEXT) ? dma_a_done : dma_out_done),
    .dma_cprime_done(dma_out_done),
    .dma_error(dma_error_any),

    .mm_done(mm_done_int)
);

//============================================================================
// DMA Start Signal Aggregation
//============================================================================
// DMA A is used for: I, Q', S (read), P (read)
wire start_dma_a = start_dma_i | start_dma_qprime |
                   (start_dma_s && current_op == OP_SOFTMAX) |
                   (start_dma_p && current_op == OP_CONTEXT);

// DMA B is used for: W, K'^T, V'
wire start_dma_b = start_dma_w | start_dma_kprime_t | start_dma_vprime;

// DMA Out is used for: Q'/K'^T/V', S (write), P (write), C'
wire start_dma_out = start_dma_proj_out |
                     (start_dma_s && current_op == OP_ATTN_S) |
                     (start_dma_p && current_op == OP_SOFTMAX) |
                     start_dma_cprime;

//============================================================================
// AXI4 Signals for Read Path A
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
// AXI4 Signals for Read Path B
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
// AXI4 Signals for Write Path
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
// AXI-Stream Signals
//============================================================================
// Read A stream to MM/Softmax
wire [D_W-1:0]     axis_a_tdata;
wire               axis_a_tvalid;
wire               axis_a_tlast;
wire               axis_a_tready;

// Read B stream to MM
wire [D_W-1:0]     axis_b_tdata;
wire               axis_b_tvalid;
wire               axis_b_tlast;
wire               axis_b_tready;

// MM output (32-bit)
wire [D_W_ACC-1:0] axis_mm_out_tdata;
wire               axis_mm_out_tvalid;
wire               axis_mm_out_tlast;
wire               axis_mm_out_tready;

// Requant output (8-bit)
wire [D_W-1:0]     axis_req_out_tdata;
wire               axis_req_out_tvalid;
wire               axis_req_out_tlast;
wire               axis_req_out_tready;

// Softmax output (8-bit)
wire [D_W-1:0]     axis_softmax_out_tdata;
wire               axis_softmax_out_tvalid;
wire               axis_softmax_out_tlast;
wire               axis_softmax_out_tready;

// Mux for write DMA input (from requant or softmax)
wire [D_W-1:0]     axis_write_tdata;
wire               axis_write_tvalid;
wire               axis_write_tlast;
wire               axis_write_tready;

// Select softmax output during SOFTMAX operation, otherwise requant
assign axis_write_tdata = (current_op == OP_SOFTMAX) ? axis_softmax_out_tdata : axis_req_out_tdata;
assign axis_write_tvalid = (current_op == OP_SOFTMAX) ? axis_softmax_out_tvalid : axis_req_out_tvalid;
assign axis_write_tlast = (current_op == OP_SOFTMAX) ? axis_softmax_out_tlast : axis_req_out_tlast;
assign axis_softmax_out_tready = (current_op == OP_SOFTMAX) ? axis_write_tready : 1'b0;
assign axis_req_out_tready = (current_op != OP_SOFTMAX) ? axis_write_tready : 1'b0;

//============================================================================
// XPM_NMU Instances
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
) xpm_nmu_read_a (
    .s_axi_aclk(clk),
    // Write channel (unused)
    .s_axi_awid({AXI_ID_WIDTH{1'b0}}), .s_axi_awaddr({AXI_ADDR_WIDTH{1'b0}}),
    .s_axi_awlen(8'h0), .s_axi_awsize(3'h0), .s_axi_awburst(2'b01),
    .s_axi_awlock(1'b0), .s_axi_awcache(4'h0), .s_axi_awprot(3'h0),
    .s_axi_awregion(4'h0), .s_axi_awqos(4'h0), .s_axi_awuser(16'h0),
    .s_axi_awvalid(1'b0), .s_axi_awready(),
    .s_axi_wid(), .s_axi_wdata({AXI_DATA_WIDTH{1'b0}}),
    .s_axi_wstrb({(AXI_DATA_WIDTH/8){1'b0}}), .s_axi_wlast(1'b0),
    .s_axi_wuser(16'h0), .s_axi_wvalid(1'b0), .s_axi_wready(),
    .s_axi_bid(), .s_axi_bresp(), .s_axi_buser(), .s_axi_bvalid(), .s_axi_bready(1'b0),
    // Read channel
    .s_axi_arid(axi_a_arid), .s_axi_araddr(axi_a_araddr), .s_axi_arlen(axi_a_arlen),
    .s_axi_arsize(axi_a_arsize), .s_axi_arburst(axi_a_arburst), .s_axi_arlock(axi_a_arlock),
    .s_axi_arcache(axi_a_arcache), .s_axi_arprot(axi_a_arprot), .s_axi_arregion(4'h0),
    .s_axi_arqos(axi_a_arqos), .s_axi_aruser(16'h0), .s_axi_arvalid(axi_a_arvalid),
    .s_axi_arready(axi_a_arready), .s_axi_rid(axi_a_rid), .s_axi_rdata(axi_a_rdata),
    .s_axi_rresp(axi_a_rresp), .s_axi_rlast(axi_a_rlast), .s_axi_ruser(),
    .s_axi_rvalid(axi_a_rvalid), .s_axi_rready(axi_a_rready),
    .nmu_usr_interrupt_in(4'b0)
);

xpm_nmu_mm # (
    .NOC_FABRIC("VNOC"),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH),
    .AUSER_WIDTH(16),
    .DUSER_WIDTH(0),
    .ENABLE_USR_INTERRUPT("false"),
    .SIDEBAND_PINS("false")
) xpm_nmu_read_b (
    .s_axi_aclk(clk),
    // Write channel (unused)
    .s_axi_awid({AXI_ID_WIDTH{1'b0}}), .s_axi_awaddr({AXI_ADDR_WIDTH{1'b0}}),
    .s_axi_awlen(8'h0), .s_axi_awsize(3'h0), .s_axi_awburst(2'b01),
    .s_axi_awlock(1'b0), .s_axi_awcache(4'h0), .s_axi_awprot(3'h0),
    .s_axi_awregion(4'h0), .s_axi_awqos(4'h0), .s_axi_awuser(16'h0),
    .s_axi_awvalid(1'b0), .s_axi_awready(),
    .s_axi_wid(), .s_axi_wdata({AXI_DATA_WIDTH{1'b0}}),
    .s_axi_wstrb({(AXI_DATA_WIDTH/8){1'b0}}), .s_axi_wlast(1'b0),
    .s_axi_wuser(16'h0), .s_axi_wvalid(1'b0), .s_axi_wready(),
    .s_axi_bid(), .s_axi_bresp(), .s_axi_buser(), .s_axi_bvalid(), .s_axi_bready(1'b0),
    // Read channel
    .s_axi_arid(axi_b_arid), .s_axi_araddr(axi_b_araddr), .s_axi_arlen(axi_b_arlen),
    .s_axi_arsize(axi_b_arsize), .s_axi_arburst(axi_b_arburst), .s_axi_arlock(axi_b_arlock),
    .s_axi_arcache(axi_b_arcache), .s_axi_arprot(axi_b_arprot), .s_axi_arregion(4'h0),
    .s_axi_arqos(axi_b_arqos), .s_axi_aruser(16'h0), .s_axi_arvalid(axi_b_arvalid),
    .s_axi_arready(axi_b_arready), .s_axi_rid(axi_b_rid), .s_axi_rdata(axi_b_rdata),
    .s_axi_rresp(axi_b_rresp), .s_axi_rlast(axi_b_rlast), .s_axi_ruser(),
    .s_axi_rvalid(axi_b_rvalid), .s_axi_rready(axi_b_rready),
    .nmu_usr_interrupt_in(4'b0)
);

xpm_nmu_mm # (
    .NOC_FABRIC("VNOC"),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ADDR_WIDTH(AXI_ADDR_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH),
    .AUSER_WIDTH(16),
    .DUSER_WIDTH(0),
    .ENABLE_USR_INTERRUPT("false"),
    .SIDEBAND_PINS("false")
) xpm_nmu_write (
    .s_axi_aclk(clk),
    // Write channel
    .s_axi_awid(axi_out_awid), .s_axi_awaddr(axi_out_awaddr), .s_axi_awlen(axi_out_awlen),
    .s_axi_awsize(axi_out_awsize), .s_axi_awburst(axi_out_awburst), .s_axi_awlock(axi_out_awlock),
    .s_axi_awcache(axi_out_awcache), .s_axi_awprot(axi_out_awprot), .s_axi_awregion(4'h0),
    .s_axi_awqos(axi_out_awqos), .s_axi_awuser(16'h0), .s_axi_awvalid(axi_out_awvalid),
    .s_axi_awready(axi_out_awready), .s_axi_wid(), .s_axi_wdata(axi_out_wdata),
    .s_axi_wstrb(axi_out_wstrb), .s_axi_wlast(axi_out_wlast), .s_axi_wuser(16'h0),
    .s_axi_wvalid(axi_out_wvalid), .s_axi_wready(axi_out_wready),
    .s_axi_bid(axi_out_bid), .s_axi_bresp(axi_out_bresp), .s_axi_buser(),
    .s_axi_bvalid(axi_out_bvalid), .s_axi_bready(axi_out_bready),
    // Read channel (unused)
    .s_axi_arid({AXI_ID_WIDTH{1'b0}}), .s_axi_araddr({AXI_ADDR_WIDTH{1'b0}}),
    .s_axi_arlen(8'h0), .s_axi_arsize(3'h0), .s_axi_arburst(2'b01),
    .s_axi_arlock(1'b0), .s_axi_arcache(4'h0), .s_axi_arprot(3'h0),
    .s_axi_arregion(4'h0), .s_axi_arqos(4'h0), .s_axi_aruser(16'h0),
    .s_axi_arvalid(1'b0), .s_axi_arready(), .s_axi_rid(), .s_axi_rdata(),
    .s_axi_rresp(), .s_axi_rlast(), .s_axi_ruser(), .s_axi_rvalid(), .s_axi_rready(1'b0),
    .nmu_usr_interrupt_in(4'b0)
);

//============================================================================
// Read DMA A
//============================================================================
wire dma_a_error;
axi4_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_read_a (
    .aclk(clk), .aresetn(rstn),
    .start_addr(dma_a_addr),
    .transfer_length(dma_a_size),
    .start(start_dma_a),
    .done(dma_a_done),
    .error(dma_a_error),
    .m_axi_arid(axi_a_arid), .m_axi_araddr(axi_a_araddr), .m_axi_arlen(axi_a_arlen),
    .m_axi_arsize(axi_a_arsize), .m_axi_arburst(axi_a_arburst), .m_axi_arlock(axi_a_arlock),
    .m_axi_arcache(axi_a_arcache), .m_axi_arprot(axi_a_arprot), .m_axi_arqos(axi_a_arqos),
    .m_axi_arvalid(axi_a_arvalid), .m_axi_arready(axi_a_arready),
    .m_axi_rid(axi_a_rid), .m_axi_rdata(axi_a_rdata), .m_axi_rresp(axi_a_rresp),
    .m_axi_rlast(axi_a_rlast), .m_axi_rvalid(axi_a_rvalid), .m_axi_rready(axi_a_rready),
    .m_axis_tdata(axis_a_tdata), .m_axis_tvalid(axis_a_tvalid),
    .m_axis_tlast(axis_a_tlast), .m_axis_tready(axis_a_tready)
);

//============================================================================
// Read DMA B
//============================================================================
wire dma_b_error;
axi4_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_read_b (
    .aclk(clk), .aresetn(rstn),
    .start_addr(dma_b_addr),
    .transfer_length(dma_b_size),
    .start(start_dma_b),
    .done(dma_b_done),
    .error(dma_b_error),
    .m_axi_arid(axi_b_arid), .m_axi_araddr(axi_b_araddr), .m_axi_arlen(axi_b_arlen),
    .m_axi_arsize(axi_b_arsize), .m_axi_arburst(axi_b_arburst), .m_axi_arlock(axi_b_arlock),
    .m_axi_arcache(axi_b_arcache), .m_axi_arprot(axi_b_arprot), .m_axi_arqos(axi_b_arqos),
    .m_axi_arvalid(axi_b_arvalid), .m_axi_arready(axi_b_arready),
    .m_axi_rid(axi_b_rid), .m_axi_rdata(axi_b_rdata), .m_axi_rresp(axi_b_rresp),
    .m_axi_rlast(axi_b_rlast), .m_axi_rvalid(axi_b_rvalid), .m_axi_rready(axi_b_rready),
    .m_axis_tdata(axis_b_tdata), .m_axis_tvalid(axis_b_tvalid),
    .m_axis_tlast(axis_b_tlast), .m_axis_tready(axis_b_tready)
);

assign dma_error_any = dma_a_error | dma_b_error;

//============================================================================
// Matrix Multiply Core
//============================================================================
// Note: For full flexibility, we'd need to reconfigure MM dimensions dynamically
// For now, we instantiate with max dimensions and use dimension ports
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
    .TRANSPOSE_B(0)  // Note: transpose is handled by pre-transposed data
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
    .m_axis_mm2s_tdata(axis_mm_out_tdata),
    .m_axis_mm2s_tvalid(axis_mm_out_tvalid),
    .m_axis_mm2s_tready(axis_mm_out_tready),
    .m_axis_mm2s_tlast(axis_mm_out_tlast),
    .M2(mm_M2),
    .M3(mm_M3),
    .M1xM3dN1(mm_M1xM3dN1),
    .M1dN1(mm_M1dN1),
    .M3dN2(mm_M3dN2),
    .M1xM3dN1xN2(mm_M1xM3dN1xN2)
);

// MM done detection
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
assign mm_done_int = mm_output_complete;

//============================================================================
// Requantization Module
//============================================================================
wire req_bias_tready, req_m_tready, req_e_tready;
wire req_in_tready;

requant #(
    .D_W_ACC(D_W_ACC),
    .D_W(D_W),
    .OUT_BITS(D_W),
    .CLIP(1)
) requant_inst (
    .clk(clk),
    .rst(~rstn),
    .in_tdata(axis_mm_out_tdata),
    .in_tvalid(axis_mm_out_tvalid && current_op != OP_SOFTMAX),
    .in_tready(req_in_tready),
    .in_tlast(axis_mm_out_tlast),
    .in_tdata_bias({D_W_ACC{1'b0}}),
    .in_tvalid_bias(axis_mm_out_tvalid && current_op != OP_SOFTMAX),
    .in_tready_bias(req_bias_tready),
    .in_tlast_bias(axis_mm_out_tlast),
    .in_tdata_m(current_requant_m),
    .in_tvalid_m(axis_mm_out_tvalid && current_op != OP_SOFTMAX),
    .in_tready_m(req_m_tready),
    .in_tlast_m(axis_mm_out_tlast),
    .in_tdata_e(current_requant_e),
    .in_tvalid_e(axis_mm_out_tvalid && current_op != OP_SOFTMAX),
    .in_tready_e(req_e_tready),
    .in_tlast_e(axis_mm_out_tlast),
    .out_tdata(axis_req_out_tdata),
    .out_tvalid(axis_req_out_tvalid),
    .out_tready(axis_req_out_tready),
    .out_tlast(axis_req_out_tlast)
);

// MM output tready mux: during OP_SOFTMAX (set in COMPUTE_S), softmax consumes MM output directly
// Softmax module doesn't have backpressure (always accepts when enabled)
assign axis_mm_out_tready = (current_op == OP_SOFTMAX) ? 1'b1 : req_in_tready;

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
assign requant_done_int = requant_output_complete;

//============================================================================
// Softmax Module
// S values (32-bit) stream directly from MM output during COMPUTE_S
// No DDR round-trip for S since DMA is 8-bit and S is 32-bit
//============================================================================
softmax #(
    .D_W(D_W),
    .D_W_ACC(D_W_ACC),
    .N(TOKENS),
    .FP_BITS(30),
    .MAX_BITS(30),
    .OUT_BITS(6)
) softmax_inst (
    .clk(clk),
    .rst(~rstn),
    // Enable during SOFTMAX operation (includes COMPUTE_S which sets current_op=OP_SOFTMAX)
    .enable(current_op == OP_SOFTMAX),
    // Feed 32-bit MM output directly to softmax when current_op=OP_SOFTMAX (set in COMPUTE_S)
    .in_valid(axis_mm_out_tvalid && current_op == OP_SOFTMAX),
    .qin(axis_mm_out_tdata),  // 32-bit attention scores from MM
    .qb(softmax_qb),
    .qc(softmax_qc),
    .qln2(softmax_qln2),
    .qln2_inv(softmax_qln2_inv),
    .Sreq(softmax_sreq),
    .out_valid(axis_softmax_out_tvalid),
    .qout(axis_softmax_out_tdata)
);

// Softmax tlast generation (after N×N elements)
// Count all outputs produced, not just accepted (tready doesn't gate the count)
reg [$clog2(TOKENS*TOKENS):0] softmax_out_count;
always @(posedge clk) begin
    if (!rstn || start_softmax) begin
        softmax_out_count <= 0;
    end else if (axis_softmax_out_tvalid) begin
        softmax_out_count <= softmax_out_count + 1;
        if (softmax_out_count >= TOKENS * TOKENS - 5)
            $display("[%t] SOFTMAX_TLAST: count=%0d/%0d tvalid=%b tready=%b tlast=%b",
                     $time, softmax_out_count, TOKENS*TOKENS-1,
                     axis_softmax_out_tvalid, axis_softmax_out_tready,
                     (softmax_out_count == TOKENS * TOKENS - 1));
    end
end
assign axis_softmax_out_tlast = (softmax_out_count == TOKENS * TOKENS - 1) &&
                                 axis_softmax_out_tvalid;

// Softmax done detection
reg softmax_output_complete;
always @(posedge clk) begin
    if (!rstn) begin
        softmax_output_complete <= 1'b0;
    end else begin
        if (start_softmax) begin
            softmax_output_complete <= 1'b0;
        end else if (axis_softmax_out_tvalid && axis_softmax_out_tready && axis_softmax_out_tlast) begin
            softmax_output_complete <= 1'b1;
        end
    end
end
assign softmax_done_int = softmax_output_complete;

//============================================================================
// Write DMA
//============================================================================
wire dma_out_error;
axi4_write_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(D_W),
    .MAX_BURST_LEN(256)
) dma_write (
    .aclk(clk), .aresetn(rstn),
    .start_addr(dma_out_addr),
    .transfer_length(dma_out_size),
    .start(start_dma_out),
    .done(dma_out_done),
    .error(dma_out_error),
    .s_axis_tdata(axis_write_tdata),
    .s_axis_tvalid(axis_write_tvalid),
    .s_axis_tlast(axis_write_tlast),
    .s_axis_tready(axis_write_tready),
    .m_axi_awid(axi_out_awid), .m_axi_awaddr(axi_out_awaddr), .m_axi_awlen(axi_out_awlen),
    .m_axi_awsize(axi_out_awsize), .m_axi_awburst(axi_out_awburst), .m_axi_awlock(axi_out_awlock),
    .m_axi_awcache(axi_out_awcache), .m_axi_awprot(axi_out_awprot), .m_axi_awqos(axi_out_awqos),
    .m_axi_awvalid(axi_out_awvalid), .m_axi_awready(axi_out_awready),
    .m_axi_wdata(axi_out_wdata), .m_axi_wstrb(axi_out_wstrb), .m_axi_wlast(axi_out_wlast),
    .m_axi_wvalid(axi_out_wvalid), .m_axi_wready(axi_out_wready),
    .m_axi_bid(axi_out_bid), .m_axi_bresp(axi_out_bresp),
    .m_axi_bvalid(axi_out_bvalid), .m_axi_bready(axi_out_bready)
);

endmodule
