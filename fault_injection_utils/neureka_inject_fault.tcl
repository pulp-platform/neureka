# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

transcript quietly

# General Settings
set verbosity            2
set log_injections       1
# Easy way to generate a variable seed
# set seed                 [clock seconds]
# Default value
set seed                 12345
set print_statistics     1
set script_base_path [file join ${ROOT} fault_injection_sim scripts]
append script_base_path /
set use_netlist    0
set netlist_from_file    0

set inject_start_time 2250000
set inject_stop_time  2340000
set injection_clock "tb_neureka/i_dut/clk_i"
set injection_clock_trigger 0
set fault_period 10
set rand_initial_injection_phase 1
# max_num set to 0 means until stop_time
set max_num_fault_inject 2
set signal_fault_duration 1000
set register_fault_duration 0ns

# Flip settings
# set allow_multi_bit_upset $::env(MULTI_BIT_UPSET)
set use_bitwidth_as_weight 0
set check_core_output_modification 0
set check_core_next_state_modification 0
set reg_to_sig_ratio 1

# Netlists
set inject_register_netlist []
set inject_signals_netlist []
set inject_signals_netlist_from_file []
set output_netlist []
set next_state_netlist []
set assertion_disable_list []

set utils_base_path  [file join ${ROOT} fault_injection_utils]
source [file join $utils_base_path neureka_extract_nets.tcl]

# for {set idx 0} {$idx < 12} {incr idx} {
#     set inject_signals_netlist [list {*}$inject_signals_netlist {*}[get_all_core_nets $idx]]
#     set output_netlist [list {*}$output_netlist {*}[get_core_output_nets $idx]]
# }

# set inject_register_netlist [list {*}$inject_register_netlist {*}[get_neureka_registers]]
# set inject_signals_netlist [list {*}$inject_signals_netlist {*}[get_neureka_signals]]

# By default fault_injection_test_signals provides input buffer signal as candidates
set inject_register_netlist [list {*}$inject_register_netlist {*}[fault_injection_test_signals]]

source [file join $script_base_path inject_fault.tcl]
