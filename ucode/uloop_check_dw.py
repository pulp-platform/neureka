#!/usr/bin/env python3
#
# uloop_check.sv
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

# high-level loop
def iterate_hl_loop(subtile_nb_k, subtile_nb_ho, subtile_nb_wo, h_size_out, w_size_out, infeat_hom_iter, infeat_wom_iter, infeat_km_iter, weights_km_iter, outfeat_hom_iter, outfeat_wom_iter, outfeat_km_iter, scale_km_iter):

    for k_major in range(subtile_nb_k):
        for i_major in range(subtile_nb_ho):
            for j_major in range(subtile_nb_wo):

                # auto base_addr_x = i_major*h_size_out*this->w_in_int*this->k_in + j_major*w_size_out*this->k_in + k_in_major*this->TP_IN;
                base_addr_x = i_major*infeat_hom_iter + j_major*infeat_wom_iter + k_major*infeat_km_iter

                # auto base_addr_W_3x3 = (k_out_major*this->TP_OUT*this->subtile_nb_ki*this->qw + k_in_major*this->qw) * this->FILTER_SIZE*this->FILTER_SIZE * 2;
                # auto base_addr_W_1x1 = (k_out_major*this->TP_OUT*this->subtile_nb_ki + k_in_major) * this->qw * 2;
                base_addr_W = k_major*weights_km_iter

                # auto base_addr_y = i_major*h_size_out*this->w_out_int*this->k_out + j_major*w_size_out*this->k_out + k_out_major*this->TP_OUT;
                base_addr_y = i_major*outfeat_hom_iter + j_major*outfeat_wom_iter + k_major*outfeat_km_iter

                base_addr_s = k_major*scale_km_iter

                yield base_addr_W, base_addr_x, base_addr_y, base_addr_s

VERBOSE = True


