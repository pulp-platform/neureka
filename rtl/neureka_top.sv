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
 
`include "hci_helpers.svh"

module neureka_top
  import neureka_package::*;
  import hwpe_ctrl_package::*;
  import hci_package::*;
#(
  parameter int unsigned TP_IN     = NEUREKA_TP_IN,   // number of input elements processed per cycle
  parameter int unsigned TP_OUT    = NEUREKA_TP_OUT,  // number of output elements processed per cycle
  parameter int unsigned CNT       = VLEN_CNT_SIZE,   // counter size
  parameter int unsigned ID        = ID_WIDTH,
  parameter int unsigned BW        = NEUREKA_MEM_BANDWIDTH_EXT, // NEUREKA_MEM_BANDWIDTH
  parameter int unsigned DW        = NEUREKA_STREAM_BANDWIDTH,
  parameter int unsigned REGFILE_N_EVT = 2,

  parameter int unsigned N_CORES   = NR_CORES,
  parameter int unsigned N_CONTEXT = NR_CONTEXT,

  parameter int unsigned PE_H      = NEUREKA_PE_H_DEFAULT,
  parameter int unsigned PE_W      = NEUREKA_PE_W_DEFAULT,

  parameter int unsigned HMR_DELAY  = 1,
  parameter bit          ENGINE_HMR = 1'b1,
  parameter bit          CTRL_TMR   = 1'b1,

  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
) (
  // global signals
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  logic                                  test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  output logic                                  busy_o,
  // tcdm master ports
  hci_core_intf.initiator                       tcdm,
  // periph slave port
  hwpe_ctrl_intf_periph.slave                   periph
);

  // signals
  logic enable;
  logic clear;
  logic ctrl_tmr_error_d, ctrl_tmr_error_q;

  ctrl_streamer_t  streamer_ctrl;
  flags_streamer_t streamer_flags;
  errs_streamer_t  streamer_ecc_errs;
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

  neureka_engine #(
    .PE_H       ( PE_H ),
    .PE_W       ( PE_W ),
    .HMR        ( ENGINE_HMR ),
    .HMR_DELAY  ( HMR_DELAY  )
  ) i_engine (
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
    .BW                    ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm)     )
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
    .ecc_errors_o( streamer_ecc_errs ),
    .ctrl_i      ( streamer_ctrl  ),
    .flags_o     ( streamer_flags )
  );

  localparam int unsigned N_COPIES = CTRL_TMR ? 3 : 1;

  typedef struct packed {
    logic                                  busy;
    logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt;
    logic                                  clear;
    ctrl_streamer_t                        streamer_ctrl;
    ctrl_engine_t                          engine_ctrl;
    logic                                  periph_gnt;
    logic [31:0]                           periph_r_data;
    logic                                  periph_r_valid;
    logic [ID-1:0]                         periph_r_id;
  } ctrl_out_t;

  ctrl_out_t [N_COPIES-1:0] ctrl_out;
  ctrl_out_t                ctrl_voted;

  hwpe_ctrl_intf_periph #(.ID_WIDTH(ID)) ctrl_periph [N_COPIES-1:0] ( .clk (clk_i));

  neureka_ctrl #(
    .ID      ( ID      ),
    .N_CORES ( N_CORES ),
    .PE_H    ( PE_H    ),
    .PE_W    ( PE_W    )
  ) i_ctrl (
    .clk_i            ( clk_i                      ),
    .rst_ni           ( rst_ni                     ),
    .test_mode_i      ( test_mode_i                ),
    .busy_o           ( ctrl_out[0].busy          ),
    .evt_o            ( ctrl_out[0].evt           ),
    .clear_o          ( ctrl_out[0].clear         ),
    .ctrl_streamer_o  ( ctrl_out[0].streamer_ctrl ),
    .flags_streamer_i ( streamer_flags             ),
    .ctrl_engine_o    ( ctrl_out[0].engine_ctrl   ),
    .flags_engine_i   ( engine_flags               ),
    .errs_streamer_i  ( streamer_ecc_errs          ),
    .periph           ( ctrl_periph[0]             ),
    .ctrl_tmr_error_i ( ctrl_tmr_error_q           )
  );

  always_comb begin
    // Request
    ctrl_periph[0].req  = periph.req;
    ctrl_periph[0].add  = periph.add;
    ctrl_periph[0].wen  = periph.wen;
    ctrl_periph[0].be   = periph.be;
    ctrl_periph[0].data = periph.data;
    ctrl_periph[0].id   = periph.id;

    // Response
    ctrl_out[0].periph_gnt     = ctrl_periph[0].gnt;
    ctrl_out[0].periph_r_data  = ctrl_periph[0].r_data;
    ctrl_out[0].periph_r_valid = ctrl_periph[0].r_valid;
    ctrl_out[0].periph_r_id    = ctrl_periph[0].r_id;
  end

  always_comb begin
    // Ctrl signals
    busy_o         = ctrl_voted.busy;
    enable         = ctrl_voted.busy;
    evt_o          = ctrl_voted.evt;
    clear          = ctrl_voted.clear;
    streamer_ctrl  = ctrl_voted.streamer_ctrl;
    engine_ctrl    = ctrl_voted.engine_ctrl;
    // Periph response
    periph.gnt     = ctrl_voted.periph_gnt;
    periph.r_data  = ctrl_voted.periph_r_data;
    periph.r_valid = ctrl_voted.periph_r_valid;
    periph.r_id    = ctrl_voted.periph_r_id;
  end

  if (CTRL_TMR) begin : gen_ctrl_tmr

    ctrl_out_t [N_COPIES-1:0] ctrl_out_mask;

    bitwise_TMR_voter #(
      .DataWidth ($bits(ctrl_out_t))
    ) tmr_ctrl_voter (
      .a_i         (ctrl_out[0] & ~ctrl_out_mask[0]),
      .b_i         (ctrl_out[1] & ~ctrl_out_mask[1]),
      .c_i         (ctrl_out[2] & ~ctrl_out_mask[2]),
      .majority_o  (ctrl_voted),
      .error_o     (ctrl_tmr_error_d),
      .error_cba_o ()
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) ctrl_tmr_error_q <= 1'b0;
      else         ctrl_tmr_error_q <= ctrl_tmr_error_d;
    end

    for (genvar ii=0; ii<3; ii++) begin : gen_ctrl_out_masks
      // We need to mask signals which are not driven, otherwise the voter cannot
      // generate proper error signals
      always_comb begin
        ctrl_out_mask[ii] = '0;

        ctrl_out_mask[ii].engine_ctrl.ctrl_binconv_array.ctrl_pe.ctrl_col.scale_shift      = '1;
        ctrl_out_mask[ii].engine_ctrl.ctrl_binconv_array.ctrl_pe.ctrl_col.dw_weight_offset = '1;
        ctrl_out_mask[ii].engine_ctrl.ctrl_binconv_array.ctrl_pe.ctrl_col.block_cnt        = '1;
        ctrl_out_mask[ii].engine_ctrl.ctrl_binconv_array.ctrl_pe.ctrl_col.invalidate       = '1;

        if (!ctrl_out[ii].periph_r_valid)
          ctrl_out_mask[ii].periph_r_data = '1;
      end
    end

    for (genvar ii=1; ii<3; ii++) begin : gen_ctrl_copies

      always_comb begin
        // Request
        ctrl_periph[ii].req  = periph.req;
        ctrl_periph[ii].add  = periph.add;
        ctrl_periph[ii].wen  = periph.wen;
        ctrl_periph[ii].be   = periph.be;
        ctrl_periph[ii].data = periph.data;
        ctrl_periph[ii].id   = periph.id;

        // Response
        ctrl_out[ii].periph_gnt     = ctrl_periph[ii].gnt;
        ctrl_out[ii].periph_r_data  = ctrl_periph[ii].r_data;
        ctrl_out[ii].periph_r_valid = ctrl_periph[ii].r_valid;
        ctrl_out[ii].periph_r_id    = ctrl_periph[ii].r_id;
      end

      neureka_ctrl #(
        .ID      ( ID      ),
        .N_CORES ( N_CORES ),
        .PE_H    ( PE_H    ),
        .PE_W    ( PE_W    )
      ) i_ctrl (
        .clk_i            ( clk_i                      ),
        .rst_ni           ( rst_ni                     ),
        .test_mode_i      ( test_mode_i                ),
        .busy_o           ( ctrl_out[ii].busy          ),
        .evt_o            ( ctrl_out[ii].evt           ),
        .clear_o          ( ctrl_out[ii].clear         ),
        .ctrl_streamer_o  ( ctrl_out[ii].streamer_ctrl ),
        .flags_streamer_i ( streamer_flags             ),
        .ctrl_engine_o    ( ctrl_out[ii].engine_ctrl   ),
        .flags_engine_i   ( engine_flags               ),
        .errs_streamer_i  ( streamer_ecc_errs          ),
        .periph           ( ctrl_periph[ii]            ),
        .ctrl_tmr_error_i ( ctrl_tmr_error_q           )
      );
    end
  end else begin : gen_ctrl_no_tmr
    assign ctrl_voted = ctrl_out[0];
    assign ctrl_tmr_error_d = 1'b0;
    assign ctrl_tmr_error_q = 1'b0;
  end

endmodule // neureka_top
