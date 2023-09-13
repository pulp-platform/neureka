/*
 * neureka_infeat_buffer_scm.sv
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

module neureka_infeat_buffer_scm
#(
  parameter int unsigned ADDR_WIDTH   = 6,
  parameter int unsigned DATA_WIDTH   = 128,
  parameter int unsigned NUM_WORDS    = 64
)
(
  input  logic                                 clk_i,
  input  logic                                 rst_ni,
  input  logic                                 clear_i,
  input  logic                                 test_mode_i,

  // Read port
  input  logic                                 re_i,
  input  logic [ADDR_WIDTH-1:0]                raddr_i,
  output logic [DATA_WIDTH-1:0]                rdata_o,

  // Write port
  input  logic                                 we_i,
  input  logic                                 we_all_i,
  input  logic [ADDR_WIDTH-1:0]                waddr_i,
  input  logic [DATA_WIDTH-1:0]                wdata_i,

  output logic [NUM_WORDS-1:0][DATA_WIDTH-1:0] infeat_buffer_o
);

  // Read address register, located at the input of the address decoder
  logic [NUM_WORDS-1:0][DATA_WIDTH-1:0] buffer;
  logic [NUM_WORDS-1:0]  waddr_onehot;
  logic [NUM_WORDS-1:0]  clk_we;

  logic [DATA_WIDTH-1:0] wdata_q;

  // ========================================================================
  // WDATA SAMPLING
  // ========================================================================
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)
      wdata_q <= '0;
    else if(clear_i)
      wdata_q <= '0;
    else if(we_i)
      wdata_q <= wdata_i;
  end

  // ========================================================================
  // SCM (LATCHES)
  // ========================================================================

  // use the sampled address to select the correct rdata_o
  // decode
  generate
    for(genvar ii=0; ii<NUM_WORDS; ii++) begin : WADDR_DECODE

      always_comb
      begin : waddr_decoding
        if((we_i==1'b1) && (waddr_i == ii))
          waddr_onehot[ii] = 1'b1;
        else if(we_all_i==1'b1)
          waddr_onehot[ii] = 1'b1;
        else
          waddr_onehot[ii] = clear_i;
      end

    end
  endgenerate

  // generate one clock-gating cell for each register element
  generate
    for(genvar ii=0; ii<NUM_WORDS; ii++) begin : CG_CELL_WORD_ITER

      cluster_clock_gating i_cg
      (
        .clk_o     ( clk_we[ii]       ),
        .en_i      ( waddr_onehot[ii] ),
        .test_en_i ( test_mode_i      ),
        .clk_i     ( clk_i            )
      );

    end
  endgenerate

  generate

    for(genvar ii=0; ii<NUM_WORDS; ii++) begin : LATCH

      always_latch
      begin : latch_wdata
        if( clk_we[ii] ) begin
          buffer[ii] = clear_i ? '0 : wdata_q;
        end
      end

    end

  endgenerate

  assign infeat_buffer_o = buffer;

endmodule // neureka_infeat_buffer_scm
