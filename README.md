# Mapping iBERT to AMD Versal Network-on-Chip

This project maps a BERT-style (iBERT) encoder datapath onto the AMD Versal hardened Network-on-Chip (NoC). The system is roughly integrated as follows: DDR → NoC → DMA → AXI-Stream → PL compute → AXI-Stream → DMA → NoC → DDR, and validating correctness under realistic NoC/AXI constraints.

## Architecture Overview

DDR-backed buffers are accessed through NoC endpoints (XPM NMUs). Read DMAs convert AXI memory-mapped reads into AXI-Stream for PL compute blocks. Write DMAs commit AXI-Stream outputs back to DDR through the NoC.

DDR (Matrix A) ──> XPM_NMU ──> NoC ──> Read DMA ──> AXI-Stream   ─┐
                                                                  │
DDR (Matrix B) ──> XPM_NMU ──> NoC ──> Read DMA ──> AXI-Stream  ──┼──> Systolic MM (2x2) ──> AXI-Stream ──> Write DMA ──> NoC ──> XPM_NMU ──> DDR (Result)

This transport pattern is reused for attention projections and other encoder stages.

## Methodology

- DDR <-> NoC <-> DMA <-> AXI-Stream infrastructure integrated in simulation
- Multi-head self-attention functional with 4 heads and verified across larger parameter sets (subject to tiling constraints)
- Self-output and feed-forward stages partially integrated and most sensitive to buffering/backpressure during scaling

## Simulation and Verification

DDR/VIP simulation observability is limited, so correctness is validated primarily using SystemVerilog backdoor inspection at key stream boundaries (payload ordering, completeness, and stage boundary values) prior to full closure with the Vivado NoC compiler flow.

Run simulation:
source /zfsspare/opt/Xilinx/2025.1/Vivado/settings64.sh && (vivado -mode batch -source scripts/build_simulation.tcl 2>&1 | tee build.log) && cd noc_mm_sim/noc_mm_sim.sim/sim_1/behav/xsim && (xsim noc_mm_tb_behav -runall 2>&1 | tee ../../../../sim.log)

## Scaling constraints for valid configurations:

1. HEAD_DIM must be integer: EMBED % NUM_HEADS == 0
2. Systolic tiling compatibility: TOKENS % N1 == 0 and HEAD_DIM % N2 == 0
3. Memory alignment preference: use powers of 2 or multiples of 16 for EMBED/HEAD_DIM

Systolic tiling compatibility: TOKENS % N1 == 0 and HEAD_DIM % N2 == 0

Memory alignment preference: use powers of 2 or multiples of 16 for EMBED/HEAD_DIM