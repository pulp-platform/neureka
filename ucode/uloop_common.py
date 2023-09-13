#!/usr/bin/env python
#
# uloop_common.sv
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
from bitstring import *
import yaml

try:
    from collections import OrderedDict
except ImportError:
    from ordereddict import OrderedDict

DEFAULT_NB_LOOPS  = 4
ULOOP_LEN = 352 # was 176

def yaml_ordered_load(stream, Loader=yaml.Loader, object_pairs_hook=OrderedDict):
    class OrderedLoader(Loader):
        pass
    def construct_mapping(loader, node):
        loader.flatten_mapping(node)
        return object_pairs_hook(loader.construct_pairs(node))
    OrderedLoader.add_constructor(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
        construct_mapping)
    return yaml.load(stream, OrderedLoader)

def uloop_state_machine(loops, curr_state, verbose=False, nb_loops=DEFAULT_NB_LOOPS):
    curr_addr, curr_loop, curr_op, curr_idx = curr_state
    next_addr = curr_addr
    next_loop = curr_loop
    next_op   = curr_op
    next_idx  = curr_idx
    end = False
    busy = False
    execute = False
    # if next operation is within the current loop, update address
    if curr_idx[curr_loop] < loops[curr_loop]['range'] - 1 and curr_op < loops[curr_loop]['nb_ops'] - 1:
        if verbose:
            print ("@%d %s UPDATE CURRENT LOOP %d                   " % (curr_addr, str(curr_state[3][::-1]), curr_loop))
        next_addr = curr_addr + 1
        next_op   = curr_op + 1
        busy = True
        execute = True
    # if there is a lower level loop, go to it
    elif curr_idx[curr_loop] < loops[curr_loop]['range'] - 1 and curr_loop > 0:
        if verbose:
            print ("@%d %s ITERATE CURRENT LOOP %d & GOTO LOOP 0" % (curr_addr, str(curr_state[3][::-1]), curr_loop))
        next_loop = 0
        for j in range(0,curr_loop):
            next_idx[j] = 0
        next_idx[curr_loop] = curr_idx[curr_loop] + 1
        next_addr = loops[0]['uloop_addr']
        next_op   = 0
        busy = False
        execute = True
    # if we are still within the current loop range, go back to start loop address
    elif curr_idx[curr_loop] < loops[curr_loop]['range'] - 1:
        if verbose:
            print ("@%d %s ITERATE CURRENT LOOP %d                  " % (curr_addr, str(curr_state[3][::-1]), curr_loop))
        next_addr = loops[curr_loop]['uloop_addr']
        next_op   = 0
        next_idx[curr_loop] = curr_idx[curr_loop] + 1
        busy = False
        execute = True
    # if not, go to next loop
    elif curr_loop < nb_loops-1:
        if verbose:
            print ("@%d %s GOTO NEXT LOOP %d                        " % (curr_addr, str(curr_state[3][::-1]), curr_loop+1))
        next_loop = curr_loop + 1
        next_addr = loops[curr_loop+1]['uloop_addr']
        next_op   = 0
        busy = True
        execute = False
    else:
        if verbose:
            print ("@%d %s TERMINATION                              " % (curr_addr, str(curr_state[3][::-1])))
        end = True
        next_loop = 0
        next_addr = 0
        next_op   = 0
        next_idx  = []
        for j in range(nb_loops):
            next_idx.append(0)
        busy = False
        execute = False
    next_state = next_addr, next_loop, next_op, next_idx
    return execute,end,busy,next_state

def uloop_execute(state, code, registers):
    addr, loop, op, idx = state
    new_registers = registers[:]
    try:
        if code[addr]['op_sel']:
            new_registers[code[addr]['a']] = registers[code[addr]['a']] + registers[code[addr]['b']]
        else:
            new_registers[code[addr]['a']] = registers[code[addr]['b']]
    except TypeError:
        import pdb; pdb.set_trace()
    return new_registers

def uloop_print_idx(state, registers, compact=False, register_names=None):
    if not compact and register_names is None:
        print ("r0:%x r1:%x r2:%x r3:%x" % (registers[0], registers[1], registers[2], registers[3]))
    elif not compact:
        print ("%s:%x %s:%x %s:%x %s:%x" % (register_names[0], registers[0], register_names[1], registers[1], register_names[2], registers[2], register_names[3], registers[3]))
    else:
        print ("%d,%d,%d,%d" % (registers[0], registers[1], registers[2], registers[3]))

def uloop_bytecode(code, loops_ops):
    bytecode = {}
    bytecode['code'] = BitArray()
    for c in code[::-1]:
        if c['op_sel'] == 1:
            b = BitArray(uint=1, length=1)
        else:
            b = BitArray(uint=0, length=1)
        a_b = BitArray(uint=c['a'], length=5)
        b_b = BitArray(uint=c['b'], length=5)
        b.append(a_b)
        b.append(b_b)
        bytecode['code'].append(b)
    if bytecode['code'].length < ULOOP_LEN:
        bytecode['code'].prepend(BitArray(uint=0, length=ULOOP_LEN-bytecode['code'].length))
    else:
        print("Error!!! ULOOP_LEN=%d is too small for bytecode of %d bits" % (ULOOP_LEN, bytecode['code'].length))
        return None
    bytecode['loops'] = BitArray()
    a = 0
    loops_addr = []
    for o in loops_ops:
        loops_addr.append(a)
        a += o
    for o,a in zip(loops_ops[::-1], loops_addr[::-1]):
        a_b = BitArray(uint=a, length=5)
        o_b = BitArray(uint=o, length=4)
        bytecode['loops'].append(a_b)
        bytecode['loops'].append(o_b)
    return bytecode

def uloop_load(name):
    with open(name) as f:
        code_p = yaml_ordered_load(f, yaml.SafeLoader)
    mnem_p = code_p['mnemonics']
    code_p = code_p['code']
    # code_p is a dictionary of loops
    code_l = []
    loops_ops = []
    for l in code_p:
        code_l.extend(code_p[l])
        loops_ops.append(len(code_p[l]))
    code = []
    for c in code_l:
        cn = {}
        if c['op'] == 'add':
            cn['op_sel'] = 1
        else:
            cn['op_sel'] = 0
        try:
            cn['a'] = mnem_p[c['a']]
        except KeyError:
            cn['a'] = c['a']
        try:
            cn['b'] = mnem_p[c['b']]
        except KeyError:
            cn['b'] = c['b']
        code.append(cn)
    return loops_ops,code,mnem_p

def uloop_get_loops(loops_ops, loops_range):
    loops = []
    a = 0
    for o,r in zip(loops_ops, loops_range):
        l = {}
        l['nb_ops']     = o
        l['range']      = r
        l['uloop_addr'] = a
        a += o
        loops.append(l)
    return loops

