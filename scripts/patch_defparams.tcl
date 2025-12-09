#
# Patch defparams.vh with proper NoC routing configuration
# This is a workaround for validate_noc not populating XPM_NMU routing in simulation-only flow
#

set defparams_file "noc_mm_sim/noc_mm_sim.gen/sources_1/common/nsln/defparams.vh"

puts "INFO: Patching defparams.vh with NoC routing configuration..."
puts "INFO: Reading $defparams_file..."

# Read the existing defparams.vh
set fp [open $defparams_file r]
set content [read $fp]
close $fp

# Configuration for routing to DDR MC at base address 0x0, size 2GB
# DestId = 0 (from design_1_wrapper.ncr)
# Base = 0x00000000
# Mask = 0x7FFFFFFF (2GB range)
set dest_id "00000000"
set addr_enable "00000001"
set base_addr "00000000"
set addr_mask "7FFFFFFF"

# Patch xpm_nmu_input_i (Read Input I from DDR)
puts "INFO: Patching xpm_nmu_input_i routing..."
regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_input_i\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_ENABLE = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_input_i.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_ENABLE = 'h${addr_enable};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_input_i\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_DST0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_input_i.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_DST0 = 'h${dest_id};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_input_i\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_MADDR0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_input_i.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_MADDR0 = 'h${base_addr};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_input_i\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_MASK0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_input_i.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_MASK0 = 'h${addr_mask};" \
    content

# Patch xpm_nmu_weight_w (Read Weights W^Q/K/V from DDR)
puts "INFO: Patching xpm_nmu_weight_w routing..."
regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_weight_w\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_ENABLE = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_weight_w.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_ENABLE = 'h${addr_enable};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_weight_w\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_DST0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_weight_w.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_DST0 = 'h${dest_id};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_weight_w\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_MADDR0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_weight_w.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_MADDR0 = 'h${base_addr};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_weight_w\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_MASK0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_weight_w.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_MASK0 = 'h${addr_mask};" \
    content

# Patch xpm_nmu_output (Write outputs Q'/K'^T/V' to DDR)
puts "INFO: Patching xpm_nmu_output routing..."
regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_output\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_ENABLE = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_output.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_ENABLE = 'h${addr_enable};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_output\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_DST0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_output.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_DST0 = 'h${dest_id};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_output\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_MADDR0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_output.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_MADDR0 = 'h${base_addr};" \
    content

regsub {defparam design_1_wrapper_i\.noc_attn_proj_top_inst\.xpm_nmu_output\.NOC1\.VNOC\.NOC_NMU512_INST\.REG_ADDR_MASK0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_i.noc_attn_proj_top_inst.xpm_nmu_output.NOC1.VNOC.NOC_NMU512_INST.REG_ADDR_MASK0 = 'h${addr_mask};" \
    content

# Write the patched content back
puts "INFO: Writing patched defparams.vh..."
set fp [open $defparams_file w]
puts -nonewline $fp $content
close $fp

puts "INFO: defparams.vh patched successfully!"
puts "INFO: Configuration applied:"
puts "       DestId = 0x${dest_id} (route to DDR MC Port0)"
puts "       Base Address = 0x${base_addr}"
puts "       Address Mask = 0x${addr_mask} (2GB range)"
puts "       Address Enable = 0x${addr_enable} (entry 0 enabled)"
