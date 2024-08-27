/*
 * neureka_binconv_column.sv
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

module neureka_binconv_pe #(
  parameter int unsigned COLUMN_SIZE      = NEUREKA_COLUMN_SIZE,         // number of BinConv blocks per column (default 9)
  parameter int unsigned BLOCK_SIZE       = NEUREKA_BLOCK_SIZE,          // number of Binconv per block
  parameter int unsigned BC_COLBLOCK_SIZE = COLUMN_SIZE*BLOCK_SIZE,      // total number of binconv per PE
  parameter int unsigned TP_IN            = NEUREKA_TP_IN                // number of input elements processed per cycle
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  // input activation stream + handshake
  hwpe_stream_intf_stream.sink   activation_i  [BC_COLBLOCK_SIZE-1:0],
  // input weight stream + handshake
  hwpe_stream_intf_stream.sink   weight_i      [COLUMN_SIZE-1:0],
  // output features + handshake
  hwpe_stream_intf_stream.source column_pres_o,
  hwpe_stream_intf_stream.source column_pres_depthwise_o[BLOCK_SIZE-1:0],
  // control channel
  input  ctrl_binconv_pe_t   ctrl_i,
  output flags_binconv_column_t  flags_o
);

  ///////////////////////////////////////////
  // Local Params, Interfaces, and Signals //
  ///////////////////////////////////////////

  localparam COLUMN_PRES_SIZE  = NEUREKA_QA_IN+NEUREKA_QA_16BIT+8+$clog2(COLUMN_SIZE);
  localparam CORE_PRES_SIZE = COLUMN_PRES_SIZE+$clog2(BLOCK_SIZE);

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( COLUMN_PRES_SIZE )
  `ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
  ) col_pres [BLOCK_SIZE-1:0] (
    .clk ( clk_i )
  );

  logic signed [CORE_PRES_SIZE-1:0]   binconv_core_pres, binconv_core_pres_d, binconv_core_pres_q;
  logic                               binconv_core_pres_valid, binconv_core_pres_valid_d, binconv_core_pres_valid_q;
  logic        [CORE_PRES_SIZE/8-1:0] binconv_core_pres_strb, binconv_core_pres_strb_d, binconv_core_pres_strb_q;

  logic signed [BLOCK_SIZE-1:0][COLUMN_PRES_SIZE-1:0] col_pres_data;

  logic depthwise_accumulator_active;

  assign depthwise_accumulator_active = ctrl_i.dw_accum;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 1 )
  `ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
  ) weight_transposed [BLOCK_SIZE*COLUMN_SIZE-1:0] (
    .clk ( clk_i )
  );

  ///////////////////
  // Block Modules //
  ///////////////////
  generate 
    for(genvar ii=0; ii<BLOCK_SIZE; ii++) begin : weight_transposed_block_gen
      for(genvar jj=0; jj<COLUMN_SIZE; jj++) begin : weight_transposed_column_gen
          localparam ii_jj = ii*COLUMN_SIZE+jj;
          assign weight_transposed[ii_jj].data  = weight_i[jj].data[ii];
          assign weight_transposed[ii_jj].valid = weight_i[jj].valid;
          assign weight_transposed[ii_jj].strb  = weight_i[jj].strb;
      end //weight_transposed_column_gen
    end //weight_transposed_block_gen
  endgenerate

  generate 
    for(genvar jj=0; jj<COLUMN_SIZE; jj++) begin : weight_ready_transposed_column_gen
      assign weight_i[jj].ready = weight_transposed[0].ready;
    end
  endgenerate


  generate
    for(genvar ii=0; ii<BLOCK_SIZE; ii++) begin : col_gen

      ctrl_binconv_col_t ctrl_col;

      localparam ii_rem_4 = ii % 4;

      always_comb
      begin
        ctrl_col = ctrl_i.ctrl_col;
        ctrl_col.scale_shift = ii/4; // used for 1x1
        ctrl_col.dw_weight_offset = ctrl_i.dw_weight_offset[ii] | depthwise_accumulator_active;
        ctrl_col.enable_block = ctrl_col.enable_block & ctrl_i.enable_col_pw[9*(ii_rem_4+1)-1:9*ii_rem_4] & {9{ctrl_i.enable_col[ii]}};
        ctrl_col.sign_and_magn_1x1 = ctrl_i.sign_and_magn_1x1[ii];
      end

      neureka_binconv_column #(
        .BLOCK_SIZE ( BLOCK_SIZE ),
        .COLUMN_SIZE(NEUREKA_COLUMN_SIZE),
        .TP_IN      ( TP_IN      ),
        .PIPELINE( 0 )
      ) i_col (
        .clk_i        ( clk_i                                                 ),
        .rst_ni       ( rst_ni                                                ),
        .test_mode_i  ( test_mode_i                                           ),
        .enable_i     ( ctrl_col.enable_block[0]                              ),
        .clear_i      ( clear_i                                               ),
        .activation_i ( activation_i [(ii+1)*COLUMN_SIZE-1:ii*COLUMN_SIZE]    ),
        .weight_i     ( weight_transposed[(ii+1)*COLUMN_SIZE-1:ii*COLUMN_SIZE]),
        .col_pres_o   ( col_pres [ii]                                         ),
        .ctrl_i       ( ctrl_col                                              ),
        .flags_o      (                                                       )
      );

      assign col_pres_data[ii] = ctrl_col.enable_block[0] ? col_pres[ii].data : '0;

      assign column_pres_depthwise_o[ii].data  = col_pres[ii].data;
      assign column_pres_depthwise_o[ii].valid = depthwise_accumulator_active ? col_pres[0].valid : 0; 
      assign column_pres_depthwise_o[ii].strb  = col_pres[ii].strb;

    end : col_gen
  endgenerate


  ///////////////////////////////////
  // Computation of Column Results //
  ///////////////////////////////////

  always_comb
  begin
    binconv_core_pres = '0;
    for(int i=0; i<BLOCK_SIZE; i++) begin
      binconv_core_pres += COLUMN_PRES_SIZE'(signed'(col_pres_data[i]));
    end
  end
  assign binconv_core_pres_valid = depthwise_accumulator_active ? 0 : col_pres[0].valid;
  assign binconv_core_pres_strb  = col_pres[0].strb;

  ////////////////////////
  // Output Assignments //
  ////////////////////////

  assign column_pres_o.valid = binconv_core_pres_valid_q;
  assign column_pres_o.strb  = binconv_core_pres_strb_q;
  assign column_pres_o.data  = enable_i ? binconv_core_pres_q : ctrl_i.padding_value[COLUMN_PRES_SIZE-1:0];

  generate
    for(genvar ii=0; ii<BLOCK_SIZE; ii++) begin : ready_prop_gen
      assign col_pres[ii].ready = column_pres_o.ready;
    end // ready_prop_gen
  endgenerate


  ///////////////
  // Registers //
  ///////////////

  // registers for column results
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      binconv_core_pres_q <= '0;
      binconv_core_pres_valid_q <= '0;
      binconv_core_pres_strb_q  <= '0;
    end else begin  
      binconv_core_pres_q <= binconv_core_pres_d;
      binconv_core_pres_valid_q <= binconv_core_pres_valid_d;
      binconv_core_pres_strb_q  <= binconv_core_pres_strb_d;
    end 
  end

  always_comb begin
    binconv_core_pres_valid_d = binconv_core_pres_valid_q;
    binconv_core_pres_strb_d  = binconv_core_pres_strb_q;
    binconv_core_pres_d = binconv_core_pres_q;
    if(clear_i) begin 
      binconv_core_pres_valid_d = '0;
      binconv_core_pres_strb_d  = '0;
      binconv_core_pres_d = '0;
    end else if(col_pres[0].ready) begin 
      binconv_core_pres_valid_d = binconv_core_pres_valid;
      binconv_core_pres_strb_d  = binconv_core_pres_strb;
      if(enable_i & col_pres[0].valid ) begin 
        binconv_core_pres_d = binconv_core_pres;
      end 
    end  
  end 

endmodule // neureka_binconv_pe
