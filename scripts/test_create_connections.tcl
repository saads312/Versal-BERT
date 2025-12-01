#
# Test creating NoC connections manually
#
open_project noc_mm_sim/noc_mm_sim.xpr

# Get NoC interfaces
puts "INFO: Getting NoC interfaces..."
set nmu_matrix_a [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_a/S_AXI_nmu]
set nmu_matrix_b [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_b/S_AXI_nmu]
set nmu_matrix_d [get_noc_interfaces noc_mm_top_inst/xpm_nmu_matrix_d/S_AXI_nmu]
set ddrmc_nsu [get_noc_interfaces design_1_i/axi_noc_0/PORT0_ddrc]

puts "INFO: nmu_matrix_a = $nmu_matrix_a"
puts "INFO: nmu_matrix_b = $nmu_matrix_b"
puts "INFO: nmu_matrix_d = $nmu_matrix_d"
puts "INFO: ddrmc_nsu = $ddrmc_nsu"

# Try to create connections
puts "INFO: Creating NoC connections..."
set conn_a [create_noc_connection -source $nmu_matrix_a -target $ddrmc_nsu]
puts "INFO: conn_a = $conn_a"

set conn_b [create_noc_connection -source $nmu_matrix_b -target $ddrmc_nsu]
puts "INFO: conn_b = $conn_b"

set conn_d [create_noc_connection -source $nmu_matrix_d -target $ddrmc_nsu]
puts "INFO: conn_d = $conn_d"

# Set QoS properties
puts "INFO: Setting QoS properties..."
set_property -dict [list READ_BANDWIDTH 1000 READ_AVERAGE_BURST 4 WRITE_BANDWIDTH 0] $conn_a
set_property -dict [list READ_BANDWIDTH 1000 READ_AVERAGE_BURST 4 WRITE_BANDWIDTH 0] $conn_b
set_property -dict [list READ_BANDWIDTH 0 WRITE_BANDWIDTH 1000 WRITE_AVERAGE_BURST 4] $conn_d

# Validate NoC
puts "INFO: Validating NoC..."
validate_noc

puts "INFO: NoC connections created and validated successfully!"
close_project
