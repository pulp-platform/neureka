/*
 * neureka_binconv_block.sv
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

module neureka_binconv_column #(
  parameter int unsigned BLOCK_SIZE = NEUREKA_BLOCK_SIZE,           
  parameter int unsigned COLUMN_SIZE= NEUREKA_COLUMN_SIZE,
  parameter int unsigned TP_IN      = NEUREKA_TP_IN,                
  parameter int unsigned PIPELINE   = 1
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,
  // input activation stream + handshake
  hwpe_stream_intf_stream.sink   activation_i [COLUMN_SIZE-1:0],
  // input weight stream + handshake
  hwpe_stream_intf_stream.sink   weight_i[COLUMN_SIZE-1:0],
  // output features + handshake
  hwpe_stream_intf_stream.source col_pres_o,
  // control channel
  input  ctrl_binconv_col_t    ctrl_i,
  output flags_binconv_block_t   flags_o
);

  logic clk_gated;
  cluster_clock_gating i_hier_block_gate (
    .clk_i     ( clk_i              ),
    .en_i      ( enable_i | clear_i ),
    .test_en_i ( test_mode_i        ),
    .clk_o     ( clk_gated          )
  );

  ///////////////////////////////////////////
  // Local Params, Interfaces, and Signals //
  ///////////////////////////////////////////

  localparam COL_NON_SCALED_WIDTH = NEUREKA_QA_IN+$clog2(COLUMN_SIZE)+NEUREKA_QA_16BIT;
  localparam COL_SCALED_WIDTH = NEUREKA_QA_IN+$clog2(COLUMN_SIZE)+NEUREKA_QA_16BIT+8;


  // internal weight interface
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( 1 )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) weight_int [COLUMN_SIZE-1:0] (
    .clk ( clk_i )
  );

  // BinConv result interface
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( NEUREKA_QA_IN )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) popcount [COLUMN_SIZE-1:0] (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( COL_NON_SCALED_WIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres_nonscaled (
    .clk ( clk_i )
  );

  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( COL_SCALED_WIDTH )
`ifndef SYNTHESIS
    ,
    .BYPASS_VCR_ASSERT( 1'b1  ),
    .BYPASS_VDR_ASSERT( 1'b1  )
`endif
  ) pres (
    .clk ( clk_i )
  );

  logic clear_int;

  logic [COL_NON_SCALED_WIDTH-1:0] binconv_col_pres_nonscaled_data, binconv_col_pres_nonscaled_data_d,  binconv_col_pres_nonscaled_data_q;
  logic                            binconv_col_pres_nonscaled_valid, binconv_col_pres_nonscaled_valid_d, binconv_col_pres_nonscaled_valid_q;

  logic [COL_SCALED_WIDTH-1:0] binconv_col_pres_data, binconv_col_pres_data_d, binconv_col_pres_data_q;
  logic                        binconv_col_pres_valid_d, binconv_col_pres_valid_q;

  ctrl_scale_t scale_ctrl, scale_ctrl_d, scale_ctrl_q;

  logic [COLUMN_SIZE-1:0] [NEUREKA_QA_IN-1:0]     popcount_data;

  assign clear_int = clear_i | ctrl_i.clear;

  ///////////////////////////////
  // BinConv and Scale Modules //
  ///////////////////////////////
  // iterate over all COLUMN_SIZE BinConvs in a singe block

  generate

    for(genvar ii=0; ii<COLUMN_SIZE; ii+=1) begin : sop_gen

      assign weight_int[ii].data  = ctrl_i.weight_offset ? 1    : weight_i[ii].data;
      assign weight_int[ii].valid = ctrl_i.weight_offset ? 1'b1 : weight_i[ii].valid;
      assign weight_int[ii].strb  = weight_i[ii].strb;

      assign popcount[ii].valid = (ctrl_i.weight_offset==1'b0)                  ? activation_i[ii].valid & activation_i[ii].ready & weight_int[ii].valid & weight_int[ii].ready :
                                  (ctrl_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW) ? activation_i[ii].valid & activation_i[ii].ready & ~ctrl_i.invalidate :
                                  (ctrl_i.block_cnt=='0)                        ? activation_i[ii].valid : '0;
      assign popcount[ii].strb  = '1;

      // 1x8bit "multipliers" (i.e., simple multiplexers)
      assign popcount[ii].data  = ctrl_i.dw_weight_offset & weight_int[ii].data & ctrl_i.enable_block[ii]? activation_i[ii].data : '0;
      assign weight_i[ii].ready = weight_int[0].ready;

      // ========================================================================
      // INPUT STREAMER HANDSHAKING
      // ========================================================================

      always_comb
      begin : ready_propagation
        case({activation_i[ii].valid, weight_int[ii].valid})
          2'b00 : begin
            activation_i[ii].ready = popcount[ii].ready;
            weight_int[ii].ready   = popcount[ii].ready;
          end
          2'b01 : begin
            activation_i[ii].ready = popcount[ii].ready;
            weight_int[ii].ready   = 1'b0;
          end
          2'b10 : begin
            activation_i[ii].ready = 1'b0;
            weight_int[ii].ready   = popcount[ii].ready;
          end
          2'b11 : begin
            activation_i[ii].ready = popcount[ii].ready;
            weight_int[ii].ready   = popcount[ii].ready;
          end
        endcase
      end

      assign popcount_data[ii] = popcount[ii].data;
      assign popcount[ii].ready = pres_nonscaled.ready;

    end // sop_gen

    if (PIPELINE ==1 ) begin : pipe_stage_gen

      always_ff @(posedge clk_gated or negedge rst_ni)
      begin
        if(~rst_ni) begin
          binconv_col_pres_nonscaled_data_q       <= '0;
          binconv_col_pres_nonscaled_valid_q      <= '0;
          scale_ctrl_q <= '0;
        end
        else begin
          binconv_col_pres_nonscaled_data_q       <= binconv_col_pres_nonscaled_data_d;
          binconv_col_pres_nonscaled_valid_q      <= binconv_col_pres_nonscaled_valid_d;
          scale_ctrl_q <= scale_ctrl_d;
        end
      end

    end
    else begin

      assign binconv_col_pres_nonscaled_data_q = binconv_col_pres_nonscaled_data;
      assign binconv_col_pres_nonscaled_valid_q = binconv_col_pres_nonscaled_valid;
      assign scale_ctrl_q = scale_ctrl;

    end

  endgenerate


  //////////////////////////////////
  // Column-level reduction
  //////////////////////////////////
  always_comb
  begin
    binconv_col_pres_nonscaled_data = '0;
    for(int i=0; i<COLUMN_SIZE; i+=1) begin
      binconv_col_pres_nonscaled_data += popcount_data[i];
    end
    binconv_col_pres_nonscaled_data_d = binconv_col_pres_nonscaled_data_q;
    binconv_col_pres_nonscaled_valid_d = binconv_col_pres_nonscaled_valid_q;
    scale_ctrl_d = scale_ctrl_q;
    if(clear_int) begin 
      binconv_col_pres_nonscaled_data_d = '0;
      binconv_col_pres_nonscaled_valid_d = '0;
      scale_ctrl_d = '0;
    end else if(enable_i) begin 
      binconv_col_pres_nonscaled_data_d = binconv_col_pres_nonscaled_data;
      binconv_col_pres_nonscaled_valid_d = binconv_col_pres_nonscaled_valid;
      scale_ctrl_d = scale_ctrl;
    end 
  end

  assign binconv_col_pres_nonscaled_valid = popcount[0].valid;

  assign pres_nonscaled.strb  = '1;
  assign pres_nonscaled.data  = binconv_col_pres_nonscaled_data_q;
  assign pres_nonscaled.valid = binconv_col_pres_nonscaled_valid_q;

  //////////////////////////////////
  // Scaling factor
  //////////////////////////////////
  neureka_scale #(
    .INP_ACC     ( COL_NON_SCALED_WIDTH ),
    .OUT_ACC     ( COL_SCALED_WIDTH     ),
    .N_SHIFTS    ( 8                    )
  ) i_binconv_scale (
    .clk_i       ( clk_gated      ),
    .rst_ni      ( rst_ni         ),
    .test_mode_i ( test_mode_i    ),
    .data_i      ( pres_nonscaled ),
    .data_o      ( pres           ),
    .ctrl_i      ( scale_ctrl_q   ),
    .flags_o     (                )
  );

  assign flags_o = '0; // FIXME

  ////////////////////////
  // Output Assignments //
  ////////////////////////

  assign col_pres_o.valid = binconv_col_pres_valid_q;
  assign col_pres_o.data  = binconv_col_pres_data_q;

  assign pres.ready = col_pres_o.ready;

  ///////////////
  // Registers //
  ///////////////
  // registers for block results
  logic  pres_handshake;
  assign pres_handshake = pres.valid & pres.ready;
  assign binconv_col_pres_data = pres_handshake ? pres.data : binconv_col_pres_data_q; 

 always_comb begin
    binconv_col_pres_data_d = binconv_col_pres_data_q;
    binconv_col_pres_valid_d = binconv_col_pres_valid_q;
    if(clear_int) begin 
      binconv_col_pres_data_d = '0;
      binconv_col_pres_valid_d = '0;
    end else begin 
      binconv_col_pres_data_d = binconv_col_pres_data;
      if(pres.ready)
        binconv_col_pres_valid_d = pres.valid;
    end  
  end   

  always_ff @(posedge clk_gated or negedge rst_ni)
    begin
      if(~rst_ni) begin 
        binconv_col_pres_data_q <= '0;
        binconv_col_pres_valid_q <= '0;
      end else begin 
        binconv_col_pres_data_q <= binconv_col_pres_data_d;
        binconv_col_pres_valid_q <= binconv_col_pres_valid_d;
      end 
    end

  generate
    assign scale_ctrl.shift_sel = (ctrl_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW & ctrl_i.weight_offset) ? '0 :
                                  (ctrl_i.filter_mode == NEUREKA_FILTER_MODE_1X1)     ? ctrl_i.scale_shift :
                                  ctrl_i.block_cnt;
    assign scale_ctrl.invert = 1'b0;
  endgenerate

endmodule // neureka_binconv_column
