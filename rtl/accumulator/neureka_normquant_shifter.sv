/*
 * neureka_normquant_shifter.sv
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

module neureka_normquant_shifter #(
  parameter int unsigned ACC = neureka_package::NEUREKA_ACCUM_SIZE,
  parameter int unsigned INT = 33,
  parameter int unsigned OUTPUT_REGISTER = 0
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  input  logic                           test_mode_i,
  input  logic                           clear_i,
  input  logic unsigned [INT-1:0]        data_i,
  input  logic unsigned [7:0]            shift_i,
  output logic signed   [ACC-1:0]        accumulator_o,
  input  neureka_package::ctrl_normquant_t  ctrl_i
);

  logic [INT-1:0] shifted;
  logic signed [INT-1:0] rounding;
  logic [ACC-1:0] accumulator, accumulator_d, accumulator_q;
  logic [5:0] right_shift;

  assign right_shift = shift_i;

  assign rounding = 1 <<< (right_shift-1);
  assign shifted = ~ctrl_i.use_shifting ? $signed(data_i) :
                                          $signed(data_i) >>> right_shift;

  logic [INT-2:0] sat_big_or_shifted;
  logic [INT-2:0] sat_big_nand_shifted;

  always_comb
  begin
    sat_big_or_shifted   =  shifted[INT-2:0];
    sat_big_nand_shifted = ~shifted[INT-2:0];
    if(ctrl_i.relu) begin
      if(ctrl_i.quant_mode == NEUREKA_MODE_8B) begin
        sat_big_or_shifted [7:0] = '0;
      end
      else if(ctrl_i.quant_mode == NEUREKA_MODE_16B) begin
        sat_big_or_shifted [15:0] = '0;
      end
      else if(ctrl_i.quant_mode == NEUREKA_MODE_32B) begin
        sat_big_or_shifted = '0;
      end
    end
    else begin
      if(ctrl_i.quant_mode == NEUREKA_MODE_8B) begin
        sat_big_or_shifted  [6:0] = '0;
        sat_big_nand_shifted[6:0] = '0;
      end
      else if(ctrl_i.quant_mode == NEUREKA_MODE_16B) begin
        sat_big_or_shifted  [14:0] = '0;
        sat_big_nand_shifted[14:0] = '0;
      end
      else if(ctrl_i.quant_mode == NEUREKA_MODE_32B) begin
        sat_big_or_shifted  [30:0] = '0;
        sat_big_nand_shifted[30:0] = '0;
      end
    end
  end

  always_comb
  begin

    accumulator = '0;
    if(ctrl_i.quant_mode == NEUREKA_MODE_8B) begin
      accumulator[7:0] = shifted[7:0];
    end
    else if(ctrl_i.quant_mode == NEUREKA_MODE_16B) begin
      accumulator[15:0] = shifted[15:0];
    end
    else if(ctrl_i.quant_mode == NEUREKA_MODE_32B) begin
      accumulator = shifted[ACC-1:0];
    end

    if(ctrl_i.use_shifting) begin
      if(ctrl_i.relu) begin
        if(shifted[INT-1])
          accumulator = '0; // neg or sat- with relu active
        else if(~shifted[INT-1] & (|(sat_big_or_shifted))) begin
          accumulator = '1; // sat+
        end
      end
      else begin
        if (shifted[INT-1] & (|(sat_big_nand_shifted))) begin
          accumulator = '0;
          if(ctrl_i.quant_mode == NEUREKA_MODE_8B) begin
            accumulator[7] = 1'b1; // sat-
          end
          else if(ctrl_i.quant_mode == NEUREKA_MODE_16B) begin
            accumulator[15] = 1'b1; // sat-
          end
          else if(ctrl_i.quant_mode == NEUREKA_MODE_32B) begin
            accumulator[31] = 1'b1; // sat-
          end
        end
        else if(~shifted[INT-1] & (|(sat_big_or_shifted))) begin
          accumulator = '1; // sat+
          if(ctrl_i.quant_mode == NEUREKA_MODE_32B) begin
            accumulator[31] = 1'b0; // sat+
          end
          else if(ctrl_i.quant_mode == NEUREKA_MODE_16B) begin
            accumulator[15] = 1'b0; // sat+
          end
          else if(ctrl_i.quant_mode == NEUREKA_MODE_8B) begin
            accumulator[7] = 1'b0; // sat+
          end
        end
      end
    end

  end

  if(OUTPUT_REGISTER) begin : output_register_gen

    always_comb begin 
      accumulator_d = accumulator_q; 
      if(clear_i) begin 
        accumulator_d = '0;
      end else if (ctrl_i.start) begin  
        accumulator_d = accumulator;
      end 
    end 

    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        accumulator_q <= '0;
      end
      else begin
        accumulator_q <= accumulator_d;
      end
    end

  end
  else begin : no_output_register_gen
    assign accumulator_q = accumulator;
  end

  assign accumulator_o = accumulator_q;

endmodule // neureka_normquant_shifter
