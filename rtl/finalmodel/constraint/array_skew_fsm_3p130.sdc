# Skew FSM top. 16 A row words + 16 B column words per RUN cycle.
create_clock -name core_clk -period 3.130 [get_ports clk]
set_input_delay 0.250 -clock core_clk [get_ports {mode_in* start A_rows_flat* B_cols_flat*}]
set_output_delay 0.250 -clock core_clk [all_outputs]
set_load 0.010 [all_outputs]
set_false_path -from [get_ports rst_n]
