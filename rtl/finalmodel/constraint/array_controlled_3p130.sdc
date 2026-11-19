# Controlled wrapper same TSMC65 setup, with FSM I/O instead of clear_tile.
create_clock -name core_clk -period 3.130 [get_ports clk]
set_input_delay 0.250 -clock core_clk [get_ports {mode_in* start stream_last A_left_flat* B_top_flat* A_left_valid* B_top_valid*}]
set_output_delay 0.250 -clock core_clk [all_outputs]
set_load 0.010 [all_outputs]
set_false_path -from [get_ports rst_n]
