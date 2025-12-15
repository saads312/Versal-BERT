################################
# Get NoC Interfaces
################################

# XPM_NMU interfaces from RTL module instantiated in design_1_wrapper_inter
# noc_inter_top has 3 XPM_NMU instances:
#   - xpm_nmu_input_a: Read Matrix A from DDR 
#   - xpm_nmu_weight_k: Read Matrix K (Weight) from DDR 
#   - xpm_nmu_out_g: Write Result Matrix G to DDR 
set nmu_input_a  [get_noc_interfaces noc_inter_top_inst/xpm_nmu_input_a/S_AXI_nmu]
set nmu_weight_k [get_noc_interfaces noc_inter_top_inst/xpm_nmu_weight_k/S_AXI_nmu]
set nmu_out_g    [get_noc_interfaces noc_inter_top_inst/xpm_nmu_out_g/S_AXI_nmu]

# DDR MC NSU interface from Block Design (PORT0_ddrc is the port to DDR MC)
set ddrmc_nsu [get_noc_interfaces design_1_i/axi_noc_0/PORT0_ddrc]

################################
# Create NoC Connections
################################

# Input A read path: RTL NMU -> NoC -> DDR
set conn_a [create_noc_connection -source $nmu_input_a -target $ddrmc_nsu]

# Weight K read path: RTL NMU -> NoC -> DDR
set conn_k [create_noc_connection -source $nmu_weight_k -target $ddrmc_nsu]

# Output G write path: RTL NMU -> NoC -> DDR
set conn_g [create_noc_connection -source $nmu_out_g -target $ddrmc_nsu]

################################
# Quality of Service for NoC Connections
################################

# Input A: Read-heavy workload
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_a

# Weight K: Read-heavy workload
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_k

# Output G: Write-only workload
set_property -dict [list \
    READ_BANDWIDTH {0} \
    WRITE_BANDWIDTH {1000} \
    WRITE_AVERAGE_BURST {4} \
] $conn_g
