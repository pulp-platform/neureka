#
# Copyright (C) 2018-2019 ETH Zurich and University of Bologna
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

import numpy as np
import sys

# Instructions start at 0x1c00_0000
# Data starts at 0x1c01_0000
# Stack starts at 0x1c04_0000
# We only keep last 2 bytes so memory will be filled with no offset.
# The CPU will also reference it as to not have any offset.
MEM_START  = 0x1c000000
INSTR_SIZE = 0x8000
INSTR_END  = MEM_START + INSTR_SIZE
DATA_BASE  = MEM_START + 0x10000
DATA_SIZE  = 0x30000
DATA_END   = DATA_BASE + DATA_SIZE

INSTR_MEM_SIZE = 32*1024
DATA_MEM_SIZE  = 6*8192

with open(sys.argv[1], "r") as f:
    s = f.read()

if len(sys.argv) >= 4:
    instr_txt = sys.argv[2]
    data_txt  = sys.argv[3]
else:
    instr_txt = "stim_instr.txt"
    data_txt  = "stim_data.txt"

instr_mem = np.zeros(INSTR_MEM_SIZE, dtype='int')
data_mem  = np.zeros(DATA_MEM_SIZE,  dtype='int')

for l in s.split():
    addr = int(l[0:8], 16)
    wh = int(l[9:17], 16)
    wl = int(l[17:25], 16)
    rel_data_addr = addr - DATA_BASE
    rel_imem_addr = addr - MEM_START
    if addr >= DATA_BASE and addr < DATA_END:
        data_mem [int(rel_data_addr / 4)]     = wl
        data_mem [int(rel_data_addr / 4) + 1] = wh
    elif addr >= MEM_START and  addr < INSTR_END:
        instr_mem[int(rel_imem_addr / 4)]     = wl
        instr_mem[int(rel_imem_addr / 4) + 1] = wh

s = ""
for m in instr_mem:
    s += "%08x\n" % m
with open(instr_txt, "w") as f:
    f.write(s)

s = ""
for m in data_mem:
    s += "%08x\n" % m
with open(data_txt, "w") as f:
    f.write(s.rstrip('\n'))
