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
HW_BUILD_DIR      ?= $(mkfile_path)/sim/build
ifneq (,$(wildcard /etc/iis.version))
	QUESTA ?= questa-2022.3
else
	QUESTA ?=
endif
BENDER ?= sim/bender
WAVES          ?= $(mkfile_path)/sim/wave.do

compile_script ?= compile.tcl
compile_flag   ?= -suppress 2583 -suppress 13314

WORK_PATH = $(HW_BUILD_DIR)
RESERVOIR_SIZE = 1024

# Useful Parameters
gui      ?= 0
P_STALL  ?= 0.0
USE_ECC  ?= 0

# Setup build object dirs
VSIM_INI=$(HW_BUILD_DIR)/modelsim.ini
VSIM_LIBS=$(HW_BUILD_DIR)/work

# Build implicit rules
$(HW_BUILD_DIR):
	mkdir -p $(HW_BUILD_DIR)

SHELL := /bin/bash

# Download bender
sim:
	mkdir -p sim

$(BENDER): sim
	curl --proto '=https'  \
	--tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- 0.24.0
	mv bender $(BENDER)

.PHONY: update-ips
update-ips: $(BENDER)
	git submodule update --init
	$(BENDER) update
	$(BENDER) script vsim        \
	--vlog-arg="$(compile_flag)" \
	--vcom-arg="-pedanticerrors" \
	-t rtl -t neureka_standalone \
	> sim/${compile_script}

.PHONY: generate-scripts
generate-scripts: $(BENDER)
	$(BENDER) script vsim        \
	--vlog-arg="$(compile_flag)" \
	--vcom-arg="-pedanticerrors" \
	-t rtl -t neureka_standalone \
	> sim/${compile_script}

