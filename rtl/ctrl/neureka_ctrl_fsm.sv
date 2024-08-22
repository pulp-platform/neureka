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
  input  logic             uloop_ready_i,
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

  ctrl_uloop_t       ctrl_uloop;
  flags_uloop_t      flags_uloop;
  uloop_code_t       code_uloop;
  logic [17:0][31:0] ro_reg;

  logic prefetch_done;

  index_neureka_t     index, index_d, index_q;
  index_neureka_t     next_index, next_index_d, next_index_q;
  index_update_neureka_t index_update, index_update_d, index_update_q;
  base_addr_neureka_t base_addr, base_addr_d, base_addr_q;
  base_addr_neureka_t next_base_addr, next_base_addr_d, next_base_addr_q;
  logic streamin_en;

  logic prefetch_done_d, prefetch_done_q;
  logic prefetch_valid_d, prefetch_valid_q;
  logic accum_done_d, accum_done_q;
  logic prefetch_matrixvec_done;
  logic load_done;
  
  assign prefetch_o               = prefetch_valid_q;
  assign load_done                = (flags_engine_i.flags_double_infeat_buffer.flags_odd_infeat_buffer.state == IB_EXTRACT)|(flags_engine_i.flags_double_infeat_buffer.flags_even_infeat_buffer.state == IB_EXTRACT);
  assign prefetch_done            = ((flags_engine_i.flags_double_infeat_buffer.flags_odd_infeat_buffer.state == IB_EXTRACT)&(~flags_engine_i.flags_double_infeat_buffer.read)) || ((flags_engine_i.flags_double_infeat_buffer.flags_even_infeat_buffer.state == IB_EXTRACT) & (flags_engine_i.flags_double_infeat_buffer.read));
  assign prefetch_matrixvec_done  = (prefetch_done_d & accum_done_d)|(prefetch_done_d & accum_done_q)|(prefetch_done_q & accum_done_d)|(prefetch_done_q & accum_done_q);
  
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
          if(~uloop_ready_i) begin
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
          state_d = STREAMOUT;
          state_change_d = 1'b1;
        end
      end

      NORMQUANT_BIAS: begin
        if(accumulators_state == AQ_NORMQUANT_DONE) begin
          state_d = STREAMOUT;
          state_change_d = 1'b1;
        end
      end

      STREAMOUT: begin
        if(accumulators_state == AQ_STREAMOUT_DONE) begin
          if(flags_uloop.done) begin
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
        if(uloop_ready_i) begin
          state_d = UPDATEIDX;
          state_change_d = 1'b1;
        end
      end

      UPDATEIDX: begin
        if(flags_uloop.valid) begin
          if((config_i.filter_mode != NEUREKA_FILTER_MODE_3X3_DW) && (flags_uloop.idx_update == 4'b0001) && (~flags_uloop.done)) begin
            if(config_i.prefetch) begin
              state_d = WEIGHTOFFS;
            end else begin
              state_d = LOAD;
            end 
            state_change_d = 1'b1;
          end
          else if(~config_i.streamout_quant) begin
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

  /* uloop instantiation */
  always_comb
  begin
    code_uloop = '0;
    code_uloop.code     = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_CODE_DEPTHWISE   : ULOOP_CODE_NORMAL;
    code_uloop.loops    = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? ULOOP_LOOPS_DEPTHWISE  : ULOOP_LOOPS_NORMAL;
    code_uloop.range[0] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_wo : config_i.subtile_nb_ki;
    code_uloop.range[1] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ho : config_i.subtile_nb_wo;
    code_uloop.range[2] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? config_i.subtile_nb_ko : config_i.subtile_nb_ho;
    code_uloop.range[3] = config_i.filter_mode == NEUREKA_FILTER_MODE_3X3_DW ? 1                      : config_i.subtile_nb_ko;
  end

  assign ctrl_uloop.enable = (state_q == UPDATEIDX) & ~flags_uloop.valid;
  assign ctrl_uloop.clear  = (state_q == IDLE);
  assign ctrl_uloop.ready  = config_i.filter_mode == NEUREKA_FILTER_MODE_1X1 ? 1'b1 : uloop_ready_i;

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
    .uloop_code_i     ( code_uloop                 ),
    .registers_read_i ( ro_reg                     )
  );

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

  /* index registers */
  logic index_sample_en;
  assign index_sample_en = ((state_d == WEIGHTOFFS & config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW) || state_d == LOAD || (config_i.prefetch & (state_d == WEIGHTOFFS)) ||state_d == STREAMOUT_DONE) & state_change_d;
  
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
        base_addr_d = base_addr; 
      end
      if(flags_uloop.next_valid) begin 
        next_index_d = next_index;
        next_base_addr_d = next_base_addr; 
        index_update_d = index_update;
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

  /* FSM output binding */
  assign state_o        = state_d;
  assign state_change_o = state_change_d;

  assign index.k_out_major = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[2] : flags_uloop.idx[3];
  assign index.i_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[1] : flags_uloop.idx[2];
  assign index.j_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[0] : flags_uloop.idx[1];
  assign index.k_in_major  = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx[2] : flags_uloop.idx[0];

  assign next_index.k_out_major = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[2] : flags_uloop.next_idx[3];
  assign next_index.i_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[1] : flags_uloop.next_idx[2];
  assign next_index.j_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[0] : flags_uloop.next_idx[1];
  assign next_index.k_in_major  = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.next_idx[2] : flags_uloop.next_idx[0];

  assign index_update.k_out_major = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[2] : flags_uloop.idx_update[3];
  assign index_update.i_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[1] : flags_uloop.idx_update[2];
  assign index_update.j_major     = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[0] : flags_uloop.idx_update[1];
  assign index_update.k_in_major  = config_i.filter_mode==NEUREKA_FILTER_MODE_3X3_DW ? flags_uloop.idx_update[2] : flags_uloop.idx_update[0];

  assign base_addr.weights = flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_W];
  assign base_addr.infeat  = flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_X];
  assign base_addr.outfeat = flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_Y];
  assign base_addr.scale   = flags_uloop.offs[NEUREKA_ULOOP_BASE_ADDR_S];

  assign next_base_addr.weights = flags_uloop.next_offs[NEUREKA_ULOOP_BASE_ADDR_W];
  assign next_base_addr.infeat  = flags_uloop.next_offs[NEUREKA_ULOOP_BASE_ADDR_X];
  assign next_base_addr.outfeat = flags_uloop.next_offs[NEUREKA_ULOOP_BASE_ADDR_Y];
  assign next_base_addr.scale   = flags_uloop.next_offs[NEUREKA_ULOOP_BASE_ADDR_S];

  assign index_o     = index_sample_en ? index_d     : index_q;
  assign base_addr_o = index_sample_en ? base_addr : base_addr_q;

  assign next_index_o     = prefetch_pulse_o ? next_index_d     : next_index_q;
  assign next_base_addr_o = index_sample_en ? next_base_addr : next_base_addr_q;

  assign prefetch_pulse_o = flags_uloop.next_valid;

  assign streamin_en = config_i.streamin & ((index_update.k_out_major | index_update.i_major | index_update.j_major) | (index_q.k_out_major=='0 & index_q.k_in_major=='0 & index_q.i_major=='0 & index_q.j_major=='0));

endmodule // neureka_ctrl_fsm
