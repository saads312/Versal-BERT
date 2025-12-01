################################
# noc ifaces
################################
# extract XPM_NMU interfaces from RTL (read DMAs for A and B)
set nmu_matrix_a [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_a/S_AXI_nmu]
set nmu_matrix_b [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_b/S_AXI_nmu]

# extract XPM_NMU interface from RTL (write DMAs for matrix D)
set nmu_matrix_d [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_d/S_AXI_nmu]

# Get DDR Memory Controller NoC interface from AXI NoC IP
set ddrmc_nsu [get_noc_interfaces design_1_i/axi_noc_0/PORT0_ddrc]

################################
# noc connections
################################
# Connect Read DMA A → DDR MC
set conn_a [create_noc_connection -source $nmu_matrix_a -target $ddrmc_nsu]
set_property -dict [list READ_BANDWIDTH 500 READ_AVERAGE_BURST 4 WRITE_BANDWIDTH 0 WRITE_AVERAGE_BURST 0] $conn_a
# Connect Read DMA B → DDR MC
set conn_b [create_noc_connection -source $nmu_matrix_b -target $ddrmc_nsu]
set_property -dict [list READ_BANDWIDTH 500 READ_AVERAGE_BURST 4 WRITE_BANDWIDTH 0 WRITE_AVERAGE_BURST 0] $conn_b
# Connect Write DMA D → DDR MC
set conn_d [create_noc_connection -source $nmu_matrix_d -target $ddrmc_nsu]
set_property -dict [list READ_BANDWIDTH 0 READ_AVERAGE_BURST 0 WRITE_BANDWIDTH 500 WRITE_AVERAGE_BURST 4] $conn_d