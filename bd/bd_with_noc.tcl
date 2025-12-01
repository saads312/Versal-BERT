#
# Block Design with AXI NoC and DDR4 Memory Controller
# Based on Vivado RTL Foundational tutorial pattern
#

create_bd_design "design_1"

# Create CIPS
create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:* versal_cips_0

set_property -dict [list \
    CONFIG.PS_PMC_CONFIG { \
        DDR_MEMORY_MODE {Connectivity to DDR via NoC} \
        DESIGN_MODE {1} \
        PMC_CRP_PL0_REF_CTRL_FREQMHZ {300} \
        PMC_USE_PMC_NOC_AXI0 {1} \
        PS_HSDP_EGRESS_TRAFFIC {JTAG} \
        PS_HSDP_INGRESS_TRAFFIC {JTAG} \
        PS_HSDP_MODE {NONE} \
        PS_NUM_FABRIC_RESETS {1} \
        PS_PL_CONNECTIVITY_MODE {Custom} \
        PS_USE_FPD_CCI_NOC {1} \
        PS_USE_M_AXI_FPD {0} \
        PS_USE_NOC_LPD_AXI0 {0} \
        PS_USE_PMCPL_CLK0 {1} \
        SMON_ALARMS {Set_Alarms_On} \
        SMON_ENABLE_TEMP_AVERAGING {0} \
        SMON_TEMP_AVERAGING_SAMPLES {0} \
    } \
] [get_bd_cells versal_cips_0]

# Create AXI NoC with DDR
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:* axi_noc_0

# Enable one DDR memory controller with 4 CCI slave interfaces (required for CCI interleaving)
set_property -dict [list \
    CONFIG.NUM_SI {4} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_CLKS {4} \
    CONFIG.NUM_MC {1} \
    CONFIG.MC0_CONFIG_NUM {config17} \
    CONFIG.MC0_FLIPPED_PINOUT {true} \
    CONFIG.MC_INPUTCLK0_PERIOD {5000} \
    CONFIG.MC_MEMORY_DEVICETYPE {UDIMMs} \
    CONFIG.MC_F1_TRCD {15000} \
    CONFIG.MC_F1_TRCDMIN {15000} \
    CONFIG.MC_SYSTEM_CLOCK {Differential} \
] [get_bd_cells axi_noc_0]

# Configure S00_AXI: ps_cci category with connection to DDR MC_0
set_property -dict [list \
    CONFIG.CATEGORY {ps_cci} \
    CONFIG.CONNECTIONS {MC_0 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}} \
] [get_bd_intf_pins /axi_noc_0/S00_AXI]

# Configure S01_AXI: ps_cci category with connection to DDR MC_0
set_property -dict [list \
    CONFIG.CATEGORY {ps_cci} \
    CONFIG.CONNECTIONS {MC_0 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}} \
] [get_bd_intf_pins /axi_noc_0/S01_AXI]

# Configure S02_AXI: ps_cci category with connection to DDR MC_0
set_property -dict [list \
    CONFIG.CATEGORY {ps_cci} \
    CONFIG.CONNECTIONS {MC_0 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}} \
] [get_bd_intf_pins /axi_noc_0/S02_AXI]

# Configure S03_AXI: ps_cci category with connection to DDR MC_0
set_property -dict [list \
    CONFIG.CATEGORY {ps_cci} \
    CONFIG.CONNECTIONS {MC_0 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}} \
] [get_bd_intf_pins /axi_noc_0/S03_AXI]

# Associate clocks with slave interfaces
set_property CONFIG.ASSOCIATED_BUSIF {S00_AXI} [get_bd_pins /axi_noc_0/aclk0]
set_property CONFIG.ASSOCIATED_BUSIF {S01_AXI} [get_bd_pins /axi_noc_0/aclk1]
set_property CONFIG.ASSOCIATED_BUSIF {S02_AXI} [get_bd_pins /axi_noc_0/aclk2]
set_property CONFIG.ASSOCIATED_BUSIF {S03_AXI} [get_bd_pins /axi_noc_0/aclk3]

# Connect CIPS to NoC - all 4 CCI interfaces required for interleaving
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_0] [get_bd_intf_pins axi_noc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_1] [get_bd_intf_pins axi_noc_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_2] [get_bd_intf_pins axi_noc_0/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_3] [get_bd_intf_pins axi_noc_0/S03_AXI]

# Connect clocks - each CCI interface has its own clock
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi0_clk] [get_bd_pins axi_noc_0/aclk0]
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi1_clk] [get_bd_pins axi_noc_0/aclk1]
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi2_clk] [get_bd_pins axi_noc_0/aclk2]
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi3_clk] [get_bd_pins axi_noc_0/aclk3]

# Create DDR4 ports
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 CH0_DDR4_0
connect_bd_intf_net [get_bd_intf_pins axi_noc_0/CH0_DDR4_0] [get_bd_intf_ports CH0_DDR4_0]

create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk0
set_property CONFIG.FREQ_HZ {200000000} [get_bd_intf_ports sys_clk0]
connect_bd_intf_net [get_bd_intf_pins axi_noc_0/sys_clk0] [get_bd_intf_ports sys_clk0]

# Create ports for PL connection
create_bd_port -dir O -type clk clk_pl
create_bd_port -dir O -type rst rstn_pl

connect_bd_net [get_bd_pins versal_cips_0/pl0_ref_clk] [get_bd_ports clk_pl]
connect_bd_net [get_bd_pins versal_cips_0/pl0_resetn] [get_bd_ports rstn_pl]

# Assign addresses - map each CIPS CCI interface to DDR address space
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces versal_cips_0/FPD_CCI_NOC_0] [get_bd_addr_segs axi_noc_0/S00_AXI/C0_DDR_LOW0] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces versal_cips_0/FPD_CCI_NOC_1] [get_bd_addr_segs axi_noc_0/S01_AXI/C0_DDR_LOW0] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces versal_cips_0/FPD_CCI_NOC_2] [get_bd_addr_segs axi_noc_0/S02_AXI/C0_DDR_LOW0] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces versal_cips_0/FPD_CCI_NOC_3] [get_bd_addr_segs axi_noc_0/S03_AXI/C0_DDR_LOW0] -force

# Validate
validate_bd_design
save_bd_design
