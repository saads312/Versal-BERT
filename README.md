# Mapping IBERT to Versal NoC

Due to DDR IP in simulation not being available for complete read/write access and the limits we start to see with BRAMs, we're going to be validating the data integrity of our operations using simple SV backdoor signal access, and then using the full DDR IP (which in Xilinx's xsim case, jsut mocks the reads/writes) and compiling it with NoC Compiler.

This is the setup at the moment

DDR (Matrix A) ──> XPM_NMU ──> NoC ──> Read DMA ──> AXI-Stream   ─┐
                                                                  │
DDR (Matrix B) ──> XPM_NMU ──> NoC ──> Read DMA ──> AXI-Stream  ──┼──> Systolic MM (2x2) ──> AXI-Stream ──> Write DMA ──> NoC ──> XPM_NMU ──> DDR (Result)


Run it with

```
source /zfsspare/opt/Xilinx/2025.1/Vivado/settings64.sh  && (vivado -mode batch -source scripts/build_simulation.tcl 2>&1 | tee build.log) && cd noc_mm_sim/noc_mm_sim.sim/sim_1/behav/xsim && (xsim noc_mm_tb_behav -runall 2>&1 | tee ../../../../sim.log)
```

To go all the way, we'll be following a similar structure as the above flowchart for mapping the whole operation onto