################################
# Get NoC Interfaces
################################

# XPM_NMU interfaces from RTL module instantiated in design_1_wrapper
# noc_attn_proj_top has 3 XPM_NMU instances:
#   - xpm_nmu_input_i: Read Input I from DDR
#   - xpm_nmu_weight_w: Read Weights W^Q/K/V from DDR
#   - xpm_nmu_output: Write outputs Q'/K'^T/V' to DDR
set nmu_input_i  [get_noc_interfaces noc_attn_proj_top_inst/xpm_nmu_input_i/S_AXI_nmu]
set nmu_weight_w [get_noc_interfaces noc_attn_proj_top_inst/xpm_nmu_weight_w/S_AXI_nmu]
set nmu_output   [get_noc_interfaces noc_attn_proj_top_inst/xpm_nmu_output/S_AXI_nmu]

# DDR MC NSU interface from Block Design (PORT0_ddrc is the port to DDR MC)
set ddrmc_nsu [get_noc_interfaces design_1_i/axi_noc_0/PORT0_ddrc]

################################
# Create NoC Connections
################################

# Input I read path: RTL NMU -> NoC -> DDR
# I is read 3 times (once per Q/K/V projection)
set conn_i [create_noc_connection -source $nmu_input_i -target $ddrmc_nsu]

# Weight W read path: RTL NMU -> NoC -> DDR
# W^Q, W^K, W^V are read sequentially
set conn_w [create_noc_connection -source $nmu_weight_w -target $ddrmc_nsu]

# Output write path: RTL NMU -> NoC -> DDR
# Q', K'^T, V' are written sequentially
set conn_out [create_noc_connection -source $nmu_output -target $ddrmc_nsu]

################################
# Quality of Service for NoC Connections
################################

# Input I: Read-heavy workload (24KB * 3 reads = 72KB total)
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_i

# Weight W: Read-heavy workload (48KB * 3 weights = 144KB total)
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_w

# Output: Write-only workload (2KB * 3 outputs = 6KB total)
set_property -dict [list \
    READ_BANDWIDTH {0} \
    WRITE_BANDWIDTH {1000} \
    WRITE_AVERAGE_BURST {4} \
] $conn_out
