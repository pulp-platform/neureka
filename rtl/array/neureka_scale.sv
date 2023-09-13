/*
 * neureka_scale.sv
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

module neureka_scale #(
  parameter int unsigned INP_ACC  =  8, // input bitwidth
  parameter int unsigned OUT_ACC  = 16, // output bitwidth
  parameter int unsigned N_SHIFTS =  8  // number of mutliplexed shifts
) (
  // global signals
  input logic                    clk_i,
  input logic                    rst_ni,
  input logic                    test_mode_i,
  // local enable & clear
  // input  logic                enable_i,
  // input  logic                clear_i,
  // input data
  hwpe_stream_intf_stream.sink   data_i,
  // output data
  hwpe_stream_intf_stream.source data_o,
  // control channel
  input ctrl_scale_t             ctrl_i,
  output flags_scale_t           flags_o
);

  // ========================================================================
  // SIGNAL DECLARATIONS
  // ========================================================================

  logic [OUT_ACC-1:0] shifted_data  [N_SHIFTS-1:0];
  logic [OUT_ACC-1:0] unshifted_data;
  logic [OUT_ACC-1:0] shifted_data_out;
  logic signed [OUT_ACC-1:0] inverted_data_out;

  logic [INP_ACC-1:0] data;

  assign data = data_i.data;

  assign unshifted_data[INP_ACC-1:0] = data[INP_ACC-1:0];

  generate
    if (OUT_ACC-1 >= INP_ACC) begin
      assign unshifted_data[OUT_ACC-1:INP_ACC] = '0;
    end
  endgenerate

  // All other shifts
  always_comb
    begin
      // Assign data with shift index 0
      // assign shifted_data[0] = unshifted_data;

      for(int i=0; i<N_SHIFTS; i++)
        shifted_data[i] = unshifted_data << i;
    end

  assign shifted_data_out = shifted_data[ctrl_i.shift_sel];
  assign inverted_data_out = -shifted_data_out;
  assign data_o.data  = ctrl_i.invert ? inverted_data_out : shifted_data_out;

  assign data_i.ready = data_o.ready;
  assign data_o.valid = data_i.valid;
  assign data_o.strb  = data_i.strb;

  assign flags_o.shift_sel = ctrl_i.shift_sel;

endmodule // neureka_scale
