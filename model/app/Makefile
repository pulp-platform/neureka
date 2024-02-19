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

.PHONY: sw-all sw-clean

ACCELERATOR ?= neureka

LIBDIR := $(abspath ../deps/pulp-nnx)
ACC_DIR := $(LIBDIR)/$(ACCELERATOR)
BUILD_DIR ?= build
SW_DIR ?= ../../sw

## Test
INC_DIRS += inc
APP_SRCS += $(wildcard src/*.c)
SRC_DIRS += src

## Library
INC_DIRS += $(LIBDIR)/inc $(LIBDIR)/util
APP_SRCS += $(LIBDIR)/src/pulp_nnx_$(ACCELERATOR).c $(wildcard $(LIBDIR)/util/*.c)
SRC_DIRS += $(LIBDIR)/src $(LIBDIR)/util

## Accelerator
INC_DIRS += $(ACC_DIR)/hal $(ACC_DIR)/gvsoc $(ACC_DIR)/bsp $(ACC_DIR)/bsp/testbench
APP_SRCS += $(wildcard $(ACC_DIR)/hal/*.c) $(wildcard $(ACC_DIR)/gvsoc/*.c) $(wildcard $(ACC_DIR)/bsp/testbench/*.c)
SRC_DIRS += $(ACC_DIR)/hal $(ACC_DIR)/gvsoc $(ACC_DIR)/bsp/testbench

## Generated 
INC_DIRS += gen/inc
APP_SRCS += $(wildcard gen/src/*.c)
SRC_DIRS += gen/src

INC_FLAGS += $(addprefix -I,$(INC_DIRS))

# Flags
ACCELERATOR_UPPERCASE := $(shell echo $(ACCELERATOR) | tr [:lower:] [:upper:])
APP_CFLAGS += -DNNX_ACCELERATOR=\"$(ACCELERATOR)\" -DNNX_$(ACCELERATOR_UPPERCASE) -DNNX_NEUREKA_TESTBENCH -DNNX_NEUREKA_PE_H=4 -DNNX_NEUREKA_PE_W=4
APP_CFLAGS += $(INC_FLAGS)

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
OBJ=$(patsubst %, build/%, $(notdir $(APP_SRCS:%.c=%.o)))
BIN=$(BUILD_DIR)/main.bin
STIM_INSTR=$(BUILD_DIR)/stim_instr.txt
STIM_DATA=$(BUILD_DIR)/stim_data.txt

# Build implicit rules
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

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
$(BUILD_DIR)/%.o: | $(BUILD_DIR)
	$(CC) $(CC_OPTS) $(DEPFLAGS) $(APP_CFLAGS) -c $(call find-src,$*) -o $@

# Function to find source file for each object file
find-src = $(firstword $(wildcard $(addsuffix /$*.c,$(SRC_DIRS))))

sw-all: $(STIM_INSTR) $(STIM_DATA)

sw-clean:
	rm -rf $(OBJ) $(CRT) $(BIN) $(STIM_DATA) $(STIM_INSTR)
