#
# Patch defparams.vh with proper NoC routing configuration for self-output layer
# This is a workaround for validate_noc not populating XPM_NMU routing in simulation-only flow
#

set defparams_file "noc_self_output_sim/noc_self_output_sim.gen/sources_1/common/nsln/defparams.vh"

puts "INFO: Patching defparams.vh with NoC routing configuration for self-output layer..."
puts "INFO: Reading $defparams_file..."

# Read the existing defparams.vh
set fp [open $defparams_file r]
set content [read $fp]
close $fp

# Normalize all NMU instance names to match the 128-bit NMU that is instantiated
# (the generated defparams may still carry "NOC_NMU512_INST" strings)
regsub -all {NOC_NMU512_INST} $content {NOC_NMU128_INST} content

# Configuration for routing to DDR MC at base address 0x0, size 2GB
# DestId = 0 (from design_1_wrapper_self_output.ncr)
# Base = 0x00000000
# Mask = 0x7FFFFFFF (2GB range)
set dest_id "00000000"
set addr_enable "00000001"
set base_addr "00000000"
set addr_mask "7FFFFFFF"

# Patch xpm_nmu_attn_read (Read Attention Output from DDR)
puts "INFO: Patching xpm_nmu_attn_read routing..."
regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_attn_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_ENABLE = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_attn_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_ENABLE = 'h${addr_enable};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_attn_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_DST0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_attn_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_DST0 = 'h${dest_id};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_attn_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MADDR0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_attn_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MADDR0 = 'h${base_addr};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_attn_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MASK0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_attn_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MASK0 = 'h${addr_mask};" \
    content

# Patch xpm_nmu_weight_read (Read W_self_output from DDR)
puts "INFO: Patching xpm_nmu_weight_read routing..."
regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_weight_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_ENABLE = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_weight_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_ENABLE = 'h${addr_enable};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_weight_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_DST0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_weight_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_DST0 = 'h${dest_id};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_weight_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MADDR0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_weight_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MADDR0 = 'h${base_addr};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_weight_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MASK0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_weight_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MASK0 = 'h${addr_mask};" \
    content

# Patch xpm_nmu_residual_read (Read Residual from DDR)
puts "INFO: Patching xpm_nmu_residual_read routing..."
regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_residual_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_ENABLE = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_residual_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_ENABLE = 'h${addr_enable};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_residual_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_DST0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_residual_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_DST0 = 'h${dest_id};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_residual_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MADDR0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_residual_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MADDR0 = 'h${base_addr};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_residual_read\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MASK0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_residual_read.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MASK0 = 'h${addr_mask};" \
    content

# Patch xpm_nmu_output_write (Write final output to DDR)
puts "INFO: Patching xpm_nmu_output_write routing..."
regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_output_write\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_ENABLE = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_output_write.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_ENABLE = 'h${addr_enable};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_output_write\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_DST0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_output_write.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_DST0 = 'h${dest_id};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_output_write\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MADDR0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_output_write.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MADDR0 = 'h${base_addr};" \
    content

regsub {defparam design_1_wrapper_self_output_i\.noc_self_output_top_inst\.xpm_nmu_output_write\.NOC1\.VNOC\.NOC_NMU[0-9]+_INST\.REG_ADDR_MASK0 = 'h00000000;} \
    $content \
    "defparam design_1_wrapper_self_output_i.noc_self_output_top_inst.xpm_nmu_output_write.NOC1.VNOC.NOC_NMU128_INST.REG_ADDR_MASK0 = 'h${addr_mask};" \
    content

# Write the patched content back
puts "INFO: Writing patched defparams.vh..."
set fp [open $defparams_file w]
puts -nonewline $fp $content
close $fp

puts "INFO: defparams.vh patched successfully for self-output layer!"
puts "INFO: Configuration applied:"
puts "       DestId = 0x${dest_id} (route to DDR MC Port0)"
puts "       Base Address = 0x${base_addr}"
puts "       Address Mask = 0x${addr_mask} (2GB range)"
puts "       Address Enable = 0x${addr_enable} (entry 0 enabled)"
puts "INFO: Patched 4 XPM_NMU instances:"
puts "       - xpm_nmu_attn_read"
puts "       - xpm_nmu_weight_read"
puts "       - xpm_nmu_residual_read"
puts "       - xpm_nmu_output_write"
