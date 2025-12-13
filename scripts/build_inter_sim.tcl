#
# Simulation Build Script for NoC Intermediate Stage Design
# Tests Matrix Multiply + GELU + Requantization
#

set project_name "noc_inter_sim"
set project_dir "[file normalize .]"
set rtl_dir "${project_dir}/rtl"
set bd_dir "${project_dir}/bd"
set xdc_dir "${project_dir}/xdc"
set sim_dir "${project_dir}/sim"

# Create project
puts "INFO: Creating simulation project..."
create_project ${project_name} ${project_dir}/${project_name} -part xcvc1902-vsva2197-2MP-e-S -force

# Set VCK190 board
set_property board_part xilinx.com:vck190:part0:3.2 [current_project]

# Set target language and simulator
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

#####################################################
# Generate Block Design (CIPS + AXI NoC + DDR4)
#####################################################
puts "INFO: Generating Block Design with NoC and DDR..."
source ${bd_dir}/bd_with_noc.tcl

#####################################################
# Add Simulation Sources
#####################################################
puts "INFO: Adding simulation sources..."

# Add parameter file to include path
# This allows `include "ibert_params.svh" to work
import_files -fileset sources_1 ${sim_dir}/ibert_params.svh
import_files -fileset sim_1 ${sim_dir}/ibert_params.svh

# Set include directories for verilog compilation
set_property include_dirs [list ${sim_dir}] [get_filesets sources_1]
set_property include_dirs [list ${sim_dir}] [get_filesets sim_1]

# Import Testbench
import_files -fileset sim_1 ${sim_dir}/noc_inter_tb.sv
set_property top noc_inter_tb [get_filesets sim_1]

#####################################################
# Add RTL sources with XPM NMUs
#####################################################
puts "INFO: Adding RTL sources with XPM NoC instances..."

# Import all RTL files including SystemVerilog modules
import_files -norecurse [glob ${rtl_dir}/*.sv]

# Import Verilog files
import_files -norecurse ${rtl_dir}/axi4_read_dma.v
import_files -norecurse ${rtl_dir}/axi4_write_dma.v
import_files -norecurse ${rtl_dir}/noc_inter_control.v
import_files -norecurse ${rtl_dir}/noc_inter_top.v

# Import the top-level wrapper that combines BD + RTL (SystemVerilog for parameter include)
import_files -norecurse ${rtl_dir}/design_1_wrapper_inter.sv

# Set top module to the wrapper (combines block design and RTL)
set_property top design_1_wrapper_inter [current_fileset]

#####################################################
# Generate ALL targets BEFORE validate_noc (AMD pattern)
#####################################################
puts "INFO: Generating synthesis AND simulation targets for Block Design..."
generate_target {synthesis simulation instantiation_template} [get_files design_1.bd]

#####################################################
# Update compile order
#####################################################
puts "INFO: Updating compile order..."
update_compile_order -fileset sources_1

#####################################################
# Source NoC constraints as TCL (not XDC) BEFORE validate_noc
# CRITICAL: In simulation-only flow, XDC doesn't run, must source as TCL
#####################################################
puts "INFO: Sourcing NoC constraints TCL commands..."
source ${xdc_dir}/noc_constraints_sim.xdc

#####################################################
# Validate NoC - will use connections created above
# This generates routing but defparams.vh may not be populated correctly
#####################################################
puts "INFO: Validating NoC (after creating connections)..."
validate_noc

#####################################################
# WORKAROUND: Patch defparams.vh with routing configuration
# validate_noc doesn't populate XPM_NMU routing in simulation-only flow
#####################################################
puts "INFO: Patching defparams.vh with NoC routing configuration..."
source ${project_dir}/scripts/patch_defparams.tcl

#####################################################
# Simulation Settings
#####################################################
puts "INFO: Configuring simulation settings..."

set_property -name {xsim.simulate.runtime} -value {100ms} -objects [get_filesets sim_1]

# Enable waveform
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

#####################################################
# Update compile order again after validate_noc
#####################################################
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

#####################################################
# Launch Simulation
#####################################################
puts "INFO: Launching behavioral simulation..."
launch_simulation

puts "INFO: Simulation project created successfully"
puts "INFO: To run simulation, use: run 50us"
