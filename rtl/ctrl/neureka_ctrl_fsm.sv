/*
 * neureka_ctrl_fsm.sv
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

module neureka_ctrl_fsm
#(
  parameter int unsigned NUM_PE = NEUREKA_NUM_PE_MAX
)
(
  // global signals
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             test_mode_i,
  input  logic             clear_i,
  input  logic             start_i,
  // ctrl & flags
  input  flags_engine_t    flags_engine_i,
  input  flags_streamer_t  flags_streamer_i,
  input  config_neureka_t     config_i,
  output state_neureka_t      state_o,
  output logic             state_change_o,
  output logic             active_datapath_o,
  output logic             active_datapath_change_o,
  output logic             double_active_datapath_o, // TODO Find a more suitable name
  input  logic [1:0]       uloop_ready_i,
  output logic             prefetch_o,
  output logic             prefetch_pulse_o,
  output index_neureka_t      index_o,
  output base_addr_neureka_t  base_addr_o,
  output index_neureka_t      next_index_o,
  output base_addr_neureka_t  next_base_addr_o
);

  /* signal declarations */
  state_neureka_t state_d, state_q;
  logic state_change_d, state_change_q;

  logic active_datapath_change, active_datapath_change_sticky, active_datapath_d, active_datapath_q;
  logic single_load;

  ctrl_uloop_t       ctrl_uloop, ctrl_uloop_1;
  flags_uloop_t      flags_uloop, flags_uloop_1;
  uloop_code_t       code_uloop_0, code_uloop_1;
  logic [17:0][31:0] ro_reg;

  ctrl_uloop_t       ctrl_uloop_aux;
  flags_uloop_t      flags_uloop_aux;
  uloop_code_t       code_uloop_aux;
  logic [3:0][31:0] ro_reg_aux;
  logic [1:0][31:0] uloop_aux_set;
  logic [3:0][31:0] uloop_1_set;

  logic prefetch_done;

  index_neureka_t     index, index_d, index_q;
  index_neureka_t     next_index, next_index_d, next_index_q;
  index_update_neureka_t index_update, index_update_d, index_update_q;
  base_addr_neureka_t base_addr, base_addr_d, base_addr_q;
  base_addr_neureka_t next_base_addr, next_base_addr_d, next_base_addr_q;

  index_neureka_t        index_lcs;
  // index_neureka_t     next_index_lcs;
  // index_update_neureka_t index_update_lcs;
  base_addr_neureka_t    base_addr_lcs;
  // base_addr_neureka_t next_base_addr_lcs;

  index_neureka_t     index_aux;
  // index_neureka_t     next_index_aux;
  // index_update_neureka_t index_update_aux;
  base_addr_neureka_t base_addr_aux;
  // base_addr_neureka_t next_base_addr_aux;

  logic sticky_error;

  logic streamin_en;
  logic next_valid_sticky;

  logic prefetch_done_d, prefetch_done_q;
  logic prefetch_valid_d, prefetch_valid_q;
  logic accum_done_d, accum_done_q;
  logic prefetch_matrixvec_done;
  logic load_done;
  logic streamout_done;
  logic done;

  assign prefetch_o               = prefetch_valid_q;
  assign load_done                = (flags_engine_i.flags_double_infeat_buffer.flags_odd_infeat_buffer.state == IB_EXTRACT)|(flags_engine_i.flags_double_infeat_buffer.flags_even_infeat_buffer.state == IB_EXTRACT) & (config_i.resilience_mode == 1 || config_i.subtile_nb_wo == 1 || single_load  ? 1 : active_datapath_q == 1);
  assign prefetch_done            = ((flags_engine_i.flags_double_infeat_buffer.flags_odd_infeat_buffer.state == IB_EXTRACT)&(~flags_engine_i.flags_double_infeat_buffer.read)) || ((flags_engine_i.flags_double_infeat_buffer.flags_even_infeat_buffer.state == IB_EXTRACT) & (flags_engine_i.flags_double_infeat_buffer.read));
  assign prefetch_matrixvec_done  = (prefetch_done_d & accum_done_d)|(prefetch_done_d & accum_done_q)|(prefetch_done_q & accum_done_d)|(prefetch_done_q & accum_done_q);
  assign streamout_done           = flags_engine_i.flags_accumulator[config_i.last_pe].state == AQ_STREAMOUT_DONE && (config_i.resilience_mode == 1 || active_datapath_q == 1 || ( ~active_datapath_change_sticky));
  assign done                     = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && config_i.subtile_nb_ko == 2) ? (flags_uloop.done && flags_uloop_1.done) : flags_uloop.done; // TODO Check this for nb_ko > 2

  state_aq_t accumulators_state;
  assign accumulators_state = flags_engine_i.flags_accumulator[config_i.last_pe].state;

  /* finite state machine */
  always_ff @(posedge clk_i or negedge rst_ni)
  begin : fsm_sequential
    if(~rst_ni) begin
      state_q <= IDLE;
      state_change_q <= '0;
    end
    else begin
      state_q <= state_d;
      state_change_q <= state_change_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) 
  begin : prefetch_check_ff
    if(~rst_ni) begin
      accum_done_q      <= 0;
      prefetch_done_q   <= 0;
      prefetch_valid_q  <= 0; 
    end else begin
      accum_done_q      <= accum_done_d;
      prefetch_done_q   <= prefetch_done_d;
      prefetch_valid_q  <= prefetch_valid_d;
    end
  end

  assign prefetch_valid_d = clear_i ? '0 : (state_d == UPDATEIDX & state_change_o) ? 0 : 
                            flags_uloop.next_valid ? 1'b1 : 
                            prefetch_valid_q;
  assign accum_done_d     = clear_i ? '0 : (state_q == MATRIXVEC) ? (accumulators_state == AQ_ACCUM_DONE) ? 1'b1 : accum_done_q :0;
  assign prefetch_done_d  = clear_i ? '0 : (state_q == MATRIXVEC) ? (~config_i.prefetch ? 1'b1 : (flags_uloop.next_done? 1'b1 : (prefetch_done ? 1'b1 : prefetch_done_q))) : 
                            ~config_i.prefetch;

  always_comb
  begin: fsm_next_state
    state_d = state_q;
    state_change_d = 1'b0;

    case(state_q)

      IDLE: begin
        if(start_i) begin
          state_d = LOAD;
          state_change_d = 1'b1;
        end
      end

      LOAD: begin
        if(load_done) begin
          if(streamin_en)
            state_d = STREAMIN;
          else
            state_d = WEIGHTOFFS;
            state_change_d = 1'b1;
        end
      end

      WEIGHTOFFS: begin
          if(accumulators_state == AQ_ACCUM_DONE) begin
              state_d = MATRIXVEC;
              state_change_d = 1'b1;
          end
        end

      STREAMIN: begin
        if(accumulators_state == AQ_STREAMIN_DONE) begin
          state_d = WEIGHTOFFS;
          state_change_d = 1'b1;
        end
      end

      MATRIXVEC: begin
        if(prefetch_matrixvec_done) begin
          if(~uloop_ready_i[0]) begin
            state_d = UPDATEIDX_WAIT;
            state_change_d = 1'b1;
          end
          else begin
            state_d = UPDATEIDX;
            state_change_d = 1'b1;
          end
        end
      end

      NORMQUANT_SHIFT: begin
        if(accumulators_state == AQ_NORMQUANT) begin
          state_d = NORMQUANT;
          state_change_d = 1'b1;
        end
      end

      NORMQUANT: begin
        if(accumulators_state == AQ_NORMQUANT_BIAS) begin
          state_d = NORMQUANT_BIAS;
          state_change_d = 1'b1;
        end
        else if(~config_i.norm_option_bias & accumulators_state == AQ_NORMQUANT_DONE) begin
          if (config_i.resilience_mode) begin
            state_d = OUTCHECK;
            state_change_d = 1'b1;
          end else
            state_d = STREAMOUT;
            state_change_d = 1'b1;
        end
      end

      NORMQUANT_BIAS: begin
        if(accumulators_state == AQ_NORMQUANT_DONE) begin
          if (config_i.resilience_mode) begin
            state_d = OUTCHECK;
            state_change_d = 1'b1;
          end else
            state_d = STREAMOUT;
            state_change_d = 1'b1;
        end
      end

      OUTCHECK: begin
        if(flags_engine_i.outputcheck_valid) begin
          if(flags_engine_i.mismatch_detected) begin
            state_d = ERROR;
            state_change_d = 1'b1;
          end
          else begin
            state_d = STREAMOUT;
            state_change_d = 1'b1;
          end
        end
      end

      ERROR: begin
        state_d = LOAD;
        state_change_d = 1'b1;
      end

      STREAMOUT: begin
        if(streamout_done) begin
          if(done) begin
            state_d = DONE;
            state_change_d = 1'b1;
          end
          else begin
            state_d = STREAMOUT_DONE;
            state_change_d = 1'b1;
          end
        end
      end

      STREAMOUT_DONE: begin
        if(flags_streamer_i.tcdm_fifo_empty) begin
          if(config_i.prefetch)
            if(streamin_en)
              state_d = STREAMIN;
            else
              state_d = WEIGHTOFFS;
          else
            state_d = LOAD;
          state_change_d = 1'b1;
        end
      end

      UPDATEIDX_WAIT: begin
        if(uloop_ready_i[0]) begin
          state_d = UPDATEIDX;
          state_change_d = 1'b1;
        end
      end

      UPDATEIDX: begin
        if(flags_uloop.valid & ~sticky_error | (flags_uloop_aux.valid | flags_uloop_aux.done & sticky_error) ) begin
          if((config_i.filter_mode != NEUREKA_FILTER_MODE_3X3_DW) && ((config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? (flags_uloop_1.idx_update == 4'b0001) && (~flags_uloop_1.done) : sticky_error ? ~flags_uloop_aux.done : (flags_uloop.idx_update == 4'b0001 && (~flags_uloop.done)))) begin
            if(config_i.prefetch) begin
              state_d = WEIGHTOFFS;
            end else begin
              state_d = LOAD;
            end
            state_change_d = 1'b1;
          end
          else if(~config_i.streamout_quant) begin
            if (config_i.resilience_mode) begin
              state_d = OUTCHECK;
              state_change_d = 1'b1;
            end else
              state_d = STREAMOUT;
              state_change_d = 1'b1;
          end
          else if(config_i.norm_option_shift) begin
            state_d = NORMQUANT_SHIFT;
            state_change_d = 1'b1;
          end
          else begin
            state_d = NORMQUANT;
            state_change_d = 1'b1;
          end
        end
      end

      DONE: begin
        state_d = IDLE;
        state_change_d = 1'b1;
      end

    endcase
    if(clear_i) begin
      state_d = IDLE; 
      state_change_d = '0; 
    end 
  end

  logic init_set, init_set_d, init_set_q;
  logic degenerate_case;
  logic switch_range_d, switch_range_q;
  logic [31:0] uloop_0_range_j_major, uloop_1_range_j_major;

  assign degenerate_case = (config_i.subtile_nb_wo == 1);

  always_comb // this structure is needed to execute the swap between the ranges; this swap is needed when subtile is odd and while changing row tile or output channel tile
  begin
    uloop_0_range_j_major = '0;
    uloop_1_range_j_major = '0;
    if (config_i.subtile_nb_wo[0] == 1)
      uloop_0_range_j_major = switch_range_q ? (config_i.subtile_nb_wo >> 1) : (config_i.subtile_nb_wo >> 1) +1; // input_channel index is odd OR output_channel index is odd AND row subtile is odd
      uloop_1_range_j_major = switch_range_q ? (config_i.subtile_nb_wo >> 1) +1 : (config_i.subtile_nb_wo >> 1); // input_channel index is odd OR output_channel index is odd AND row subtile is odd
  end

  always_comb begin
    switch_range_d = switch_range_q;
    if(clear_i) begin
      switch_range_d = '0;
    end else if(~config_i.resilience_mode && (flags_uloop.idx_update[2] || flags_uloop.idx_update[3]) && flags_uloop.valid) begin
      switch_range_d  = (~switch_range_q);
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      switch_range_q <= '0;
    end else begin
      switch_range_q <= switch_range_d;
    end
  end

  /* uloop instantiation */
  always_comb
  begin
    code_uloop_0 = '0;
    // code_uloop_1 = '0;
    code_uloop_1 = code_uloop_0;
    if (config_i.resilience_mode | degenerate_case) begin
      code_uloop_0.code     = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_CODE_DEPTHWISE   : ULOOP_CODE_NORMAL;
      code_uloop_0.loops    = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_LOOPS_DEPTHWISE  : ULOOP_LOOPS_NORMAL;
      code_uloop_0.range[0] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_wo : config_i.subtile_nb_ki;
      code_uloop_0.range[1] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ho : config_i.subtile_nb_wo;
      code_uloop_0.range[2] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ko : config_i.subtile_nb_ho;
      code_uloop_0.range[3] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? 1                      : config_i.subtile_nb_ko;
      code_uloop_1.code     = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_CODE_DEPTHWISE   : ULOOP_CODE_NORMAL_LCS;
      code_uloop_1.loops    = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_LOOPS_DEPTHWISE  : ULOOP_LOOPS_NORMAL_LCS;
      code_uloop_1.range    = code_uloop_0.range;
    end else begin
      code_uloop_0.code     = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_CODE_DEPTHWISE   : ULOOP_CODE_NORMAL_PERF;
      code_uloop_0.loops    = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_LOOPS_DEPTHWISE  : ULOOP_LOOPS_NORMAL_PERF;
      code_uloop_0.range[0] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_wo : config_i.subtile_nb_ki;
      code_uloop_0.range[1] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ho : config_i.subtile_nb_wo >> 1;
      code_uloop_0.range[2] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ko : config_i.subtile_nb_ho;
      code_uloop_0.range[3] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? 1                      : config_i.subtile_nb_ko;
      code_uloop_1 = code_uloop_0;
      code_uloop_1.code     = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_CODE_DEPTHWISE   : ULOOP_CODE_NORMAL_PERF;
      code_uloop_1.loops    = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_LOOPS_DEPTHWISE  : ULOOP_LOOPS_NORMAL_PERF;
      // code_uloop_1.range    = code_uloop_0.range;
      if (config_i.subtile_nb_wo[0] == 1) begin
        code_uloop_0.range[1] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ho : uloop_0_range_j_major;
        code_uloop_1.range[1] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ho : uloop_1_range_j_major;
      end
    end
  end

  assign ctrl_uloop.enable = ((state_q == UPDATEIDX) & ~flags_uloop.valid) & (config_i.resilience_mode ? ~sticky_error : 1'b1);
  assign ctrl_uloop.clear  = (state_q == IDLE);
  assign ctrl_uloop.ready  = (config_i.filter_mode == NEUREKA_FILTER_MODE_1X1 && config_i.resilience_mode) ? 1'b1 : uloop_ready_i[0];
  assign ctrl_uloop.set = '0;

  always_comb
  begin
    ctrl_uloop_1 = '0;
    if (~degenerate_case) begin
      ctrl_uloop_1 = ctrl_uloop;
      ctrl_uloop_1.enable = (config_i.resilience_mode) ? (flags_uloop.valid & ~(flags_uloop.idx_update[1] == 1) & ~flags_uloop.next_done) | (state_d == STREAMOUT) & (state_change_d==1'b1) & (~flags_uloop_1.valid) : (state_q == UPDATEIDX) & ~flags_uloop.valid && ((config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0]) ? (flags_uloop.next_idx[3] == flags_uloop_1.next_idx[3]) : 1) ; // When I need to iterate both over inut and output channels, in some cases we need to realign the two loops by stalling the second one once
      ctrl_uloop_1.ready  = (config_i.resilience_mode) ? 1'b1 : uloop_ready_i[1];
      ctrl_uloop_1.set    = (config_i.resilience_mode) ? '0 : init_set & (~init_set_q);
    end
  end

  always_comb
  begin
    code_uloop_aux = '0;
    if (config_i.resilience_mode) begin
      code_uloop_aux.code     = ULOOP_CODE_AUX;
      code_uloop_aux.loops    = ULOOP_LOOPS_AUX;
      code_uloop_aux.range[0] = config_i.subtile_nb_ki;
      code_uloop_aux.range[1] = 1;
    end
  end

  always_comb
  begin
    ctrl_uloop_aux = '0;
    if (config_i.resilience_mode) begin
      ctrl_uloop_aux = ctrl_uloop;
      ctrl_uloop_aux.ready  = 1'b1;
      ctrl_uloop_aux.enable = (config_i.resilience_mode & sticky_error) ? (state_q == UPDATEIDX & ~flags_uloop_aux.valid) : 0;
      ctrl_uloop_aux.clear  = (state_q == IDLE) | (((state_d == OUTCHECK) & (state_change_d==1'b1)) & sticky_error);
      ctrl_uloop_aux.set    = (state_d == ERROR) & (state_change_d==1'b1); // |(flags_uloop_1.idx_update) & flags_uloop_1.valid;
    end
  end

  hwpe_ctrl_uloop #(
    .LENGTH    ( 32 ),
    .NB_LOOPS  ( 4  ),
    .NB_RO_REG ( 18 ),
    .NB_REG    ( 4  ),
    .REG_WIDTH ( 32 ),
    .CNT_WIDTH ( 16 ),
    .SHADOWED  ( 1  )
`ifndef SYNTHESIS
    ,
    .DEBUG_DISPLAY ( 0 )
`endif
  ) i_uloop (
    .clk_i            ( clk_i                      ),
    .rst_ni           ( rst_ni                     ),
    .test_mode_i      ( test_mode_i                ),
    .clear_i          ( clear_i | ctrl_uloop.clear ),
    .ctrl_i           ( ctrl_uloop                 ),
    .flags_o          ( flags_uloop                ),
    .uloop_code_i     ( code_uloop_0               ),
    .registers_read_i ( ro_reg                     ),
    .registers_set_i  ( '0              )
  );

  hwpe_ctrl_uloop #(
    .LENGTH    ( 32 ),
    .NB_LOOPS  ( 4  ),
    .NB_RO_REG ( 18 ),
    .NB_REG    ( 4  ),
    .REG_WIDTH ( 32 ),
    .CNT_WIDTH ( 16 ),
    .SHADOWED  ( 1  )
`ifndef SYNTHESIS
    ,
    .DEBUG_DISPLAY ( 0 )
`endif
  ) i_uloop_1 (
    .clk_i            ( clk_i                      ),
    .rst_ni           ( rst_ni                     ),
    .test_mode_i      ( test_mode_i                ),
    .clear_i          ( clear_i | ctrl_uloop.clear ),
    .ctrl_i           ( ctrl_uloop_1                 ),
    .flags_o          ( flags_uloop_1              ),
    .uloop_code_i     ( code_uloop_1               ),
    .registers_read_i ( ro_reg                     ),
    .registers_set_i  ( uloop_1_set                 )
  );

    hwpe_ctrl_uloop #(
    .LENGTH    ( 32 ),
    .NB_LOOPS  ( 2  ),
    .NB_RO_REG ( 4 ),
    .NB_REG    ( 2  ),
    .REG_WIDTH ( 32 ),
    .CNT_WIDTH ( 16 ),
    .SHADOWED  ( 0  )
`ifndef SYNTHESIS
    ,
    .DEBUG_DISPLAY ( 0 )
`endif
  ) i_uloop_aux (
    .clk_i            ( clk_i                      ),
    .rst_ni           ( rst_ni                     ),
    .test_mode_i      ( test_mode_i                ),
    .clear_i          ( clear_i | ctrl_uloop.clear ),
    .ctrl_i           ( ctrl_uloop_aux           ),
    .flags_o          ( flags_uloop_aux          ),
    .uloop_code_i     ( code_uloop_aux           ),
    .registers_read_i ( ro_reg_aux                 ),
    .registers_set_i  ( uloop_aux_set              )
  );

  assign index_lcs.k_out_major = flags_uloop_1.idx[3];
  assign index_lcs.i_major     = flags_uloop_1.idx[2];
  assign index_lcs.j_major     = flags_uloop_1.idx[1];
  assign index_lcs.k_in_major  = flags_uloop_1.idx[0];

  assign base_addr_lcs.weights = flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_W];
  assign base_addr_lcs.infeat  = flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_X];
  assign base_addr_lcs.outfeat = flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_Y];
  assign base_addr_lcs.scale   = flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_S];

  assign base_addr_aux.weights = flags_uloop_aux.offs[0];
  assign base_addr_aux.infeat  = flags_uloop_aux.offs[1];
  assign base_addr_aux.outfeat = '0;
  assign base_addr_aux.scale   = '0;

  assign index_aux.k_out_major = '0;
  assign index_aux.i_major     = '0;
  assign index_aux.j_major     = '0;
  assign index_aux.k_in_major  = flags_uloop_aux.idx[0];

  assign ro_reg[NEUREKA_ULOOP_RO_WEIGHTS_KOM_ITER]       = config_i.uloop_iter.weights_kom_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_WEIGHTS_KIM_ITER]       = config_i.uloop_iter.weights_kim_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_WEIGHTS_KOM_RESET_ITER] = config_i.uloop_iter.weights_kom_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_WEIGHTS_KIM_RESET_ITER] = config_i.uloop_iter.weights_kim_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_INFEAT_KIM_ITER]        = config_i.uloop_iter.infeat_kim_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_INFEAT_WOM_ITER]        = config_i.uloop_iter.infeat_wom_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_INFEAT_HOM_ITER]        = config_i.uloop_iter.infeat_hom_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_INFEAT_KIM_RESET_ITER]  = config_i.uloop_iter.infeat_kim_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_INFEAT_WOM_RESET_ITER]  = config_i.uloop_iter.infeat_wom_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_INFEAT_HOM_RESET_ITER]  = config_i.uloop_iter.infeat_hom_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_OUTFEAT_WOM_ITER]       = config_i.uloop_iter.outfeat_wom_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_OUTFEAT_HOM_ITER]       = config_i.uloop_iter.outfeat_hom_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_OUTFEAT_KOM_ITER]       = config_i.uloop_iter.outfeat_kom_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_OUTFEAT_WOM_RESET_ITER] = config_i.uloop_iter.outfeat_wom_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_OUTFEAT_HOM_RESET_ITER] = config_i.uloop_iter.outfeat_hom_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_OUTFEAT_KOM_RESET_ITER] = config_i.uloop_iter.outfeat_kom_reset_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_SCALE_KOM_ITER]         = config_i.uloop_iter.scale_kom_iter;
  assign ro_reg[NEUREKA_ULOOP_RO_ZERO]                   = '0;

  assign ro_reg_aux[0] = (config_i.resilience_mode) ? config_i.uloop_iter.weights_kim_iter : '0;
  assign ro_reg_aux[1] = (config_i.resilience_mode) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_W] : '0;
  assign ro_reg_aux[2] = (config_i.resilience_mode) ? config_i.uloop_iter.infeat_kim_iter : '0;
  assign ro_reg_aux[3] = (config_i.resilience_mode) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_X] : '0;

  always_comb begin
    uloop_1_set = '0;
    if (config_i.resilience_mode==0) begin
      uloop_1_set[1] = config_i.uloop_iter.infeat_wom_iter;
      uloop_1_set[2] = config_i.uloop_iter.outfeat_wom_iter;
    end
  end
  assign uloop_aux_set[0] = (config_i.resilience_mode) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_W] : '0;
  assign uloop_aux_set[1] = (config_i.resilience_mode) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_X] : '0;

  /* index and base_addr registers */
  logic index_sample_en, next_index_sample_en;
  logic base_addr_sample_en, next_base_addr_sample_en;
  assign index_sample_en = ((state_d == WEIGHTOFFS & config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW) ||
                            (state_d == LOAD & active_datapath_q == 0) ||
                            (config_i.prefetch & (state_d == WEIGHTOFFS)) ||
                            (state_d == STREAMOUT_DONE))
                            & state_change_d;

  assign base_addr_sample_en = config_i.resilience_mode ? index_sample_en : (((state_d == WEIGHTOFFS & config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW) ||
                                                                             (state_d == LOAD) ||
                                                                             (config_i.prefetch & (state_d == WEIGHTOFFS)) ||
                                                                             (state_d == STREAMOUT_DONE))
                                                                             & state_change_d) ||
                                                                             (state_d == LOAD && active_datapath_change);

  assign next_index_sample_en = config_i.prefetch ? flags_uloop.next_valid : index_sample_en; // TODO this will crash everything when prefetch is enabled

  assign next_base_addr_sample_en = config_i.prefetch ? flags_uloop.next_valid : base_addr_sample_en; // TODO this will crash everything when prefetch is enabled

  // I need to divide the assingments of base_addr and index
  // In resilience mode they have to be sampled in different situations
  always_comb begin
    index_d = index_q;
    next_index_d = next_index_q;
    base_addr_d = base_addr_q;
    next_base_addr_d = next_base_addr_q;
    index_update_d = index_update_q;
    if(clear_i) begin 
      index_d = '0;
      base_addr_d = '0;
      next_index_d = '0;
      next_base_addr_d = '0;
      index_update_d = '0;
    end else begin 
      if(index_sample_en) begin 
        index_d = index;
      end
      if (base_addr_sample_en) begin
        base_addr_d = base_addr;
      end
      if(next_index_sample_en) begin
        next_index_d = next_index;
        index_update_d = index_update;
      end
      if (next_base_addr_sample_en) begin
        next_base_addr_d = next_base_addr;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      next_index_q   <= '0;
      index_update_q <= '0;
      next_base_addr_q<='0;
      index_q        <= '0;
      base_addr_q    <= '0;
    end
    else begin
      next_base_addr_q <= next_base_addr_d;
      index_update_q <= index_update_d;
      next_index_q   <= next_index_d;
      index_q        <= index_d;     
      base_addr_q    <= base_addr_d;
    end
  end

  // I need to perform only a single load when the next is done depending on which datapath is the one that is concluding because
  // we need to take into account the exchange that occurs when subtile_ko && subtile_j are odd.
  // Originally I need to check the uloop1 to have finished because D0 is always the one to perform the last computation, but when we are processing another ko tile, since they are swapped, I need to check for the uloop0
  // In addition the single load must be performed when the next operation is to switch to next ko tile but I need to iterate over the D0 first (so the subtile j is odd and also the subtile i is odd)
  assign single_load = (config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1) && (flags_uloop.idx[3][0] == 1) ? flags_uloop.done : flags_uloop_1.next_done ||
                       (config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1) && (flags_uloop.idx[3] ^ flags_uloop_1.next_idx[3]);

  assign active_datapath_change = (config_i.resilience_mode) || (degenerate_case) ? '0 :
                                (state_d==STREAMOUT && accumulators_state == AQ_STREAMOUT_DONE && active_datapath_change_sticky) ||
                                (state_d==LOAD && flags_engine_i.flags_double_infeat_buffer.flags_even_infeat_buffer.state == IB_EXTRACT && next_valid_sticky && ~single_load); // TODO not valid with prefetch
                             // (state_d==LOAD && flags_engine_i.flags_double_infeat_buffer.flags_even_infeat_buffer.state == IB_EXTRACT && ~single_load && (next_valid_sticky || flags_uloop_1.next_done)); // TODO not valid with prefetch

  always_comb begin
    active_datapath_d = active_datapath_q;
    if(clear_i) begin
      active_datapath_d = 0;
    end else if (config_i.resilience_mode || degenerate_case) begin // TODO Check this because it could be redundant since active_datapath_change is inhibited
      active_datapath_d = 0;
    end else if ((state_d==MATRIXVEC || state_d==STREAMOUT_DONE || state_d==DONE) && state_change_d==1'b1) begin // TODO check this, maybe can be replaced simply by active_datapath_change
      active_datapath_d = 0;
    end else if(active_datapath_change) begin
      active_datapath_d  = (~active_datapath_q);
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      active_datapath_q <= 0;
    end else begin
      active_datapath_q <= active_datapath_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      active_datapath_change_sticky  <= 1'b0;
    else if(state_d==STREAMOUT_DONE && state_change_d==1'b1) // TODO check this, maybe can be replaced simply by active_datapath_change
      active_datapath_change_sticky  <= 1'b0;
    else if(active_datapath_change)
      active_datapath_change_sticky <= 1'b1;
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      next_valid_sticky  <= 1'b0;
    else if(state_d==LOAD && active_datapath_change==1'b1)
      next_valid_sticky  <= 1'b0;
    else if(flags_uloop_1.next_valid)
      next_valid_sticky <= 1'b1;
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      sticky_error  <= 1'b0;
    else if(state_d==STREAMOUT)
      sticky_error  <= 1'b0;
    else if(state_d==ERROR)
      sticky_error <= 1'b1;
  end

  assign init_set = ctrl_uloop_1.ready & ~(ctrl_uloop_1.clear);
  always_comb begin
    init_set_d = init_set_q;
    if(clear_i)
      init_set_d = '0;
    else if(~config_i.resilience_mode)
        init_set_d = init_set;
  end

  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      init_set_q <= 1'b0;
    else if(~config_i.resilience_mode)
      init_set_q <= init_set_d;
  end

  /* FSM output binding */
  assign state_o        = state_d;
  assign state_change_o = state_change_d;

  assign active_datapath_o = active_datapath_change ? active_datapath_d : active_datapath_q;
  assign active_datapath_change_o = active_datapath_change;

  assign double_active_datapath_o = active_datapath_change_sticky;

  assign index.k_out_major = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[2] : (sticky_error) ? index_lcs.k_out_major : flags_uloop.idx[3];
  assign index.i_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[1] : (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop_1.idx[2] : (sticky_error) ? index_lcs.i_major : flags_uloop.idx[2];
  assign index.j_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[0] : config_i.resilience_mode ? (sticky_error) ? index_lcs.j_major : flags_uloop.idx[1] : (config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? (flags_uloop_1.idx[1] << 1) +1 : flags_uloop.idx[1] << 1;
  assign index.k_in_major  = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[2] : (sticky_error) ? index_aux.k_in_major : flags_uloop.idx[0];

  assign next_index.k_out_major = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[2] : flags_uloop_1.next_idx[3];
  assign next_index.i_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[1] : (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop.idx[2] : flags_uloop_1.next_idx[2];
  assign next_index.j_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[0] : (config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? (flags_uloop.idx[1] << 1) : (flags_uloop_1.next_idx[1] << 1) +1;
  assign next_index.k_in_major  = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[2] : flags_uloop_1.next_idx[0];

  assign index_update.k_out_major = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[2] : flags_uloop.idx_update[3];
  assign index_update.i_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[1] : flags_uloop.idx_update[2];
  assign index_update.j_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[0] : flags_uloop.idx_update[1];
  assign index_update.k_in_major  = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[2] : flags_uloop.idx_update[0];

  assign base_addr.weights = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_W] : (sticky_error) ? base_addr_aux.weights : flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_W];
  assign base_addr.infeat  = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_X] : (sticky_error) ? base_addr_aux.infeat : flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_X];
  assign base_addr.outfeat = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_Y] : (sticky_error) ? base_addr_lcs.outfeat : flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_Y];
  assign base_addr.scale   = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop_1.offs[NEUREKA_ULOOP_BASE_ADDR_S] : (sticky_error) ? base_addr_lcs.scale : flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_S];

  assign next_base_addr.weights = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_W] : flags_uloop_1.next_offs[NEUREKA_ULOOP_BASE_ADDR_W];
  assign next_base_addr.infeat  = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_X] : flags_uloop_1.next_offs[NEUREKA_ULOOP_BASE_ADDR_X];
  assign next_base_addr.outfeat = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_Y] : flags_uloop_1.next_offs[NEUREKA_ULOOP_BASE_ADDR_Y];
  assign next_base_addr.scale   = (config_i.resilience_mode == 0 && config_i.subtile_nb_wo[0] == 1 && ~(config_i.subtile_nb_wo == 1) && config_i.subtile_nb_ho[0] == 1 && flags_uloop.idx[3][0] == 1) ? flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_S] : flags_uloop_1.next_offs[NEUREKA_ULOOP_BASE_ADDR_S];

  assign index_o     = index_sample_en ? index_d     : index_q;
  assign base_addr_o = base_addr_sample_en ? base_addr : base_addr_q;

  assign next_index_o     = next_index_sample_en ? next_index_d     : next_index_q;
  assign next_base_addr_o = next_base_addr_sample_en ? next_base_addr : next_base_addr_q;

  assign prefetch_pulse_o = flags_uloop.next_valid;

  assign streamin_en = config_i.streamin & ((index_update.k_out_major | index_update.i_major | index_update.j_major) | (index_q.k_out_major=='0 & index_q.k_in_major=='0 & index_q.i_major=='0 & index_q.j_major=='0));

endmodule // neureka_ctrl_fsm
