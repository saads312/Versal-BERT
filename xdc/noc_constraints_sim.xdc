################################
# Get NoC Interfaces
################################

# XPM_NMU interfaces from RTL module instantiated in design_1_wrapper
set nmu_matrix_a [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_a/S_AXI_nmu]
set nmu_matrix_b [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_b/S_AXI_nmu]
set nmu_matrix_d [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_d/S_AXI_nmu]

# DDR MC NSU interface from Block Design (PORT0_ddrc is the port to DDR MC)
set ddrmc_nsu [get_noc_interfaces design_1_i/axi_noc_0/PORT0_ddrc]

################################
# Create NoC Connections
################################

# mat A read path: RTL NMU -> NoC -> DDR
set conn_a [create_noc_connection -source $nmu_matrix_a -target $ddrmc_nsu]

# mat B read path: RTL NMU -> NoC -> DDR
set conn_b [create_noc_connection -source $nmu_matrix_b -target $ddrmc_nsu]

# mat D write path: RTL NMU -> NoC -> DDR
set conn_d [create_noc_connection -source $nmu_matrix_d -target $ddrmc_nsu]

################################
# quality of service for noc connections
################################

# Matrix A: Read-only workload
set_property -dict [list \
    READ_BANDWIDTH {1000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_a

# Matrix B: Read-only workload
set_property -dict [list \
    READ_BANDWIDTH {1000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_b

# Matrix D: Write-only workload
set_property -dict [list \
    READ_BANDWIDTH {0} \
    WRITE_BANDWIDTH {1000} \
    WRITE_AVERAGE_BURST {4} \
] $conn_d
