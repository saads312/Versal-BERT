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

// ============================================================================
// Requantization Parameters
// ============================================================================

parameter [31:0] REQUANT_M = 32'h0000_0100;  // Scale multiplier
parameter [7:0]  REQUANT_E = 8'd8;           // Shift amount

// ============================================================================
// Simulation Control
// ============================================================================

// Timeout in clock cycles for waiting on operations
parameter TIMEOUT_CYCLES = 1000000;

// ============================================================================
// Intermediate Layer Parameters
// ============================================================================
parameter INPUT_SIZE = 32;          // Input size (rows of A~)
parameter HIDDEN_SIZE = 768;        // Hidden size (cols of A~, rows of K'^T)
parameter EXP_SIZE = 3072;          // Expansion size (cols of K'^T)

// Addresses (aligned to 4KB for safety)
parameter [63:0] ADDR_A = 64'h0000_0000_8000_0000;
parameter [63:0] ADDR_K = 64'h0000_0000_8010_0000;
parameter [63:0] ADDR_G = 64'h0000_0000_8040_0000;

// Requantization defaults
parameter [31:0] REQUANT_M_MULT = 32'd1000; 
parameter [7:0]  REQUANT_E_MULT = 8'd10;
parameter [31:0] REQUANT_M_G    = 32'd1000;
parameter [7:0]  REQUANT_E_G    = 8'd10;

`endif // IBERT_PARAMS_SVH
