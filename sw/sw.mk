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

RISCV_PREFIX ?= riscv32-unknown-elf-
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
CC=$(RISCV_PREFIX)gcc
LD=$(RISCV_PREFIX)gcc
CC_OPTS=-march=rv32imc -D__riscv__ -DK_IN=$(K_IN) -D K_OUT=$(K_OUT) -D H_OUT=$(H_OUT) -D W_OUT=$(W_OUT) -D FS=$(FS) -D QW=$(QW) \
-D RELU_BYPASS=$(RELU_BYPASS) -D RELU=$(RELU) -O2 -g -Wextra -Wall -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function -Wundef -fdata-sections -ffunction-sections -MMD -MP
LD_OPTS=-march=rv32imc -D__riscv__ -MMD -MP -nostartfiles -nostdlib -Wl,--gc-sections

# Setup build object dirs
CRT=$(BUILD_DIR)/crt0.o
OBJ=$(BUILD_DIR)/tb_fir.o
BIN=$(BUILD_DIR)/tb_fir
STIM_INSTR=$(BUILD_DIR)/stim_instr.txt
STIM_DATA=$(BUILD_DIR)/stim_data.txt

# Build implicit rules
$(STIM_INSTR) $(STIM_DATA): $(BIN)
	objcopy --srec-len 1 --output-target=srec $(BIN) $(BIN).s19
	sw/parse_s19.pl $(BIN).s19 > $(BIN).txt
	python sw/s19tomem.py $(BIN).txt $(STIM_INSTR) $(STIM_DATA)

$(BIN): $(CRT) $(OBJ) sw/link.ld
	$(LD) $(LD_OPTS) -o $(BIN) $(CRT) $(OBJ) -Tsw/link.ld
	$(RISCV_OBJDUMP) -D $(BIN) > $(BIN).dump

$(CRT): $(BUILD_DIR) sw/crt0.S
	$(CC) $(CC_OPTS) -c sw/crt0.S -o $(CRT)

$(OBJ): $(BUILD_DIR)
	$(CC) $(CC_OPTS) -c sw/tb_fir.c -I$(BUILD_DIR) -o $(OBJ)

sw-all: $(STIM_INSTR) $(STIM_DATA)

sw-clean:
	rm -rf $(OBJ) $(CRT) $(BIN) $(STIM_DATA) $(STIM_INSTR)
