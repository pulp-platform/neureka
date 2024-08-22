/*
 * neureka_accumulator_normquant.sv
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

module neureka_accumulator_normquant #(
  parameter int unsigned TP               = NEUREKA_TP_IN, // output filter size in bits/cycle
  parameter int unsigned AP               = NEUREKA_TP_OUT, // number of accumulators
  parameter int unsigned ACC              = NEUREKA_ACCUM_SIZE,
  parameter int unsigned CNT              = VLEN_CNT_SIZE,
  parameter int unsigned PIPE_NORMQUANT   = 1,
  parameter int unsigned OUTREG_NORMQUANT = 0
) (
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,// enable accumulator depending on the column used for the operation.
  input  logic                   clear_i,// when it is idle or STREAMOUT is done 
  // incoming psums
  hwpe_stream_intf_stream.sink   conv_i,
  hwpe_stream_intf_stream.sink   conv_dw_i[NEUREKA_BLOCK_SIZE-1:0],
  // incoming normalization parameters
  hwpe_stream_intf_stream.sink   norm_i,
  // incoming streamin accumulators
  hwpe_stream_intf_stream.sink   streamin_i,
  // output features + handshake
  hwpe_stream_intf_stream.source conv_o,
  // control channel
  input  ctrl_aq_t               ctrl_i,
  output flags_aq_t              flags_o
);

  localparam WIDTH_FACTOR = NEUREKA_MEM_BANDWIDTH / ACC;

  logic clk_en_gated, clk_en_state, clk_en_regs, clk_en_normquant, clk_en_normquant_bias;
  logic clk_gated, clk_state, clk_regs, clk_normquant, clk_normquant_bias;

  logic signed [4*ACC-1:0]                  normalized_q;
  logic signed [ACC-1:0]                    accumulator_plus_d;
  logic                                     addr_cnt_en_stage1_d, addr_cnt_en_stage1_q, addr_cnt_en_stage1_2q;
  logic                                     addr_cnt_en_stage2_d, addr_cnt_en_stage2_q;
  logic                                     accumulator_clr;


  logic [AP-1:0][7:0] shift_buffer_d, shift_buffer_q;


  
  state_aq_t fsm_state_q, fsm_state_d;

  logic [CNT-1:0] addr_cnt_stage2_d, addr_cnt_stage2_q, addr_cnt_stage2_2q;
  logic [CNT-1:0] addr_cnt_stage1_d, addr_cnt_stage1_q;
  logic           addr_cnt_clear;

  logic                       we;
  logic                       we_wide;
  logic                       we_all; 
  logic [AP-1:0]              we_all_mask, rd_all_mask; 
  logic [AP-1:0]              we_all_mask_temp; 

  logic [$clog2(AP)-1:0]      waddr; 
  logic [ACC-1:0]             wdata; 
  logic [WIDTH_FACTOR*ACC-1:0]wdata_wide;
  logic [AP*ACC-1:0]          wdata_all;
  logic [AP*ACC-1:0]          add_wdata_all; 

  logic [$clog2(AP)-1:0]      raddr;
  logic [ACC-1:0]             rdata;
  logic [WIDTH_FACTOR*ACC-1:0]rdata_wide;
  logic [AP*ACC-1:0]          rdata_all; 
  logic [AP*ACC-1:0]          add_rdata_all; 

  logic conv_handshake_d, conv_handshake_q, conv_handshake_2q;

  logic [CNT-1:0] full_accumulation_cnt_d, full_accumulation_cnt_q;
  logic [CNT-1:0] qw_accumulation_cnt_d, qw_accumulation_cnt_q ;

  localparam NMULT = 4;

  logic [NEUREKA_MEM_BANDWIDTH/8 -1:0][ 7:0] norm_data_8b;
  logic [NEUREKA_MEM_BANDWIDTH/16-1:0][15:0] norm_data_16b;
  logic [NEUREKA_MEM_BANDWIDTH/32-1:0][31:0] norm_data_32b;
  logic [NMULT-1:0][NORM_MULT_SIZE-1:0] norm_mult;
  logic [NMULT-1:0][ 7:0] norm_shift;
  logic [NMULT*ACC-1:0] normquant_in;
  ctrl_normquant_t ctrl_normquant;
  flags_normquant_t [3:0] flags_normquant;
  logic [NEUREKA_MEM_BANDWIDTH/8 -1:0][ 7:0] shift_data_stage1_d,shift_data_stage1_q;
  logic [NMULT-1:0][ 7:0] shift_data_stage2_d, shift_data_stage2_q;

  logic shift_data_stage2_en_d, shift_data_stage2_en_q;
  logic [8-1:0][ 7:0] norm_shift_bias;

  logic full_accumulation_cnt_en;
  logic [AP-1:0] adder_enable;
  logic [AP-1:0] bypass;

  logic [AP-1:0][ACC-1:0] partial_sum;

  logic [255:0] conv_data_8b;
  logic [255:0] conv_data_32b;

  logic depthwise_accumulator_active;

  assign depthwise_accumulator_active = ctrl_i.dw_accum; 

  logic [31:0] conv_data; //signed extension 
  logic [AP*ACC-1:0] dw_conv_data;
  logic norm_ready_en;
  assign norm_ready_en = fsm_state_q == AQ_NORMQUANT_BIAS ? (addr_cnt_stage1_q[2] & addr_cnt_stage1_q[1] & addr_cnt_stage1_q[0]) | (addr_cnt_stage2_q == ctrl_i.bias_len-1 && addr_cnt_en_stage1_q == 1'b1) :
                                                       (addr_cnt_stage1_q[2] & addr_cnt_stage1_q[1] & addr_cnt_stage1_q[0]) | (addr_cnt_stage2_q == ctrl_i.scale_len-1 && addr_cnt_en_stage1_q == 1'b1); // norm_ready when addr_cnt is full, or in the last cycle of AQ_NORMQUANT
  assign norm_i.ready = ~ctrl_i.enable_streamout ? 1'b1 :
                        (fsm_state_q == AQ_NORMQUANT) ? norm_i.valid & norm_ready_en :
                        (fsm_state_q == AQ_NORMQUANT_SHIFT) ? norm_i.valid :
                        (fsm_state_q == AQ_NORMQUANT_BIAS) ? norm_i.valid : 1'b0;

  logic [VLEN_CNT_SIZE-1:0] norm_bias_lim;
  assign norm_bias_lim = ctrl_i.bias_len > 24 ? 3 :
                         ctrl_i.bias_len > 16 ? 2 :
                         ctrl_i.bias_len > 8  ? 1 : 0;

  assign conv_data = $signed(conv_i.data);
  generate  
      for(genvar ii=0; ii<AP; ii++) begin
      always_comb begin
        dw_conv_data[(ii+1)*ACC-1:ii*ACC] = $signed(conv_dw_i[ii].data); 
        conv_dw_i[ii].ready               = conv_i.ready;
      end 
    end
  endgenerate 

  always_comb
  begin
    ctrl_normquant = ctrl_i.ctrl_normquant;
    ctrl_normquant.start = (fsm_state_q == AQ_NORMQUANT) ? 1'b1 : (fsm_state_q == AQ_ACCUM & ctrl_i.weight_offset == 1) ? 1'b1 : 1'b0;
  end
 
  assign streamin_i.ready = ~ctrl_i.enable_streamout ? 1'b1 : 
                            (fsm_state_q == AQ_STREAMIN) ? streamin_i.valid : 1'b0;

  assign conv_handshake_d = clear_i ? '0 : depthwise_accumulator_active ? conv_dw_i[0].ready & conv_dw_i[0].valid : conv_i.valid & conv_i.ready; 
  assign conv_i.ready = ~ctrl_i.enable_streamout ? 1'b1 :
                        (fsm_state_q == AQ_ACCUM) ? 1'b1 : 1'b0;


  logic [255:0] streamin_data_in;
  assign streamin_data_in = streamin_i.data;

  logic [31:0][7:0] streamin_data_32x8;
  logic [31:0][31:0] streamin_data_32x32;

  always_comb begin
    for(int i=0; i<32; i++) begin 
      streamin_data_32x8[i][7:0] = streamin_data_in[i*8 +: 8];
      streamin_data_32x32[i] = {{24{streamin_data_32x8[i][7]}}, {streamin_data_32x8[i]}};
    end 
  end


  // accumulator address counter
  always_comb begin
    addr_cnt_stage1_d = addr_cnt_stage1_q;
    addr_cnt_en_stage2_d = addr_cnt_en_stage2_q;
    addr_cnt_stage2_d = addr_cnt_stage2_q;
    if(enable_i | ctrl_i.clear) begin 
      if(clear_i) begin 
        addr_cnt_stage1_d = '0;
        addr_cnt_en_stage2_d = '0;
      end else begin 
        addr_cnt_stage1_d = (clear_i | addr_cnt_clear) ? '0 : addr_cnt_en_stage1_d ? addr_cnt_stage1_q + 1 : addr_cnt_stage1_q; 
      end 
      if(clear_i | addr_cnt_clear) begin
        addr_cnt_stage2_d = '0;
      end else if((conv_i.valid & conv_i.ready) | (addr_cnt_en_stage1_q)) begin 
        addr_cnt_stage2_d = addr_cnt_stage1_q;
      end 
    end 
  end 

  always_ff @(posedge clk_state or negedge rst_ni)
  begin : address_counter
    if(~rst_ni) begin
      addr_cnt_stage1_q <= '0;
      addr_cnt_stage2_q    <= '0;
      addr_cnt_stage2_2q   <= '0;
      addr_cnt_en_stage1_q <= '0;
      addr_cnt_en_stage2_q <= '0;

    end
    else begin
      addr_cnt_stage1_q <= addr_cnt_stage1_d;
      addr_cnt_stage2_q <= addr_cnt_stage2_d;
      addr_cnt_stage2_2q <= addr_cnt_stage2_q;
      addr_cnt_en_stage1_q <= addr_cnt_en_stage1_d;
      addr_cnt_en_stage1_2q <= addr_cnt_en_stage1_q;
      addr_cnt_en_stage2_q <= addr_cnt_en_stage2_d;
    end
  end

  assign accumulator_clr  = clear_i | ctrl_i.clear;

  // clock-gate modules hierarchically to save dynamic power
  assign clk_en_gated          = ctrl_i.enable_streamout  & ctrl_i.clock_gating | accumulator_clr;
  assign clk_en_state          = ctrl_i.last_pe | clk_en_gated;
  assign clk_en_regs           = (ctrl_i.enable_streamout & (fsm_state_q != AQ_IDLE)) | accumulator_clr;
  assign clk_en_normquant      = (ctrl_i.enable_streamout & ((fsm_state_q == AQ_NORMQUANT
                                                           || fsm_state_q == AQ_NORMQUANT_SHIFT))) | accumulator_clr | ctrl_i.weight_offset;
  assign clk_en_normquant_bias = (ctrl_i.enable_streamout & (fsm_state_q == AQ_NORMQUANT
                                                          || fsm_state_q == AQ_NORMQUANT_BIAS)) | accumulator_clr;

  cluster_clock_gating i_hier_accum_gate (
    .clk_i     ( clk_i        ),
    .en_i      ( clk_en_gated ),
    .test_en_i ( test_mode_i  ),
    .clk_o     ( clk_gated    )
  );

  cluster_clock_gating i_hier_state_gate (
    .clk_i     ( clk_i        ),
    .en_i      ( clk_en_state ),
    .test_en_i ( test_mode_i  ),
    .clk_o     ( clk_state    )
  );

  cluster_clock_gating i_hier_regs_gate (
    .clk_i     ( clk_i       ),
    .en_i      ( clk_en_regs ),
    .test_en_i ( test_mode_i ),
    .clk_o     ( clk_regs    )
  );

  cluster_clock_gating i_hier_nq_gate (
    .clk_i     ( clk_i            ),
    .en_i      ( clk_en_normquant ),
    .test_en_i ( test_mode_i      ),
    .clk_o     ( clk_normquant    )
  );

  cluster_clock_gating i_hier_nqb_gate (
    .clk_i     ( clk_i                 ),
    .en_i      ( clk_en_normquant_bias ),
    .test_en_i ( test_mode_i           ),
    .clk_o     ( clk_normquant_bias    )
  );

  neureka_accumulator_buffer #(
    .DATA_WIDTH(NEUREKA_ACCUM_SIZE),
    .NUM_WORDS(NEUREKA_TP_OUT)
  ) i_accumulator_buffer (
    .clk_i        ( clk_regs        ),
    .rst_ni       ( rst_ni          ),

    .enable_i     ( enable_i        ),
    .clear_i      ( accumulator_clr ),
    
    .we_i         ( we            ),
    .we_wide_i    ( we_wide       ),
    .we_all_i     ( we_all        ),
    .we_all_mask_i( we_all_mask   ),

    .waddr_i      ( waddr         ),
    .wdata_i      ( wdata         ),
    .wdata_wide_i ( wdata_wide    ),
    .wdata_all_i  ( wdata_all     ),
    
    .raddr_i      ( raddr         ),
    .rdata_o      ( rdata         ),
    .rd_all_mask_i( rd_all_mask   ),
    .rdata_wide_o ( rdata_wide    ),
    .rdata_all_o  ( rdata_all     )
  );

  neureka_accumulator_adder #(
  ) i_accumulator_adder (
    .clk_i        ( clk_gated     ),
    .rst_ni       ( rst_ni        ),
    .test_mode_i  ( test_mode_i   ),
    .clear_i      ( clear_i       ),
    .enable_i     ( adder_enable  ),
    .bypass_i     ( bypass        ),
    .accumulator_i( add_rdata_all ),
    .partial_sum_i( partial_sum   ),
    .accumulator_o( add_wdata_all )
  );


  neureka_normquant #(
    .NMULT           ( NMULT            ),
    .ACC             ( ACC              ),
    .PIPE            ( PIPE_NORMQUANT   ),
    .OUTPUT_REGISTER ( OUTREG_NORMQUANT )
  ) i_normquant (
    .clk_i         ( clk_normquant   ),
    .rst_ni        ( rst_ni          ),
    .test_mode_i   ( test_mode_i     ),
    .clear_i       ( clear_i         ),
    .norm_mult_i   ( norm_mult       ),
    .shift_i       ( norm_shift      ),
    .accumulator_i ( normquant_in    ),
    .accumulator_o ( normalized_q    ),
    .ctrl_i        ( ctrl_normquant  ),
    .flags_o       ( flags_normquant )
  );

  logic [255:0] norm_bias;
  logic [255:0] biased_data, shifted_data;
  assign norm_bias = norm_i.data;

// Only used for the shift as the bias is done using neureka_accumulator_adder 
  neureka_normquant_bias i_normquant_bias (
    .clk_i         ( clk_normquant_bias ),
    .rst_ni        ( rst_ni             ),
    .test_mode_i   ( test_mode_i        ),
    .clear_i       ( clear_i            ),
    .shift_i       ( norm_shift_bias    ),
    .accumulator_i ( biased_data        ),
    .accumulator_o ( shifted_data       ),
    .ctrl_i        ( ctrl_normquant     )
  );

  
  assign normquant_in = ctrl_i.weight_offset ? { 96'b0, $signed(conv_i.data) } : (ctrl_i.norm_mode == NEUREKA_MODE_32B) ? {96'b0,{rdata}}: rdata_wide;

  assign norm_data_8b  = norm_i.data;
  assign norm_data_16b = norm_i.data;
  assign norm_data_32b = ctrl_i.weight_offset ? {NEUREKA_MEM_BANDWIDTH/32 {ctrl_i.weight_offset_scale}} : norm_i.data;
  
  generate
    for(genvar ii=0; ii<NMULT; ii++) begin : norm_mult_gen
      always_comb begin
        norm_mult [ii] = '0;
        norm_shift[ii] = shift_data_stage2_q[ii];
        if(ctrl_i.norm_mode == NEUREKA_MODE_32B || ctrl_i.weight_offset==1'b1) begin // actually 24 bits!
          norm_mult[ii]  = norm_data_32b[addr_cnt_stage1_q[2:0]][(ii+1)*8-1:ii*8];
        end
        else if(ctrl_i.norm_mode == NEUREKA_MODE_16B) begin
          localparam ii_div2 = ii/2;
          localparam ii_rem2 = ii%2;
          norm_mult[ii] = norm_data_16b[{addr_cnt_stage1_q[2:0], 1'b0} + ii_div2][(ii_rem2+1)*8-1:ii_rem2*8];
        end
        else if(ctrl_i.norm_mode == NEUREKA_MODE_8B) begin
          norm_mult[ii] = norm_data_8b[{addr_cnt_stage1_q[2:0], 2'b0} + ii];
        end  
      end

      always_comb begin
        shift_data_stage2_d[ii] = shift_data_stage2_q[ii]; 
        if(clear_i) begin
          shift_data_stage2_d[ii] = '0;
        end
        else if(shift_data_stage2_en_q) begin
          if(ctrl_i.norm_mode == NEUREKA_MODE_32B || ctrl_i.weight_offset==1'b1) begin // actually 24 bits!
            shift_data_stage2_d[ii] = shift_data_stage1_q [addr_cnt_stage1_q[5:0]];
          end
          else if(ctrl_i.norm_mode == NEUREKA_MODE_16B) begin
            localparam ii_div2 = ii/2;
            localparam ii_rem2 = ii%2;
            shift_data_stage2_d[ii] = shift_data_stage1_q [{addr_cnt_stage1_q[5:0], 1'b0} + ii_rem2];
          end
          else if(ctrl_i.norm_mode == NEUREKA_MODE_8B) begin
            shift_data_stage2_d[ii] = shift_data_stage1_q [{addr_cnt_stage1_q[5:0], 2'b0}+ii];
          end
        end else begin
          shift_data_stage2_d[ii] = shift_data_stage2_q[ii]; 
        end 
      end 

      always_ff @(posedge clk_state or negedge rst_ni)
      begin
        if(~rst_ni) begin
          shift_data_stage2_q[ii] <= '0;
        end else begin
          shift_data_stage2_q[ii] <= shift_data_stage2_d[ii];
        end
      end
    end
    for(genvar ii=0; ii<8; ii++) begin : norm_add_gen
      assign norm_shift_bias[ii] = shift_data_stage1_q [{addr_cnt_stage1_q[5:0], 3'b0}+ii];
    end
  endgenerate

  assign flags_o.state    = fsm_state_q;
  assign flags_o.addr_cnt_en_q = addr_cnt_en_stage1_q;
  assign flags_o.count    = full_accumulation_cnt_q;
  
  always_ff @(posedge clk_state or negedge rst_ni)
  begin : fsm_state_seq
    if(~rst_ni) begin
      fsm_state_q <= AQ_IDLE;
    end
    else begin 
      fsm_state_q <= fsm_state_d;
    end
  end

  // ========================================================================
  // FSM Code
  // ========================================================================

  always_comb
  begin : fsm_out_comb

    addr_cnt_en_stage1_d = 1'b0;
    addr_cnt_clear = 1'b0;
    adder_enable = '0;


    we          = '0;
    we_wide     = '0;
    we_all      = '0;
    we_all_mask = '0;
    rd_all_mask = '0;
    waddr       = '0; 
    wdata       = '0; 
    wdata_wide  = '0;
    bypass      = '0;

    raddr       = '0;
    partial_sum = '0;
    add_rdata_all = rdata_all;
    wdata_all     = add_wdata_all;
    biased_data = '0;


    // addr_cnt en/clear
    case(fsm_state_q)
      AQ_IDLE, AQ_ACCUM_DONE, AQ_NORMQUANT_SHIFT, AQ_NORMQUANT_TOBIAS, AQ_NORMQUANT_DONE, AQ_STREAMIN_DONE, AQ_STREAMOUT_DONE : begin
        addr_cnt_clear = 1'b1;
      end
      AQ_ACCUM : begin
        addr_cnt_en_stage1_d = (ctrl_i.qw == '0) ? conv_i.valid & conv_i.ready :
                                            conv_handshake_d & ((qw_accumulation_cnt_q == ctrl_i.qw-1) | (ctrl_i.weight_offset & ctrl_i.depthwise));
      end
      AQ_NORMQUANT : begin
        addr_cnt_en_stage1_d = norm_i.valid; // normalization and stream-in use the same stream?
      end
      AQ_NORMQUANT_BIAS : begin
        addr_cnt_en_stage1_d = norm_i.valid; // normalization and stream-in use the same stream?
      end
      AQ_STREAMIN : begin
        addr_cnt_en_stage1_d = streamin_i.valid & streamin_i.ready;
      end
      AQ_STREAMOUT : begin
        addr_cnt_en_stage1_d = conv_o.valid & conv_o.ready;
      end
    endcase

    // selector for addresses
    if(fsm_state_q == AQ_ACCUM) begin
      partial_sum = depthwise_accumulator_active ? dw_conv_data : ctrl_i.weight_offset ? {AP{normalized_q[ACC-1:0]}} : {AP{conv_data}};
      we_all      = ctrl_i.weight_offset ? OUTREG_NORMQUANT ? conv_handshake_2q : conv_handshake_q : conv_handshake_d; // during weight offset the normalization takes 1 cycle thus handshaking with conv_handshake_q (2 cycles if normquant is pipelined, so conv_handshake_2q)
      we          = 1'b0;
      adder_enable= ctrl_i.weight_offset & (!ctrl_i.depthwise) ? '1 :
                    depthwise_accumulator_active  ? '1 : 
                    ctrl_i.weight_offset & (ctrl_i.depthwise)  ? 32'h01<<addr_cnt_stage2_q : 32'h01<<addr_cnt_stage1_q;
      we_all_mask = adder_enable;
     
    end
    else if(fsm_state_q == AQ_NORMQUANT) begin
      partial_sum = ctrl_i.norm_mode==NEUREKA_MODE_8B ? {8{normalized_q}} : 
                    ctrl_i.norm_mode==NEUREKA_MODE_16B ? {(2*AP/WIDTH_FACTOR){normalized_q[2*ACC-1:0]}} :{AP{normalized_q[ACC-1:0]}};
      we_all      = OUTREG_NORMQUANT ? addr_cnt_en_stage1_2q : addr_cnt_en_stage1_q;
      adder_enable= 0;
      bypass      = OUTREG_NORMQUANT ?
                      ctrl_i.norm_mode==NEUREKA_MODE_8B     ? 32'h0f << { addr_cnt_stage2_2q[2:0], 2'b0 } :
                      ctrl_i.norm_mode==NEUREKA_MODE_16B    ? 32'h03 << { addr_cnt_stage2_2q[3:0], 1'b0 } : 32'h01<<addr_cnt_stage2_2q[4:0]
                    : ctrl_i.norm_mode==NEUREKA_MODE_8B     ? 32'h0f << { addr_cnt_stage2_q[2:0], 2'b0 } :
                      ctrl_i.norm_mode==NEUREKA_MODE_16B    ? 32'h03 << { addr_cnt_stage2_q[3:0], 1'b0 } : 32'h01<<addr_cnt_stage2_q[4:0];
      raddr       = addr_cnt_stage1_q;
      we_all_mask = bypass;
    end
    else if(fsm_state_q == AQ_NORMQUANT_BIAS) begin
      partial_sum  = {AP/WIDTH_FACTOR{norm_bias}};
      we_all       = norm_i.valid & norm_i.ready;
      adder_enable = 32'hff<<(addr_cnt_stage1_q<<3);
      raddr        = addr_cnt_stage1_q;
      we_all_mask  = adder_enable;
      biased_data  = addr_cnt_stage1_q[1:0]==2'b01 ? add_wdata_all[2*WIDTH_FACTOR*ACC-1:WIDTH_FACTOR*ACC] :
                     addr_cnt_stage1_q[1:0]==2'b10 ? add_wdata_all[3*WIDTH_FACTOR*ACC-1:2*WIDTH_FACTOR*ACC] :
                     addr_cnt_stage1_q[1:0]==2'b11 ? add_wdata_all[4*WIDTH_FACTOR*ACC-1:3*WIDTH_FACTOR*ACC] : 
                     add_wdata_all[WIDTH_FACTOR*ACC-1:0] ;
      wdata_all    = {AP/WIDTH_FACTOR{shifted_data}};
    end
    else if(fsm_state_q == AQ_STREAMIN || fsm_state_q == AQ_STREAMIN_DONE) begin
      partial_sum  = (ctrl_i.streamin_mode == NEUREKA_STREAMIN_MODE_8B) ? streamin_data_32x32 : {AP/WIDTH_FACTOR{streamin_i.data}};
      we_all       = streamin_i.valid & streamin_i.ready;
      adder_enable = (ctrl_i.streamin_mode == NEUREKA_STREAMIN_MODE_8B) ? 32'hffffffff : 32'hff << (addr_cnt_stage1_q<<3);
      we_all_mask  = (ctrl_i.streamin_mode == NEUREKA_STREAMIN_MODE_8B) ? 32'hffffffff : 32'hff << (addr_cnt_stage1_q<<3);//streamin bandwidth is 256bits. it can write to 8x32 data bits. Thus, WIDTH_FACTOR=8 accumulators. With each counter increment the bitmask is shifted 8 times.
    end
    else if(fsm_state_q == AQ_STREAMOUT || fsm_state_q == AQ_STREAMOUT_DONE) begin
      raddr = addr_cnt_stage1_q << 1 ;
    end else begin // (fsm_state_q == AQ_STREAMOUT || fsm_state_q == AQ_STREAMOUT_DONE) + remaining cases
      raddr        = addr_cnt_stage1_q;
    end


    if(enable_i | ctrl_i.clear) begin
      if(clear_i) begin
        addr_cnt_en_stage1_d = '0;
      end
    end else begin 
      addr_cnt_en_stage1_d = addr_cnt_en_stage1_q;
    end 
  end

  generate
    for(genvar ii=0; ii<ACC; ii++) begin : streamout_data_8b_gen
      assign conv_data_8b [(ii+1)*NEUREKA_QA_OUT-1:ii*NEUREKA_QA_OUT] = rdata_all[(ii*4+1)*NEUREKA_QA_OUT-1:ii*4*NEUREKA_QA_OUT];
    end
    assign conv_data_32b = rdata_wide;
  endgenerate

  always_comb
  begin : fsm_state_d_comb
    fsm_state_d = fsm_state_q;

    case(fsm_state_q)

      AQ_IDLE, AQ_ACCUM_DONE, AQ_NORMQUANT_DONE, AQ_STREAMIN_DONE, AQ_STREAMOUT_DONE : begin
        if(ctrl_i.goto_accum) begin
          fsm_state_d = AQ_ACCUM;
        end
        else if(ctrl_i.goto_normquant) begin
          if(ctrl_i.norm_option_shift)
            fsm_state_d = AQ_NORMQUANT_SHIFT;
          else
            fsm_state_d = AQ_NORMQUANT;
        end
        else if(ctrl_i.goto_accum) begin
          fsm_state_d = AQ_ACCUM;
        end
        else if(ctrl_i.goto_streamin) begin
          fsm_state_d = AQ_STREAMIN;
        end
        else if(ctrl_i.goto_streamout) begin
          fsm_state_d = AQ_STREAMOUT;
        end
        else begin
          fsm_state_d = AQ_IDLE;
        end
      end

      AQ_ACCUM : begin
        if((full_accumulation_cnt_q == ctrl_i.full_accumulation_len-1) & full_accumulation_cnt_en) begin
          fsm_state_d = AQ_ACCUM_DONE;
        end
        
      end

      AQ_NORMQUANT_SHIFT : begin
        if(norm_i.valid & norm_i.ready)
          fsm_state_d = AQ_NORMQUANT;
        
      end

      AQ_NORMQUANT : begin
        if((OUTREG_NORMQUANT && addr_cnt_stage2_2q == ctrl_i.scale_len-1 && addr_cnt_en_stage1_2q == 1'b1) ||
          (!OUTREG_NORMQUANT && addr_cnt_stage2_q == ctrl_i.scale_len-1 && addr_cnt_en_stage1_q)) begin
          if(ctrl_i.norm_option_bias)
            fsm_state_d = AQ_NORMQUANT_TOBIAS;
          else
            fsm_state_d = AQ_NORMQUANT_DONE;
        end
        
      end

      AQ_NORMQUANT_TOBIAS : begin
        fsm_state_d = AQ_NORMQUANT_BIAS;
      end

      AQ_NORMQUANT_BIAS : begin
        if(addr_cnt_stage2_q == norm_bias_lim && addr_cnt_en_stage1_q == 1'b1) begin
          fsm_state_d = AQ_NORMQUANT_DONE;
        end
      end

      AQ_STREAMIN : begin
        if(ctrl_i.streamin_mode == NEUREKA_STREAMIN_MODE_8B) begin
          if((addr_cnt_stage1_q == 0) && (streamin_i.valid & streamin_i.ready)) begin
            fsm_state_d = AQ_STREAMIN_DONE;
          end
        end else begin
          if((addr_cnt_stage1_q == (ctrl_i.streamout_len/WIDTH_FACTOR + (ctrl_i.streamout_len%WIDTH_FACTOR==0 ? 0 : 1) -1)) && (streamin_i.valid & streamin_i.ready)) begin
            fsm_state_d = AQ_STREAMIN_DONE;
          end
        end 
      end

      AQ_STREAMOUT : begin
        if(ctrl_i.quant_mode == NEUREKA_MODE_8B && addr_cnt_stage1_q == 0 && (conv_o.valid & conv_o.ready)) begin
          fsm_state_d = AQ_STREAMOUT_DONE;
        end
        else if(ctrl_i.quant_mode == NEUREKA_MODE_32B && (addr_cnt_stage1_q == (ctrl_i.streamout_len/WIDTH_FACTOR + (ctrl_i.streamout_len%WIDTH_FACTOR==0 ? 0 : 1) -1)) && (conv_o.valid & conv_o.ready)) begin
          fsm_state_d = AQ_STREAMOUT_DONE;
        end
      end

    endcase
    if(enable_i) begin
      if(clear_i)
        fsm_state_d = AQ_IDLE;
    end else begin 
      fsm_state_d = fsm_state_q;
    end 

  end


  always_ff @(posedge clk_state or negedge rst_ni)
  begin
    if(~rst_ni) begin
      conv_handshake_q <= '0;
      conv_handshake_2q <= '0;
    end
    else begin
      conv_handshake_q <= conv_handshake_d;
      conv_handshake_2q <= conv_handshake_q;
    end
  end

  always_comb begin
     full_accumulation_cnt_d = full_accumulation_cnt_q;
     if(enable_i) begin
      if(clear_i | ctrl_i.clear)
        full_accumulation_cnt_d = '0;
      else if(fsm_state_q != AQ_ACCUM)
        full_accumulation_cnt_d = '0;
      else if(full_accumulation_cnt_en)
        full_accumulation_cnt_d = full_accumulation_cnt_q + 1;
    end
  end


  always_ff @(posedge clk_state or negedge rst_ni)
  begin : accum_counter
    if(~rst_ni) begin
      full_accumulation_cnt_q <= '0;
    end
    else begin
      full_accumulation_cnt_q <= full_accumulation_cnt_d;
    end
  end
 assign full_accumulation_cnt_en = (OUTREG_NORMQUANT & ctrl_i.weight_offset == 1'b1) ? conv_handshake_2q : conv_handshake_q;

 logic qw_accumulation_cnt_en;
  assign qw_accumulation_cnt_en = conv_handshake_d & (ctrl_i.qw != '0);

  // counter of number of qw accumulations done

  always_comb begin 
    qw_accumulation_cnt_d = qw_accumulation_cnt_q;
    if(enable_i) begin
      if(clear_i | ctrl_i.clear | fsm_state_q != AQ_ACCUM)
        qw_accumulation_cnt_d = '0;
      else if(qw_accumulation_cnt_en) begin
        if(qw_accumulation_cnt_q != ctrl_i.qw-1)
          qw_accumulation_cnt_d = qw_accumulation_cnt_q+1;
        else
          qw_accumulation_cnt_d = '0;
      end
    end
  end 

  always_ff @(posedge clk_state or negedge rst_ni)
  begin : qw_counter
    if(~rst_ni) begin
      qw_accumulation_cnt_q <= '0;
    end
    else begin
      qw_accumulation_cnt_q <= qw_accumulation_cnt_d;
    end
  end


  always_comb 
  begin
    shift_data_stage1_d = shift_data_stage1_q;
    if(clear_i | ctrl_i.weight_offset)
      shift_data_stage1_d = '0;  
    else if(~ctrl_i.norm_option_shift & ctrl_i.sample_shift) begin
      shift_data_stage1_d = {(NEUREKA_MEM_BANDWIDTH/8) {3'b0, ctrl_i.ctrl_normquant.right_shift}};
    end else if(fsm_state_q==AQ_NORMQUANT_SHIFT & norm_i.valid & norm_i.ready) begin
      shift_data_stage1_d = norm_data_8b;
    end
  end 

  always_ff @(posedge clk_state or negedge rst_ni)
  begin
    if(~rst_ni) begin
      shift_data_stage1_q <= '0;
    end
    else begin
      shift_data_stage1_q <= shift_data_stage1_d;
    end
  end

  assign shift_data_stage2_en_d = clear_i ? '0 : ctrl_i.weight_offset | (~ctrl_i.norm_option_shift & ctrl_i.sample_shift) | (fsm_state_q==AQ_NORMQUANT_SHIFT) | (fsm_state_q==AQ_NORMQUANT_BIAS) | (fsm_state_q==AQ_NORMQUANT);

  always_ff @(posedge clk_state or negedge rst_ni)
  begin
    if(~rst_ni) begin
      shift_data_stage2_en_q <= '0;
    end
    else begin
      shift_data_stage2_en_q <= shift_data_stage2_en_d;
    end
  end

  assign conv_o.valid     = ~ctrl_i.enable_streamout      ? 1'b1 :
                            (fsm_state_q == AQ_STREAMOUT) ? 1'b1 : 1'b0;
  assign conv_o.data = (ctrl_i.quant_mode == NEUREKA_MODE_8B)  ? conv_data_8b  :
                       (ctrl_i.quant_mode == NEUREKA_MODE_32B) ? conv_data_32b : '0; // 256 bit
  assign conv_o.strb = ~ctrl_i.enable_streamout             ? '0 :
                       (ctrl_i.quant_mode == NEUREKA_MODE_8B)  ? (ctrl_i.streamout_len == 0     ? '1 : (1 << ( ctrl_i.streamout_len))   - 1)  :
                       (ctrl_i.quant_mode == NEUREKA_MODE_32B && addr_cnt_stage1_q < (ctrl_i.streamout_len/WIDTH_FACTOR + (ctrl_i.streamout_len%WIDTH_FACTOR==0 ? 0 : 1) -1) ) ? '1 :
                       (ctrl_i.quant_mode == NEUREKA_MODE_32B) ? (ctrl_i.streamout_len % 8 == 0 ? '1 : (1 << ((ctrl_i.streamout_len % 8)*4)) -1) : '1;

endmodule
