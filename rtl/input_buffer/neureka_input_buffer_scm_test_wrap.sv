/*
 * neureka_infeat_buffer_scm_test_wrap.sv
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

module neureka_infeat_buffer_scm_test_wrap
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

  output logic [NUM_WORDS-1:0][DATA_WIDTH-1:0] infeat_buffer_o,

  // BIST ENABLE
  input  logic                                BIST,

  //BIST ports
  input  logic                                CSN_T,
  input  logic                                WEN_T,
  input  logic [ADDR_WIDTH-1:0]               A_T,
  input  logic [DATA_WIDTH-1:0]               D_T,
  output logic [DATA_WIDTH-1:0]               Q_T
);


   logic                         ReadEnable_muxed;
   logic [ADDR_WIDTH-1:0]        ReadAddr_muxed;

   logic                         WriteEnable_all_muxed;
   logic                         WriteEnable_muxed;
   logic [ADDR_WIDTH-1:0]        WriteAddr_muxed;
   logic [DATA_WIDTH-1:0]        WriteData_muxed;

   logic                         clear_muxed;

   always_comb
   begin
      if(BIST)
      begin
         ReadEnable_muxed  = (( CSN_T == 1'b0 ) && ( WEN_T == 1'b1));
         ReadAddr_muxed    = A_T;

         WriteEnable_all_muxed = 1'b0;
         WriteEnable_muxed = (( CSN_T == 1'b0 ) && ( WEN_T == 1'b0));
         WriteAddr_muxed   = A_T;
         WriteData_muxed   = D_T;

         clear_muxed       = 1'b0;
      end
      else
      begin
         ReadEnable_muxed  = re_i;
         ReadAddr_muxed    = raddr_i;

         WriteEnable_muxed     = we_i;
         WriteEnable_all_muxed = we_all_i;
         WriteAddr_muxed       = waddr_i;
         WriteData_muxed       = wdata_i;

         clear_muxed           = clear_i;
      end
   end

    assign Q_T = rdata_o;


    neureka_infeat_buffer_scm
    #(
      .ADDR_WIDTH     ( ADDR_WIDTH ),
      .DATA_WIDTH     ( DATA_WIDTH ),
      .NUM_WORDS      ( NUM_WORDS  )
    )
    neureka_infeat_buffer_scm_i
    (
      .clk_i          ( clk_i                 ),
      .rst_ni         ( rst_ni                ),
      .clear_i        ( clear_muxed           ),
      .test_mode_i    ( test_mode_i           ),

      // Read port
      .re_i           ( ReadEnable_muxed      ),
      .raddr_i        ( ReadAddr_muxed        ),
      .rdata_o        ( rdata_o               ),

      // Write port
      .we_i           ( WriteEnable_muxed     ),
      .we_all_i       ( WriteEnable_all_muxed ),
      .waddr_i        ( WriteAddr_muxed       ),
      .wdata_i        ( WriteData_muxed       ),

      .infeat_buffer_o ( infeat_buffer_o        )
    );

endmodule : neureka_infeat_buffer_scm_test_wrap
