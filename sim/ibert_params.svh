//
// IBERT Parameter Configuration
// Only truly independent parameters need to be set here.
// All other dimensions are derived from matrix multiply constraints.
//

`ifndef IBERT_PARAMS_SVH
`define IBERT_PARAMS_SVH

// ============================================================================
// IBERT Model Parameters (Independent)
// ============================================================================
// Available configurations (all satisfy HEAD_DIM % 2 == 0 and TOKENS % 2 == 0):
//
// CONFIG        | TOKENS | EMBED | HEADS | HEAD_DIM | Proj Size      | Sim Time | Use Case
// --------------|--------|-------|-------|----------|----------------|----------|------------------
// Minimal       | 16     | 32    | 4     | 8        | 16x32 → 16x8   | ~1 min   | Fastest testing
// Tiny          | 32     | 64    | 8     | 8        | 32x64 → 32x8   | ~3 min   | Fast iteration
// Small      ⭐ | 32     | 128   | 8     | 16       | 32x128 → 32x16 | ~5 min   | Good middle ground
// Medium        | 32     | 256   | 8     | 32       | 32x256 → 32x32 | ~10 min  | Larger tests
// Medium-Plus   | 32     | 384   | 12    | 32       | 32x384 → 32x32 | ~15 min  | Pre-Base validation
// Base (BERT)   | 32     | 768   | 12    | 64       | 32x768 → 32x64 | ~25 min  | Full BERT

// Active configuration: Small
parameter TOKENS = 32;
parameter EMBED = 128;
parameter NUM_HEADS = 8;
// ============================================================================
// Derived Parameters (from matrix multiply constraints)
// ============================================================================

// Per-head dimension: EMBED must be divisible by NUM_HEADS
parameter HEAD_DIM = EMBED / NUM_HEADS;  // 768/12 = 64

// ============================================================================
// Data Widths
// ============================================================================

parameter D_W = 8;           // Input/weight data width (8-bit quantized)
parameter D_W_ACC = 32;      // Accumulator width for matmul output

// ============================================================================
// Systolic Array Parameters
// ============================================================================

parameter N1 = 2;            // Systolic array rows
parameter N2 = 2;            // Systolic array columns

// ============================================================================
// Memory Sizes (Derived from matrix dimensions)
// ============================================================================

// Input I: TOKENS × EMBED elements, 8-bit each
parameter SIZE_I_BYTES = TOKENS * EMBED;              // 32×768 = 24KB

// Weight W^Q/K/V: EMBED × HEAD_DIM elements, 8-bit each
parameter SIZE_W_BYTES = EMBED * HEAD_DIM;            // 768×64 = 48KB

// Output Q/K/V (before requant): TOKENS × HEAD_DIM elements, 32-bit each
parameter SIZE_OUT_32B_BYTES = TOKENS * HEAD_DIM * 4; // 32×64×4 = 8KB

// Output Q'/K'/V' (after requant): TOKENS × HEAD_DIM elements, 8-bit each
parameter SIZE_OUT_8B_BYTES = TOKENS * HEAD_DIM;      // 32×64 = 2KB

// Attention scores S: TOKENS × TOKENS elements, 32-bit each
parameter SIZE_S_BYTES = TOKENS * TOKENS * 4;         // 32×32×4 = 4KB

// Softmax output P: TOKENS × TOKENS elements, 8-bit each
parameter SIZE_P_BYTES = TOKENS * TOKENS;             // 32×32 = 1KB

// Context output C': TOKENS × HEAD_DIM elements, 8-bit each
parameter SIZE_C_PRIME_BYTES = TOKENS * HEAD_DIM;     // 32×64 = 2KB

// Self-Output Layer: Attention output (TOKENS × EMBED), 8-bit each
parameter SIZE_ATTN_OUTPUT_BYTES = TOKENS * EMBED;    // 32×768 = 24KB

// Self-Output Weight: W_self_output (EMBED × EMBED), 8-bit each
parameter SIZE_SELF_WEIGHT_BYTES = EMBED * EMBED;     // 768×768 = 576KB

