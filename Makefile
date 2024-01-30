# Copyright (C) 2022-2023 ETH Zurich and University of Bologna
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Yvan Tortorella (yvan.tortorella@unibo.it)
#         Francesco Conti (f.conti@unibo.it)
#

# valid alternatives are: tb_neureka
TESTBENCH ?= tb_neureka

# Paths to folders
mkfile_path    := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
BUILD_DIR      ?= $(mkfile_path)/sim/build
QUESTA         ?=
BENDER_DIR     ?= .
BENDER         ?= sim/bender
WAVES          ?= $(mkfile_path)/sim/wave.do

compile_script ?= compile.tcl
compile_flag   ?= -suppress 2583 -suppress 13314

WORK_PATH = $(BUILD_DIR)
RESERVOIR_SIZE = 1024

# Useful Parameters
gui      ?= 0
P_STALL_GEN  ?= 0.0
P_STALL_RECV ?= 0.0

# Setup build object dirs
VSIM_INI=$(BUILD_DIR)/modelsim.ini
VSIM_LIBS=$(BUILD_DIR)/work

# Build implicit rules
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

SHELL := /bin/bash

# Generate instructions and data stimuli
include sw/sw.mk

# Simulation parameters
VSIM_DEPS=$(CRT)
VSIM_PARAMS=-gPROB_STALL=$(P_STALL)   \
	-gSTIM_INSTR=build/stim_instr.txt \
	-gSTIM_DATA=build/stim_data.txt

# Run the simulation
run:
ifeq ($(gui), 0)
	cd sim;                                \
	$(QUESTA) vsim -c vopt_tb -do "run -a" \
	$(VSIM_PARAMS)	
else
	cd sim; $(QUESTA) vsim vopt_tb       \
	-do "add log -r sim:/$(TESTBENCH)/*" \
	$(VSIM_PARAMS)
endif

# Download bender
sim:
	mkdir -p sim

$(BENDER): sim
	curl --proto '=https'  \
	--tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- 0.24.0
	mv bender $(BENDER)

update-ips: $(BENDER)
	git submodule update --init
	$(BENDER) update
	$(BENDER) script vsim        \
	--vlog-arg="$(compile_flag)" \
	--vcom-arg="-pedanticerrors" \
	-t rtl -t test               \
	> sim/${compile_script}

build-hw: hw-all

# Hardware rules
hw-clean-all:
	rm -rf $(BUILD_DIR)
	rm -rf .bender
	rm -rf $(compile_script)
	rm -rf sim/modelsim.ini
	rm -rf sim/*.log
	rm -rf sim/transcript
	rm -rf .cached_ipdb.json

hw-opt:
	cd sim; $(QUESTA) vopt +acc=npr -o vopt_tb $(TESTBENCH) -floatparameters+$(TESTBENCH) -work $(BUILD_DIR)/work

hw-compile:
	cd sim; $(QUESTA) vsim -c +incdir+$(UVM_HOME) -do 'quit -code [source $(compile_script)]'

hw-lib:
	@touch sim/modelsim.ini
	@mkdir -p $(BUILD_DIR)
	@cd sim; $(QUESTA) vlib $(BUILD_DIR)/work
	@cd sim; $(QUESTA) vmap work $(BUILD_DIR)/work
	@chmod +w sim/modelsim.ini

hw-clean:
	rm -rf sim/transcript
	rm -rf sim/modelsim.ini

hw-all: hw-lib hw-compile hw-opt
