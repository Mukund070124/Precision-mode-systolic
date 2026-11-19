# Run directly: genus -files scripts/synth_array.tcl -log Reports/Array16x16_Synthesis.log
# For included controller: SYNTH_TOP=column_shared_tensor_unit_16x16 genus -files ...
set ROOT [file normalize [pwd]]
set TOP systolic_array_16x16
if {[info exists ::env(SYNTH_TOP)] && $::env(SYNTH_TOP) ne ""} {set TOP $::env(SYNTH_TOP)}
if {$TOP ni {systolic_array_16x16 column_shared_tensor_unit_16x16 column_shared_skew_fsm_16x16}} {error "Unsupported SYNTH_TOP: $TOP"}
if {![info exists ::env(TSMC_LIB_FILE)] || ![file isfile $::env(TSMC_LIB_FILE)]} {
    error {Set TSMC_LIB_FILE to readable TSMC 65nm NLDM .lib}
}
set LIB [file normalize $::env(TSMC_LIB_FILE)]
set PREFIX Array16x16
set SDC [file join $ROOT constraints array_3p130.sdc]
if {$TOP eq "column_shared_tensor_unit_16x16"} {
    set PREFIX Controlled16x16
    set SDC [file join $ROOT constraints array_controlled_3p130.sdc]
}
if {$TOP eq "column_shared_skew_fsm_16x16"} {
    set PREFIX SkewFSM16x16
    set SDC [file join $ROOT constraints array_skew_fsm_3p130.sdc]
}
file mkdir [file join $ROOT Reports]
file mkdir [file join $ROOT Netlist]
set_db init_lib_search_path [list [file dirname $LIB]]
set_db library [list $LIB]
set_db init_hdl_search_path [list [file join $ROOT rtl]]
set FILES [lsort [glob [file join $ROOT rtl *.v]]]
foreach f $FILES {if {![file isfile $f]} {error "Missing RTL: $f"}}
puts "COLUMN_SHARED_TOP: $TOP"
puts "COLUMN_SHARED_LIBRARY: $LIB"
read_hdl -language v2001 $FILES
elaborate $TOP
check_design -unresolved
read_sdc $SDC
puts {SYNTH_CLOCK_TARGET_NS: 3.130}
write_db -to_file [file join $ROOT Netlist ${TOP}_elab.db]
syn_generic
syn_map
syn_opt
report_area > [file join $ROOT Reports ${PREFIX}_Area.rpt]
report_gates > [file join $ROOT Reports ${PREFIX}_Gates.rpt]
report_timing > [file join $ROOT Reports ${PREFIX}_Timing.rpt]
report_power > [file join $ROOT Reports ${PREFIX}_Vectorless_Power.rpt]
write_hdl > [file join $ROOT Netlist ${TOP}_synth.v]
write_sdc > [file join $ROOT Netlist ${TOP}_synth.sdc]
write_db -to_file [file join $ROOT Netlist ${TOP}_mapped.db]
puts "COLUMN_SHARED_SYNTH_OK: $TOP"
exit
