/*
 * neureka_top.sv
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
import hwpe_ctrl_package::*;
import hci_package::*;

module neureka_top #(
  parameter int unsigned TP_IN     = NEUREKA_TP_IN,   // number of input elements processed per cycle
  parameter int unsigned TP_OUT    = NEUREKA_TP_OUT,  // number of output elements processed per cycle
  parameter int unsigned CNT       = VLEN_CNT_SIZE,   // counter size
  parameter int unsigned ID        = ID_WIDTH,
  parameter int unsigned BW        = NEUREKA_MEM_BANDWIDTH_EXT, // NEUREKA_MEM_BANDWIDTH
  parameter int unsigned DW        = NEUREKA_STREAM_BANDWIDTH,

  parameter int unsigned N_CORES   = NR_CORES,
  parameter int unsigned N_CONTEXT = NR_CONTEXT
) (
  // global signals
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  logic                                  test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  output logic                                  busy_o,
  // tcdm master ports
  hci_core_intf.master                          tcdm,
  // periph slave port
  hwpe_ctrl_intf_periph.slave                   periph
);

  // signals
  logic enable;
  logic clear;

  ctrl_streamer_t  streamer_ctrl;
  flags_streamer_t streamer_flags;
  ctrl_engine_t    engine_ctrl;
  flags_engine_t   engine_flags;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH(DW)
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) feat   (.clk(clk_i));

  hwpe_stream_intf_stream #(
    .DATA_WIDTH(NEUREKA_MEM_BANDWIDTH_EXT)
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) weight (.clk(clk_i));

  hwpe_stream_intf_stream #(
    .DATA_WIDTH(NEUREKA_MEM_BANDWIDTH)
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) norm   (.clk(clk_i));

  hwpe_stream_intf_stream #(
    .DATA_WIDTH(NEUREKA_MEM_BANDWIDTH)
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) streamin   (.clk(clk_i));

  hwpe_stream_intf_stream #(
    .DATA_WIDTH(NEUREKA_MEM_BANDWIDTH)
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) conv   (.clk(clk_i));

  neureka_engine i_engine (
    .clk_i         ( clk_i        ),
    .rst_ni        ( rst_ni       ),
    .test_mode_i   ( test_mode_i  ),
    .enable_i      ( enable       ),
    .clear_i       ( clear        ),
    .load_in       ( feat         ),
    .load_weight   ( weight       ),
    .load_norm     ( norm         ),
    .load_streamin ( streamin     ),
    .store_out     ( conv         ),
    .ctrl_i        ( engine_ctrl  ),
    .flags_o       ( engine_flags )
  );

  neureka_streamer #(
    .BW ( NEUREKA_MEM_BANDWIDTH_EXT )
  ) i_streamer (
    .clk_i       ( clk_i          ),
    .rst_ni      ( rst_ni         ),
    .test_mode_i ( test_mode_i    ),
    .enable_i    ( enable         ),
    .clear_i     ( clear          ),
    .feat_o      ( feat           ),
    .weight_o    ( weight         ),
    .norm_o      ( norm           ),
    .streamin_o  ( streamin       ),
    .conv_i      ( conv           ),
    .tcdm        ( tcdm           ),
    .ctrl_i      ( streamer_ctrl  ),
    .flags_o     ( streamer_flags )
  );

  neureka_ctrl #(
    .ID      ( ID      ),
    .N_CORES ( N_CORES )
  ) i_ctrl (
    .clk_i            ( clk_i          ),
    .rst_ni           ( rst_ni         ),
    .test_mode_i      ( test_mode_i    ),
    .busy_o           ( busy_o         ),
    .evt_o            ( evt_o          ),
    .clear_o          ( clear          ),
    .ctrl_streamer_o  ( streamer_ctrl  ),
    .flags_streamer_i ( streamer_flags ),
    .ctrl_engine_o    ( engine_ctrl    ),
    .flags_engine_i   ( engine_flags   ),
    .periph           ( periph         )
  );

  assign enable = busy_o;

endmodule // neureka_top
