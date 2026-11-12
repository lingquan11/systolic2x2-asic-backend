# 试跑假设（非设计规格，沿用mac4试跑）：时钟周期10ns、理想时钟，输入/输出延迟各1ns，无负载、无线负载模型
create_clock -name clk -period 10.0 [get_ports clk]
set_input_delay  1.0 -clock clk [get_ports {rst_n in_valid a0* a1* b0* b1*}]
set_output_delay 1.0 -clock clk [all_outputs]
