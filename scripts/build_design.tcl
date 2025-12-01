#
# Build script for NoC Matrix Multiply Design
# Following Vivado RTL + NoC flow
#

set project_name "noc_mm_project"
set project_dir "[file normalize ..]"
set rtl_dir "${project_dir}/rtl"
set bd_dir "${project_dir}/bd"
set xdc_dir "${project_dir}/xdc"
set ip_dir "${project_dir}/ip"

# Create project
create_project ${project_name} ${project_dir}/${project_name} -part xcvc1902-vsva2197-2MP-e-S -force

# Set VCK190 board
set_property board_part xilinx.com:vck190:part0:3.2 [current_project]

# Set target language
set_property target_language Verilog [current_project]

#####################################################
# Generate Block Design (CIPS + DDR NoC)
#####################################################
puts "INFO: Generating Block Design..."
source ${bd_dir}/bd.tcl

# Generate BD outputs
generate_target {synthesis instantiation_template} [get_files design_1.bd]

#####################################################
# Add RTL sources
#####################################################
puts "INFO: Adding RTL sources..."

# Add all SystemVerilog modules from llm_rtl
add_files -fileset sources_1 [glob ${rtl_dir}/*.sv]

# DMA controllers
add_files -fileset sources_1 ${rtl_dir}/axi4_read_dma.v
add_files -fileset sources_1 ${rtl_dir}/axi4_write_dma.v

# Top-level with XPM NoC macros
add_files -fileset sources_1 ${rtl_dir}/noc_mm_top.v
add_files -fileset sources_1 ${rtl_dir}/noc_mm_wrapper.v

# Set top module
set_property top noc_mm_wrapper [current_fileset]

#####################################################
# Add XDC constraints
#####################################################
puts "INFO: Adding NoC constraints..."
add_files -fileset constrs_1 ${xdc_dir}/noc_constraints.xdc

# CRITICAL: Set NoC constraints to run before synthesis
set_property USED_IN {synthesis_pre} [get_files ${xdc_dir}/noc_constraints.xdc]

#####################################################
# Update compile order
#####################################################
update_compile_order -fileset sources_1

#####################################################
# Validate NoC
#####################################################
puts "INFO: Validating NoC..."
validate_noc

#####################################################
# Run Synthesis
#####################################################
puts "INFO: Launching Synthesis..."
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: Synthesis failed!"
}

#####################################################
# Run Implementation
#####################################################
puts "INFO: Launching Implementation..."
set_property strategy Performance_ExploreWithRemap [get_runs impl_1]
launch_runs impl_1 -to_step write_device_image -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: Implementation failed!"
}

#####################################################
# Generate Reports
#####################################################
puts "INFO: Generating reports..."
open_run impl_1

report_utilization -file ${project_dir}/utilization.rpt
report_timing_summary -file ${project_dir}/timing.rpt
report_power -file ${project_dir}/power.rpt
report_noc -file ${project_dir}/noc.rpt

puts "INFO: Build complete! Device image written."
puts "INFO: Reports generated in ${project_dir}/"

exit
