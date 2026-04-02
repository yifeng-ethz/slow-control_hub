create_clock -name i_clk -period 5.818 [get_ports {i_clk}]

set_false_path -from [remove_from_collection [all_inputs] [get_ports {i_clk}]]
set_false_path -to [all_outputs]
