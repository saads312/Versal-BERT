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

// Sequence length (number of tokens)
parameter TOKENS = 4;       // Full IBERT: 32

// Embedding dimension (hidden size)
parameter EMBED = 64;       // Full IBERT: 768

// Number of attention heads
parameter NUM_HEADS = 4;    // Full IBERT: 12 → HEAD_DIM = 16

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

// Self-Output Layer addresses
parameter [63:0] ADDR_ATTN_OUTPUT = DDR_BASE + 64'h0005_0000;  // Attention output (+320KB)
parameter [63:0] ADDR_SELF_WEIGHT = DDR_BASE + 64'h0006_0000;  // W_self_output (+384KB)
parameter [63:0] ADDR_RESIDUAL    = DDR_BASE + 64'h000F_0000;  // Residual (+960KB, after weight)
parameter [63:0] ADDR_SELF_OUTPUT = DDR_BASE + 64'h0010_0000;  // Final output (+1MB)

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
// Simulation Control
// ============================================================================

// Timeout in clock cycles for waiting on operations
parameter TIMEOUT_CYCLES = 1000000;

`endif // IBERT_PARAMS_SVH
