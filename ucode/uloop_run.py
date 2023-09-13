#!/usr/bin/env python
#
# uloop_run.sv
# Francesco Conti <fconti@iis.ee.ethz.ch>
#
# Copyright (C) 2017-2019 ETH Zurich, University of Bologna
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# See LICENSE.sw.txt for details.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from __future__ import print_function
from uloop_common import *
import math

VERBOSE = True
FB = 5 # filter buffer size (FB*FB)
BS = 4 # block size
TP = 32

fs = 3
oh = 1
ow = 1
ih = (oh - 1) + fs
iw = (ow - 1) + fs
nof = 32
nif = 32
qa = 4
qw = 4

qa_max     = 4 #min(4,qa)

n_tiles_qa = 1
n_tiles_kin = nif/TP
n_tiles_kout = nof/TP


n_tiles_K_in = int(math.ceil(nif/TP))
n_tiles_K_out = int(math.ceil(nof/TP))
n_tiles_Hout = int(math.ceil(ih/FB))
n_tiles_Wout = int(math.ceil(iw/FB))
n_tiles_qa   = int(math.ceil(qa/BS))
n_xpatches = n_tiles_Hout * n_tiles_Wout # * n_tiles_qa

print("n_xpatches: ", n_xpatches)

loops_range = [
    n_tiles_qa,
    n_tiles_K_in,
    n_tiles_K_out,
    n_xpatches
]

if fs==3:
    stream_size_fs = TP*fs*qw

else:
    stream_size_fs = TP*fs*fs*qw

registers = [
    0,
    0,
    0,
    0,
    0,
    0,
    nif,
    nof,
    TP*FB*FB*4,
    TP*9,
    stream_size_fs, #TP*fs*qw, # or TP*fs*fs*qw
    TP*fs*fs*qw+2,
    32*(32+16),
    0
]

loops_ops,code,mnem = uloop_load("code.yml")
loops = uloop_get_loops(loops_ops, loops_range)

idx  = []
for j in range(NB_LOOPS):
    idx.append(0)
state = (0,0,0,idx)
busy = False
execute = True
uloop_print_idx(state, registers, compact=True)
nb_iter = 0
for i in range(0,1000000):
    new_registers = uloop_execute(state, code, registers)
    execute,end,busy,state = uloop_state_machine(loops, state, verbose=VERBOSE)
    if execute:
        registers = new_registers
    if not busy:
        nb_iter += 1
        uloop_print_idx(state, registers, compact=True)
    if end:
        break
print("nb_iter=%d" % (nb_iter+1))
