(vivado -mode batch -source scripts/build_inter_sim.tcl 2>&1 | tee build.log) && \
cd noc_inter_sim/noc_inter_sim.sim/sim_1/behav/xsim && \
(xsim noc_inter_tb_behav -runall 2>&1 | tee ../../../../sim.log) && \
cd -
