# RVX imp 폴더의 set_ocd_env.tcl 을 이 묶음 안 상대경로로 옮긴 것입니다.
# 원본은 /opt/rvx 절대경로(set_path.tcl)를 읽어서 다른 PC 에서 못 씁니다.
foreach f {ervp_jtag_memorymap_offset ervp_platform_controller_memorymap_offset
           ervp_external_peri_group_memorymap_offset munoc_memorymap_offset} {
  source ./rvx_env/$f.tcl
}
source ./arch/memorymap_info.tcl
source ./arch/hw_info.tcl
source ./arch/ssw_info.tcl
foreach f {util jtag_function memory_function control_function mmio_function
           misc_api platform_controller_api flash_api noc_api dump_api} {
  source ./rvx_env/$f.tcl
}
print_platform_info
