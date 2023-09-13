/*
 * neureka_normquant_multiplier.sv
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

module neureka_normquant_multiplier #(
  parameter int unsigned NMS = neureka_package::NORM_MULT_SIZE,
  parameter int unsigned ACC = neureka_package::NEUREKA_ACCUM_SIZE,
  parameter int unsigned PIPE = 0
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,
  input  logic                      test_mode_i,
  input  logic                      clear_i,
  input  logic                      enable_i,
  input  logic signed [NMS:0]       norm_mult_signed_i,
  input  logic signed [ACC-1:0]     accumulator_i,
  output logic signed [NMS+ACC-1:0] product_o
);

  logic [NMS+ACC-1:0] product, product_d, product_q;
  assign product = norm_mult_signed_i * accumulator_i;

  generate

    if(PIPE == 1) begin : pipe_gen
      always_comb begin
        product_d = product_q;
        if(clear_i) begin
          product_d = '0;
        end else if (enable_i) begin 
          product_d = product;  
        end 
      end  
      always_ff@(posedge clk_i or negedge rst_ni)
      begin
        if(~rst_ni) begin
          product_q <= '0;
        end
        else begin
          product_q <= product_d;
        end
      end
      assign product_o = product_q;
    end
    else begin : no_pipe_gen
      assign product_o = product;
    end

  endgenerate

endmodule // neureka_normquant_multiplier
