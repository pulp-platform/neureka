/*
 * neureka_engine.sv
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
 * Authors (RBE):     Gianna Paulin <pauling@iis.ee.ethz.ch>
 *                    Francesco Conti <f.conti@unibo.it>
 * Authors (NE16):    Francesco Conti <francesco.conti@greenwaves-technologies.com>
 * Authors (NEUREKA): Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 *                    Francesco Conti <f.conti@unibo.it>
 */

import neureka_package::*;

module neureka_engine #(
  parameter int unsigned COLUMN_SIZE    = NEUREKA_COLUMN_SIZE, // number of BinConv blocks per column (default 9)
  parameter int unsigned BLOCK_SIZE     = NEUREKA_BLOCK_SIZE,  // number of SoP's per BinConv block (default 4),
  parameter int unsigned TP_IN          = NEUREKA_TP_IN,       // number of input elements processed per cycle
  parameter int unsigned TP_OUT         = NEUREKA_TP_OUT,
  parameter int unsigned PE_H           = NEUREKA_PE_H_DEFAULT,
  parameter int unsigned PE_W           = NEUREKA_PE_W_DEFAULT
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  // input streams + handshake
  hwpe_stream_intf_stream.sink   load_in,
  hwpe_stream_intf_stream.sink   load_weight,
  hwpe_stream_intf_stream.sink   load_norm,
  hwpe_stream_intf_stream.sink   load_streamin,
  hwpe_stream_intf_stream.source store_out,
  input  ctrl_engine_t           ctrl_i,
  output flags_engine_t          flags_o
);

  /* Local Params, Interfaces, and Signals */
  localparam COLUMN_PRES_SIZE  = NEUREKA_QA_IN+NEUREKA_QA_16BIT+8+$clog2(COLUMN_SIZE);
  localparam BLOCK_PRES_SIZE   = COLUMN_PRES_SIZE+$clog2(BLOCK_SIZE);
  localparam int unsigned INPUT_BUF_SIZE = (PE_H+2)*(PE_W+2)*NEUREKA_TP_IN;
  localparam int unsigned NR_PE = PE_H*PE_W;

  logic                      all_norm_ready;
  logic [NR_PE-1:0] all_norm_ready_tree;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) load_in_blocks [BLOCK_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH_WEIGHT )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) load_weight_fifo (
    .clk ( clk_i )
  );


  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( TP_IN )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) load_weight_rows_conv [COLUMN_SIZE-1:0] (
    .clk ( clk_i )
  );


  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) store_out_cols [NR_PE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) load_streamin_cols [NR_PE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) in_from_buf [INPUT_BUF_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( BLOCK_PRES_SIZE )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres [NR_PE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( COLUMN_PRES_SIZE )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres_depthwise [BLOCK_SIZE*NR_PE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) norm [NR_PE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) load_norm_fifo (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) load_streamin_fifo (
    .clk ( clk_i )
  );

  // Infeat data from the input buffer is split in blocks of size 8bits
  //
  //            load_in[256b]
  //                 ||
  //                 \/
  //         +-----------------+
  //         |hwpe_stream_split|
  //         +-----------------+
  //                 ||
  //                 \/
  //        load_in_blocks[31:0][8b]

  hwpe_stream_split #(
    .NB_OUT_STREAMS ( BLOCK_SIZE            ),
    .DATA_WIDTH_IN  ( NEUREKA_QA_IN*BLOCK_SIZE )
  ) i_split_load_in_blocks (
    .clk_i   ( clk_i          ),
    .rst_ni  ( rst_ni         ),
    .clear_i ( clear_i        ),
    .push_i  ( load_in        ),
    .pop_o   ( load_in_blocks )
  );
  
  hwpe_stream_fifo #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .FIFO_DEPTH ( 2                  )
  ) i_fifo_load_weight (
    .clk_i   ( clk_i            ),
    .rst_ni  ( rst_ni           ),
    .clear_i ( clear_i          ),
    .flags_o (                  ),
    .push_i  ( load_weight      ),
    .pop_o   ( load_weight_fifo )
  );


  hwpe_stream_split #(
    .NB_OUT_STREAMS ( COLUMN_SIZE              ),
    .DATA_WIDTH_IN  ( NEUREKA_MEM_BANDWIDTH_WEIGHT)
  ) load_weight_rows_conv_split (
    .clk_i   ( clk_i                       ),
    .rst_ni  ( rst_ni                      ),
    .clear_i ( clear_i                     ),
    .push_i  ( load_weight_fifo            ),
    .pop_o   ( load_weight_rows_conv       )
  );


  // Streamout data from the column accumulators is serialized one column after the other
  //
  //        store_out_cols[8:0][256b]
  //                 ||
  //                 \/
  //       +---------------------+
  //       |hwpe_stream_serialize|
  //       +---------------------+
  //                 ||
  //                 \/
  //           store_out[256b]

  hwpe_stream_serialize #(
    .NB_IN_STREAMS ( NR_PE          ),
    .DATA_WIDTH    ( NEUREKA_MEM_BANDWIDTH )
  ) i_serialize_store_out (
    .clk_i   ( clk_i                 ),
    .rst_ni  ( rst_ni                ),
    .clear_i ( clear_i               ),
    .ctrl_i  ( ctrl_i.ctrl_serialize_streamout ),
    .push_i  ( store_out_cols        ),
    .pop_o   ( store_out             )
  );

  // Streamin data goingo into the column accumulators comes per column and is deserialized
  //
  //          load_streamin[256b]
  //                 ||
  //                 \/
  //               |____|
  //               |____| hwpe_stream_fifo
  //                 ||
  //                 \/
  //        load_streamin_fifo[256b]
  //                 ||
  //                 \/
  //      +-----------------------+
  //      |hwpe_stream_deserialize|
  //      +-----------------------+
  //                 ||
  //                 \/
  //           load_streamin_cols[8:0][256b]

  hwpe_stream_fifo #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH ),
    .FIFO_DEPTH ( 2                  )
  ) i_fifo_load_streamin (
    .clk_i   ( clk_i              ),
    .rst_ni  ( rst_ni             ),
    .clear_i ( clear_i            ),
    .flags_o (                    ),
    .push_i  ( load_streamin      ),
    .pop_o   ( load_streamin_fifo )
  );

  hwpe_stream_deserialize #(
    .NB_OUT_STREAMS ( NR_PE          ),
    .DATA_WIDTH     ( NEUREKA_MEM_BANDWIDTH )
  ) i_deserialize_load_streamin (
    .clk_i   ( clk_i                      ),
    .rst_ni  ( rst_ni                     ),
    .clear_i ( clear_i | ctrl_i.clear_des ),
    .ctrl_i  ( ctrl_i.ctrl_serialize_streamin      ),
    .push_i  ( load_streamin_fifo         ),
    .pop_o   ( load_streamin_cols         )
  );

  // The same norm stream, coming simply from a FIFO, is shared between all columns.
  //
  //          load_norm[256b]
  //                 ||
  //                 \/
  //               |____|
  //               |____| hwpe_stream_fifo
  //                 ||
  //                 \/
  //          load_norm_fifo[256b]
  //                 || copy 9x
  //                 \/
  //             norm[8:0][256b]

  // enqueue norm stream
  hwpe_stream_fifo #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH ),
    .FIFO_DEPTH ( 2                  )
  ) i_fifo_load_norm (
    .clk_i   ( clk_i          ),
    .rst_ni  ( rst_ni         ),
    .clear_i ( clear_i        ),
    .flags_o (                ),
    .push_i  ( load_norm      ),
    .pop_o   ( load_norm_fifo )
  );

  // duplicate norm stream
  generate
    for(genvar ii=0; ii<NR_PE; ii++) begin
      assign all_norm_ready_tree[ii] = norm[ii].ready;
      assign norm[ii].data           = load_norm_fifo.data;
      assign norm[ii].valid          = load_norm_fifo.valid;
      assign norm[ii].strb           = load_norm_fifo.strb;
    end

    assign all_norm_ready = &(all_norm_ready_tree);
    assign load_norm_fifo.ready = all_norm_ready;
  endgenerate

  /* Input Buffer */
  localparam int INFEAT_BUFFER_SIZE_H  = PE_H+2; // Input Feature buffer size across height. 
  localparam int INFEAT_BUFFER_SIZE_W  = PE_W+2; // Input Feature buffer size across width
  localparam int INFEAT_BUFFER_SIZE_HW = INFEAT_BUFFER_SIZE_H*INFEAT_BUFFER_SIZE_W; // Input Feature buffer size 
  neureka_double_infeat_buffer #(
    .INPUT_BUF_SIZE        ( INPUT_BUF_SIZE        ),
    .BLOCK_SIZE            ( BLOCK_SIZE            ),
    .DW                    ( NEUREKA_QA_IN         ),
    .PE_H                  ( PE_H                  ),
    .PE_W                  ( PE_W                  ),
    .INFEAT_BUFFER_SIZE_H  ( INFEAT_BUFFER_SIZE_H  ),
    .INFEAT_BUFFER_SIZE_W  ( INFEAT_BUFFER_SIZE_W  ),
    .INFEAT_BUFFER_SIZE_HW ( INFEAT_BUFFER_SIZE_HW )
  ) i_double_infeat_buffer (
    .clk_i       ( clk_i                              ),
    .rst_ni      ( rst_ni                             ),
    .test_mode_i ( test_mode_i                        ),
    .enable_i    ( enable_i                           ),
    .clear_i     ( clear_i                            ),
    .ctrl_i      ( ctrl_i.ctrl_double_infeat_buffer   ),
    .flags_o     ( flags_o.flags_double_infeat_buffer ),
    .feat_i      ( load_in_blocks                     ),
    .feat_o      ( in_from_buf                        )
  );

  /* BinConv Array */
  neureka_binconv_array #(
    .COLUMN_SIZE         ( COLUMN_SIZE          ),
    .NR_PE               ( NR_PE                ),
    .NR_ACTIVATIONS      ( INPUT_BUF_SIZE       ),
    .BLOCK_SIZE          ( BLOCK_SIZE           ),
    .INPUT_BUFFER_SIZE_W ( INFEAT_BUFFER_SIZE_W ),
    .TP_IN               ( TP_IN                ),
    .PE_H                ( PE_H                 ),
    .PE_W                ( PE_W                 )
  ) i_binconv_array (
    .clk_i             ( clk_i                          ),
    .rst_ni            ( rst_ni                         ),
    .test_mode_i       ( test_mode_i                    ),
    .enable_i          ( enable_i                       ),
    .clear_i           ( clear_i                        ),
    .activation_i      ( in_from_buf                    ),
    .weight_conv_i     ( load_weight_rows_conv          ),
    .pres_o            ( pres                           ),
    .pres_depthwise_o  ( pres_depthwise                 ),
    .ctrl_i            ( ctrl_i.ctrl_binconv_array      ),
    .flags_o           ( flags_o.flags_binconv_array    )
  );

  /* Accumulators + Normalization/Quantization */
  generate
    for (genvar ii=0; ii<NR_PE; ii++) begin : accumulator_gen

      ctrl_aq_t ctrl_accumulator;
      always_comb
      begin
        ctrl_accumulator = ctrl_i.ctrl_accumulator;
        ctrl_accumulator.enable_streamout = ctrl_i.enable_accumulator[ii];
      end

      neureka_accumulator_normquant #(
        .TP               ( TP_IN  ),
        .AP               ( TP_OUT ),
        .ACC              ( 32     ),
        .OUTREG_NORMQUANT ( 1      )
      ) i_accumulator (
        .clk_i       ( clk_i                                              ),
        .rst_ni      ( rst_ni                                             ),
        .test_mode_i ( test_mode_i                                        ),
        .enable_i    ( enable_i                                           ),
        .clear_i     ( clear_i                                            ),
        .conv_i      ( pres                       [ii]                    ),
        .conv_dw_i   ( pres_depthwise [(ii+1)*BLOCK_SIZE-1:ii*BLOCK_SIZE] ),
        .norm_i      ( norm                       [ii]                    ),
        .streamin_i  ( load_streamin_cols         [ii]                    ),
        .conv_o      ( store_out_cols             [ii]                    ),
        .ctrl_i      ( ctrl_accumulator                                   ),
        .flags_o     ( flags_o.flags_accumulator  [ii]                    )
      );

    end // accumulator_gen
  endgenerate

endmodule // neureka_engine
