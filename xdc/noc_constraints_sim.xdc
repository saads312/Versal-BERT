################################
# Get NoC Interfaces
################################

# XPM_NMU interfaces from RTL module instantiated in design_1_wrapper
# noc_self_attn_top has 3 XPM_NMU instances:
#   - xpm_nmu_read_a: Read path A (I, Q', P for different operations)
#   - xpm_nmu_read_b: Read path B (W, K'^T, V' for different operations)
#   - xpm_nmu_write: Write outputs (Q'/K'^T/V', P, C')
set nmu_read_a  [get_noc_interfaces noc_self_attn_top_inst/xpm_nmu_read_a/S_AXI_nmu]
set nmu_read_b  [get_noc_interfaces noc_self_attn_top_inst/xpm_nmu_read_b/S_AXI_nmu]
set nmu_write   [get_noc_interfaces noc_self_attn_top_inst/xpm_nmu_write/S_AXI_nmu]

# DDR MC NSU interface from Block Design (PORT0_ddrc is the port to DDR MC)
set ddrmc_nsu [get_noc_interfaces design_1_i/axi_noc_0/PORT0_ddrc]

################################
# Create NoC Connections
################################

# Read path A: RTL NMU -> NoC -> DDR
# Used for: I (3x), Q', P
set conn_a [create_noc_connection -source $nmu_read_a -target $ddrmc_nsu]

# Read path B: RTL NMU -> NoC -> DDR
# Used for: W^Q/K/V, K'^T, V'
set conn_b [create_noc_connection -source $nmu_read_b -target $ddrmc_nsu]

# Write path: RTL NMU -> NoC -> DDR
# Used for: Q'/K'^T/V', P, C'
set conn_out [create_noc_connection -source $nmu_write -target $ddrmc_nsu]

################################
# Quality of Service for NoC Connections
################################

# Read path A: Read-heavy workload
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_a

# Read path B: Read-heavy workload
set_property -dict [list \
    READ_BANDWIDTH {2000} \
    READ_AVERAGE_BURST {4} \
    WRITE_BANDWIDTH {0} \
] $conn_b

# Write path: Write-only workload
set_property -dict [list \
    READ_BANDWIDTH {0} \
    WRITE_BANDWIDTH {1000} \
    WRITE_AVERAGE_BURST {4} \
] $conn_out
