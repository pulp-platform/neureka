/*
 * neureka_infeat_buffer.sv
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

module neureka_double_infeat_buffer #(
  parameter int unsigned INPUT_BUF_SIZE = 2048,
  parameter int unsigned BLOCK_SIZE     = NEUREKA_BLOCK_SIZE,
  parameter int unsigned DW             = NEUREKA_QA_IN
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,

  // local enable and clear
  input  logic                   enable_i,
  input  logic                   clear_i,

  // control channel
  input  ctrl_double_infeat_buffer_t     ctrl_i,
  output flags_double_infeat_buffer_t    flags_o,

  // input / output streams
  hwpe_stream_intf_stream.sink   feat_i [BLOCK_SIZE-1:0],
  hwpe_stream_intf_stream.source feat_o [INPUT_BUF_SIZE-1:0]
);

  localparam NW = INPUT_BUF_SIZE/BLOCK_SIZE;
  localparam AW = $clog2(NW);
  localparam DS = DW*BLOCK_SIZE;

  hwpe_stream_intf_stream #(
  .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
  ,
  .BYPASS_VCR_ASSERT( 1'b1  ),
  .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) feat_input_buf [2*BLOCK_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
  .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
  ,
  .BYPASS_VCR_ASSERT( 1'b1  ),
  .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) feat_input_odd_buf [BLOCK_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
  .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
  ,
  .BYPASS_VCR_ASSERT( 1'b1  ),
  .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) feat_input_even_buf [BLOCK_SIZE-1:0] (
    .clk ( clk_i )
  );


  hwpe_stream_intf_stream #(
  .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
  ,
  .BYPASS_VCR_ASSERT( 1'b1  ),
  .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) feat_output_buf [2*INPUT_BUF_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
  .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
  ,
  .BYPASS_VCR_ASSERT( 1'b1  ),
  .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) feat_output_odd_buf [INPUT_BUF_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
  .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
  ,
  .BYPASS_VCR_ASSERT( 1'b1  ),
  .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) feat_output_even_buf [INPUT_BUF_SIZE-1:0] (
    .clk ( clk_i )
  );

  genvar ii;

  generate
    for(ii=0; ii<BLOCK_SIZE; ii++) begin 
      hwpe_stream_demux_static 
      #(
        .NB_OUT_STREAMS(2)
      ) i_feat_i_demux_static
      (
        .clk_i    ( clk_i                         ),
        .rst_ni   ( rst_ni                        ),
        .clear_i  ( clear_i                       ),
        .sel_i    ( ctrl_i.write                  ),
        .push_i   ( feat_i[ii]                    ),
        .pop_o    ( feat_input_buf[2*ii+1:2*ii]   )
      );
      hwpe_stream_assign i_to_even_feat_input_buf (.push_i(feat_input_buf[2*ii]), .pop_o(feat_input_even_buf[ii]));
      hwpe_stream_assign i_to_odd_feat_input_buf (.push_i(feat_input_buf[2*ii+1]), .pop_o(feat_input_odd_buf[ii]));
    end 
  endgenerate

  generate
    for(ii=0; ii<INPUT_BUF_SIZE; ii++) begin
      hwpe_stream_mux_static 
      #(
        // .NB_OUT_STREAMS(2)
      ) i_feat_o_mux_static
      (
        .clk_i    ( clk_i                   ),
        .rst_ni   ( rst_ni                  ),
        .clear_i  ( clear_i                 ),
        .sel_i    ( ctrl_i.read             ),
        .push_0_i ( feat_output_buf[2*ii]   ),
        .push_1_i ( feat_output_buf[2*ii+1] ),
        .pop_o    ( feat_o[ii]              )
      );
      hwpe_stream_assign i_even_to_feat_input_buf (.push_i(feat_output_even_buf[ii]), .pop_o(feat_output_buf[2*ii]));
      hwpe_stream_assign i_odd_to_feat_input_buf (.push_i(feat_output_odd_buf[ii]), .pop_o(feat_output_buf[2*ii+1]));
    end 
  endgenerate

  neureka_infeat_buffer #(
    .INPUT_BUF_SIZE ( INPUT_BUF_SIZE ),
    .BLOCK_SIZE     ( BLOCK_SIZE     ),
    .DW             ( NEUREKA_QA_IN     )
  ) i_odd_infeat_buffer (
    .clk_i       ( clk_i                            ),
    .rst_ni      ( rst_ni                           ),
    .test_mode_i ( test_mode_i                      ),
    .enable_i    ( enable_i                         ),
    .clear_i     ( clear_i                          ),
    .ctrl_i      ( ctrl_i.ctrl_odd_infeat_buffer     ),
    .flags_o     ( flags_o.flags_odd_infeat_buffer   ),
    .feat_i      ( feat_input_odd_buf               ),
    .feat_o      ( feat_output_odd_buf              )
  );

  neureka_infeat_buffer #(
    .INPUT_BUF_SIZE ( INPUT_BUF_SIZE ),
    .BLOCK_SIZE     ( BLOCK_SIZE     ),
    .DW             ( NEUREKA_QA_IN     )
  ) i_even_infeat_buffer (
    .clk_i       ( clk_i                            ),
    .rst_ni      ( rst_ni                           ),
    .test_mode_i ( test_mode_i                      ),
    .enable_i    ( enable_i                         ),
    .clear_i     ( clear_i                          ),
    .ctrl_i      ( ctrl_i.ctrl_even_infeat_buffer    ),
    .flags_o     ( flags_o.flags_even_infeat_buffer  ),
    .feat_i      ( feat_input_even_buf              ),
    .feat_o      ( feat_output_even_buf             )
  );

  assign flags_o.write = ctrl_i.write;
  assign flags_o.read = ctrl_i.read;

endmodule // neureka_infeat_buffer