# Hardware rules
.PHONY: hw-clean-all hw-opt hw-compile hw-lib hw-clean hw-all
hw-clean-all:
	rm -rf $(HW_BUILD_DIR)
	rm -rf .bender
	rm -rf $(compile_script)
	rm -rf sim/modelsim.ini
	rm -rf sim/*.log
	rm -rf sim/transcript
	rm -rf .cached_ipdb.json

hw-opt:
	cd sim; $(QUESTA) vopt +acc -o vopt_tb $(TESTBENCH) -floatparameters+$(TESTBENCH) -work $(HW_BUILD_DIR)/work

hw-compile:
	cd sim; $(QUESTA) vsim -c +incdir+$(UVM_HOME) -do 'quit -code [source $(compile_script)]'

hw-lib:
	@touch sim/modelsim.ini
	@mkdir -p $(HW_BUILD_DIR)
	@cd sim; $(QUESTA) vlib $(HW_BUILD_DIR)/work
	@cd sim; $(QUESTA) vmap work $(HW_BUILD_DIR)/work
	@chmod +w sim/modelsim.ini

hw-clean:
	rm -rf sim/transcript
	rm -rf sim/modelsim.ini

hw-all: hw-lib hw-compile hw-opt

# Software stuff... to be moved?
.PHONY: stimuli build-cleanup

FS ?= 1
ifeq ($(FS), 3)
  H_IN ?= 6
  W_IN ?= 6
else
  H_IN ?= 4
  W_IN ?= 4
endif
K_IN ?= 64
K_OUT ?= 32
DW ?= 0
ifeq ($(DW), 1)
  DW_ARG=--depthwise
  K_OUT=$(K_IN)
else
  DW_ARG=
endif
PADDING_TOP ?= 0
PADDING_RIGHT ?= 0
PADDING_BOTTOM ?= 0
PADDING_LEFT ?= 0
SYNTH_WEIGHTS ?= 0
ifeq ($(SYNTH_WEIGHTS), 1)
  SYNTH_WEIGHTS_ARG=--synthetic_weights
else
  SYNTH_WEIGHTS_ARG=
endif
SYNTH_INPUTS ?= 0
ifeq ($(SYNTH_INPUTS), 1)
  SYNTH_INPUTS_ARG=--synthetic_inputs
else
  SYNTH_INPUTS_ARG=
endif
NOPRINT ?= 0
ifeq ($(NOPRINT), 1)
  NOPRINT_FLAG=-DDISABLE_PRINTF
else
  NOPRINT_FLAG=
endif

# construct build directory
BUILD_DIR=build/ki$(K_IN)_ko$(K_OUT)_in$(H_IN).$(W_IN)_fs$(FS)_dw$(DW)_pad$(PADDING_TOP).$(PADDING_RIGHT).$(PADDING_BOTTOM).$(PADDING_LEFT)
MODEL_DIR=$(dir $(abspath model))/model

$(BUILD_DIR):
	mkdir -p $@
	ln -sfn $(VSIM_INI) $(BUILD_DIR)/
	ln -sfn $(VSIM_LIBS) $(BUILD_DIR)/
	ln -sfn $(mkfile_path)/waves $(BUILD_DIR)

STIMULI=$(BUILD_DIR)/app/gen
$(STIMULI): $(BUILD_DIR)
	cd $(BUILD_DIR) && \
	mkdir -p app && \
	ln -sfn $(MODEL_DIR)/app/src app/src && \
	ln -sfn $(MODEL_DIR)/app/inc app/inc && \
	python $(MODEL_DIR)/gen_toml.py --in_height=$(H_IN) --in_width=$(W_IN) --in_channel=$(K_IN) --out_channel=$(K_OUT) $(DW_ARG) \
	                                --kernel_height=$(FS) --kernel_width=$(FS) --stride_height=1 --stride_width=1 \
	                                --padding_top=$(PADDING_TOP) --padding_right=$(PADDING_RIGHT) --padding_bottom=$(PADDING_BOTTOM) --padding_left=$(PADDING_LEFT) \
									$(SYNTH_WEIGHTS_ARG) $(SYNTH_INPUTS_ARG) && \
	python $(MODEL_DIR)/deps/pulp-nnx/test/testgen.py test -t test -a neureka --headers -c conf.toml --skip-save --print-tensors > stimuli.log

stimuli: $(STIMULI) sw-clean

build-cleanup:
	rm -rf build/*

# copy-pasted from local model/app makefile
.PHONY: sw-all sw-clean sw-bin

ACCELERATOR = neureka

APPDIR := $(MODEL_DIR)/app
GENDIR := $(BUILD_DIR)/app/gen
LIBDIR := $(MODEL_DIR)/deps/pulp-nnx
ACC_DIR := $(LIBDIR)/$(ACCELERATOR)
SW_DIR ?= sw

## Test
INC_DIRS += $(APPDIR)/inc
APP_SRCS += $(wildcard $(APPDIR)/src/*.c)
SRC_DIRS += $(APPDIR)/src

## Library
INC_DIRS += $(LIBDIR)/inc $(LIBDIR)/util
APP_SRCS += $(LIBDIR)/src/pulp_nnx_$(ACCELERATOR).c $(wildcard $(LIBDIR)/util/*.c)
SRC_DIRS += $(LIBDIR)/src $(LIBDIR)/util

## Accelerator
INC_DIRS += $(ACC_DIR)/hal $(ACC_DIR)/gvsoc $(ACC_DIR)/bsp $(ACC_DIR)/bsp/testbench
APP_SRCS += $(wildcard $(ACC_DIR)/hal/*.c) $(wildcard $(ACC_DIR)/gvsoc/*.c) $(wildcard $(ACC_DIR)/bsp/testbench/*.c)
SRC_DIRS += $(ACC_DIR)/hal $(ACC_DIR)/gvsoc $(ACC_DIR)/bsp/testbench

## Generated (enumerate sources manually as wildcard is evaluated at the start)
INC_DIRS += $(GENDIR)/inc
APP_SRCS += $(GENDIR)/src/bias.c $(GENDIR)/src/input.c $(GENDIR)/src/output.c $(GENDIR)/src/scale.c $(GENDIR)/src/weight.c
SRC_DIRS += $(GENDIR)/src

INC_FLAGS += $(addprefix -I,$(INC_DIRS))

# Flags
ACCELERATOR_UPPERCASE := $(shell echo $(ACCELERATOR) | tr [:lower:] [:upper:])
APP_CFLAGS += -DNNX_ACCELERATOR=\"$(ACCELERATOR)\" -DNNX_$(ACCELERATOR_UPPERCASE) -DNNX_NEUREKA_TESTBENCH
# -DNEUREKA_WEIGHT_SOURCE_WMEM
APP_CFLAGS += $(INC_FLAGS)
APP_CFLAGS += $(NOPRINT_FLAG)

# RISC-V options
RISCV_PREFIX ?= riscv32-unknown-elf-
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
CC=$(RISCV_PREFIX)gcc
LD=$(RISCV_PREFIX)gcc
CC_OPTS=-march=rv32imc -D__riscv__ -O2 -g -Wextra -Wall -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function -Wundef -fdata-sections -ffunction-sections
LD_OPTS=-march=rv32imc -D__riscv__ -MMD -MP -nostartfiles -nostdlib -Wl,--gc-sections
DEPDIR := $(BUILD_DIR)/.deps
DEPFLAGS = -MT $@ -MMD -MP -MF $(DEPDIR)/$(notdir $*.d)

# Setup build object dirs
CRT=$(BUILD_DIR)/crt0.o
OBJ=$(patsubst %, $(BUILD_DIR)/%, $(notdir $(APP_SRCS:%.c=%.o)))
BIN=$(BUILD_DIR)/main.bin
STIM_INSTR=$(BUILD_DIR)/stim_instr.txt
STIM_DATA=$(BUILD_DIR)/stim_data.txt

# Build implicit rules
$(DEPDIR):
	@mkdir -p $@

$(STIM_INSTR) $(STIM_DATA): $(BIN)
	objcopy --srec-len 1 --output-target=srec $(BIN) $(BIN).s19
	$(SW_DIR)/parse_s19.pl $(BIN).s19 > $(BIN).txt
	python $(SW_DIR)/s19tomem.py $(BIN).txt $(STIM_INSTR) $(STIM_DATA)

$(BIN): $(CRT) $(OBJ) $(SW_DIR)/link.ld
	$(LD) $(LD_OPTS) -o $(BIN) $(CRT) $(OBJ) -T$(SW_DIR)/link.ld
	$(RISCV_OBJDUMP) -D $(BIN) > $(BIN).dump

$(CRT): $(BUILD_DIR) $(SW_DIR)/crt0.S
	$(CC) $(CC_OPTS) -c $(SW_DIR)/crt0.S -o $(CRT)

# Generic rule for compiling objects
$(BUILD_DIR)/%.o: | $(BUILD_DIR) $(DEPDIR)
	$(CC) $(CC_OPTS) $(DEPFLAGS) $(APP_CFLAGS) -c $(call find-src,$*) -o $@

# Function to find source file for each object file
find-src = $(firstword $(wildcard $(addsuffix /$*.c,$(SRC_DIRS))))

sw-all: $(STIM_INSTR) $(STIM_DATA)

sw-clean:
	rm -rf $(OBJ) $(CRT) $(BIN) $(STIM_DATA) $(STIM_INSTR)

# Simulation parameters
VSIM_DEPS=$(CRT)
VSIM_PARAMS=-gPROB_STALL=$(P_STALL)   \
	-gSTIM_INSTR=stim_instr.txt \
	-gSTIM_DATA=stim_data.txt \
	-gUSE_ECC=$(USE_ECC) \
        -suppress vsim-3009

# Run the simulation
run:
ifeq ($(gui), 0)
	cd $(BUILD_DIR);                       \
	$(QUESTA) vsim -c vopt_tb -do "run -a" \
	$(VSIM_PARAMS);                        \
	if grep -q 'errors happened' transcript; then exit 1; fi
else
	cd $(BUILD_DIR); $(QUESTA) vsim vopt_tb \
	-do "add log -r sim:/$(TESTBENCH)/*"    \
	$(VSIM_PARAMS)
endif
