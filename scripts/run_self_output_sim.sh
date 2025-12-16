#!/bin/bash
(vivado -mode batch -source scripts/build_self_output_sim.tcl 2>&1 | tee build.log) && \
cd noc_self_output_sim/noc_self_output_sim.sim/sim_1/behav/xsim && \
(xsim noc_self_output_tb_behav -runall 2>&1 | tee ../../../../sim.log) && \
cd -
