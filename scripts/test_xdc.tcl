#
# Test XDC constraints in existing project
#
open_project noc_mm_sim/noc_mm_sim.xpr

# Try to get the NoC interfaces
puts "INFO: Attempting to get NoC interfaces..."

set nmu_matrix_a [get_noc_interfaces -quiet noc_mm_top_inst/xpm_nmu_matrix_a/S_AXI_nmu]
puts "INFO: nmu_matrix_a = $nmu_matrix_a"

set nmu_matrix_b [get_noc_interfaces -quiet noc_mm_top_inst/xpm_nmu_matrix_b/S_AXI_nmu]
puts "INFO: nmu_matrix_b = $nmu_matrix_b"

set nmu_matrix_d [get_noc_interfaces -quiet noc_mm_top_inst/xpm_nmu_matrix_d/S_AXI_nmu]
puts "INFO: nmu_matrix_d = $nmu_matrix_d"

set ddrmc_nsu [get_noc_interfaces -quiet design_1_i/axi_noc_0/PORT0_ddrc]
puts "INFO: ddrmc_nsu = $ddrmc_nsu"

# List all NoC interfaces in the design
puts "INFO: All NoC interfaces in design:"
foreach iface [get_noc_interfaces] {
    puts "  $iface"
}

close_project
