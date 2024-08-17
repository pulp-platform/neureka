/*
 * neureka_package.sv
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

package neureka_package;

  // ========================================================================
  // PULP contents
  // ========================================================================

  parameter int NR_HWPE_REG   = 11;
  parameter int NR_HCI_REG    = 1;
  parameter int NR_UCODE_REG  = 12;
  parameter int REGFILE_SCM   = 0;

  // general PULP environment parameters including clusters etc
  // default number of cores
  parameter int NR_CORES = 9;

  parameter int NEUREKA_PE_H_DEFAULT = -1; // 4; // Number of PEs across height
  parameter int NEUREKA_PE_W_DEFAULT = -1; // 4; // Number of PEs across width
  parameter int NEUREKA_PE_HW_DEFAULT = -1; // NEUREKA_PE_H_DEFAULT*NEUREKA_PE_W_DEFAULT; // Total number of PEs

  parameter int NEUREKA_INFEAT_BUFFER_SIZE_H_DEFAULT = -1; // NEUREKA_PE_H_DEFAULT+2; // Input Feature buffer size across height. 
  parameter int NEUREKA_INFEAT_BUFFER_SIZE_W_DEFAULT = -1; // NEUREKA_PE_W_DEFAULT+2; // Input Feature buffer size across width
  parameter int NEUREKA_INFEAT_BUFFER_SIZE_HW_DEFAULT = -1; // NEUREKA_INFEAT_BUFFER_SIZE_H_DEFAULT*NEUREKA_INFEAT_BUFFER_SIZE_W_DEFAULT; // Input Feature buffer size 
  parameter int NEUREKA_INFEAT_BUFFER_SIZE_HW_MAX = 36; // Max. input buffer size currently considered

  // number of contexts
  parameter int NR_CONTEXT = 1;

  // default id width
  parameter int ID_WIDTH = 16;

  // number of registers
  parameter int NR_IO_REGS      = NR_HWPE_REG + NR_UCODE_REG; // 10 + 11 = 21
  parameter int NR_GENERIC_REGS = NR_HCI_REG;                 // 1

  // ========================================================================
  // CTRL Registers
  // ========================================================================

  // ctrl counter bit-widths
  parameter int SPATIAL_CNT_SIZE   = 16;
  parameter int FILTER_CNT_SIZE    =  5;
  parameter int FEAT_CNT_SIZE      = 12;
  parameter int QUANT_CNT_SIZE     =  8;
  parameter int NB_ACC_CNT_SIZE    =  8;

  // ========================================================================
  // BANDWIDTH related types
  parameter int NEUREKA_MEM_BANDWIDTH_EXT    = 288; // bits (9 ports x 32 bits)  to support misaligned access
  parameter int NEUREKA_MEM_BANDWIDTH_WEIGHT = 288; // bits (9 ports x 32 bits) 
  parameter int NEUREKA_MEM_BANDWIDTH        = 256; // bits (8 ports x 32 bits) -- this is after realignment
  parameter int NEUREKA_STREAM_BANDWIDTH     = 320; // bits (10 ports x 32 bits) 

  // ========================================================================
  // BINCONV related types
  // Throughput parameter for a single BinConv module
  parameter int NEUREKA_TP_IN     = 32;
  parameter int NEUREKA_QA_IN     = 8;
  parameter int NEUREKA_QA_OUT    = 8;
  parameter int NEUREKA_TP_OUT    = 32;
  parameter int NEUREKA_QA_16BIT  = 0; // overhead in 16-bit. Not supported in this version 

  // number of 1x8-bit multipliers per BinConv block
  parameter int NEUREKA_BLOCK_SIZE = 32;

  // number of binary BinConv blocks per BinConv column
  parameter int NEUREKA_COLUMN_SIZE = 9;

  // number of PEs 
  // parameter int NEUREKA_NUM_PE = NEUREKA_PE_H*NEUREKA_PE_W;
  parameter int NEUREKA_NUM_PE_MAX = 36;

  // number of shift cycles
  parameter int NEUREKA_SHIFT_CYCLES = 2;

  // ========================================================================
  // ACCUMULATOR module related types
  // number of bits used in vlen_cnt
  parameter int NEUREKA_ACCUM_SIZE = 32;
  parameter int VLEN_CNT_SIZE           = 16;

  // (batch-)normalization parameters
  parameter int unsigned NORM_MULT_SIZE = 8;

  // ========================================================================
  // ECC-extended HCI related types
  // number of data bits to encode separately
  parameter int unsigned ECC_CHUNK_SIZE = 32;
  parameter int unsigned ECC_N_CHUNK    = NEUREKA_MEM_BANDWIDTH_EXT / ECC_CHUNK_SIZE;

  // ========================================================================
  // FEAT_BUFFER related types
  // ========================================================================
  typedef struct packed {
    logic                     goto_load;
    logic                     goto_extract;
    logic                     goto_idle;
    logic [VLEN_CNT_SIZE-1:0] load_len;
    logic [NEUREKA_INFEAT_BUFFER_SIZE_HW_MAX-1:0] enable_implicit_padding;
    logic [NEUREKA_INFEAT_BUFFER_SIZE_HW_MAX-1:0] enable_explicit_padding;
    logic [NEUREKA_QA_IN-1:0]    explicit_padding_value_hi;
    logic [NEUREKA_QA_IN-1:0]    explicit_padding_value_lo;
    logic [1:0]               filter_mode;
    logic                     feat_broadcast;
  } ctrl_infeat_buffer_t;


  typedef struct packed {
    logic write;
    logic read;
    ctrl_infeat_buffer_t ctrl_odd_infeat_buffer;
    ctrl_infeat_buffer_t ctrl_even_infeat_buffer;
   
  } ctrl_double_infeat_buffer_t;



  typedef enum {
    IB_IDLE, IB_LOAD, IB_EXTRACT
  } state_infeat_buffer_t;

  typedef struct packed {
    state_infeat_buffer_t state;
  } flags_infeat_buffer_t;


  typedef struct packed {
    logic write;
    logic read ;  
    flags_infeat_buffer_t flags_odd_infeat_buffer;
    flags_infeat_buffer_t flags_even_infeat_buffer;
  } flags_double_infeat_buffer_t;


  // ========================================================================
  // SIGN_BUFFER related types
  // ========================================================================
  typedef struct packed {
    logic                     goto_load;
    logic                     goto_extract;
    logic [VLEN_CNT_SIZE-1:0] i_vlen;       // virtual buffer length
    logic [VLEN_CNT_SIZE-1:0] o_vlen;
  } ctrl_sign_buf_t;

  typedef enum {
    SR_IDLE, SR_LOAD, SR_EXTRACT
  } state_sign_buf_t;

  typedef struct packed {
    state_sign_buf_t state;
  } flags_sign_buf_t;


  // ========================================================================
  // SOP related types
  // ========================================================================
  typedef struct packed {
    logic                    operation_sel; // 1:xnor, 0: and
    logic [NEUREKA_TP_IN-1:0]   inactive_mask;
    logic                    clear;
  } ctrl_sop_t;


  // ========================================================================
  // Accumulator Quantizor related types
  // ========================================================================

  typedef struct packed {
    logic                            start;
    logic                            relu;
    logic [4:0]                      right_shift;
    logic [1:0]                      norm_mode;
    logic [1:0]                      quant_mode;
    logic                            norm_signed;
    logic                            use_rounding;
    logic                            use_shifting;
  } ctrl_normquant_t;

  typedef struct packed {
    logic ready;
  } flags_normquant_t;

  parameter logic[1:0] NEUREKA_MODE_8B  = 2'b00;
  parameter logic[1:0] NEUREKA_MODE_16B = 2'b01;
  parameter logic[1:0] NEUREKA_MODE_32B = 2'b10;


  parameter logic[1:0] NEUREKA_STREAMIN_8B_QUANT_8B = 2'b00;
  parameter logic[1:0] NEUREKA_STREAMIN_8B_QUANT_32B = 2'b01;
  parameter logic[1:0] NEUREKA_STREAMIN_32B_QUANT_8B = 2'b10;
  parameter logic[1:0] NEUREKA_STREAMIN_32B_QUANT_32B = 2'b11;


  parameter logic NEUREKA_STREAMIN_MODE_8B  = 1'b0;
  parameter logic NEUREKA_STREAMIN_MODE_32B = 1'b1;

  parameter logic[1:0] NEUREKA_FILTER_MODE_1X1    = 2'b10;
  parameter logic[1:0] NEUREKA_FILTER_MODE_3X3_DW = 2'b01;
  parameter logic[1:0] NEUREKA_FILTER_MODE_3X3    = 2'b00;

  typedef struct packed {
    logic [       VLEN_CNT_SIZE-1:0] full_accumulation_len;   // nr of accumulations
    logic [       VLEN_CNT_SIZE-1:0] streamout_len;
    logic [       VLEN_CNT_SIZE-1:0] scale_len;
    logic [       VLEN_CNT_SIZE-1:0] bias_len;
    logic                            clear;
    logic                            dw_accum;
    logic                            clock_gating;
    logic                            clear_offset;
    logic                            goto_normquant;
    logic                            goto_accum;
    logic                            goto_streamin;
    logic                            goto_streamout;
    logic                            goto_idle;
    logic                            sample_shift;
    logic [1:0]                      quant_mode;   // 00: 8 bits, 01: 16 bits (reserved for future usage), 11: 32 bits
    logic [1:0]                      norm_mode;    // 00: 8 bits, 01: 16 bits, 11: 32 bits
    logic                            streamin_mode;
    ctrl_normquant_t                 ctrl_normquant;
    logic                            norm_option_bias;
    logic                            norm_option_shift;
    logic                            weight_offset;
    logic [31:0]                     weight_offset_scale;
    logic [$clog2(QUANT_CNT_SIZE):0] qw;       // weights quantization
    logic                            enable_streamout;
    logic                            depthwise;
  } ctrl_aq_t;

  typedef enum {
    AQ_IDLE, AQ_ACCUM, AQ_NORMQUANT_SHIFT, AQ_NORMQUANT, AQ_NORMQUANT_TOBIAS, AQ_NORMQUANT_BIAS, AQ_STREAMIN, AQ_STREAMOUT, AQ_ACCUM_DONE, AQ_NORMQUANT_DONE, AQ_STREAMIN_DONE, AQ_STREAMOUT_DONE
  } state_aq_t;

  typedef struct packed {
    state_aq_t  state;
    logic       addr_cnt_en_q;
    logic [VLEN_CNT_SIZE-1:0] count;
  } flags_aq_t;

  // ========================================================================
  // SCALE related types
  // ========================================================================

  parameter int unsigned MAX_SHIFT = 16;
  typedef struct packed {
    logic [$clog2(MAX_SHIFT):0] shift_sel;
    logic                       invert;
  } ctrl_scale_t;

  typedef struct packed {
    logic [$clog2(MAX_SHIFT):0] shift_sel;
  } flags_scale_t;


  typedef struct packed {
    logic [$clog2(QUANT_CNT_SIZE):0] qw;
    logic [1:0] filter_mode;              // filter size
    logic [$clog2(8):0] scale_shift;
    logic                weight_offset;
    logic                dw_weight_offset;
    logic                clear;
    logic [NEUREKA_COLUMN_SIZE-1:0] enable_block;
    logic [$clog2(NEUREKA_QA_IN):0] block_cnt;
    logic invalidate;
  } ctrl_binconv_col_t;

  typedef struct packed {
    flags_scale_t [NEUREKA_BLOCK_SIZE-1:0]  flags_scale;
  } flags_binconv_block_t;

  // ========================================================================
  // BINCONV_PE related types
  // ========================================================================
  typedef struct packed {
    ctrl_binconv_col_t                ctrl_col;
    logic [NEUREKA_BLOCK_SIZE-1:0]    enable_col;
    logic [4*NEUREKA_COLUMN_SIZE-1:0] enable_col_pw;
    logic                             dw_accum;
    logic [31:0]                      padding_value;
  } ctrl_binconv_pe_t;

  typedef struct packed {
    flags_binconv_block_t [NEUREKA_COLUMN_SIZE-1:0] flags_block;
  } flags_binconv_column_t;

  // ========================================================================
  // BINCONV_ARRAY related types
  // ========================================================================

  typedef struct packed {
    ctrl_binconv_pe_t               ctrl_pe;
    logic [$clog2(NEUREKA_TP_IN):0] depthwise_len;
    logic [NEUREKA_NUM_PE_MAX-1:0]  enable_pe;
    logic [1:0]                     filter_mode;
    logic                           mode_linear;
    logic                           weight_offset;
  } ctrl_binconv_array_t;

  typedef struct packed {
    flags_binconv_column_t [NEUREKA_NUM_PE_MAX-1:0] flags_column;
  } flags_binconv_array_t;

  // ========================================================================
  // ENGINE related types
  // ========================================================================

  typedef struct packed {
    ctrl_double_infeat_buffer_t         ctrl_double_infeat_buffer;
    ctrl_binconv_array_t                ctrl_binconv_array;
    ctrl_aq_t                           ctrl_accumulator;
    hwpe_stream_package::ctrl_serdes_t  ctrl_serialize_streamin;
    hwpe_stream_package::ctrl_serdes_t  ctrl_serialize_streamout;
    logic [NEUREKA_NUM_PE_MAX-1:0]      enable_accumulator;
    logic                               clear_des;
    logic                               mode_linear;
  } ctrl_engine_t;

  typedef struct packed {
    flags_double_infeat_buffer_t          flags_double_infeat_buffer;
    flags_aq_t   [NEUREKA_NUM_PE_MAX-1:0] flags_accumulator;
    flags_binconv_array_t                 flags_binconv_array;
  } flags_engine_t;

  // ========================================================================
  // URISCY CTRL related types
  // ========================================================================

  typedef struct packed {
    logic start;
  } ctrl_ctrlmult_t;

  typedef struct packed {
    logic valid;
  } flags_ctrlmult_t;


  // ========================================================================
  // STREAMER related types
  // ========================================================================

  typedef enum { LD_FEAT_SEL, LD_FEAT_WEIGHT_SEL, LD_WEIGHT_SEL, LD_NORM_SEL, LD_STREAMIN_SEL } ld_which_mux_sel_t;
  parameter logic LD_SEL = 1'b0;
  parameter logic ST_SEL = 1'b1;

  typedef struct packed {
    ld_which_mux_sel_t               ld_which_mux_sel;
    logic                            ld_st_mux_sel;
    logic                            clear_fifo;
    logic                            clear_source;
    logic                            clear_sink;
    logic                            wmem_sel;
    hci_package::hci_streamer_ctrl_t infeat_source_ctrl;
    hci_package::hci_streamer_ctrl_t weight_source_ctrl;
    hci_package::hci_streamer_ctrl_t wmem_source_ctrl;
    hci_package::hci_streamer_ctrl_t norm_source_ctrl;
    hci_package::hci_streamer_ctrl_t outfeat_sink_ctrl;
    hci_package::hci_streamer_ctrl_t streamin_source_ctrl;
  } ctrl_streamer_t;

  typedef struct packed {
    hci_package::hci_streamer_flags_t feat_source_flags;
    hci_package::hci_streamer_flags_t weight_source_flags;
    hci_package::hci_streamer_flags_t norm_source_flags;
    hci_package::hci_streamer_flags_t conv_sink_flags;
    logic tcdm_fifo_empty;
  } flags_streamer_t;


  // ========================================================================
  // CTRL FSM related types
  // ========================================================================

  typedef enum {
    IDLE, STREAMIN, LOAD, WEIGHTOFFS, MATRIXVEC, NORMQUANT, NORMQUANT_BIAS, NORMQUANT_SHIFT, STREAMOUT, STREAMOUT_DONE, UPDATEIDX, UPDATEIDX_WAIT, DONE
  } state_neureka_t; 

  typedef struct packed {
    logic [31:0] weights_kom_iter;
    logic [31:0] weights_kim_iter;
    logic [31:0] weights_kom_reset_iter;
    logic [31:0] weights_kim_reset_iter;
    logic [31:0] infeat_kim_iter;
    logic [31:0] infeat_wom_iter;
    logic [31:0] infeat_hom_iter;
    logic [31:0] infeat_kim_reset_iter;
    logic [31:0] infeat_wom_reset_iter;
    logic [31:0] infeat_hom_reset_iter;
    logic [31:0] outfeat_wom_iter;
    logic [31:0] outfeat_hom_iter;
    logic [31:0] outfeat_kom_iter;
    logic [31:0] outfeat_wom_reset_iter;
    logic [31:0] outfeat_hom_reset_iter;
    logic [31:0] outfeat_kom_reset_iter;
    logic [31:0] scale_kom_iter;
  } uloop_iter_neureka_t;

  typedef struct packed {
    logic [31:0] weights_ptr;
    logic [31:0] infeat_ptr;
    logic [31:0] outfeat_ptr;
    logic [31:0] scale_ptr;
    logic [31:0] streamin_ptr;
    logic [31:0] scale_shift_ptr;
    logic [31:0] scale_bias_ptr;
    logic [15:0] subtile_nb_ko; // register n_tiles_k_out
    logic [15:0] subtile_rem_ko; // register k_out_rest
    logic [15:0] subtile_nb_ki; // register n_tiles_k_in
    logic [15:0] subtile_rem_ki; // register k_in_rest
    logic [15:0] subtile_nb_ho; // register n_tiles_h_out
    logic [15:0] subtile_rem_ho; // register h_out_rest
    logic [15:0] subtile_nb_wo; // register n_tiles_w_out
    logic [15:0] subtile_rem_wo; // register w_out_rest
    logic [15:0] subtile_rem_hi; // register h_in_rest
    logic [15:0] subtile_rem_wi; // register w_in_rest
    logic [31:0] infeat_d0_stride; // register x_word_stride
    logic [31:0] infeat_d1_stride; // register x_line_stride
    logic [31:0] infeat_d2_stride; // register x_block_stride
    logic [31:0] weights_d0_stride; // register W_word_stride
    logic [31:0] weights_d1_stride; // register W_line_stride
    logic [31:0] weights_d2_stride; // register W_block_stride
    logic [31:0] outfeat_d0_stride; // register y_word_stride
    logic [31:0] outfeat_d1_stride; // register y_line_stride
    logic [31:0] outfeat_d2_stride; // register y_block_stride
    logic [3:0]  padding_top;
    logic [3:0]  padding_right;
    logic [3:0]  padding_bottom;
    logic [3:0]  padding_left;
    logic [15:0] padding_value;
    logic        feat_broadcast;
    logic        norm_option_bias;
    logic        norm_option_shift;
    logic [31:0] weight_offset_scale;
    logic [7:0]  filter_mask_top;
    logic [7:0]  filter_mask_right;
    logic [7:0]  filter_mask_bottom;
    logic [7:0]  filter_mask_left;
    logic [1:0]  filter_mode;
    logic [1:0]  norm_mode;
    logic [1:0]  quant_mode;
    logic        streamin_mode;
    logic        relu;
    logic        streamin;
    logic        streamout_quant;
    logic        wmem_sel;
    logic        prefetch;
    logic        mode_linear;
    logic        mode_strided;
    logic [3:0]  weight_bits;
    logic        use_rounding;
    logic [4:0]  shift_reqnt;
    uloop_iter_neureka_t uloop_iter;
  } config_neureka_t;

  typedef struct packed {
    logic [15:0] k_out_major;
    logic [15:0] i_major;
    logic [15:0] j_major;
    logic [15:0] k_in_major;
  } index_neureka_t;

  typedef struct packed {
    logic k_out_major;
    logic i_major;
    logic j_major;
    logic k_in_major;
  } index_update_neureka_t;

  typedef struct packed {
    logic [31:0] weights;
    logic [31:0] infeat;
    logic [31:0] outfeat;
    logic [31:0] scale;
  } base_addr_neureka_t;

  parameter int unsigned NEUREKA_ULOOP_BASE_ADDR_W            = 0;
  parameter int unsigned NEUREKA_ULOOP_BASE_ADDR_X            = 1;
  parameter int unsigned NEUREKA_ULOOP_BASE_ADDR_Y            = 2;
  parameter int unsigned NEUREKA_ULOOP_BASE_ADDR_S            = 3;
  parameter int unsigned NEUREKA_ULOOP_RO_WEIGHTS_KOM_ITER  = 4  - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_WEIGHTS_KIM_ITER  = 5  - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_WEIGHTS_KOM_RESET_ITER = 6  - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_WEIGHTS_KIM_RESET_ITER = 7  - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_INFEAT_KIM_ITER   = 8  - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_INFEAT_WOM_ITER   = 9  - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_INFEAT_HOM_ITER   = 10 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_INFEAT_KIM_RESET_ITER  = 11 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_INFEAT_WOM_RESET_ITER  = 12 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_INFEAT_HOM_RESET_ITER  = 13 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_OUTFEAT_WOM_ITER  = 14 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_OUTFEAT_HOM_ITER  = 15 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_OUTFEAT_KOM_ITER  = 16 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_OUTFEAT_WOM_RESET_ITER = 17 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_OUTFEAT_HOM_RESET_ITER = 18 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_OUTFEAT_KOM_RESET_ITER = 19 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_SCALE_KOM_ITER         = 20 - 4;
  parameter int unsigned NEUREKA_ULOOP_RO_ZERO                   = 21 - 4;

  // implemented with dual-context hwpe regs:
  parameter int NEUREKA_REG_WEIGHTS_PTR       = 0;  // Weights pointer: pointer to Weights tensor in memory (d3=Ko, d2=Fy, d1=Fx, d0=Ki).
  parameter int NEUREKA_REG_INFEAT_PTR        = 1;  // InFeat pointer: pointer to InFeat tensor in memory (d2=Hi, d1=Wi, d0=Ki).
  parameter int NEUREKA_REG_OUTFEAT_PTR       = 2;  // OutFeat pointer: pointer to OutFeat tensor in memory (d2=Ho, d1=Wo, d0=Ko).
  parameter int NEUREKA_REG_SCALE_PTR         = 3;  // Scale pointer: pointer to Scale parameters in memory (d0=Ko).
  parameter int NEUREKA_REG_SCALE_SHIFT_PTR   = 4;  // ScaleShift pointer: pointer to ScaleShift parameters in memory (d0=Ko).
  parameter int NEUREKA_REG_SCALE_BIAS_PTR    = 5;  // ScaleBias pointer: pointer to ScaleBias parameters in memory (d0=Ko).
  parameter int NEUREKA_REG_INFEAT_D0_STRIDE  = 6;  // InFeat d0 stride 
  parameter int NEUREKA_REG_INFEAT_D1_STRIDE  = 7;  // InFeat d1 stride
  parameter int NEUREKA_REG_INFEAT_D2_STRIDE  = 8;  // InFeat d2 stride
  parameter int NEUREKA_REG_OUTFEAT_D0_STRIDE = 9;  // OutFeat d0 stride
  parameter int NEUREKA_REG_OUTFEAT_D1_STRIDE = 10; // OutFeat d1 stride
  parameter int NEUREKA_REG_OUTFEAT_D2_STRIDE = 11; // OutFeat d2 stride
  parameter int NEUREKA_REG_WEIGHTS_D0_STRIDE = 12; // Weights d0 stride
  parameter int NEUREKA_REG_WEIGHTS_D1_STRIDE = 13; // Weights d1 stride
  parameter int NEUREKA_REG_WEIGHTS_D2_STRIDE = 14; // Weights d2 stride (may be removable)
  parameter int NEUREKA_REG_SUBTILE_REM0      = 15; // Subtile Remainder 0: [31:16] Ko, [15:0] Ki.
  parameter int NEUREKA_REG_SUBTILE_REM1      = 16; // Subtile Remainder 1: [31:16] Ho, [15:0] Wo.
  parameter int NEUREKA_REG_SUBTILE_REM2      = 17; // Subtile Remainder 2: [31:16] Hi, [15:0] Wi.
  parameter int NEUREKA_REG_SUBTILE_NB0       = 18; // Subtile Number 0: [31:16] Ko, [15:0] Ki.
  parameter int NEUREKA_REG_SUBTILE_NB1       = 19; // Subtile Number 1: [31:16] Ho, [15:0] Wo.
  parameter int NEUREKA_REG_PADDING           = 20; // Padding
  parameter int NEUREKA_REG_WEIGHT_OFFSET     = 21; // Weight offset factor
  parameter int NEUREKA_REG_FILTER_MASK       = 22; // Filter masking: [31:24] top, [23:16] right, [15:8] bottom, [7:0] left.
  parameter int NEUREKA_REG_CONFIG0           = 23; // Config 0:  [31:16] Reserved (striding, dilation?) [15] weight_offseting [14] streamin [13:12] normalization bits (00=8, 01=16, 10=32), [11] rounding (0=round, 1=do not round), [10:7] padding flag (top/right/bottom/left)  [6:5] filter mode (11=linear, 10=1x1, 01=3x3 depthwise, 00=3x3)  [4] streamout / quantization, [3] reserved (16 bits?), [2:0] weight bits minus 1.
  parameter int NEUREKA_REG_STREAMIN_PTR      = 24; // Streamin pointer: pointer to Streamin to initialize accumulators.

  // normal uloop microcode, generated by ucode/uloop_compile.py
  parameter logic[351:0] ULOOP_CODE_NORMAL     = 352'h04748a101215c078a30b22942d89f0aa15c078a30b22742985701e14405;
  parameter logic[53:0]  ULOOP_LOOPS_NORMAL    = 54'b011001001001100110000100100000000010;
  // depthwise uloop microcode, generated by ucode/uloop_compile_dw.py
  parameter logic[351:0] ULOOP_CODE_DEPTHWISE  = 352'h0420863a4288a101228c2c8a50b627c2a8a30b227429;
  parameter logic[53:0]  ULOOP_LOOPS_DEPTHWISE = 54'b011100010001101000000100100000000010;

  // mapping of weights in linear layers
  parameter int NEUREKA_LINEAR_MAP[0:80] = {
    0,  1,  2,  3,  4,  5,  6,  7,  -1,
    8,  9,  10, 11, 12, 13, 14, 15, -1,
    16, 17, 18, 19, 20, 21, 22, 23, -1,
    24, 25, 26, 27, 28, 29, 30, 31, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1
  };

  typedef struct packed {
    logic [1:0][ECC_N_CHUNK-1:0] r_data_single_err;
    logic [1:0][ECC_N_CHUNK-1:0] r_data_multi_err;
    logic [1:0]                  r_meta_single_err;
    logic [1:0]                  r_meta_multi_err;
  } errs_streamer_t;

endpackage
