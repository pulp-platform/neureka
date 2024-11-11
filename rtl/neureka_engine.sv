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
  parameter int unsigned PE_W           = NEUREKA_PE_W_DEFAULT,
  parameter bit          FAULT_TOLERANCE = 1,
  parameter int unsigned N_COPIES       = FAULT_TOLERANCE ? 2 : 1
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
  ) in_from_buf [N_COPIES*INPUT_BUF_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( BLOCK_PRES_SIZE )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres [N_COPIES*NR_PE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( COLUMN_PRES_SIZE )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres_depthwise [N_COPIES*BLOCK_SIZE*NR_PE-1:0] (
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
    .clk_i   ( clk_i                           ),
    .rst_ni  ( rst_ni                          ),
    .clear_i ( clear_i | ctrl_i.clear_ser      ),
    .ctrl_i  ( ctrl_i.ctrl_serialize_streamout ),
    .push_i  ( store_out_cols                  ),
    .pop_o   ( store_out                       )
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
    .clk_i   ( clk_i                          ),
    .rst_ni  ( rst_ni                         ),
    .clear_i ( clear_i | ctrl_i.clear_des     ),
    .ctrl_i  ( ctrl_i.ctrl_serialize_streamin ),
    .push_i  ( load_streamin_fifo             ),
    .pop_o   ( load_streamin_cols             )
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

  // hwpe_stream_copy #( .NB_COPY_STREAMS (NR_PE) ) i_norm ( .push_i (load_norm_fifo.sink), .pop_o (norm.source) ); // I don't remember why it can't be used here

  /* Input Buffer */
  localparam int INFEAT_BUFFER_SIZE_H  = PE_H+2; // Input Feature buffer size across height. 
  localparam int INFEAT_BUFFER_SIZE_W  = PE_W+2; // Input Feature buffer size across width
  localparam int INFEAT_BUFFER_SIZE_HW = INFEAT_BUFFER_SIZE_H*INFEAT_BUFFER_SIZE_W; // Input Feature buffer size 
  if (FAULT_TOLERANCE) begin : ft_datapath_gen

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) out_cols [N_COPIES*NR_PE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) out_cols_0 [NR_PE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) out_cols_1 [NR_PE-1:0] (
      .clk ( clk_i )
    );

  //   hwpe_stream_intf_stream #(
  //     .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  // `ifndef SYNTHESIS
  //     ,
  //     .BYPASS_VCR_ASSERT( 1'b1  ),
  //     .BYPASS_VDR_ASSERT( 1'b1  )
  // `endif
  //   ) out_cols_demuxed [N_COPIES*NR_PE-1:0] (
  //     .clk ( clk_i )
  //   );

  //   hwpe_stream_intf_stream #(
  //     .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  // `ifndef SYNTHESIS
  //     ,
  //     .BYPASS_VCR_ASSERT( 1'b1  ),
  //     .BYPASS_VDR_ASSERT( 1'b1  )
  // `endif
  //   ) store_out_cols_pre_check [N_COPIES*NR_PE-1:0] (
  //     .clk ( clk_i )
  //   );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_QA_IN )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) load_in_blocks_copy [N_COPIES*BLOCK_SIZE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_QA_IN )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) load_in_blocks_demuxed [N_COPIES*BLOCK_SIZE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_QA_IN )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) load_in_blocks_datapath [N_COPIES*BLOCK_SIZE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( TP_IN )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) load_weight_rows_conv_copy [N_COPIES*COLUMN_SIZE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( TP_IN )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) load_weight_rows_conv_datapath [N_COPIES*COLUMN_SIZE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) load_streamin_cols_copy [N_COPIES*NR_PE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) load_streamin_cols_datapath [N_COPIES*NR_PE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) norm_copy [N_COPIES*NR_PE-1:0] (
      .clk ( clk_i )
    );

    hwpe_stream_intf_stream #(
      .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH )
  `ifndef SYNTHESIS
      ,
      .BYPASS_VCR_ASSERT( 1'b1  ),
      .BYPASS_VDR_ASSERT( 1'b1  )
  `endif
    ) norm_copy_datapath [N_COPIES*NR_PE-1:0] (
      .clk ( clk_i )
    );

    flags_engine_t [N_COPIES-1:0] flags;
    logic [NR_PE-1:0] data_fault_d, data_fault_q;
    logic [NR_PE-1:0] mismatch;

    ctrl_double_infeat_buffer_t [N_COPIES-1:0] ctrl_double_infeat_buffer_copy;

    assign ctrl_double_infeat_buffer_copy[0] = (ctrl_i.resilience_mode == 1) ? ctrl_i.ctrl_double_infeat_buffer : (ctrl_i.active_datapath == 0) ? ctrl_i.ctrl_double_infeat_buffer : '0; // second load here
    assign ctrl_double_infeat_buffer_copy[1] = (ctrl_i.resilience_mode == 1) ? ctrl_i.ctrl_double_infeat_buffer : (ctrl_i.active_datapath == 1) ? ctrl_i.ctrl_double_infeat_buffer : '0 ;

    assign flags_o.active_datapath = ctrl_i.active_datapath; // second load here

    // duplicate load_in_blocks, load_weight_rows_conv, load_streamin_cols, norm stream

    // TODO Maybe it's better to rewrite the copy module to keep without the NB_IN_STREAMS since it sucks
    //      However this will require to rewrite the assignment down below (0 -> 0, 1 ; 1 -> 2, 3)
    // for(genvar ii=0; ii<BLOCK_SIZE; ii++) begin
    //   hwpe_stream_copy #( .NB_COPY_STREAMS (N_COPIES) ) i_copy_load_in_blocks ( .push_i (load_in_blocks[ii]), .pop_o (load_in_blocks_copy[N_COPIES*ii+1:N_COPIES*ii]) );
    // end
    for(genvar ii=0; ii<COLUMN_SIZE; ii++) begin
      hwpe_stream_copy #( .NB_COPY_STREAMS (2) ) i_copy_load_weight_rows_conv ( .push_i (load_weight_rows_conv[ii]), .pop_o (load_weight_rows_conv_copy[2*ii+1:2*ii]) );
      hwpe_stream_assign i_to_load_weight_rows_conv_datapath_0 (.push_i(load_weight_rows_conv_copy[2*ii]), .pop_o(load_weight_rows_conv_datapath[ii]));
      hwpe_stream_assign i_to_load_weight_rows_conv_datapath_1 (.push_i(load_weight_rows_conv_copy[2*ii+1]), .pop_o(load_weight_rows_conv_datapath[COLUMN_SIZE+ii]));
    end
    for (genvar ii=0; ii<NR_PE; ii++) begin
      hwpe_stream_copy #( .NB_COPY_STREAMS (2) ) i_copy_load_streamin_cols ( .push_i (load_streamin_cols[ii]), .pop_o (load_streamin_cols_copy[2*ii+1:2*ii]) );
      hwpe_stream_assign i_to_load_streamin_cols_datapath_0 (.push_i(load_streamin_cols_copy[2*ii]), .pop_o(load_streamin_cols_datapath[ii]));
      hwpe_stream_assign i_to_load_streamin_cols_datapath_1 (.push_i(load_streamin_cols_copy[2*ii+1]), .pop_o(load_streamin_cols_datapath[NR_PE+ii]));
      hwpe_stream_copy #( .NB_COPY_STREAMS (2) ) i_copy_norm ( .push_i (norm[ii]), .pop_o (norm_copy[2*ii+1:2*ii]) );
      hwpe_stream_assign i_to_norm_copy_datapath_0 (.push_i(norm_copy[2*ii]), .pop_o(norm_copy_datapath[ii]));
      hwpe_stream_assign i_to_norm_copy_datapath_1 (.push_i(norm_copy[2*ii+1]), .pop_o(norm_copy_datapath[NR_PE+ii]));
    end


    logic [BLOCK_SIZE-1:0][2-1:0] load_in_blocks_datapath_ready;

    for(genvar ii=0; ii<2; ii++) begin : stream_copy
      for(genvar jj=0; jj<BLOCK_SIZE; jj++) begin
        localparam ii_jj = ii*BLOCK_SIZE+jj;

        assign load_in_blocks_datapath[ii_jj].data  = load_in_blocks[jj].data;
        assign load_in_blocks_datapath[ii_jj].strb  = load_in_blocks[jj].strb;
        assign load_in_blocks_datapath[ii_jj].valid = load_in_blocks[jj].valid;

        // auxiliary for ready generation
        assign load_in_blocks_datapath_ready[jj][ii] = load_in_blocks_datapath[ii_jj].ready;

      end
    end

    for(genvar jj=0; jj<BLOCK_SIZE; jj++) begin : ready_assign
      assign load_in_blocks[jj].ready = (ctrl_i.resilience_mode == 1) ? &(load_in_blocks_datapath_ready[jj]) : (ctrl_i.active_datapath == 0) ? load_in_blocks_datapath_ready[jj][0] : load_in_blocks_datapath_ready[jj][1];
    end

    // for(genvar ii=0; ii<BLOCK_SIZE; ii++) begin

    //   hwpe_stream_demux_static i_load_in_demux
    //   (
    //     .clk_i    ( clk_i                         ),
    //     .rst_ni   ( rst_ni                        ),
    //     .clear_i  ( clear_i                       ),
    //     .sel_i    ( ctrl_i.active_datapath           ),
    //     .push_i   ( load_in_blocks[ii]       ),
    //     .pop_o    ( load_in_blocks_demuxed[2*ii+1:2*ii]   )
    //   );

    //   hwpe_stream_copy #( .NB_COPY_STREAMS (2) ) i_copy_load_in_blocks ( .push_i (load_in_blocks_demuxed[2*ii]), .pop_o (load_in_blocks_copy[2*ii+1:2*ii]) );

    //   hwpe_stream_assign i_to_in_blocks_datapath (.push_i(load_in_blocks_copy[2*ii]), .pop_o(load_in_blocks_datapath[ii]));

    //   hwpe_stream_mux_static i_load_in_mux (
    //     .clk_i   ( clk_i            ),
    //     .rst_ni  ( rst_ni           ),
    //     .clear_i ( clear_i          ),
    //     .sel_i   ( ctrl_i.active_datapath),
    //     .push_0_i( load_in_blocks_copy[2*ii+1]     ),
    //     .push_1_i( load_in_blocks_demuxed[2*ii+1] ),
    //     .pop_o   ( load_in_blocks_datapath[BLOCK_SIZE+ii] )
    //   );

    // end

    // hwpe_stream_copy #( .NB_IN_STREAMS (BLOCK_SIZE), .NB_COPY_STREAMS (N_COPIES) )
    //   i_copy_load_in_blocks ( .push_i (load_in_blocks.sink), .pop_o (load_in_blocks_copy.source) );
    // hwpe_stream_copy #( .NB_IN_STREAMS (COLUMN_SIZE), .NB_COPY_STREAMS (N_COPIES) )
    //   i_copy_load_weight_rows_conv ( .push_i (load_weight_rows_conv.sink), .pop_o (load_weight_rows_conv_copy.source) );
    // hwpe_stream_copy #( .NB_IN_STREAMS (NR_PE), .NB_COPY_STREAMS (N_COPIES) )
    //   i_copy_load_streamin_cols    ( .push_i (load_streamin_cols.sink), .pop_o (load_streamin_cols_copy.source) );
    // hwpe_stream_copy #( .NB_IN_STREAMS (NR_PE), .NB_COPY_STREAMS (N_COPIES) )
    //   i_copy_norm                  ( .push_i (norm.sink), .pop_o (norm_copy.source) );

    for (genvar jj=0; jj<N_COPIES; jj++) begin : redundancy_gen

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
        .ctrl_i      ( ctrl_double_infeat_buffer_copy[jj]   ),
        .flags_o     ( flags[jj].flags_double_infeat_buffer ),
        .feat_i      ( load_in_blocks_datapath[jj*BLOCK_SIZE+:BLOCK_SIZE] ),
        .feat_o      ( in_from_buf[jj*INPUT_BUF_SIZE+:INPUT_BUF_SIZE] )
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
        .activation_i      ( in_from_buf[jj*INPUT_BUF_SIZE+:INPUT_BUF_SIZE] ),
        .weight_conv_i     ( load_weight_rows_conv_datapath[jj*COLUMN_SIZE+:COLUMN_SIZE]          ),
        .pres_o            ( pres[jj*NR_PE+:NR_PE]          ),
        .pres_depthwise_o  ( pres_depthwise[jj*BLOCK_SIZE*NR_PE+:BLOCK_SIZE*NR_PE] ), // check this
        .ctrl_i            ( ctrl_i.ctrl_binconv_array      ),
        .flags_o           ( flags[jj].flags_binconv_array  )
      );

      /* Accumulators + Normalization/Quantization */
      for (genvar ii=0; ii<NR_PE; ii++) begin : accumulator_gen

        ctrl_aq_t ctrl_accumulator;
        always_comb
        begin
          ctrl_accumulator = ctrl_i.ctrl_accumulator;
          ctrl_accumulator.enable_streamout = ctrl_i.enable_accumulator[ii];
        end

        neureka_accumulator_normquant #(
          .TP  ( TP_IN  ),
          .AP  ( TP_OUT ),
          .ACC ( 32     )
        ) i_accumulator (
          .clk_i       ( clk_i                                              ),
          .rst_ni      ( rst_ni                                             ),
          .test_mode_i ( test_mode_i                                        ),
          .enable_i    ( enable_i                                           ),
          .clear_i     ( clear_i                                            ),
          .conv_i      ( pres             [jj*NR_PE+ii]                    ),
          .conv_dw_i   ( pres_depthwise   [(jj*NR_PE+ii)*BLOCK_SIZE+:BLOCK_SIZE] ), // check this
          .norm_i      ( norm_copy_datapath                       [jj*NR_PE+ii]      ),
          .streamin_i  ( load_streamin_cols_datapath         [jj*NR_PE+ii]      ),
          .conv_o      ( out_cols                        [jj*NR_PE+ii]      ),
          .ctrl_i      ( ctrl_accumulator                                   ),
          .flags_o     ( flags[jj].flags_accumulator    [ii]                )
        );

      end // accumulator_gen
    end // redundancy_gen

    for(genvar ii=0; ii<NR_PE; ii++) begin

      // Workaround
      hwpe_stream_assign i_to_out_cols_0 (.push_i(out_cols[ii]), .pop_o(out_cols_0[ii]));

      assign out_cols_1[ii].data  = out_cols[NR_PE+ii].data;
      assign out_cols_1[ii].valid = out_cols[NR_PE+ii].valid;
      assign out_cols_1[ii].strb  = out_cols[NR_PE+ii].strb;

      assign out_cols[NR_PE+ii].ready = (ctrl_i.resilience_mode) ? out_cols_0[ii].ready : out_cols_1[ii].ready;


      // hwpe_stream_assign i_to_store_out_cols (.push_i(store_out_cols_pre_check[ii]), .pop_o(store_out_cols[ii]));
      // assign store_out_cols_pre_check[NR_PE+ii].ready = store_out_cols[ii].ready; // temporary solution

      // hwpe_stream_demux_static
      // #(
      //   .NB_OUT_STREAMS(2)
      // ) i_load_in_demux_0
      // (
      //   .clk_i    ( clk_i                         ),
      //   .rst_ni   ( rst_ni                        ),
      //   .clear_i  ( clear_i                       ),
      //   .sel_i    ( '0                  ),
      //   .push_i   ( out_cols[ii]       ),
      //   .pop_o    ( out_cols_demuxed[2*ii+1:2*ii]   )
      // );

      hwpe_stream_mux_static i_out_cols_mux (
        .clk_i    ( clk_i            ),
        .rst_ni   ( rst_ni           ),
        .clear_i  ( clear_i          ),
        .sel_i    ( ctrl_i.active_datapath ),
        .push_0_i ( out_cols_0[ii]     ),
        .push_1_i ( out_cols_1[ii]     ),
        .pop_o    ( store_out_cols[ii] )
      );

      // Maurus's solution
      // TODO At the moment this solution isn't viable; there is a problem with the ready signal
      // Another problem of this module is that it's always on. I could at least add a clock-gating cell
      // hwpe_stream_copy_sink
      // #(
      //   .COPY_TYPE("COPY"),
      //   .DATA_WIDTH(NEUREKA_MEM_BANDWIDTH)
      // ) i_output_check
      // (
      //   .clk_i      ( clk_i            ),
      //   .rst_ni     ( rst_ni           ),
      //   .original_i ( out_cols[ii]       ),
      //   .copy_i     ( out_cols[NR_PE+ii] ),
      //   .fault_o    ( mismatch[ii]     )
      // );

      // Output Checker
      // It checks for mismatches at PE level
      always_comb
      begin
        if (1) // resilience_mode or maybe I can avoid it
          data_fault_d[ii] = out_cols_0[ii].data != out_cols_1[ii].data;
        else
          data_fault_d[ii] = '0;
      end
    end

    // Output Checker
    // It checks for mismatches at PE level
    // logic [NR_PE-1:0] mismatch_d, mismatch_q;
    // logic [NR_PE-1:0][N_COPIES-1:0][BLOCK_SIZE*NEUREKA_QA_IN-1:0] datatest; // TODO Change this name
    // for (genvar ii=0; ii<NR_PE; ii++) begin : check_out
    //   for (genvar jj=0; jj<N_COPIES; jj++) begin
    //     localparam ii_jj = jj*NR_PE+ii;
    //     assign datatest[ii][jj] = store_out_cols_pre_check[ii_jj].data;
    //   end
    //   assign mismatch_d[ii] = |(datatest[ii][0]^datatest[ii][1]);
    // end

    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        data_fault_q <= '0;
      end
      else begin
        data_fault_q <= data_fault_d;
      end
    end

    assign flags_o.mismatch_detected = |(data_fault_q) & ctrl_i.enable_outputcheck;
    always_comb
    begin
    if (flags_o.mismatch_detected)
      $info("[Neureka] Error detected!");
    end

    logic sel;
    assign sel = ctrl_i.active_datapath;

    assign flags_o.flags_double_infeat_buffer = (ctrl_i.resilience_mode == 1) ? flags[0].flags_double_infeat_buffer : flags[sel].flags_double_infeat_buffer;
    assign flags_o.flags_accumulator = (ctrl_i.resilience_mode == 1) ? flags[0].flags_accumulator : flags[sel].flags_accumulator;
    assign flags_o.flags_binconv_array = (ctrl_i.resilience_mode == 1) ? flags[0].flags_binconv_array : flags[sel].flags_binconv_array;

  end else begin : datapath_gen
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
    for (genvar ii=0; ii<NR_PE; ii++) begin : accumulator_gen

      ctrl_aq_t ctrl_accumulator;
      always_comb
      begin
        ctrl_accumulator = ctrl_i.ctrl_accumulator;
        ctrl_accumulator.enable_streamout = ctrl_i.enable_accumulator[ii];
        if(ctrl_i.enable_accumulator[ii] == '0) begin
          ctrl_accumulator.goto_normquant        = '0;
          ctrl_accumulator.goto_accum            = '0;
          ctrl_accumulator.goto_streamin         = '0;
          ctrl_accumulator.goto_streamout        = '0;
          ctrl_accumulator.goto_idle             = '0;
          ctrl_accumulator.ctrl_normquant        = '0;
          ctrl_accumulator.weight_offset         = '0;
          ctrl_accumulator.sample_shift          = '0;
        end
        if(ctrl_i.last_pe == ii) begin
          ctrl_accumulator.last_pe = 1'b1;
        end
      end

      neureka_accumulator_normquant #(
        .TP               ( TP_IN   ),
        .AP               ( TP_OUT  ),
        .ACC              ( 32      ),
        .OUTREG_NORMQUANT ( 1       )
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

  end

endmodule // neureka_engine
