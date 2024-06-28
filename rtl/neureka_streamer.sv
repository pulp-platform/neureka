/*
 * neureka_streamer.sv
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

module neureka_streamer 
  import neureka_package::*;
  import hwpe_stream_package::*;
  import hci_package::*;
#(
  parameter int unsigned TCDM_FIFO_DEPTH = 2,
  parameter int unsigned BW = NEUREKA_MEM_BANDWIDTH_EXT, // bandwidth
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  // input feat stream + handshake
  hwpe_stream_intf_stream.source feat_o,
  // input weight stream + handshake
  hwpe_stream_intf_stream.source weight_o,
  // input norm stream + handshake
  hwpe_stream_intf_stream.source norm_o,
  // input streamin stream + handshake
  hwpe_stream_intf_stream.source streamin_o,
  // output features + handshake
  hwpe_stream_intf_stream.sink   conv_i,
  // TCDM ports
  hci_core_intf.initiator        tcdm,
  // ECC error signals
  output errs_streamer_t         ecc_errors_o,
  // control channel
  input  ctrl_streamer_t         ctrl_i,
  output flags_streamer_t        flags_o
);

  localparam int unsigned UW  = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned IW  = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned EW  = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(tcdm);

  hci_streamer_ctrl_t  all_source_ctrl, wmem_source_ctrl;
  hci_streamer_flags_t all_source_flags, wmem_source_flags;
  flags_fifo_t tcdm_fifo_flags;
  flags_fifo_t tcdm_weight_fifo_flags;

  logic [1:0][ECC_N_CHUNK-1:0] r_data_single_err;
  logic [1:0][ECC_N_CHUNK-1:0] r_data_multi_err;
  logic [1:0]                  r_meta_single_err;
  logic [1:0]                  r_meta_multi_err;

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH_EXT )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) all_source (
    .clk ( clk_i )
  );
/* Dedicated Weightport related signals*/
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH_EXT )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) wmem_source (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH_EXT )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) weight[1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_MEM_BANDWIDTH_EXT )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) virt_source[3:0] (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .DW  ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .UW  ( UW                        ),
    .IW  ( IW                        ),
    .EW  ( EW                        ),
    .EHW ( EHW                       )
  ) virt_tcdm [0:2] (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .DW  ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .UW  ( UW                        ),
    .IW  ( IW                        ),
    .EW  ( EW                        ),
    .EHW ( EHW                       )
`ifndef SYNTHESIS
    ,
    .WAIVE_RSP3_ASSERT ( 1'b1 ), // waive RSP-3 on memory-side of HCI FIFO
    .WAIVE_RSP5_ASSERT ( 1'b1 )  // waive RSP-5 on memory-side of HCI FIFO
`endif
  ) tcdm_premux [0:1] (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .DW  ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .UW  ( UW                        ),
    .IW  ( IW                        ),
    .EW  ( EW                        ),
    .EHW ( EHW                       )
  ) tcdm_prefifo (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .DW  ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .UW  ( UW                        ),
    .IW  ( IW                        ),
    .EW  ( EW                        ),
    .EHW ( EHW                       )
`ifndef SYNTHESIS
    ,
    .WAIVE_RSP3_ASSERT ( 1'b1 ), // waive RSP-3 on memory-side of HCI FIFO
    .WAIVE_RSP5_ASSERT ( 1'b1 )  // waive RSP-5 on memory-side of HCI FIFO
`endif
  ) tcdm_prefilter (
    .clk ( clk_i )
  );

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(tcdm_preout) = '{
    DW:  NEUREKA_MEM_BANDWIDTH_EXT,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  UW,
    IW:  1,
    EW:  EW,
    EHW: EHW
  };
  hci_core_intf #(
    .DW  ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .UW  ( UW                        ),
    .IW  ( 1                         ),
    .EW  ( EW                        ),
    .EHW ( EHW                       )
