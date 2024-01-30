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

DATA_BASE  = 0x10000
STACK_BASE = 0x1e000

INSTR_MEM_SIZE = 32*1024
DATA_MEM_SIZE  = 256*1024

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
    addr = int(l[2:8], 16)
    wh = int(l[9:17], 16)
    wl = int(l[17:25], 16)
    if addr >= DATA_BASE and addr < STACK_BASE:
        data_mem [addr // 4]     = wl
        data_mem [addr // 4 + 1] = wh
    else:
        instr_mem[addr // 4]     = wl
        instr_mem[addr // 4 + 1] = wh

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