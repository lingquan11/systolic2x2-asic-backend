# 物理流程：openroad 直接脚本流（参照 mac4 flow.tcl）。时钟10ns 为试跑假设，利用率45%（Lead指定）。
set P /home/hatch/workspace/aices-backend-setup/tools/pdk-root/sky130A
set LIBD $P/libs.ref/sky130_fd_sc_hd
set B /home/hatch/workspace/aices-backend-setup/work-systolic/work
set R /home/hatch/workspace/aices-backend-setup/work-systolic/work/or-flow
read_lef $LIBD/techlef/sky130_fd_sc_hd__max.tlef
read_lef $LIBD/lef/sky130_fd_sc_hd.lef
read_liberty $LIBD/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog $B/systolic2x2_sky130_netlist.v
link_design systolic2x2
read_sdc $B/systolic2x2.sdc
puts "== floorplan"
initialize_floorplan -utilization 45 -aspect_ratio 1 -core_space 5 -site unithd
make_tracks li1  -x_offset 0.23 -x_pitch 0.46 -y_offset 0.17 -y_pitch 0.34
make_tracks met1 -x_offset 0.17 -x_pitch 0.34 -y_offset 0.17 -y_pitch 0.34
make_tracks met2 -x_offset 0.23 -x_pitch 0.46 -y_offset 0.23 -y_pitch 0.46
make_tracks met3 -x_offset 0.34 -x_pitch 0.68 -y_offset 0.34 -y_pitch 0.68
make_tracks met4 -x_offset 0.46 -x_pitch 0.92 -y_offset 0.46 -y_pitch 0.92
make_tracks met5 -x_offset 1.70 -x_pitch 3.40 -y_offset 1.70 -y_pitch 3.40
place_pins -random -hor_layers met3 -ver_layers met2
tapcell -distance 14 -tapcell_master sky130_fd_sc_hd__tapvpwrvgnd_1
puts "== pdn"
add_global_connection -net VPWR -pin_pattern {^VPWR$} -power
add_global_connection -net VPWR -pin_pattern {^VPB$} -power
add_global_connection -net VGND -pin_pattern {^VGND$} -ground
add_global_connection -net VGND -pin_pattern {^VNB$} -ground
set_voltage_domain -name CORE -power VPWR -ground VGND
define_pdn_grid -name grid -starts_with POWER -voltage_domains CORE -pins {met4 met5}
add_pdn_stripe -layer met1 -width 0.48 -followpins
add_pdn_stripe -layer met4 -width 1.6 -pitch 27.14 -offset 13.57 -starts_with POWER
add_pdn_stripe -layer met5 -width 1.6 -pitch 27.2 -offset 13.6 -starts_with POWER
add_pdn_connect -layers {met1 met4}
add_pdn_connect -layers {met4 met5}
pdngen
puts "== place"
global_placement -density 0.5
estimate_parasitics -placement
repair_design
detailed_placement
check_placement
write_def $R/systolic2x2_place.def
puts "== cts"
set_propagated_clock [get_clocks clk]
clock_tree_synthesis -root_buf sky130_fd_sc_hd__clkbuf_16 -buf_list {sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_2}
detailed_placement
estimate_parasitics -placement
repair_timing -setup -hold
detailed_placement
check_placement
write_def $R/systolic2x2_cts.def
puts "== route"
set_global_routing_layer_adjustment met1-met5 0.3
set_routing_layers -signal met1-met5 -clock met1-met5
global_route -guide_file $R/systolic2x2.guide -congestion_iterations 30
detailed_route -output_drc $R/systolic2x2_route_drc.rpt -verbose 1
puts "== finish"
filler_placement {sky130_fd_sc_hd__fill_8 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1}
estimate_parasitics -global_routing
write_def $R/systolic2x2_final.def
write_verilog $R/systolic2x2_final.v
report_checks -path_delay max -digits 3 > $R/systolic2x2_postroute_setup.rpt
report_checks -path_delay min -digits 3 > $R/systolic2x2_postroute_hold.rpt
report_wns > $R/systolic2x2_postroute_summary.rpt
report_tns >> $R/systolic2x2_postroute_summary.rpt
report_worst_slack -max >> $R/systolic2x2_postroute_summary.rpt
report_worst_slack -min >> $R/systolic2x2_postroute_summary.rpt
report_design_area > $R/systolic2x2_area.rpt
report_cell_usage >> $R/systolic2x2_area.rpt
puts "FLOW_DONE"
exit
