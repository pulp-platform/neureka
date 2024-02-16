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

module neureka_infeat_buffer #(
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
  input  ctrl_infeat_buffer_t     ctrl_i,
  output flags_infeat_buffer_t    flags_o,

  // input / output streams
  hwpe_stream_intf_stream.sink   feat_i [BLOCK_SIZE-1:0],
  hwpe_stream_intf_stream.source feat_o [INPUT_BUF_SIZE-1:0]
);

  localparam NW = INPUT_BUF_SIZE/BLOCK_SIZE;
  localparam AW = $clog2(NW);
  localparam DS = DW*BLOCK_SIZE;

  // Standard-cell memory based feature register
  logic                  scm_re;
  logic [AW-1:0]         scm_raddr;
  logic                  scm_we;
  logic                  scm_we_all;
  logic [AW-1:0]         scm_waddr;
  logic [DS-1:0]         scm_wdata;
  logic [NW-1:0][DS-1:0] scm_infeat_buffer;

  // Finite-state machine + counters
  state_infeat_buffer_t fsm_state_q, fsm_state_d;
  logic                vlen_cnt_clr, vlen_cnt_gl_en, vlen_cnt_en;
  logic [AW-1:0] vlen_cnt;
  logic [AW-1:0] vlen_cnt_d, vlen_cnt_q;
  logic [AW-1:0] vlen_cnt_fast_d, vlen_cnt_fast_q;

  neureka_infeat_buffer_scm_test_wrap #(
    .ADDR_WIDTH ( AW ),
    .DATA_WIDTH ( DS ),
    .NUM_WORDS  ( NW )
  ) i_infeat_buffer_scm (
    .clk_i          ( clk_i            ),
    .rst_ni         ( rst_ni           ),
    .clear_i        ( clear_i          ),
    .test_mode_i    ( test_mode_i      ),
    .re_i           ( scm_re           ),
    .raddr_i        ( scm_raddr        ),
    .rdata_o        (                  ),
    .we_i           ( scm_we           ),
    .we_all_i       ( scm_we_all       ),
    .waddr_i        ( scm_waddr        ),
    .wdata_i        ( scm_wdata        ),
    .infeat_buffer_o ( scm_infeat_buffer ),
    .BIST           (                  ),
    .CSN_T          (                  ),
    .WEN_T          (                  ),
    .A_T            (                  ),
    .D_T            (                  ),
    .Q_T            (                  )
  );

  // this mask is used to load only 36 pixels instead of 64 in 1x1 mode (see neureka_ctrl for other masks)
  logic [NEUREKA_INFEAT_BUFFER_SIZE_HW-1   :0] mask_1x1, mask_1x1_temp;
  logic [NEUREKA_INFEAT_BUFFER_SIZE_W-1 :0]  mask_1x1_s;
  assign mask_1x1_s = (1 << NEUREKA_PE_W) - 1;
  always_comb
  begin
    mask_1x1 = '1;
    mask_1x1 &= {NEUREKA_INFEAT_BUFFER_SIZE_W{mask_1x1_s}};
    mask_1x1 &= mask_1x1_temp;
  end

  for(genvar ii=0; ii<NEUREKA_INFEAT_BUFFER_SIZE_W; ii++) begin
    assign mask_1x1_temp[(ii+1)*NEUREKA_INFEAT_BUFFER_SIZE_W-1:ii*NEUREKA_INFEAT_BUFFER_SIZE_W] = {NEUREKA_INFEAT_BUFFER_SIZE_W{mask_1x1_s[ii]}};
  end


  // implicit padding --> comes from incomplete subtiles in the spatial dimensions --> always padded with 0
  // explicit padding --> requested through the padding register --> padded with config.padding_value
  // priority: implicit padding --> explicit padding --> normal feature
  assign scm_we     = feat_i[0].valid & (feat_i[0].ready);
  assign scm_we_all = '0;
  assign scm_waddr  = vlen_cnt;
  generate
    for(genvar ii=0; ii<BLOCK_SIZE/2; ii++) begin : scm_wdata_gen
      assign scm_wdata[(2*ii+1)*8-1:(2*ii)  *8] = ctrl_i.enable_implicit_padding[vlen_cnt] ? '0 : ctrl_i.enable_explicit_padding[vlen_cnt] ? ctrl_i.explicit_padding_value_lo: ctrl_i.feat_broadcast ? feat_i[0].data : feat_i[2*ii].data;
      assign scm_wdata[(2*ii+2)*8-1:(2*ii+1)*8] = ctrl_i.enable_implicit_padding[vlen_cnt] ? '0 : ctrl_i.enable_explicit_padding[vlen_cnt] ? ctrl_i.explicit_padding_value_hi : ctrl_i.feat_broadcast ? feat_i[0].data : feat_i[2*ii+1].data;
    end
  endgenerate
  assign scm_re    = '0;
  assign scm_raddr = '0;

  generate
    for(genvar ii=0; ii<INPUT_BUF_SIZE/BLOCK_SIZE; ii++) begin : input_buf_output_gen_outer
      for(genvar jj=0; jj<BLOCK_SIZE; jj++) begin : input_buf_output_gen_inner
        localparam int unsigned ii_jj = ii*BLOCK_SIZE+jj;
        assign feat_o[ii_jj].data = scm_infeat_buffer[ii][(jj+1)*8-1:jj*8];
        assign feat_o[ii_jj].strb = '1;
      end
    end
  endgenerate

  /* valid/ready broadcast */
  generate
    for(genvar ii=1; ii<BLOCK_SIZE; ii++) begin : broadcast_ready_gen
      assign feat_i[ii].ready = feat_i[0].ready;
    end
    for(genvar ii=1; ii<INPUT_BUF_SIZE; ii++) begin : broadcast_valid_gen
      assign feat_o[ii].valid = feat_o[0].valid;
    end
  endgenerate

  /* control */

  // finite-state machine + buffer virtual length counter
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : fsm_seq
    if(~rst_ni)
      fsm_state_q <= IB_IDLE;
    else if(clear_i)
      fsm_state_q <= IB_IDLE;
    else if(enable_i)
      fsm_state_q <= fsm_state_d;
  end


  always_comb
  begin : fsm_comb
    fsm_state_d          = fsm_state_q;
    feat_i[0].ready = 1'b0;
    feat_o[0].valid = 1'b0;
    vlen_cnt_clr    = 1'b1;
    vlen_cnt_gl_en  = 1'b0;

    case (fsm_state_q)
      // in IB_IDLE state, wait for a IB_LOAD / IB_EXTRACT command
      IB_IDLE: begin
        if(ctrl_i.goto_load)
          fsm_state_d = IB_LOAD;
        else if(ctrl_i.goto_extract)
          fsm_state_d = IB_EXTRACT;
      end

      // in IB_LOAD state, raise the ready for the stream hs until the buffer virtual length vlen has been reached
      IB_LOAD: begin
        feat_i[0].ready = 1'b1;
        vlen_cnt_gl_en = 1'b1;
        vlen_cnt_clr = 1'b0;
        if(scm_we && ({1'b0, vlen_cnt} == ctrl_i.load_len-1)) begin
          fsm_state_d = IB_EXTRACT; // an intermediate IB_IDLE state before going to IB_EXTRACT is necessary
                               // in any case due to the way the latch-based register works
          vlen_cnt_clr = 1'b1;
        end
      end

      // in IB_EXTRACT state, raise the valid for the feat hs until the buffer virtual length vlen has been reached
      IB_EXTRACT: begin
        feat_o[0].valid = 1'b1;
        vlen_cnt_gl_en = 1'b0;
        vlen_cnt_clr = 1'b1;
        if(ctrl_i.goto_idle) begin
          fsm_state_d = IB_IDLE;
        end
      end

      default : begin
        if(ctrl_i.goto_load)
          fsm_state_d = IB_LOAD;
        else if(ctrl_i.goto_extract)
          fsm_state_d = IB_EXTRACT;
      end

    endcase
  end

  // virtual length counter (counts words of BP*32 size in IB_LOAD mode and, for now, also in IB_EXTRACT mode)
  assign vlen_cnt_en = scm_we;

  assign vlen_cnt_d = vlen_cnt_q + 1;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : vlen_counter
    if(~rst_ni)
      vlen_cnt_q <= '0;
    else if(vlen_cnt_clr)
      vlen_cnt_q <= '0;
    else if(vlen_cnt_en)
      vlen_cnt_q <= vlen_cnt_d;
  end

  assign vlen_cnt_fast_d = (vlen_cnt_fast_q % NEUREKA_INFEAT_BUFFER_SIZE_W) == NEUREKA_PE_W-1 ? vlen_cnt_fast_q+3 : vlen_cnt_fast_q+1;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : vlen_counter_fast
    if(~rst_ni)
      vlen_cnt_fast_q <= '0;
    else if(vlen_cnt_clr)
      vlen_cnt_fast_q <= '0;
    else if(vlen_cnt_en)
      vlen_cnt_fast_q <= vlen_cnt_fast_d;
  end

  assign vlen_cnt = ctrl_i.filter_mode == NEUREKA_FILTER_MODE_1X1 ? vlen_cnt_fast_q : vlen_cnt_q;

  assign flags_o.state = fsm_state_q;

endmodule // neureka_infeat_buffer
