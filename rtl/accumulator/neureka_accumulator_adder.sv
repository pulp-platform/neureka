/*
 * neureka_normquant_adder.sv
 *
 * Copyright (C) 2019-2021 ETH Zurich, University of Bologna and GreenWaves Technologies
 *
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

/*
 * Authors (RBE):  Gianna Paulin <pauling@iis.ee.ethz.ch>
 *                 Francesco Conti <f.conti@unibo.it>
 * Authors (NE16): Francesco Conti <francesco.conti@greenwaves-technologies.com>
 * Authors (NEUREKA): Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 */

import neureka_package::*;

module neureka_accumulator_adder #(
  parameter int unsigned NADD = neureka_package::NEUREKA_TP_OUT,
  parameter int unsigned ACC = neureka_package::NEUREKA_ACCUM_SIZE,
  parameter int unsigned QNT = 32,
  parameter int unsigned OUTPUT_REGISTER = 0
) (
  // global signals
  input  logic                              clk_i,
  input  logic                              rst_ni,
  input  logic                              test_mode_i,
  // local clear
  input  logic                              clear_i,
  input  logic          [NADD-1:0]          bypass_i,

  input  logic          [NADD-1:0]          enable_i,
  // normalization parameters
  input  logic signed   [NADD-1:0][ACC-1:0] accumulator_i,
  input  logic signed   [NADD-1:0][ACC-1:0] partial_sum_i,
  // accumulation
  output logic signed   [NADD-1:0][ACC-1:0] accumulator_o
  // control channel
);

  generate
    for(genvar ii=0; ii<NADD; ii++) begin : biased_data_gen
      assign accumulator_o[ii] = bypass_i[ii] ? partial_sum_i[ii] : enable_i[ii] ? (accumulator_i[ii] + partial_sum_i[ii]) : accumulator_i[ii];
    end
  endgenerate
endmodule
