/*
 * neureka_top_wrap.sv
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

module neureka_top_wrap
  import neureka_package::*;
  import hwpe_ctrl_package::*;
  import hci_package::*;
#(
  parameter int unsigned TP_IN     = NEUREKA_TP_IN,  // number of input elements processed per cycle
  parameter int unsigned TP_OUT    = NEUREKA_TP_OUT, // number of output elements processed per cycle
  parameter int unsigned CNT       = VLEN_CNT_SIZE,  // counter size
  parameter int unsigned BW        = NEUREKA_MEM_BANDWIDTH_EXT,          
  parameter int unsigned MP        = BW/32,          // number of memory ports (each a 32bit data)
  parameter int unsigned ID        = ID_WIDTH,
  parameter int unsigned N_CORES   = NR_CORES,
  parameter int unsigned N_CONTEXT = NR_CONTEXT,
  parameter int unsigned PE_H      = NEUREKA_PE_H_DEFAULT,
  parameter int unsigned PE_W      = NEUREKA_PE_W_DEFAULT,
  parameter int unsigned REGFILE_N_EVT = 2
) (
  // global signals
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  logic                                  test_mode_i,
  // evnets
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  output logic                                  busy_o,
  // tcdm master ports
  output logic [     MP-1:0]                    tcdm_req,
  input  logic [     MP-1:0]                    tcdm_gnt,
  output logic [     MP-1:0][             31:0] tcdm_add,
  output logic [     MP-1:0]                    tcdm_wen,
  output logic [     MP-1:0][              3:0] tcdm_be,
  output logic [     MP-1:0][             31:0] tcdm_data,
  input  logic [     MP-1:0][             31:0] tcdm_r_data,
  input  logic [     MP-1:0]                    tcdm_r_valid,
  // dedicated weight port
  output logic [     MP-1:0]                    tcdm_w_req,
  input  logic [     MP-1:0]                    tcdm_w_gnt,
  output logic [     MP-1:0][             31:0] tcdm_w_add,
  output logic [     MP-1:0]                    tcdm_w_wen,
  output logic [     MP-1:0][              3:0] tcdm_w_be,
  output logic [     MP-1:0][             31:0] tcdm_w_data,
  input  logic [     MP-1:0][             31:0] tcdm_w_r_data,
  input  logic [     MP-1:0]                    tcdm_w_r_valid,

  // periph slave port
  input  logic                                  periph_req,
  output logic                                  periph_gnt,
  input  logic [       31:0]                    periph_add,
  input  logic                                  periph_wen,
  input  logic [        3:0]                    periph_be,
  input  logic [       31:0]                    periph_data,
  input  logic [     ID-1:0]                    periph_id,
  output logic [       31:0]                    periph_r_data,
  output logic                                  periph_r_valid,
  output logic [     ID-1:0]                    periph_r_id
);

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '{
    DW:  BW,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  0,
    IW:  0,
    EW:  0,
    EHW: 0
  };
  hci_core_intf #(
    .DW ( BW ),
    .UW ( 0  ),
    .IW ( 0  ),
    .EW ( 0  ),
    .EHW ( 0 )
`ifndef SYNTHESIS
    ,
    .WAIVE_RSP3_ASSERT ( 1'b1 ), // waive RSP-3 on memory-side of HCI FIFO
    .WAIVE_RSP5_ASSERT ( 1'b1 )  // waive RSP-5 on memory-side of HCI FIFO
`endif
  ) tcdm (
    .clk ( clk_i )
  );

  hwpe_ctrl_intf_periph #(.ID_WIDTH(ID)) periph (.clk(clk_i));

  // bindings
  generate
    for(genvar ii=0; ii<MP; ii++) begin: tcdm_binding
      assign tcdm_req  [ii] = tcdm.req;
      assign tcdm_add  [ii] = tcdm.add + ii*4;
      assign tcdm_wen  [ii] = tcdm.wen;
      assign tcdm_be   [ii] = tcdm.be[(ii+1)*4-1:ii*4];
      assign tcdm_data [ii] = tcdm.data[(ii+1)*32-1:ii*32];
    end
    assign tcdm.gnt     = &(tcdm_gnt);
    assign tcdm.r_valid = &(tcdm_r_valid);
    assign tcdm.r_data  = { >> {tcdm_r_data} } ;
  endgenerate

  generate
    for(genvar ii=0; ii<MP; ii++) begin: tcdm_weight_binding
      assign tcdm_w_req  [ii] = '0;
      assign tcdm_w_add  [ii] = '0;
      assign tcdm_w_wen  [ii] = '0;
      assign tcdm_w_be   [ii] = '0;
      assign tcdm_w_data [ii] = '0;
    end
  endgenerate

  always_comb
    begin
      periph.req     = periph_req;
      periph.add     = periph_add;
      periph.wen     = periph_wen;
      periph.be      = periph_be;
      periph.data    = periph_data;
      periph.id      = periph_id;
      periph_gnt     = periph.gnt;
      periph_r_data  = periph.r_data;
      periph_r_valid = periph.r_valid;
      periph_r_id    = periph.r_id;
    end

  neureka_top #(
    .TP_IN                 ( TP_IN                 ),
    .TP_OUT                ( TP_OUT                ),
    .CNT                   ( CNT                   ),
    .BW                    ( BW                    ),
    .ID                    ( ID                    ),
    .N_CORES               ( N_CORES               ),
    .N_CONTEXT             ( N_CONTEXT             ),
    .PE_H                  ( PE_H                  ),
    .PE_W                  ( PE_W                  ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_neureka_top (
    .clk_i       ( clk_i          ),
    .rst_ni      ( rst_ni         ),
    .test_mode_i ( test_mode_i    ),
    .evt_o       ( evt_o          ),
    .busy_o      ( busy_o         ),
    .tcdm        ( tcdm.initiator ),
    .periph      ( periph.slave   )
  );

endmodule // neureka_top_wrap
