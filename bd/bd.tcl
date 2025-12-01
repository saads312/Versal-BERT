#
# Block Design - CIPS with AXI NoC for DDR access
# NoC connections to RTL will be made through XPM macros + XDC constraints
#

create_bd_design "design_1"

# Create CIPS with DDR via NoC
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

# Create AXI NoC for DDR connectivity
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:* axi_noc_0

set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_MC {1} \
    CONFIG.NUM_CLKS {2} \
    CONFIG.MC_CHAN_REGION1 {NONE} \
] [get_bd_cells axi_noc_0]

# Configure S00_AXI slave port (connects to FPD_CCI_NOC from CIPS)
set_property -dict [list \
    CONFIG.REGION {0} \
    CONFIG.CONNECTIONS {MC_0 {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}}} \
    CONFIG.CATEGORY {ps_cci} \
] [get_bd_intf_pins /axi_noc_0/S00_AXI]

# Associate clocks
set_property -dict [list \
    CONFIG.ASSOCIATED_BUSIF {S00_AXI} \
] [get_bd_pins /axi_noc_0/aclk0]

# Create ports for PL connection
create_bd_port -dir O -type clk clk_pl
create_bd_port -dir O -type rst rstn_pl

# Connect interfaces
connect_bd_intf_net [get_bd_intf_pins versal_cips_0/FPD_CCI_NOC_0] [get_bd_intf_pins axi_noc_0/S00_AXI]

# Connect clocks
connect_bd_net [get_bd_pins versal_cips_0/pl0_ref_clk] [get_bd_ports clk_pl] [get_bd_pins axi_noc_0/aclk1]
connect_bd_net [get_bd_pins versal_cips_0/pl0_resetn] [get_bd_ports rstn_pl]
connect_bd_net [get_bd_pins versal_cips_0/fpd_cci_noc_axi0_clk] [get_bd_pins axi_noc_0/aclk0]

# Assign address segments
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces versal_cips_0/FPD_CCI_NOC_0] [get_bd_addr_segs axi_noc_0/S00_AXI/C0_DDR_LOW0] -force

# Validate
validate_bd_design
save_bd_design