// Self-Output Residual: (TOKENS × EMBED), 8-bit each
parameter SIZE_RESIDUAL_BYTES = TOKENS * EMBED;       // 32×768 = 24KB

// Self-Output Final: (TOKENS × EMBED), 8-bit each
parameter SIZE_SELF_OUTPUT_BYTES = TOKENS * EMBED;    // 32×768 = 24KB

// ============================================================================
// DDR Address Map
// ============================================================================

// Base address in DDR region (Versal DDR starts at 0x0000_0600_0000)
parameter [63:0] DDR_BASE = 64'h0000_0600_0000;

// Address offsets (with padding for alignment)
parameter [63:0] ADDR_I        = DDR_BASE + 64'h0000_0000;  // Input I
parameter [63:0] ADDR_W_Q      = DDR_BASE + 64'h0001_0000;  // Weight W^Q (+64KB)
parameter [63:0] ADDR_W_K      = DDR_BASE + 64'h0002_0000;  // Weight W^K (+128KB)
parameter [63:0] ADDR_W_V      = DDR_BASE + 64'h0003_0000;  // Weight W^V (+192KB)
parameter [63:0] ADDR_Q_PRIME  = DDR_BASE + 64'h0004_0000;  // Output Q' (+256KB)
parameter [63:0] ADDR_K_PRIME_T= DDR_BASE + 64'h0004_1000;  // Output K'^T
parameter [63:0] ADDR_V_PRIME  = DDR_BASE + 64'h0004_2000;  // Output V'

// Self-attention intermediate results
parameter [63:0] ADDR_S        = DDR_BASE + 64'h0005_0000;  // Attention scores S (TOKENS×TOKENS×4)
parameter [63:0] ADDR_P        = DDR_BASE + 64'h0005_1000;  // Softmax output P (TOKENS×TOKENS)
parameter [63:0] ADDR_C_PRIME  = DDR_BASE + 64'h0005_2000;  // Context output C' (TOKENS×HEAD_DIM)

// Self-Output Layer addresses
parameter [63:0] ADDR_ATTN_OUTPUT = DDR_BASE + 64'h0006_0000;  // Attention output (TOKENS×EMBED)
parameter [63:0] ADDR_SELF_WEIGHT = DDR_BASE + 64'h0007_0000;  // W_self_output (EMBED×EMBED)
parameter [63:0] ADDR_RESIDUAL    = DDR_BASE + 64'h000F_0000;  // Residual (TOKENS×EMBED)
parameter [63:0] ADDR_SELF_OUTPUT = DDR_BASE + 64'h0010_0000;  // Final output (TOKENS×EMBED)

// ============================================================================
// Requantization Parameters
// ============================================================================

parameter [31:0] REQUANT_M = 32'h0000_0100;  // Scale multiplier
parameter [7:0]  REQUANT_E = 8'd8;           // Shift amount

// Self-Output Layer requantization
parameter [31:0] REQUANT_M_MM = 32'h0000_0100;  // Matmul output scale
parameter [7:0]  REQUANT_E_MM = 8'd8;           // Matmul output shift
parameter [31:0] REQUANT_M_LN = 32'h0000_0100;  // LayerNorm output scale
parameter [7:0]  REQUANT_E_LN = 8'd8;           // LayerNorm output shift

// ============================================================================
// Softmax Coefficients (fixed-point, FP_BITS=30)
// These are typical values for quantized softmax in IBERT
// ============================================================================

parameter signed [31:0] SOFTMAX_QB      = 32'sd1073741824;  // ~1.0 in FP30
parameter signed [31:0] SOFTMAX_QC      = 32'sd536870912;   // ~0.5 in FP30
parameter signed [31:0] SOFTMAX_QLN2    = 32'sd744261118;   // ln(2) in FP30
parameter signed [31:0] SOFTMAX_QLN2_INV= 32'sd1549082005;  // 1/ln(2) in FP30
parameter        [31:0] SOFTMAX_SREQ    = 32'd1073741824;   // Softmax requant scale

// ============================================================================
// Simulation Control
// ============================================================================

// Timeout in clock cycles for waiting on operations
parameter TIMEOUT_CYCLES = 1000000;

`endif // IBERT_PARAMS_SVH
