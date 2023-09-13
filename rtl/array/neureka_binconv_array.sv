/*
 * neureka_binconv_array.sv
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

module neureka_binconv_array #(
  parameter int unsigned COLUMN_SIZE          = NEUREKA_COLUMN_SIZE, // number of BinConv blocks per column (default 9)
  parameter int unsigned NR_PE                = NEUREKA_NUM_PE,      // number of BinConv columns (default 9 -- same of size of BinConv columns!)
  parameter int unsigned BLOCK_SIZE           = NEUREKA_BLOCK_SIZE,  // number of SoP's per BinConv block (default 4)
  parameter int unsigned SPATIAL_H            = NEUREKA_PE_H,
  parameter int unsigned SPATIAL_W            = NEUREKA_PE_W,
  parameter int unsigned INPUT_BUFFER_SIZE_H  = NEUREKA_INFEAT_BUFFER_SIZE_H,
  parameter int unsigned INPUT_BUFFER_SIZE_W  = NEUREKA_INFEAT_BUFFER_SIZE_W,
  parameter int unsigned NR_ACTIVATIONS       = 2048,              // 64 * BLOCK_SIZE
  parameter int unsigned TP_IN                = NEUREKA_TP_IN     // number of input elements processed per cycle
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  // input activation stream + handshake
  hwpe_stream_intf_stream.sink   activation_i  [NR_ACTIVATIONS-1:0],
  // input weight stream + handshake
  hwpe_stream_intf_stream.sink   weight_conv_i   [COLUMN_SIZE-1:0],

  // output features + handshake
  hwpe_stream_intf_stream.source pres_o        [NR_PE    -1:0],
  hwpe_stream_intf_stream.source pres_depthwise_o[NR_PE    *BLOCK_SIZE-1:0],
  // control channel
  input  ctrl_binconv_array_t    ctrl_i,
  output flags_binconv_array_t   flags_o
);


  ///////////////////////////////////////////
  // Local Params, Interfaces, and Signals //
  ///////////////////////////////////////////

  localparam COLUMN_PRES_SIZE  = NEUREKA_QA_IN+NEUREKA_QA_16BIT+8+$clog2(COLUMN_SIZE);
  localparam BLOCK_PRES_SIZE   = COLUMN_PRES_SIZE+$clog2(BLOCK_SIZE);


  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( COLUMN_PRES_SIZE )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres_depthwise [BLOCK_SIZE*NR_PE    -1:0] (
    .clk ( clk_i )
  );

  logic [NR_ACTIVATIONS-1:0][NEUREKA_QA_IN-1  :0] activation_data;
  logic [NR_ACTIVATIONS-1:0]                   activation_valid;
  logic [NR_ACTIVATIONS-1:0][NEUREKA_QA_IN/8-1:0] activation_strb;

  logic [NR_PE    -1:0][COLUMN_SIZE-1:0][BLOCK_SIZE-1:0][NEUREKA_QA_IN-1  :0] activation_mapped_fs1_data;
  logic [NR_PE    -1:0][COLUMN_SIZE-1:0][BLOCK_SIZE-1:0]                   activation_mapped_fs1_valid;
  logic [NR_PE    -1:0][COLUMN_SIZE-1:0][BLOCK_SIZE-1:0][NEUREKA_QA_IN/8-1:0] activation_mapped_fs1_strb;

  logic [NR_PE    -1:0][COLUMN_SIZE-1:0][BLOCK_SIZE-1:0][NEUREKA_QA_IN-1  :0] activation_mapped_fs3_data;
  logic [NR_PE    -1:0][COLUMN_SIZE-1:0][BLOCK_SIZE-1:0]                   activation_mapped_fs3_valid;
  logic [NR_PE    -1:0][COLUMN_SIZE-1:0][BLOCK_SIZE-1:0][NEUREKA_QA_IN/8-1:0] activation_mapped_fs3_strb;

  // block-level counter, moved here to be shared!
  logic block_cnt_en, block_clear;
  logic [$clog2(NEUREKA_QA_IN):0] block_cnt_q, block_cnt_d;

  // depthwise counter
  logic depthwise_cnt_en;
  logic [$clog2(NEUREKA_TP_IN):0] depthwise_cnt_q, depthwise_cnt_d;
  logic [NEUREKA_TP_IN:0] depthwise_cnt_oh_q, depthwise_cnt_oh_d;

  logic block_invalidate_d, block_invalidate_q;

  // interfaces
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) activation_mapped [NR_PE    *COLUMN_SIZE*BLOCK_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH       ( TP_IN )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) weight_int [NR_PE    *COLUMN_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( BLOCK_PRES_SIZE )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres_int [NR_PE    -1:0] (
    .clk ( clk_i )
  );

  logic [COLUMN_SIZE*NEUREKA_TP_IN-1:0] weight_mux, weight_temp;
  logic [COLUMN_SIZE-1:0][NEUREKA_TP_IN-1:0] weight_conv_mux;

  for(genvar ii=0; ii<COLUMN_SIZE; ii++) begin : weight_mux_assign_gen
    assign weight_temp[(ii+1)*NEUREKA_TP_IN-1:ii*NEUREKA_TP_IN] = weight_conv_i[ii].data;
  end

  for(genvar ii=0; ii<COLUMN_SIZE; ii++) begin : weight_mux_col_gen
    for(genvar jj=0; jj<NEUREKA_TP_IN; jj++) begin : weight_mux_block_gen
      localparam ii_rem8 = (ii%8);
      assign weight_mux[ii*NEUREKA_TP_IN+jj] = weight_temp[8*jj + ii_rem8];
    end
    assign weight_conv_mux[ii] = (ctrl_i.filter_mode == NEUREKA_FILTER_MODE_1X1) ? weight_mux[(ii+1)*NEUREKA_TP_IN-1:ii*NEUREKA_TP_IN] : weight_conv_i[ii].data;
  end

  //////////////////////////////////////
  // Column, Row and Block generation //
  //////////////////////////////////////

  for (genvar ii=0; ii<BLOCK_SIZE*NR_PE    ; ii++) begin
    assign pres_depthwise_o[ii].data  = pres_depthwise[ii].data;
    assign pres_depthwise_o[ii].valid = pres_depthwise[0].valid;
    assign pres_depthwise[ii].ready   = pres_depthwise_o[ii].ready; 
  end 

  // weight ready assignment
  for (genvar jj=0; jj<COLUMN_SIZE; jj++) begin : weight_conv_ready_gen
    assign weight_conv_i[jj].ready = weight_int[jj].ready & ~ctrl_i.weight_offset;
  end

  generate
    // activation extraction from interface
    for(genvar jj=0; jj<NR_ACTIVATIONS; jj++) begin : activation_assignment_gen
      assign activation_data[jj]    = activation_i[jj].data;
      assign activation_valid[jj]   = activation_i[jj].valid;
      assign activation_strb[jj]    = activation_i[jj].strb;
      assign activation_i[jj].ready = activation_mapped[0].ready;
    end

    
    for(genvar ii=0; ii<NR_PE    ; ii++) begin : column_gen

      for (genvar jj=0; jj<COLUMN_SIZE; jj++) begin : row_w_gen
        localparam ii_jj = ii*COLUMN_SIZE+jj;
        assign weight_int[ii_jj].data  = weight_conv_mux[jj];// all the column sees the same weight thus, it is only a function of jj in the RHS
        assign weight_int[ii_jj].strb  = weight_conv_i[jj].strb;
        assign weight_int[ii_jj].valid = weight_conv_i[jj].valid;
      end // row_w_gen



// INFEAT LAYOUT 3x3 MODE Column0 ---> HWC layout
//   PE0   PE1   PE2   PE3   PE4   PE5   PE6   PE7   PE8   PE9  PE10  PE11  PE12   PE13  PE14  PE15  PE16  PE17  PE18  PE19  PE20  PE21  PE22  PE23  PE24  PE25  PE26  PE27  PE28  PE29  PE30  PE31  PE32  PE33  PE34  PE35
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,0|0,1,0|0,2,0|0,3,0|0,4,0|0,5,0|1,0,0|1,1,0|1,2,0|1,3,0|1,4,0|1,5,0|2,0,0|2,1,0|2,2,0|2,3,0|2,4,0|2,5,0|3,0,0|3,1,0|3,2,0|3,3,0|3,4,0|3,5,0|4,0,0|4,1,0|4,2,0|4,3,0|4,4,0|4,5,0|5,0,0|5,1,0|5,2,0|5,3,0|5,4,0|5,5,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,1,0|0,2,0|0,3,0|0,4,0|0,5,0|0,6,0|1,1,0|1,2,0|1,3,0|1,4,0|1,5,0|1,6,0|2,1,0|2,2,0|2,3,0|2,4,0|2,5,0|2,6,0|3,1,0|3,2,0|3,3,0|3,4,0|3,5,0|3,6,0|4,1,0|4,2,0|4,3,0|4,4,0|4,5,0|4,6,0|5,1,0|5,2,0|5,3,0|5,4,0|5,5,0|5,6,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,2,0|0,3,0|0,4,0|0,5,0|0,6,0|0,7,0|1,2,0|1,3,0|1,4,0|1,5,0|1,6,0|1,7,0|2,2,0|2,3,0|2,4,0|2,5,0|2,6,0|2,7,0|3,2,0|3,3,0|3,4,0|3,5,0|3,6,0|3,7,0|4,2,0|4,3,0|4,4,0|4,5,0|4,6,0|4,7,0|5,2,0|5,3,0|5,4,0|5,5,0|5,6,0|5,7,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |1,0,0|1,1,0|1,2,0|1,3,0|1,4,0|1,5,0|2,0,0|2,1,0|2,2,0|2,3,0|2,4,0|2,5,0|3,0,0|3,1,0|3,2,0|3,3,0|3,4,0|3,5,0|4,0,0|4,1,0|4,2,0|4,3,0|4,4,0|4,5,0|5,0,0|5,1,0|5,2,0|5,3,0|5,4,0|5,5,0|6,0,0|6,1,0|6,2,0|6,3,0|6,4,0|6,5,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |1,1,0|1,2,0|1,3,0|1,4,0|1,5,0|1,6,0|2,1,0|2,2,0|2,3,0|2,4,0|2,5,0|2,6,0|3,1,0|3,2,0|3,3,0|3,4,0|3,5,0|3,6,0|4,1,0|4,2,0|4,3,0|4,4,0|4,5,0|4,6,0|5,1,0|5,2,0|5,3,0|5,4,0|5,5,0|5,6,0|6,1,0|6,2,0|6,3,0|6,4,0|6,5,0|6,6,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |1,2,0|1,3,0|1,4,0|1,5,0|1,6,0|1,7,0|2,2,0|2,3,0|2,4,0|2,5,0|2,6,0|2,7,0|3,2,0|3,3,0|3,4,0|3,5,0|3,6,0|3,7,0|4,2,0|4,3,0|4,4,0|4,5,0|4,6,0|4,7,0|5,2,0|5,3,0|5,4,0|5,5,0|5,6,0|5,7,0|6,2,0|6,3,0|6,4,0|6,5,0|6,6,0|6,7,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |2,0,0|2,1,0|2,2,0|2,3,0|2,4,0|2,5,0|3,0,0|3,1,0|3,2,0|3,3,0|3,4,0|3,5,0|4,0,0|4,1,0|4,2,0|4,3,0|4,4,0|4,5,0|5,0,0|5,1,0|5,2,0|5,3,0|5,4,0|5,5,0|6,0,0|6,1,0|6,2,0|6,3,0|6,4,0|6,5,0|7,0,0|7,1,0|7,2,0|7,3,0|7,4,0|7,5,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |2,1,0|2,2,0|2,3,0|2,4,0|2,5,0|2,6,0|3,1,0|3,2,0|3,3,0|3,4,0|3,5,0|3,6,0|4,1,0|4,2,0|4,3,0|4,4,0|4,5,0|4,6,0|5,1,0|5,2,0|5,3,0|5,4,0|5,5,0|5,6,0|6,1,0|6,2,0|6,3,0|6,4,0|6,5,0|6,6,0|7,1,0|7,2,0|7,3,0|7,4,0|7,5,0|7,6,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |2,2,0|2,3,0|2,4,0|2,5,0|2,6,0|2,7,0|3,2,0|3,3,0|3,4,0|3,5,0|3,6,0|3,7,0|4,2,0|4,3,0|4,4,0|4,5,0|4,6,0|4,7,0|5,2,0|5,3,0|5,4,0|5,5,0|5,6,0|5,7,0|6,2,0|6,3,0|6,4,0|6,5,0|6,6,0|6,7,0|7,2,0|7,3,0|7,4,0|7,5,0|7,6,0|7,7,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+

// INFEAT LAYOUT 3x3 MODE Column1 ---> HWC layout
//   PE0   PE1   PE2   PE3   PE4   PE5   PE6   PE7   PE8   PE9  PE10  PE11  PE12   PE13  PE14  PE15  PE16  PE17  PE18  PE19  PE20  PE21  PE22  PE23  PE24  PE25  PE26  PE27  PE28  PE29  PE30  PE31  PE32  PE33  PE34  PE35
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,1|0,1,1|0,2,1|0,3,1|0,4,1|0,5,1|1,0,1|1,1,1|1,2,1|1,3,1|1,4,1|1,5,1|2,0,1|2,1,1|2,2,1|2,3,1|2,4,1|2,5,1|3,0,1|3,1,1|3,2,1|3,3,1|3,4,1|3,5,1|4,0,1|4,1,1|4,2,1|4,3,1|4,4,1|4,5,1|5,0,1|5,1,1|5,2,1|5,3,1|5,4,1|5,5,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,1,1|0,2,1|0,3,1|0,4,1|0,5,1|0,6,1|1,1,1|1,2,1|1,3,1|1,4,1|1,5,1|1,6,1|2,1,1|2,2,1|2,3,1|2,4,1|2,5,1|2,6,1|3,1,1|3,2,1|3,3,1|3,4,1|3,5,1|3,6,1|4,1,1|4,2,1|4,3,1|4,4,1|4,5,1|4,6,1|5,1,1|5,2,1|5,3,1|5,4,1|5,5,1|5,6,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,2,1|0,3,1|0,4,1|0,5,1|0,6,1|0,7,1|1,2,1|1,3,1|1,4,1|1,5,1|1,6,1|1,7,1|2,2,1|2,3,1|2,4,1|2,5,1|2,6,1|2,7,1|3,2,1|3,3,1|3,4,1|3,5,1|3,6,1|3,7,1|4,2,1|4,3,1|4,4,1|4,5,1|4,6,1|4,7,1|5,2,1|5,3,1|5,4,1|5,5,1|5,6,1|5,7,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |1,0,1|1,1,1|1,2,1|1,3,1|1,4,1|1,5,1|2,0,1|2,1,1|2,2,1|2,3,1|2,4,1|2,5,1|3,0,1|3,1,1|3,2,1|3,3,1|3,4,1|3,5,1|4,0,1|4,1,1|4,2,1|4,3,1|4,4,1|4,5,1|5,0,1|5,1,1|5,2,1|5,3,1|5,4,1|5,5,1|6,0,1|6,1,1|6,2,1|6,3,1|6,4,1|6,5,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |1,1,1|1,2,1|1,3,1|1,4,1|1,5,1|1,6,1|2,1,1|2,2,1|2,3,1|2,4,1|2,5,1|2,6,1|3,1,1|3,2,1|3,3,1|3,4,1|3,5,1|3,6,1|4,1,1|4,2,1|4,3,1|4,4,1|4,5,1|4,6,1|5,1,1|5,2,1|5,3,1|5,4,1|5,5,1|5,6,1|6,1,1|6,2,1|6,3,1|6,4,1|6,5,1|6,6,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |1,2,1|1,3,1|1,4,1|1,5,1|1,6,1|1,7,1|2,2,1|2,3,1|2,4,1|2,5,1|2,6,1|2,7,1|3,2,1|3,3,1|3,4,1|3,5,1|3,6,1|3,7,1|4,2,1|4,3,1|4,4,1|4,5,1|4,6,1|4,7,1|5,2,1|5,3,1|5,4,1|5,5,1|5,6,1|5,7,1|6,2,1|6,3,1|6,4,1|6,5,1|6,6,1|6,7,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |2,0,1|2,1,1|2,2,1|2,3,1|2,4,1|2,5,1|3,0,1|3,1,1|3,2,1|3,3,1|3,4,1|3,5,1|4,0,1|4,1,1|4,2,1|4,3,1|4,4,1|4,5,1|5,0,1|5,1,1|5,2,1|5,3,1|5,4,1|5,5,1|6,0,1|6,1,1|6,2,1|6,3,1|6,4,1|6,5,1|7,0,1|7,1,1|7,2,1|7,3,1|7,4,1|7,5,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |2,1,1|2,2,1|2,3,1|2,4,1|2,5,1|2,6,1|3,1,1|3,2,1|3,3,1|3,4,1|3,5,1|3,6,1|4,1,1|4,2,1|4,3,1|4,4,1|4,5,1|4,6,1|5,1,1|5,2,1|5,3,1|5,4,1|5,5,1|5,6,1|6,1,1|6,2,1|6,3,1|6,4,1|6,5,1|6,6,1|7,1,1|7,2,1|7,3,1|7,4,1|7,5,1|7,6,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |2,2,1|2,3,1|2,4,1|2,5,1|2,6,1|2,7,1|3,2,1|3,3,1|3,4,1|3,5,1|3,6,1|3,7,1|4,2,1|4,3,1|4,4,1|4,5,1|4,6,1|4,7,1|5,2,1|5,3,1|5,4,1|5,5,1|5,6,1|5,7,1|6,2,1|6,3,1|6,4,1|6,5,1|6,6,1|6,7,1|7,2,1|7,3,1|7,4,1|7,5,1|7,6,1|7,7,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+


// INFEAT LAYOUT 1x1 MODE Column0 ---> HWC layout
//   PE0   PE1   PE2   PE3   PE4   PE5   PE6   PE7   PE8   PE9  PE10  PE11  PE12   PE13  PE14  PE15  PE16  PE17  PE18  PE19  PE20  PE21  PE22  PE23  PE24  PE25  PE26  PE27  PE28  PE29  PE30  PE31  PE32  PE33  PE34  PE35
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,0|0,1,0|0,2,0|0,3,0|0,4,0|0,5,0|1,0,0|1,1,0|1,2,0|1,3,0|1,4,0|1,5,0|2,0,0|2,1,0|2,2,0|2,3,0|2,4,0|2,5,0|3,0,0|3,1,0|3,2,0|3,3,0|3,4,0|3,5,0|4,0,0|4,1,0|4,2,0|4,3,0|4,4,0|4,5,0|5,0,0|5,1,0|5,2,0|5,3,0|5,4,0|5,5,0|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,1|0,1,1|0,2,1|0,3,1|0,4,1|0,5,1|1,0,1|1,1,1|1,2,1|1,3,1|1,4,1|1,5,1|2,0,1|2,1,1|2,2,1|2,3,1|2,4,1|2,5,1|3,0,1|3,1,1|3,2,1|3,3,1|3,4,1|3,5,1|4,0,1|4,1,1|4,2,1|4,3,1|4,4,1|4,5,1|5,0,1|5,1,1|5,2,1|5,3,1|5,4,1|5,5,1|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,2|0,1,2|0,2,2|0,3,2|0,4,2|0,5,2|1,0,2|1,1,2|1,2,2|1,3,2|1,4,2|1,5,2|2,0,2|2,1,2|2,2,2|2,3,2|2,4,2|2,5,2|3,0,2|3,1,2|3,2,2|3,3,2|3,4,2|3,5,2|4,0,2|4,1,2|4,2,2|4,3,2|4,4,2|4,5,2|5,0,2|5,1,2|5,2,2|5,3,2|5,4,2|5,5,2|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,3|0,1,3|0,2,3|0,3,3|0,4,3|0,5,3|1,0,3|1,1,3|1,2,3|1,3,3|1,4,3|1,5,3|2,0,3|2,1,3|2,2,3|2,3,3|2,4,3|2,5,3|3,0,3|3,1,3|3,2,3|3,3,3|3,4,3|3,5,3|4,0,3|4,1,3|4,2,3|4,3,3|4,4,3|4,5,3|5,0,3|5,1,3|5,2,3|5,3,3|5,4,3|5,5,3|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,4|0,1,4|0,2,4|0,3,4|0,4,4|0,5,4|1,0,4|1,1,4|1,2,4|1,3,4|1,4,4|1,5,4|2,0,4|2,1,4|2,2,4|2,3,4|2,4,4|2,5,4|3,0,4|3,1,4|3,2,4|3,3,4|3,4,4|3,5,4|4,0,4|4,1,4|4,2,4|4,3,4|4,4,4|4,5,4|5,0,4|5,1,4|5,2,4|5,3,4|5,4,4|5,5,4|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,5|0,1,5|0,2,5|0,3,5|0,4,5|0,5,5|1,0,5|1,1,5|1,2,5|1,3,5|1,4,5|1,5,5|2,0,5|2,1,5|2,2,5|2,3,5|2,4,5|2,5,5|3,0,5|3,1,5|3,2,5|3,3,5|3,4,5|3,5,5|4,0,5|4,1,5|4,2,5|4,3,5|4,4,5|4,5,5|5,0,5|5,1,5|5,2,5|5,3,5|5,4,5|5,5,5|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,6|0,1,6|0,2,6|0,3,6|0,4,6|0,5,6|1,0,6|1,1,6|1,2,6|1,3,6|1,4,6|1,5,6|2,0,6|2,1,6|2,2,6|2,3,6|2,4,6|2,5,6|3,0,6|3,1,6|3,2,6|3,3,6|3,4,6|3,5,6|4,0,6|4,1,6|4,2,6|4,3,6|4,4,6|4,5,6|5,0,6|5,1,6|5,2,6|5,3,6|5,4,6|5,5,6|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// |0,0,7|0,1,7|0,2,7|0,3,7|0,4,7|0,5,7|1,0,7|1,1,7|1,2,7|1,3,7|1,4,7|1,5,7|2,0,7|2,1,7|2,2,7|2,3,7|2,4,7|2,5,7|3,0,7|3,1,7|3,2,7|3,3,7|3,4,7|3,5,7|4,0,7|4,1,7|4,2,7|4,3,7|4,4,7|4,5,7|5,0,7|5,1,7|5,2,7|5,3,7|5,4,7|5,5,7|
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+
// | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | NU  | 
// +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+

// INFEAT LAYOUT 1x1 MODE PE0 ---> HWC layout
// +--------- W BIT 0 --------+--------- W BIT 1 --------+--------- W BIT 2 --------+--------- W BIT 3 --------+--------- W BIT 4 --------+--------- W BIT 5 --------+--------- W BIT 6 --------+--------- W BIT 7 --------+
//  COL0   COL1   COL2   COL3   COL4   COL5  COL6  COL7   COL8   COL9  COL10  COL11  COL12 COL13  COL14  COL15  COL16  COL17 COL18  COL19  COL20 COL21  COL22  COL23  COL24 COL25  COL26  COL27  COL28 COL29  COL30  COL31 
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,0|0,0,8 |0,0,16|0,0,24|0,0,0|0,0,8 |0,0,16|0,0,24|0,0,0|0,0,8 |0,0,16|0,0,24|0,0,0|0,0,8 |0,0,16|0,0,24|0,0,0|0,0,8 |0,0,16|0,0,24|0,0,0|0,0,8 |0,0,16|0,0,24|0,0,0|0,0,8 |0,0,16|0,0,24|0,0,0|0,0,8 |0,0,16|0,0,24|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,1|0,0,9 |0,0,17|0,0,25|0,0,1|0,0,9 |0,0,17|0,0,25|0,0,1|0,0,9 |0,0,17|0,0,25|0,0,1|0,0,9 |0,0,17|0,0,25|0,0,1|0,0,9 |0,0,17|0,0,25|0,0,1|0,0,9 |0,0,17|0,0,25|0,0,1|0,0,9 |0,0,17|0,0,25|0,0,1|0,0,9 |0,0,17|0,0,25|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,2|0,0,10|0,0,18|0,0,26|0,0,2|0,0,10|0,0,18|0,0,26|0,0,2|0,0,10|0,0,18|0,0,26|0,0,2|0,0,10|0,0,18|0,0,26|0,0,2|0,0,10|0,0,18|0,0,26|0,0,2|0,0,10|0,0,18|0,0,26|0,0,2|0,0,10|0,0,18|0,0,26|0,0,2|0,0,10|0,0,18|0,0,26|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,3|0,0,11|0,0,19|0,0,27|0,0,3|0,0,11|0,0,19|0,0,27|0,0,3|0,0,11|0,0,19|0,0,27|0,0,3|0,0,11|0,0,19|0,0,27|0,0,3|0,0,11|0,0,19|0,0,27|0,0,3|0,0,11|0,0,19|0,0,27|0,0,3|0,0,11|0,0,19|0,0,27|0,0,3|0,0,11|0,0,19|0,0,27|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,4|0,0,12|0,0,20|0,0,28|0,0,4|0,0,12|0,0,20|0,0,28|0,0,4|0,0,12|0,0,20|0,0,28|0,0,4|0,0,12|0,0,20|0,0,28|0,0,4|0,0,12|0,0,20|0,0,28|0,0,4|0,0,12|0,0,20|0,0,28|0,0,4|0,0,12|0,0,20|0,0,28|0,0,4|0,0,12|0,0,20|0,0,28|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,5|0,0,13|0,0,21|0,0,29|0,0,5|0,0,13|0,0,21|0,0,29|0,0,5|0,0,13|0,0,21|0,0,29|0,0,5|0,0,13|0,0,21|0,0,29|0,0,5|0,0,13|0,0,21|0,0,29|0,0,5|0,0,13|0,0,21|0,0,29|0,0,5|0,0,13|0,0,21|0,0,29|0,0,5|0,0,13|0,0,21|0,0,29|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,6|0,0,14|0,0,22|0,0,30|0,0,6|0,0,14|0,0,22|0,0,30|0,0,6|0,0,14|0,0,22|0,0,30|0,0,6|0,0,14|0,0,22|0,0,30|0,0,6|0,0,14|0,0,22|0,0,30|0,0,6|0,0,14|0,0,22|0,0,30|0,0,6|0,0,14|0,0,22|0,0,30|0,0,6|0,0,14|0,0,22|0,0,30|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// |0,0,7|0,0,15|0,0,23|0,0,31|0,0,7|0,0,15|0,0,23|0,0,31|0,0,7|0,0,15|0,0,23|0,0,31|0,0,7|0,0,15|0,0,23|0,0,31|0,0,7|0,0,15|0,0,23|0,0,31|0,0,7|0,0,15|0,0,23|0,0,31|0,0,7|0,0,15|0,0,23|0,0,31|0,0,7|0,0,15|0,0,23|0,0,31|
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+
// | NU  |  NU  |  NU  |  NU  |  NU |  NU  |  NU  |  NU  |  NU |  NU  |  NU  |  NU  |  NU |  NU  |  NU  |  NU  | NU  |  NU  |  NU  |  NU  | NU  |  NU  |  NU  |  NU  | NU  |  NU  |  NU  |  NU  | NU  |  NU  |  NU  |  NU  | 
// +-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+-----+------+------+------+


      for(genvar rr=0; rr<COLUMN_SIZE; rr++) begin : row_a_gen

        localparam i=0;
        localparam j=0;

        // filter size = 1
        localparam j_fs1  = (ii % SPATIAL_W);
        localparam i_fs1  = ((ii-(ii%SPATIAL_H)) / SPATIAL_W);

        // filter size = 3
        localparam fj_fs3 = rr % 3;
        localparam fi_fs3 = (rr-fj_fs3)/ 3;
        localparam j_fs3  = ii % SPATIAL_H + fj_fs3;
        localparam i_fs3  = (ii-(ii%SPATIAL_H)) / SPATIAL_H + fi_fs3;

        for(genvar bb=0; bb<BLOCK_SIZE; bb++) begin : act_blk_gen

          // FIXME parameterize 5 (also NR_ACTIVATIONS)
          assign activation_mapped_fs3_data [ii][rr][bb][NEUREKA_QA_IN-1:0]   = activation_data [i_fs3*NEUREKA_TP_IN*INPUT_BUFFER_SIZE_W + j_fs3*NEUREKA_TP_IN + bb][NEUREKA_QA_IN-1:0];
          assign activation_mapped_fs3_valid[ii][rr][bb]                   = activation_valid[0];
          assign activation_mapped_fs3_strb [ii][rr][bb][NEUREKA_QA_IN/8-1:0] = activation_strb [0][NEUREKA_QA_IN/8-1:0];

          localparam i_bb = bb/8;
          localparam j_bb = bb%4;

          assign activation_mapped_fs1_data [ii][rr][bb][NEUREKA_QA_IN-1:0]   = activation_data [i_fs1*NEUREKA_TP_IN*INPUT_BUFFER_SIZE_W + j_fs1*NEUREKA_TP_IN + 8*j_bb + rr][NEUREKA_QA_IN-1:0];
          assign activation_mapped_fs1_valid[ii][rr][bb]                   = activation_valid[0];
          assign activation_mapped_fs1_strb [ii][rr][bb][NEUREKA_QA_IN/8-1:0] = activation_strb [0][NEUREKA_QA_IN/8-1:0];

          localparam ii_rr_bb = ii*(COLUMN_SIZE*BLOCK_SIZE) + bb*(COLUMN_SIZE) + rr; // modified to NR_PE    , BLOCK_SIZE, COLUMN_SIZE

          assign activation_mapped[ii_rr_bb].valid = (ctrl_i.filter_mode == NEUREKA_FILTER_MODE_1X1) ? activation_mapped_fs1_valid[ii][rr][bb] : activation_mapped_fs3_valid[ii][rr][bb];
          assign activation_mapped[ii_rr_bb].data  = (ctrl_i.filter_mode == NEUREKA_FILTER_MODE_1X1) ? activation_mapped_fs1_data[ii][rr][bb]  : activation_mapped_fs3_data[ii][rr][bb];
          assign activation_mapped[ii_rr_bb].strb  = (ctrl_i.filter_mode == NEUREKA_FILTER_MODE_1X1) ? activation_mapped_fs1_strb[ii][rr][bb]  : activation_mapped_fs3_strb[ii][rr][bb];

        end // block_gen
      end // row_a_gen

      ctrl_binconv_pe_t ctrl_pe;
      always_comb
      begin
        ctrl_pe = ctrl_i.ctrl_pe;
        ctrl_pe.ctrl_col.enable_block = ctrl_i.ctrl_pe.ctrl_col.enable_block;
        ctrl_pe.ctrl_col.block_cnt = block_cnt_q;
        // in depthwise mode, MACs are enabled sequentially in the channel in dimension
        ctrl_pe.enable_col = ctrl_i.ctrl_pe.ctrl_col.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ctrl_i.ctrl_pe.enable_col & depthwise_cnt_oh_q :
                                                                                                                   ctrl_i.ctrl_pe.enable_col;
        // in depthwise mode, partial sum valid signals have to be invalidated in some cases (check)
        ctrl_pe.ctrl_col.invalidate = ctrl_i.ctrl_pe.ctrl_col.filter_mode == NEUREKA_FILTER_MODE_3X3_DW & ctrl_i.ctrl_pe.ctrl_col.weight_offset ? block_invalidate_q : 1'b0;
      end

      // column instantiation
      logic clk_gated;
      cluster_clock_gating i_hier_column_gate (
        .clk_i     ( clk_i                                         ),
        .en_i      ( enable_i & ctrl_i.enable_pe[ii] | clear_i     ),
        .test_en_i ( test_mode_i                                   ),
        .clk_o     ( clk_gated                                     )
      );

      neureka_binconv_pe #(
        .COLUMN_SIZE ( COLUMN_SIZE ),
        .BLOCK_SIZE  ( BLOCK_SIZE ),
        .TP_IN       ( TP_IN         )
      ) i_pe (
        .clk_i         ( clk_gated                                                                     ),
        .rst_ni        ( rst_ni                                                                        ),
        .test_mode_i   ( test_mode_i                                                                   ),
        .enable_i      ( enable_i & ctrl_i.enable_pe[ii]                                               ),
        .clear_i       ( clear_i                                                                       ),
        .activation_i  ( activation_mapped [(ii+1)*COLUMN_SIZE*BLOCK_SIZE-1:ii*COLUMN_SIZE*BLOCK_SIZE] ),
        .weight_i      ( weight_int [(ii+1)*COLUMN_SIZE-1:ii*COLUMN_SIZE]                              ),
        .column_pres_o ( pres_int [ii]                                                                 ),
        .column_pres_depthwise_o(pres_depthwise[(ii+1)*BLOCK_SIZE-1:ii*BLOCK_SIZE]                     ),
        .ctrl_i        ( ctrl_pe                                                                       ),
        .flags_o       ( flags_o.flags_column[ii]                                                      )
      );

      if(ii==0) begin : pres_0_gen
        assign pres_o[0].data =  pres_int[0].data;
        assign pres_o[0].valid = pres_int[0].valid;
        assign pres_o[0].strb  = pres_int[0].strb;
        assign pres_int[0].ready = pres_o[0].ready;
      end
      else begin : pres_non0_gen
        assign pres_o[ii].data = pres_int[ii].data;
        assign pres_o[ii].valid = pres_int[0].valid;
        assign pres_o[ii].strb  = pres_int[0].strb;
        assign pres_int[ii].ready = pres_o[0].ready;
      end

    end // column_gen
  endgenerate

  // counter used for scale control
  assign block_clear  = clear_i | ctrl_i.ctrl_pe.ctrl_col.clear;
  assign block_cnt_en = (ctrl_i.ctrl_pe.ctrl_col.weight_offset==1'b0)                                       ? activation_mapped[0].valid & activation_mapped[0].ready & weight_int[0].valid & weight_int[0].ready :
                        (block_cnt_q=='0 || ctrl_i.ctrl_pe.ctrl_col.filter_mode == NEUREKA_FILTER_MODE_3X3_DW) ? activation_mapped[0].valid & (activation_mapped[0].ready | weight_int[0].ready) :
                        '0;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin 
      block_cnt_q         <= '0;
      block_invalidate_q  <= '0;
    end else begin 
      block_cnt_q         <= block_cnt_d;
      block_invalidate_q  <= block_invalidate_d;
    end 
  end

  // counter used for enable control
  assign depthwise_cnt_en = ctrl_i.ctrl_pe.ctrl_col.filter_mode != NEUREKA_FILTER_MODE_3X3_DW ? '0 :
                            ctrl_i.ctrl_pe.ctrl_col.weight_offset ? block_cnt_en :
                            block_cnt_en & (block_cnt_q == ctrl_i.ctrl_pe.ctrl_col.qw-1);





  always_comb
  begin
    block_invalidate_d = block_invalidate_q;
    block_cnt_d = block_cnt_q;
    if(block_clear) begin 
      block_invalidate_d = '0;
      block_cnt_d = '0;
    end else if(block_cnt_en) begin 
      if (depthwise_cnt_q == (ctrl_i.depthwise_len-1)) begin
        block_invalidate_d = '1;
      end
      if (block_cnt_q == (ctrl_i.ctrl_pe.ctrl_col.qw-1)) block_cnt_d = '0;
      else block_cnt_d = block_cnt_q + 1;
    end 
  end

  always_comb
  begin
    depthwise_cnt_d = depthwise_cnt_q;
    depthwise_cnt_oh_d = depthwise_cnt_oh_q;
    if(block_clear) begin
      depthwise_cnt_d = '0; 
      depthwise_cnt_oh_d = 1;
    end else if(depthwise_cnt_en) begin 
      if (depthwise_cnt_q == (ctrl_i.depthwise_len-1)) begin
        depthwise_cnt_d = '0;
        depthwise_cnt_oh_d = 1;
      end
      else if(depthwise_cnt_en & ~block_invalidate_q) begin
        depthwise_cnt_d = depthwise_cnt_q + 1;
        depthwise_cnt_oh_d = '0;
        depthwise_cnt_oh_d[depthwise_cnt_q + 1] = 1'b1;
      end
    end 
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin 
      depthwise_cnt_q     <= '0;
      depthwise_cnt_oh_q  <= '0;
      
    end else begin 
      depthwise_cnt_q     <= depthwise_cnt_d;
      depthwise_cnt_oh_q  <= depthwise_cnt_oh_d;
    end 
  end

endmodule // neureka_binconv_array