def uloop_check(
    subtile_nb_k,
    subtile_nb_ho,
    subtile_nb_wo,
    h_size_out,
    w_size_out,
    k,
    w_in_int,
    w_out_int,
    qw,
    fs=3,
    FILTER_SIZE=3,
    TP_IN=16,
    TP_OUT=16, # in depthwise mode, effective TP_OUT=16
    verbose=VERBOSE
):

    infeat_hom_iter = h_size_out * w_in_int * k
    infeat_wom_iter = w_size_out * k
    infeat_km_iter = TP_IN

    weights_km_iter = qw * FILTER_SIZE*FILTER_SIZE * 2

    outfeat_hom_iter = h_size_out * w_out_int * k
    outfeat_wom_iter = w_size_out * k
    outfeat_km_iter = TP_OUT

    scale_km_iter = TP_OUT>>2

    print("> Base iter\n\tsubtile_nb_k=%d\n\tsubtile_nb_ho=%d\n\tsubtile_nb_wo=%d\n\th_size_out=%d\n\tw_size_out=%d\n\tinfeat_hom_iter=%x\n\tinfeat_wom_iter=%x\n\tinfeat_km_iter=%x\n\tweights_km_iter=%x\n\toutfeat_hom_iter=%x\n\toutfeat_wom_iter=%x\n\toutfeat_km_iter=%x\n\tscale_km_iter=%x" % (subtile_nb_k, subtile_nb_ho, subtile_nb_wo, h_size_out, w_size_out, infeat_hom_iter, infeat_wom_iter, infeat_km_iter, weights_km_iter, outfeat_hom_iter, outfeat_wom_iter, outfeat_km_iter, scale_km_iter))
    weights_km_reset_iter  = - (subtile_nb_k-1)  * weights_km_iter
    infeat_km_reset_iter   = - (subtile_nb_k-1)  * infeat_km_iter
    infeat_wom_reset_iter  = - (subtile_nb_wo-1) * infeat_wom_iter
    outfeat_wom_reset_iter = - (subtile_nb_wo-1) * outfeat_wom_iter
    infeat_hom_reset_iter  = - (subtile_nb_ho-1) * infeat_hom_iter
    outfeat_hom_reset_iter = - (subtile_nb_ho-1) * outfeat_hom_iter
    outfeat_km_reset_iter  = - (subtile_nb_k-1)  * outfeat_km_iter
    print("> Reset iter\n\tweights_km_reset_iter=%x\n\tinfeat_km_reset_iter=%x\n\tinfeat_wom_reset_iter=%x\n\toutfeat_wom_reset_iter=%x\n\tinfeat_hom_reset_iter=%x\n\toutfeat_hom_reset_iter=%x\n\toutfeat_km_reset_iter=%x" % (weights_km_reset_iter, infeat_km_reset_iter, infeat_wom_reset_iter, outfeat_wom_reset_iter, infeat_hom_reset_iter, outfeat_hom_reset_iter, outfeat_km_reset_iter))

    registers = [
        0, # base_addr_W
        0, # base_addr_x
        0, # base_addr_y
        0, # base_addr_s
        weights_km_iter, # weights_kom_iter,
        weights_km_iter, # weights_kim_iter,
        weights_km_reset_iter, # weights_kom_reset_iter,
        weights_km_reset_iter, # weights_kim_reset_iter,
        infeat_km_iter, #infeat_kim_iter,
        infeat_wom_iter,
        infeat_hom_iter,
        infeat_km_reset_iter, # infeat_kim_reset_iter,
        infeat_wom_reset_iter,
        infeat_hom_reset_iter,
        outfeat_wom_iter,
        outfeat_hom_iter,
        outfeat_km_iter, # outfeat_kom_iter,
        outfeat_wom_reset_iter,
        outfeat_hom_reset_iter,
        outfeat_km_reset_iter, # outfeat_kom_reset_iter,
        scale_km_iter, # scale_kom_iter,
        0
    ]

    loops_ops,code,mnem = uloop_load("code_dw.yml")
    loops = uloop_get_loops(loops_ops, (subtile_nb_wo, subtile_nb_ho, subtile_nb_k, 1))

    err = 0
    idx  = []
    nb_loops=4
    for j in range(nb_loops):
        idx.append(0)
    state = (0,0,0,idx)
    busy = False
    execute = True
    # uloop_print_idx(state, registers)
    hidx = 0, 0, 0, 0
    hl_loop = iterate_hl_loop(subtile_nb_k, subtile_nb_ho, subtile_nb_wo, h_size_out, w_size_out, infeat_hom_iter, infeat_wom_iter, infeat_km_iter, weights_km_iter, outfeat_hom_iter, outfeat_wom_iter, outfeat_km_iter, scale_km_iter)
    hW, hX, hY, hS = next(hl_loop)
    for i in range(0,1000000):
        new_registers = uloop_execute(state, code, registers)
        execute,end,busy,state = uloop_state_machine(loops, state, verbose=verbose, nb_loops=nb_loops)
        if execute:
            registers = new_registers
        if not busy:
            try:
                hW, hX, hY, hS = next(hl_loop)
            except StopIteration:
                pass
            if verbose:
                uloop_print_idx(state, registers, register_names=('weights', 'infeat', 'outfeat', 'scale'))
            uW, uX, uY, uS = registers[0:4]
            if (hW != uW or hX != uX or hY != uY or hS != uS):
                if verbose:
                    print("  ERROR!!!")
                    print("  High-level: weights:%x infeat:%x outfeat:%x scale:%x" % (hW, hX, hY, hS))
                    print("  uLoop:      weights:%x infeat:%x outfeat:%x scale:%x" % (uW, uX, uY, uS))
                err += 1
        if end:
            break

    print(err, " errors", "!!!" if err > 0 else "")
    return err

uloop_check(
    2, # subtile_nb_k,
    1, # subtile_nb_ho,
    1, # subtile_nb_wo,
    3, # h_size_out,
    3, # w_size_out,
    32, # k,
    5, # w_in_int,
    3, # w_out_int,
    8, # qw,
    verbose = True
)
