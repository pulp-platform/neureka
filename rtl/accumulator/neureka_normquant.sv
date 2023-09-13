/*
 * neureka_normquant.sv
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

module neureka_normquant #(
  parameter int unsigned NMULT = 4,
  parameter int unsigned NMS = neureka_package::NORM_MULT_SIZE,
  parameter int unsigned ACC = neureka_package::NEUREKA_ACCUM_SIZE,
  parameter int unsigned INT = 48,
  parameter int unsigned QNT = 32,
  parameter int unsigned PIPE = 1,
  parameter int unsigned OUTPUT_REGISTER = 0
) (
  // global signals
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          test_mode_i,
  // local clear
  input  logic                          clear_i,
  // normalization parameters
  input  logic unsigned [NMULT*NMS-1:0] norm_mult_i,
  input  logic unsigned [NMULT*8-1:0]   shift_i,
  // accumulation
  input  logic signed   [NMULT*ACC-1:0] accumulator_i,
  output logic signed   [NMULT*ACC-1:0] accumulator_o,
  // control channel
  input  neureka_package::ctrl_normquant_t  ctrl_i,
  output neureka_package::flags_normquant_t [NMULT-1:0] flags_o
);

  logic signed [NMULT-1  :0][NMS+ACC-1:0]  product;
  logic signed [NMULT-1  :0][INT-1:0]  product_48b;
  logic signed [NMULT-1  :0][INT-1:0] product_8b;
  logic signed [NMULT/2-1:0][INT-1:0] product_16b;
  logic signed              [INT-1:0] product_32b;
  logic signed [NMULT-1  :0][INT-1:0] product_to_shift;
  logic signed [NMULT-1  :0][INT-1:0] rounding;

  generate
    for(genvar ii=0; ii<NMULT; ii++) begin : mult_gen

      localparam ii_div2 = ii / 2;

      logic sign_bit;
      logic signed [NMS:0]   norm_mult_signed;
      logic        [ACC-1:0] accumulator_selected;

      assign accumulator_selected = (ctrl_i.norm_mode == NEUREKA_MODE_8B)  ? accumulator_i [(ii+1)*32-1:ii*32] :
                                    (ctrl_i.norm_mode == NEUREKA_MODE_16B) ? accumulator_i [(ii_div2+1)*32-1:ii_div2*32] :
                                    (ctrl_i.norm_mode == NEUREKA_MODE_32B) ? accumulator_i [32-1:0] : '0;

      assign sign_bit = norm_mult_i[NMULT*NMS-1]; // sign is used only in WEIGHTOFFS

      assign norm_mult_signed = {ctrl_i.norm_signed & sign_bit, norm_mult_i[(ii+1)*NMS-1:ii*NMS]};
      neureka_normquant_multiplier #(
        .NMS  ( NMS  ),
        .ACC  ( ACC  ),
        .PIPE ( PIPE )
      ) i_multiplier (
        .clk_i              ( clk_i                ),
        .rst_ni             ( rst_ni               ),
        .test_mode_i        ( test_mode_i          ),
        .clear_i            ( clear_i              ),
        .enable_i           ( 1'b1                 ),
        .norm_mult_signed_i ( norm_mult_signed     ),
        .accumulator_i      ( accumulator_selected ),
        .product_o          ( product [ii]         )
      );
    end

    // FIXME hardwired params
    assign product_48b[0] = $signed(product[0]);
    assign product_48b[1] = $signed(product[1]);
    assign product_48b[2] = $signed(product[2]);
    assign product_48b[3] = $signed(product[3]);
    assign product_32b    = $signed(product_48b[0] + (product_48b[1] <<< 8) + (product_48b[2] <<< 16) + (product_48b[3] <<< 24));
    assign product_16b[0] = $signed(product[0] + (product[1] <<< 8));
    assign product_16b[1] = $signed(product[2] + (product[3] <<< 8));
    assign product_8b[0]  = $signed(product[0]);
    assign product_8b[1]  = $signed(product[1]);
    assign product_8b[2]  = $signed(product[2]);
    assign product_8b[3]  = $signed(product[3]);
    assign product_to_shift = (ctrl_i.norm_mode == NEUREKA_MODE_8B)  ? product_8b :
                              (ctrl_i.norm_mode == NEUREKA_MODE_16B) ? { 48'b0, 48'b0, product_16b } :
                              (ctrl_i.norm_mode == NEUREKA_MODE_32B) ? { 48'b0, 48'b0, 48'b0, product_32b } : '0;

    for(genvar ii=0; ii<NMULT; ii++) begin : shift_sat_gen

      logic [31:0] accumulator_loc;
      neureka_normquant_shifter #(
        .ACC             ( ACC             ),
        .INT             ( INT             ),
        .OUTPUT_REGISTER ( OUTPUT_REGISTER )
      ) i_shifter (
        .clk_i         ( clk_i                    ),
        .rst_ni        ( rst_ni                   ),
        .test_mode_i   ( test_mode_i              ),
        .clear_i       ( clear_i                  ),
        .data_i        ( product_to_shift[ii]     ),
        .shift_i       ( shift_i[(ii+1)*8-1:ii*8] ),
        .accumulator_o ( accumulator_loc          ),
        .ctrl_i        ( ctrl_i                   )
      );
      assign accumulator_o[(ii+1)*32-1:ii*32] = accumulator_loc;

    end
  endgenerate

endmodule // neureka_normquant
