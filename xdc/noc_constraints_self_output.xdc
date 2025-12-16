################################
# Get NoC Interfaces
################################

# XPM_NMU interfaces from RTL module instantiated in design_1_wrapper_self_output
# noc_self_output_top has 4 XPM_NMU instances:
#   - xpm_nmu_attn_read: Read Attention Output from DDR
#   - xpm_nmu_weight_read: Read W_self_output weight from DDR
#   - xpm_nmu_residual_read: Read Residual from DDR
#   - xpm_nmu_output_write: Write final output to DDR
set nmu_attn     [get_noc_interfaces noc_self_output_top_inst/xpm_nmu_attn_read/S_AXI_nmu]
set nmu_weight   [get_noc_interfaces noc_self_output_top_inst/xpm_nmu_weight_read/S_AXI_nmu]
set nmu_residual [get_noc_interfaces noc_self_output_top_inst/xpm_nmu_residual_read/S_AXI_nmu]
set nmu_output   [get_noc_interfaces noc_self_output_top_inst/xpm_nmu_output_write/S_AXI_nmu]

# DDR MC NSU interface from Block Design (PORT0_ddrc is the port to DDR MC)
set ddrmc_nsu [get_noc_interfaces design_1_i/axi_noc_0/PORT0_ddrc]

################################
# Create NoC Connections
################################

# Attention output read path: RTL NMU -> NoC -> DDR
# Read attention output (TOKENS × EMBED = 24KB for 32×768)
set conn_attn [create_noc_connection -source $nmu_attn -target $ddrmc_nsu]

# Weight read path: RTL NMU -> NoC -> DDR
# Read W_self_output (EMBED × EMBED = 576KB for 768×768)
set conn_weight [create_noc_connection -source $nmu_weight -target $ddrmc_nsu]

# Residual read path: RTL NMU -> NoC -> DDR
# Read residual (TOKENS × EMBED = 24KB for 32×768)
set conn_residual [create_noc_connection -source $nmu_residual -target $ddrmc_nsu]

# Output write path: RTL NMU -> NoC -> DDR
# Write final output (TOKENS × EMBED = 24KB for 32×768)
set conn_out [create_noc_connection -source $nmu_output -target $ddrmc_nsu]

################################
# Quality of Service for NoC Connections
################################

# Attention output: Read-only workload (24KB)
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_attn

# Weight: Read-only workload (576KB is the largest transfer)
set_property -dict [list \
    READ_BANDWIDTH {3000} \
    READ_AVERAGE_BURST {8} \
    WRITE_BANDWIDTH {0} \
] $conn_weight

# Residual: Read-only workload (24KB)
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_residual

# Output: Write-only workload (24KB)
set_property -dict [list \
    READ_BANDWIDTH {0} \
    WRITE_BANDWIDTH {2000} \
    WRITE_AVERAGE_BURST {4} \
] $conn_out