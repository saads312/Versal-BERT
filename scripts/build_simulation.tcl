#
# Simulation Build Script for NoC Matrix Multiply Design
# Based on Vivado-Design-Tutorials/Versal NoC simulation flow
#

set project_name "noc_mm_sim"
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
# Add Simulation Sources FIRST
#####################################################
puts "INFO: Adding simulation testbench..."

# Add testbench to sim_1 fileset
if {[file exists ${sim_dir}/noc_mm_tb.sv]} {
    import_files -fileset sim_1 ${sim_dir}/noc_mm_tb.sv
    set_property top noc_mm_tb [get_filesets sim_1]
}

#####################################################
# Add RTL sources with XPM NMUs
#####################################################
puts "INFO: Adding RTL sources with XPM NoC instances..."

# Import all RTL files including SystemVerilog modules
import_files -norecurse [glob ${rtl_dir}/*.sv]

# Import Verilog files
import_files -norecurse ${rtl_dir}/axi4_read_dma.v
import_files -norecurse ${rtl_dir}/axi4_write_dma.v
import_files -norecurse ${rtl_dir}/noc_mm_control.v
import_files -norecurse ${rtl_dir}/noc_mm_top.v

# Import the top-level wrapper that combines BD + RTL
import_files -norecurse ${rtl_dir}/design_1_wrapper.v

# Set top module to the wrapper (combines block design and RTL)
set_property top design_1_wrapper [current_fileset]

#####################################################
# Add NoC constraints XDC (DISABLED - using TCL instead)
#####################################################
# NOTE: NoC connections are now created via TCL commands before validate_noc
# XDC constraints don't work reliably because they run before RTL elaboration
#puts "INFO: Adding NoC constraints..."
#import_files -fileset constrs_1 ${xdc_dir}/noc_constraints_sim.xdc
#set_property USED_IN {synthesis_pre} [get_files noc_constraints_sim.xdc]

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

# Set simulation runtime
set_property -name {xsim.simulate.runtime} -value {50us} -objects [get_filesets sim_1]

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
