/*
 * neureka_accumulator_buffer.sv
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
 * Authors (NEUREKA): Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 */

module neureka_accumulator_buffer #(

 parameter DATA_WIDTH     = 32,
 parameter NUM_WORDS    = 32,
 parameter WIDTH_FACTOR = 8,
 parameter NMULT        = 4,
 localparam ADDR_WIDTH  = $clog2(NUM_WORDS)
)(

  input  logic                              clk_i,
  input  logic                              rst_ni,

  input  logic                              enable_i,
  input  logic                              clear_i,

  input  logic                              we_i, // write enable for a single address
  input  logic                              we_wide_i,// write enable for 8 consecutive address
  input  logic                              we_all_i, // write enable for all the memory
  input  logic [NUM_WORDS-1:0]              we_all_mask_i, // write anable mask when entire memory is enabled

  input  logic [ADDR_WIDTH-1:0]             waddr_i, //write address for 1 memory location when we_i enabled or consecutive WIDTH_FACTOR memory location.
  input  logic [DATA_WIDTH-1:0]             wdata_i, //data to write in a single memory location
  input  logic [WIDTH_FACTOR*DATA_WIDTH-1:0]wdata_wide_i,// wide data to write into WIDTH_FACTOR memory location.
  input  logic [NUM_WORDS*DATA_WIDTH-1:0]   wdata_all_i,// write data for all memory location

  input  logic [ADDR_WIDTH-1:0]             raddr_i,//read address for a single meory location
  output logic [DATA_WIDTH-1:0]             rdata_o,//read address for a single meory location
  input  logic [NUM_WORDS-1:0]              rd_all_mask_i, // read enable mask for wide memory read
  output logic [WIDTH_FACTOR*DATA_WIDTH-1:0]rdata_wide_o,//read address for a single meory location
  output logic [NUM_WORDS*DATA_WIDTH-1:0]   rdata_all_o//read address for entire meory location

);

  logic [NUM_WORDS-1:0][DATA_WIDTH-1:0] buffer_d, buffer_q;
  logic [NUM_WORDS-1:0][DATA_WIDTH-1:0] buffer_all; // masked buffer used for all;
  logic [NUM_WORDS-1:0][DATA_WIDTH-1:0] buffer_wide; // masked buffer used for wide;

  logic [NUM_WORDS-1:0] clk_word, clk_word_en;

  for(genvar ii=0; ii<NUM_WORDS/WIDTH_FACTOR; ii++) begin : buffer_comb_gen
    for(genvar jj=0; jj<WIDTH_FACTOR; jj++) begin : buffer_comb_gen2
      localparam ii_jj = ii*WIDTH_FACTOR+jj;
      assign buffer_wide[ii_jj] = (we_all_mask_i[(ii+1)*WIDTH_FACTOR-1:ii*WIDTH_FACTOR] == 8'hff) ? wdata_wide_i[(jj+1)*DATA_WIDTH-1:jj*DATA_WIDTH] : buffer_q[ii_jj];
      assign buffer_all[ii_jj]  = we_all_mask_i[ii_jj] & we_all_i ? wdata_all_i[(ii_jj+1)*DATA_WIDTH-1:ii_jj*DATA_WIDTH] : buffer_q[ii_jj];
      assign clk_word_en[ii_jj] = (we_all_mask_i[(ii+1)*WIDTH_FACTOR-1:ii*WIDTH_FACTOR] == 8'hff) | (we_all_mask_i[ii_jj] & we_all_i);
    end
  end 

  always_comb begin : comb_buffer_update
    buffer_d = buffer_q;
    if(clear_i) begin
      buffer_d = '0; 
    end else if((~we_wide_i) & we_i)begin
      buffer_d[waddr_i] = wdata_i;
    end else if((~we_i) & (~we_all_i) & we_wide_i) begin
      buffer_d = buffer_wide;
    end else if(we_all_i)begin 
      buffer_d = buffer_all;  
    end 
  end : comb_buffer_update


  assign rdata_o       = buffer_q[raddr_i];
  assign rdata_all_o   = buffer_q;

  always_comb begin
    rdata_wide_o = buffer_q[WIDTH_FACTOR-1:0]; 
    case(raddr_i[2:0])  
      3'b000 : rdata_wide_o = buffer_q[WIDTH_FACTOR-1:0];
      3'b001 : rdata_wide_o = buffer_q[2*WIDTH_FACTOR-NMULT-1:1*WIDTH_FACTOR-NMULT];
      3'b010 : rdata_wide_o = buffer_q[2*WIDTH_FACTOR-1:1*WIDTH_FACTOR];
      3'b011 : rdata_wide_o = buffer_q[3*WIDTH_FACTOR-NMULT-1:2*WIDTH_FACTOR-NMULT];
      3'b100 : rdata_wide_o = buffer_q[3*WIDTH_FACTOR-1:2*WIDTH_FACTOR];
      3'b101 : rdata_wide_o = buffer_q[4*WIDTH_FACTOR-NMULT-1:3*WIDTH_FACTOR-NMULT];
      3'b110 : rdata_wide_o = buffer_q[4*WIDTH_FACTOR-1:3*WIDTH_FACTOR];
      3'b111 : rdata_wide_o = {64'b0, buffer_q[4*WIDTH_FACTOR-1:4*WIDTH_FACTOR-NMULT]};
    endcase
  end 

  for(genvar ii=0; ii<NUM_WORDS; ii++) begin : buffer_gen

    // word-level clock gating cell
    cluster_clock_gating i_cg (
      .clk_o     ( clk_word[ii]              ),
      .en_i      ( clk_word_en[ii] | clear_i ),
      .test_en_i ( 1'b0                      ),
      .clk_i     ( clk_i                     )
    );

    // generate flip-flop-based buffers (can not use
    // latches here due to the direct feedback with adders)
    always_ff @(posedge clk_word[ii] or negedge rst_ni)
    begin
      if(~rst_ni) begin 
        buffer_q[ii] <= '0;
      end
      else begin 
        buffer_q[ii] <= buffer_d[ii];
      end 
    end
  end 

endmodule