`ifndef SYNTHESIS
    ,
    .WAIVE_RSP3_ASSERT ( 1'b1 ), // waive RSP-3 on memory-side of HCI FIFO
    .WAIVE_RSP5_ASSERT ( 1'b1 )  // waive RSP-5 on memory-side of HCI FIFO
`endif
  ) tcdm_preout (
    .clk ( clk_i )
  );

  hci_core_intf #(
    .DW  ( NEUREKA_MEM_BANDWIDTH_EXT ),
    .UW  ( UW                        ),
    .IW  ( IW                        ),
    .EW  ( EW                        ),
    .EHW ( EHW                       )
`ifndef SYNTHESIS
    ,
    .WAIVE_RSP3_ASSERT ( 1'b1 ), // waive RSP-3 on memory-side of HCI FIFO
    .WAIVE_RSP5_ASSERT ( 1'b1 )  // waive RSP-5 on memory-side of HCI FIFO
`endif
  ) tcdm_weight_prefilter (
    .clk ( clk_i )
  );

  logic wmem_enable, all_source_enable; 

  assign wmem_enable = (~ctrl_i.ld_st_mux_sel & ctrl_i.wmem_sel & (ctrl_i.ld_which_mux_sel == LD_WEIGHT_SEL)) | (ctrl_i.ld_which_mux_sel == LD_FEAT_WEIGHT_SEL);
  assign all_source_enable = (~ctrl_i.ld_st_mux_sel & (~wmem_enable)) | (ctrl_i.ld_which_mux_sel == LD_FEAT_WEIGHT_SEL);

  if (EW > 1) begin : gen_ecc_all_source
    hci_ecc_source #(
      .PASSTHROUGH_FIFO ( 1                          ),
      .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
    ) i_all_ecc_source (
      .clk_i       ( clk_i                         ),
      .rst_ni      ( rst_ni                        ),
      .test_mode_i ( test_mode_i                   ),
      .clear_i     ( clear_i | ctrl_i.clear_source ),
      .enable_i    ( all_source_enable             ),
      .tcdm        ( virt_tcdm [0]                 ),
      .stream      ( all_source                    ),
      .r_data_single_err_o  ( r_data_single_err[0] ),
      .r_data_multi_err_o   ( r_data_multi_err[0]  ),
      .r_meta_single_err_o  ( r_meta_single_err[0] ),
      .r_meta_multi_err_o   ( r_meta_multi_err[0]  ),
      .ctrl_i      ( all_source_ctrl               ),
      .flags_o     ( all_source_flags              )
    );
  end else begin : gen_all_source
    hci_core_source #(
      .PASSTHROUGH_FIFO ( 1                          ),
      .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
    ) i_all_source (
      .clk_i       ( clk_i                         ),
      .rst_ni      ( rst_ni                        ),
      .test_mode_i ( test_mode_i                   ),
      .clear_i     ( clear_i | ctrl_i.clear_source ),
      .enable_i    ( all_source_enable             ),
      .tcdm        ( virt_tcdm [0]                 ),
      .stream      ( all_source                    ),
      .ctrl_i      ( all_source_ctrl               ),
      .flags_o     ( all_source_flags              )
    );
  end

  if (EW > 1) begin : gen_ecc_weight_source
    hci_ecc_source #(
      .PASSTHROUGH_FIFO ( 1                          ),
      .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
    ) i_weight_ecc_source (
      .clk_i       ( clk_i                         ),
      .rst_ni      ( rst_ni                        ),
      .test_mode_i ( test_mode_i                   ),
      .clear_i     ( clear_i | ctrl_i.clear_source ),
      .enable_i    ( wmem_enable                   ),
      .tcdm        ( virt_tcdm [2]                 ),
      .stream      ( weight[1]                     ),
      .r_data_single_err_o  ( r_data_single_err[1] ),
      .r_data_multi_err_o   ( r_data_multi_err[1]  ),
      .r_meta_single_err_o  ( r_meta_single_err[1] ),
      .r_meta_multi_err_o   ( r_meta_multi_err[1]  ),
      .ctrl_i      ( wmem_source_ctrl              ),
      .flags_o     ( wmem_source_flags             )
    );
  end else begin : gen_weight_source
    hci_core_source #(
      .PASSTHROUGH_FIFO ( 1                          ),
      .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
    ) i_weight_source (
      .clk_i       ( clk_i                         ),
      .rst_ni      ( rst_ni                        ),
      .test_mode_i ( test_mode_i                   ),
      .clear_i     ( clear_i | ctrl_i.clear_source ),
      .enable_i    ( wmem_enable                   ),
      .tcdm        ( virt_tcdm [2]                 ),
      .stream      ( weight[1]                     ),
      .ctrl_i      ( wmem_source_ctrl              ),
      .flags_o     ( wmem_source_flags             )
    );
  end

  if (EW > 1) begin : gen_ecc_sink
    hci_ecc_sink #(
      .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
    ) i_ecc_sink (
      .clk_i       ( clk_i                       ),
      .rst_ni      ( rst_ni                      ),
      .test_mode_i ( test_mode_i                 ),
      .clear_i     ( clear_i | ctrl_i.clear_sink ),
      .enable_i    ( ctrl_i.ld_st_mux_sel        ),
      .tcdm        ( virt_tcdm [1]               ),
      .stream      ( conv_i                      ),
      .ctrl_i      ( ctrl_i.outfeat_sink_ctrl    ),
      .flags_o     ( flags_o.conv_sink_flags     )
    );
  end else begin : gen_sink
    hci_core_sink #(
      .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
    )i_sink (
      .clk_i       ( clk_i                       ),
      .rst_ni      ( rst_ni                      ),
      .test_mode_i ( test_mode_i                 ),
      .clear_i     ( clear_i | ctrl_i.clear_sink ),
      .enable_i    ( ctrl_i.ld_st_mux_sel        ),
      .tcdm        ( virt_tcdm [1]               ),
      .stream      ( conv_i                      ),
      .ctrl_i      ( ctrl_i.outfeat_sink_ctrl    ),
      .flags_o     ( flags_o.conv_sink_flags     )
    );
  end

  generate
    if(TCDM_FIFO_DEPTH > 0) begin : use_fifo_gen
      hci_core_mux_static #(
        .NB_CHAN             ( 2                     ),
        .`HCI_SIZE_PARAM(in) ( `HCI_SIZE_PARAM(tcdm) )
      ) i_ld_st_mux_static (
        .clk_i   ( clk_i                ),
        .rst_ni  ( rst_ni               ),
        .clear_i ( clear_i              ),
        .sel_i   ( ctrl_i.ld_st_mux_sel ),
        .in      ( virt_tcdm[0:1]       ),
        .out     ( tcdm_prefifo         )
      );

      hci_core_fifo #(
        .FIFO_DEPTH                      ( TCDM_FIFO_DEPTH       ),
        .`HCI_SIZE_PARAM(tcdm_initiator) ( `HCI_SIZE_PARAM(tcdm) )
      ) i_tcdm_fifo (
        .clk_i          ( clk_i                       ),
        .rst_ni         ( rst_ni                      ),
        .clear_i        ( clear_i | ctrl_i.clear_fifo ),
        .flags_o        ( tcdm_fifo_flags             ),
        .tcdm_target    ( tcdm_prefifo                ),
        .tcdm_initiator ( tcdm_prefilter              )
      );

      hci_core_fifo #(
        .FIFO_DEPTH                      ( TCDM_FIFO_DEPTH       ),
        .`HCI_SIZE_PARAM(tcdm_initiator) ( `HCI_SIZE_PARAM(tcdm) )
      ) i_weight_tcdm_fifo (
        .clk_i          ( clk_i                       ),
        .rst_ni         ( rst_ni                      ),
        .clear_i        ( clear_i | ctrl_i.clear_fifo ),
        .flags_o        ( tcdm_weight_fifo_flags      ),
        .tcdm_target    ( virt_tcdm[2]                ),
        .tcdm_initiator ( tcdm_weight_prefilter       )
      );
    end
    else begin : dont_use_fifo_gen
      hci_core_mux_static #(
        .NB_CHAN             ( 2                     ),
        .`HCI_SIZE_PARAM(in) ( `HCI_SIZE_PARAM(tcdm) )
      ) i_ld_st_mux_static (
        .clk_i   ( clk_i                ),
        .rst_ni  ( rst_ni               ),
        .clear_i ( clear_i              ),
        .sel_i   ( ctrl_i.ld_st_mux_sel ),
        .in      ( virt_tcdm[0:1]       ),
        .out     ( tcdm_prefilter       )
      );

      hci_core_assign i_weight_tcdm (
        .tcdm_target    ( virt_tcdm[2]          ),
        .tcdm_initiator ( tcdm_weight_prefilter )
      );
      assign tcdm_fifo_flags.empty = 1'b1;
      assign tcdm_weight_fifo_flags.empty = 1'b1;
    end
  endgenerate

  hci_core_r_valid_filter #(
    .`HCI_SIZE_PARAM(tcdm_target) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_tcdm_filter (
    .clk_i          ( clk_i                ),
    .rst_ni         ( rst_ni               ),
    .clear_i        ( clear_i              ),
    .enable_i       ( 1'b1                 ),
    .tcdm_target    ( tcdm_prefilter       ),
    .tcdm_initiator ( tcdm_premux[1]       )
  );

  hci_core_r_valid_filter #(
    .`HCI_SIZE_PARAM(tcdm_target) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_tcdm_weight_filter (
    .clk_i          ( clk_i                ),
    .rst_ni         ( rst_ni               ),
    .clear_i        ( clear_i              ),
    .enable_i       ( ctrl_i.wmem_sel      ),
    .tcdm_target    ( tcdm_weight_prefilter),
    .tcdm_initiator ( tcdm_premux[0]       )
  );

  hci_core_mux_ooo #(
    .NB_CHAN              ( 2                            ),
    .`HCI_SIZE_PARAM(out) ( `HCI_SIZE_PARAM(tcdm_preout) )
  ) i_mux_ooo (
    .clk_i            ( clk_i          ),
    .rst_ni           ( rst_ni         ),
    .clear_i          ( clear_i        ),
    .priority_force_i ( 1'b0           ),
    .priority_i       ( '0             ),
    .in               ( tcdm_premux    ),
    .out              ( tcdm_preout    )
  );

  hci_core_r_id_filter #(
    .`HCI_SIZE_PARAM(tcdm_target) ( `HCI_SIZE_PARAM(tcdm_preout) )
  ) i_tcdm_id_filter (
    .clk_i          ( clk_i       ),
    .rst_ni         ( rst_ni      ),
    .clear_i        ( clear_i     ),
    .enable_i       ( 1'b1        ),
    .tcdm_target    ( tcdm_preout ),
    .tcdm_initiator ( tcdm        )
  );

  always_comb
  begin : ld_which_ctrl_mux
    all_source_ctrl = '0;
    if(ctrl_i.ld_which_mux_sel == LD_FEAT_SEL)
      all_source_ctrl = ctrl_i.infeat_source_ctrl;
    else if(ctrl_i.ld_which_mux_sel == LD_WEIGHT_SEL) begin
      all_source_ctrl = ctrl_i.weight_source_ctrl;
      if(wmem_enable) all_source_ctrl.addressgen_ctrl.tot_len=0;
    end else if(ctrl_i.ld_which_mux_sel == LD_FEAT_WEIGHT_SEL)
      all_source_ctrl = ctrl_i.infeat_source_ctrl;
    else if(ctrl_i.ld_which_mux_sel == LD_NORM_SEL)
      all_source_ctrl = ctrl_i.norm_source_ctrl;
    else if(ctrl_i.ld_which_mux_sel == LD_STREAMIN_SEL)
      all_source_ctrl = ctrl_i.streamin_source_ctrl;
  end

  always_comb begin : weight_source_ctrl_mux
    wmem_source_ctrl = '0; 
    if(((ctrl_i.ld_which_mux_sel == LD_WEIGHT_SEL) & ctrl_i.wmem_sel) | (ctrl_i.ld_which_mux_sel == LD_FEAT_WEIGHT_SEL) )
      wmem_source_ctrl = ctrl_i.wmem_source_ctrl;
  end 

  assign flags_o.feat_source_flags = all_source_flags;
  assign flags_o.norm_source_flags = all_source_flags;
  assign flags_o.weight_source_flags = ctrl_i.wmem_sel ? wmem_source_flags : all_source_flags;
  assign flags_o.tcdm_fifo_empty = tcdm_fifo_flags.empty;

  logic [1:0] ld_which_mux_sel;
  assign ld_which_mux_sel = (ctrl_i.ld_which_mux_sel == LD_FEAT_SEL)   ? 2'b00 :
                            (ctrl_i.ld_which_mux_sel == LD_WEIGHT_SEL) ? 2'b01 :
                            (ctrl_i.ld_which_mux_sel == LD_FEAT_WEIGHT_SEL) ? 2'b00 :
                            (ctrl_i.ld_which_mux_sel == LD_NORM_SEL)   ? 2'b10 :
                                                                         2'b11; // LD_STREAMIN_SEL

  hwpe_stream_demux_static #(
    .NB_OUT_STREAMS ( 4 )
  ) i_all_source_demux (
    .clk_i   ( clk_i            ),
    .rst_ni  ( rst_ni           ),
    .clear_i ( clear_i          ),
    .sel_i   ( ld_which_mux_sel ),
    .push_i  ( all_source       ),
    .pop_o   ( virt_source      )
  );

  hwpe_stream_assign i_assign_feat     ( .push_i (virt_source[0]), .pop_o ( feat_o     ) );
  hwpe_stream_assign i_assign_weight   ( .push_i (virt_source[1]), .pop_o ( weight[0]  ) );
  hwpe_stream_assign i_assign_norm     ( .push_i (virt_source[2]), .pop_o ( norm_o     ) );
  hwpe_stream_assign i_assign_streamin ( .push_i (virt_source[3]), .pop_o ( streamin_o ) );

  hwpe_stream_mux_static i_weight_source_mux (
    .clk_i   ( clk_i            ),
    .rst_ni  ( rst_ni           ),
    .clear_i ( clear_i          ),
    .sel_i   ( ctrl_i.wmem_sel  ),
    .push_0_i( weight[0]        ),
    .push_1_i( weight[1]        ),
    .pop_o   ( weight_o         )
  );

// Error signaling

logic [1:0] valid_read, valid_handshake;
assign {valid_read[0], valid_read[1]} = {virt_tcdm[0].r_valid, virt_tcdm[2].r_valid};
assign {valid_handshake[0], valid_handshake[1]} = {virt_tcdm[0].req & virt_tcdm[0].gnt, virt_tcdm[2].req & virt_tcdm[2].gnt};

for (genvar i = 0; i < 2; i++) begin: error_bind
  assign ecc_errors_o.r_data_single_err[i] = r_data_single_err[i] & {ECC_N_CHUNK{valid_read[i]}};
  assign ecc_errors_o.r_data_multi_err [i] = r_data_multi_err [i] & {ECC_N_CHUNK{valid_read[i]}};
  assign ecc_errors_o.r_meta_single_err[i] = r_meta_single_err[i] & valid_handshake[i];
  assign ecc_errors_o.r_meta_multi_err [i] = r_meta_multi_err [i] & valid_handshake[i];
end


endmodule // neureka_streamer
