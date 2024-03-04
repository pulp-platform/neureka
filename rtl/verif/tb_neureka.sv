/*
 * tb_neureka.sv
 *
 * Copyright (C) 2019-2024 ETH Zurich, University of Bologna
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
 * Authors (NEUREKA): Francesco Conti <f.conti@unibo.it>
 *                    Arpan Suravi Prasad <prasadar@iis.ee.ethz.ch>
 */

timeunit 1ps;
timeprecision 1ps;
import neureka_package::*;
module tb_neureka;

  // parameters
  parameter real PROB_STALL = 0.00;
  parameter int unsigned TP_IN  = NEUREKA_TP_IN;
  parameter int unsigned TP_OUT = NEUREKA_TP_OUT;
  parameter int unsigned BP = 9*NEUREKA_TP_OUT;
  parameter int unsigned MP = BP/NEUREKA_TP_OUT;
  parameter MEMORY_SIZE = 2*8192*3;
  parameter STACK_MEMORY_SIZE = 4*MEMORY_SIZE;
  parameter BASE_ADDR = 0;
  parameter ID = 16;
  parameter NC = 8;
  parameter HWPE_ADDR_BASE_BIT = 20;
  parameter STIM_INSTR = "./stim_instr.txt";
  parameter STIM_DATA  = "./stim_data.txt";
  parameter STIM_OUTPUT_DATA = "./stim_output_data.txt";
  parameter DATA_BASE_ADDRESS = 32'h1c01_0000;
  parameter VLEN_CNT_SIZE = 32;

  // global signals
  logic                         clk_i  = '0;
  logic                         rst_ni = '1;
  logic                         test_mode_i = '0;
  // local enable
  logic                         enable_i = '1;
  logic                         clear_i  = '0;

  logic fetch_enable = 1'b0;
  logic busy = 1'b1;
  logic randomize_conv     = 1'b0;
  logic force_ready_feat   = 1'b0;
  logic force_ready_weight = 1'b0;
  logic randomize_mem      = 1'b0;
  logic stallable_mem      = 1'b0;
  logic enable_conv   = 1'b1;
  logic enable_feat   = 1'b1;
  logic enable_weight = 1'b1;
  logic enable_mem    = 1'b1;
  int in_len;
  int out_len;
  int threshold_shift;

  hwpe_stream_intf_tcdm instr[0:0]  (.clk(clk_i));
  hwpe_stream_intf_tcdm stack[0:0]  (.clk(clk_i));
  hwpe_stream_intf_tcdm tcdm [MP:0] (.clk(clk_i)); // 1 more memory port to access from TB zeroriscy core
  hwpe_stream_intf_tcdm tcdm_weight [MP-1:0] (.clk(clk_i)); // 1 more memory port to access from TB zeroriscy core
  hwpe_ctrl_intf_periph periph (.clk(clk_i));

  logic [NC-1:0][1:0] evt;
  logic neureka_busy;

  logic [MP-1:0]       tcdm_req;
  logic [MP-1:0]       tcdm_gnt;
  logic [MP-1:0][31:0] tcdm_add;
  logic [MP-1:0]       tcdm_wen;
  logic [MP-1:0][3:0]  tcdm_be;
  logic [MP-1:0][31:0] tcdm_data;
  logic [MP-1:0][31:0] tcdm_r_data;
  logic [MP-1:0]       tcdm_r_valid;

  logic [MP-1:0]       tcdm_w_req;
  logic [MP-1:0]       tcdm_w_gnt;
  logic [MP-1:0][31:0] tcdm_w_add;
  logic [MP-1:0]       tcdm_w_wen;
  logic [MP-1:0][3:0]  tcdm_w_be;
  logic [MP-1:0][31:0] tcdm_w_data;
  logic [MP-1:0][31:0] tcdm_w_r_data;
  logic [MP-1:0]       tcdm_w_r_valid;

  logic          periph_req;
  logic          periph_gnt;
  logic [31:0]   periph_add;
  logic          periph_wen;
  logic [3:0]    periph_be;
  logic [31:0]   periph_data;
  logic [ID-1:0] periph_id;
  logic [31:0]   periph_r_data;
  logic          periph_r_valid;
  logic [ID-1:0] periph_r_id;

  logic          instr_req;
  logic          instr_gnt;
  logic          instr_rvalid;
  logic [31:0]   instr_addr;
  logic [31:0]   instr_rdata;

  logic          data_req;
  logic          data_gnt;
  logic          data_rvalid;
  logic          data_we;
  logic [3:0]    data_be;
  logic [31:0]   data_addr;
  logic [31:0]   data_wdata;
  logic [31:0]   data_rdata;
  logic          data_err;

  // ATI timing parameters.
  localparam TCP = 1.0ns; // clock period, 1 GHz clock
  localparam TA  = 0.2ns; // application time
  localparam TT  = 0.8ns; // test time

  // Performs one entire clock cycle.
  task cycle;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TCP;
  endtask

  // The following task schedules the clock edges for the next cycle and
  // advances the simulation time to that cycles test time (localparam TT)
  // according to ATI timings.
  task cycle_start;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TT;
  endtask

  // The following task finishes a clock cycle previously started with
  // cycle_start by advancing the simulation time to the end of the cycle.
  task cycle_end;
    #(TCP-TT);
  endtask

  // bindings
  always
  begin : bind_periph
    #TA;
    periph_req  = data_req & data_addr[HWPE_ADDR_BASE_BIT];
    periph_add  = data_addr;
    periph_wen  = ~data_we;
    periph_be   = data_be;
    periph_data = data_wdata;
    periph_id   = '0;
    periph.gnt     = periph_gnt;
    periph.r_data  = periph_r_data;
    periph.r_valid = periph_r_valid;
    periph.r_id    = periph_r_id;
  end

  always_comb
  begin : bind_instrs
    instr[0].req  = instr_req;
    instr[0].add  = instr_addr;
    instr[0].wen  = 1'b1;
    instr[0].be   = '0;
    instr[0].data = '0;
    instr_gnt    = instr[0].gnt;
    instr_rdata  = instr[0].r_data;
    instr_rvalid = instr[0].r_valid;
  end

  always_comb
  begin : bind_stack
    stack[0].req  = data_req & (data_addr[31:24] == '0) & ~data_addr[HWPE_ADDR_BASE_BIT];
    stack[0].add  = data_addr;
    stack[0].wen  = ~data_we;
    stack[0].be   = data_be;
    stack[0].data = data_wdata;
  end

  logic other_r_valid;
  always_ff @(posedge clk_i)
  begin
    other_r_valid <= data_req & (data_addr[31:24] == 8'h80);
  end

  generate
    for(genvar ii=0; ii<MP; ii++) begin : tcdm_binding
      assign tcdm[ii].req  = tcdm_req  [ii];
      assign tcdm[ii].add  = tcdm_add  [ii];
      assign tcdm[ii].wen  = tcdm_wen  [ii];
      assign tcdm[ii].be   = tcdm_be   [ii];
      assign tcdm[ii].data = tcdm_data [ii];
      assign tcdm_gnt     [ii] = tcdm[ii].gnt;
      assign tcdm_r_data  [ii] = tcdm[ii].r_data;
      assign tcdm_r_valid [ii] = tcdm[ii].r_valid;
    end

    for(genvar ii=0; ii<MP; ii++) begin : tcdm_w_binding
      assign tcdm_weight[ii].req  = tcdm_w_req  [ii];
      assign tcdm_weight[ii].add  = tcdm_w_add  [ii] + MEMORY_SIZE*4;
      assign tcdm_weight[ii].wen  = tcdm_w_wen  [ii];
      assign tcdm_weight[ii].be   = tcdm_w_be   [ii];
      assign tcdm_weight[ii].data = tcdm_w_data [ii];
      assign tcdm_w_gnt     [ii] = tcdm_weight[ii].gnt;
      assign tcdm_w_r_data  [ii] = tcdm_weight[ii].r_data;
      assign tcdm_w_r_valid [ii] = tcdm_weight[ii].r_valid;
    end

    assign tcdm[MP].req  = data_req & (data_addr[31:24] != '0) & (data_addr[31:24] != 8'h80) & ~data_addr[HWPE_ADDR_BASE_BIT];
    assign tcdm[MP].add  = data_addr;//-DATA_BASE_ADDRESS;
    assign tcdm[MP].wen  = ~data_we;
    assign tcdm[MP].be   = data_be;
    assign tcdm[MP].data = data_wdata;
    assign data_gnt    = periph_req ? periph_gnt : stack[0].req ? stack[0].gnt : tcdm[MP].req ? tcdm[MP].gnt : '1;
    assign data_rdata  = periph_r_valid ? periph_r_data : stack[0].r_valid ? stack[0].r_data : tcdm[MP].r_valid ? tcdm[MP].r_data : '0;
    assign data_rvalid = periph_r_valid | stack[0].r_valid | tcdm[MP].r_valid | other_r_valid;
  endgenerate

  neureka_top_wrap #(
    .TP_IN        ( TP_IN               ),
    .TP_OUT       ( TP_OUT            ),
    .CNT          ( TP_IN            ),
    // .BW           (9*32),
    // .MP           ( MP               ),
    .ID           ( ID               ),
    .PE_H         ( 4 ),
    .PE_W         ( 4 )
  ) i_dut (
    .clk_i          ( clk_i          ),
    .rst_ni         ( rst_ni         ),
    .test_mode_i    ( test_mode_i    ),
    .evt_o          ( evt            ),
    .busy_o         ( neureka_busy      ),
    .tcdm_req       ( tcdm_req       ),
    .tcdm_add       ( tcdm_add       ),
    .tcdm_wen       ( tcdm_wen       ),
    .tcdm_be        ( tcdm_be        ),
    .tcdm_data      ( tcdm_data      ),
    .tcdm_gnt       ( tcdm_gnt       ),
    .tcdm_r_data    ( tcdm_r_data    ),
    .tcdm_r_valid   ( tcdm_r_valid   ),
    .tcdm_w_req       ( tcdm_w_req       ),
    .tcdm_w_add       ( tcdm_w_add       ),
    .tcdm_w_wen       ( tcdm_w_wen       ),
    .tcdm_w_be        ( tcdm_w_be        ),
    .tcdm_w_data      ( tcdm_w_data      ),
    .tcdm_w_gnt       ( tcdm_w_gnt       ),
    .tcdm_w_r_data    ( tcdm_w_r_data    ),
    .tcdm_w_r_valid   ( tcdm_w_r_valid   ),
    .periph_req     ( periph_req     ),
    .periph_gnt     ( periph_gnt     ),
    .periph_add     ( periph_add     ),
    .periph_wen     ( periph_wen     ),
    .periph_be      ( periph_be      ),
    .periph_data    ( periph_data    ),
    .periph_id      ( periph_id      ),
    .periph_r_data  ( periph_r_data  ),
    .periph_r_valid ( periph_r_valid ),
    .periph_r_id    ( periph_r_id    )
  );

  tb_dummy_memory #(
    .MP              ( MP+1         ), // 1 more port added to interface from the TB zeroriscy core
    .MEMORY_SIZE     ( MEMORY_SIZE  ),
    .BASE_ADDR       ( 32'h1c010000 ),
    .PROB_STALL      ( PROB_STALL   ),
    .TCP             ( TCP          ),
    .TA              ( TA           ),
    .TT              ( TT           )
  ) i_dummy_memory (
    .clk_i       ( clk_i         ),
    .randomize_i ( randomize_mem ),
    .enable_i    ( enable_mem    ),
    .stallable_i ( busy          ),
    .tcdm        ( tcdm          )
  );

  tb_dummy_memory #(
    .MP              ( MP           ), 
    .MEMORY_SIZE     ( MEMORY_SIZE  ),
    .BASE_ADDR       ( 32'h1c010000+MEMORY_SIZE*4),
    .PROB_STALL      ( PROB_STALL   ),
    .TCP             ( TCP          ),
    .TA              ( TA           ),
    .TT              ( TT           )
  ) i_dummy_weight_memory (
    .clk_i       ( clk_i         ),
    .randomize_i ( randomize_mem ),
    .enable_i    ( enable_mem    ),
    .stallable_i ( busy          ),
    .tcdm        ( tcdm_weight   )
  );

  tb_dummy_memory #(
    .MP          ( 1           ),
    .MEMORY_SIZE ( MEMORY_SIZE ),
    .BASE_ADDR   ( BASE_ADDR   ),
    .PROB_STALL  ( 0           ),
    .TCP         ( TCP         ),
    .TA          ( TA          ),
    .TT          ( TT          )
  ) i_dummy_instr_memory (
    .clk_i       ( clk_i ),
    .randomize_i ( 1'b0  ),
    .enable_i    ( 1'b1  ),
    .stallable_i ( 1'b0  ),
    .tcdm        ( instr )
  );

  tb_dummy_memory #(
    .MP          ( 1                  ),
    .MEMORY_SIZE ( STACK_MEMORY_SIZE  ),
    .BASE_ADDR   ( BASE_ADDR          ),
    .PROB_STALL  ( 0                  ),
    .TCP         ( TCP                ),
    .TA          ( TA                 ),
    .TT          ( TT                 )
  ) i_dummy_stack_memory (
    .clk_i       ( clk_i ),
    .randomize_i ( 1'b0  ),
    .enable_i    ( 1'b1  ),
    .stallable_i ( 1'b0  ),
    .tcdm        ( stack )
  );

  zeroriscy_core #(
    .N_EXT_PERF_COUNTERS ( 0 ),
    .RV32E               ( 0 ),
    .RV32M               ( 1 )
  ) i_zeroriscy (
    .clk_i               ( clk_i        ),
    .rst_ni              ( rst_ni       ),
    .clock_en_i          ( 1'b1         ),
    .test_en_i           ( 1'b0         ),
    .core_id_i           ( '1           ),
    .cluster_id_i        ( '0           ),
    .boot_addr_i         ( '0           ),
    .instr_req_o         ( instr_req    ),
    .instr_gnt_i         ( instr_gnt    ),
    .instr_rvalid_i      ( instr_rvalid ),
    .instr_addr_o        ( instr_addr   ),
    .instr_rdata_i       ( instr_rdata  ),
    .data_req_o          ( data_req     ),
    .data_gnt_i          ( data_gnt     ),
    .data_rvalid_i       ( data_rvalid  ),
    .data_we_o           ( data_we      ),
    .data_be_o           ( data_be      ),
    .data_addr_o         ( data_addr    ),
    .data_wdata_o        ( data_wdata   ),
    .data_rdata_i        ( data_rdata   ),
    .data_err_i          ( data_err     ),
    .irq_i               ( evt[0][0]    ),
    .irq_id_i            ( '0           ),
    .irq_ack_o           (              ),
    .irq_id_o            (              ),
    .debug_req_i         ( '0           ),
    .debug_gnt_o         (              ),
    .debug_rvalid_o      (              ),
    .debug_addr_i        ( '0           ),
    .debug_we_i          ( '0           ),
    .debug_wdata_i       ( '0           ),
    .debug_rdata_o       (              ),
    .debug_halted_o      (              ),
    .debug_halt_i        ( '0           ),
    .debug_resume_i      ( '0           ),
    .fetch_enable_i      ( fetch_enable ),
    .ext_perf_counters_i ( '0           )
  );

  initial begin
    #(20*TCP);

    // Reset phase.
    rst_ni <= #TA 1'b0;
    #(20*TCP);
    rst_ni <= #TA 1'b1;

    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b0;
    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b1;

    while(1) begin
      cycle();
    end

  end

  integer f_t0, f_t1;
  integer f_x, f_W, f_y, f_tau;
  logic start;

  int errors = -1;
  always_ff @(posedge clk_i)
  begin
    if((data_addr == 32'h80000000 ) && (data_we & data_req == 1'b1)) begin
      errors = data_wdata;
    end
    if((data_addr == 32'h80000004 ) && (data_we & data_req == 1'b1)) begin
      $write("%c", data_wdata);
    end
  end

  int cnt_cycles;
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni)  
      cnt_cycles <= 0;
    else if(neureka_busy) begin
      cnt_cycles += 1;
    end
  end

  initial begin

    integer id;
    int cnt_rd, cnt_wr;

    f_t0 = $fopen("time_start.txt");
    f_t1 = $fopen("time_stop.txt");
    start = 1'b1;

    periph.req  <= #TA '0;
    periph.add  <= #TA '0;
    periph.wen  <= #TA '0;
    periph.be   <= #TA '0;
    periph.data <= #TA '0;
    periph.id   <= #TA '0;

    // load instruction memory
    $readmemh(STIM_INSTR, tb_neureka.i_dummy_instr_memory.memory);
    $readmemh(STIM_DATA, tb_neureka.i_dummy_memory.memory);
    $readmemh(STIM_DATA, tb_neureka.i_dummy_weight_memory.memory);
    #(60*TCP);
    fetch_enable = 1'b1;
    #TA;

    #(400*TCP);
    // end WFI + errors != -1 signals end-of-computation
    while(tb_neureka.i_zeroriscy.sleeping || errors==-1)
      #(TCP);
    cnt_rd = tb_neureka.i_dummy_memory.cnt_rd[0] + tb_neureka.i_dummy_memory.cnt_rd[1] + tb_neureka.i_dummy_memory.cnt_rd[2] + tb_neureka.i_dummy_memory.cnt_rd[3];
    cnt_wr = tb_neureka.i_dummy_memory.cnt_wr[0] + tb_neureka.i_dummy_memory.cnt_wr[1] + tb_neureka.i_dummy_memory.cnt_wr[2] + tb_neureka.i_dummy_memory.cnt_wr[3];
    
    $writememh(STIM_OUTPUT_DATA, tb_neureka.i_dummy_memory.memory);
    $display("hwpe cycles = %d\n", cnt_cycles);

    $finish;

  end

  integer f_log;

  initial
  begin
    $system("mkdir -p ne16");
    f_log = $fopen("ne16/log.json");
    $fwrite(f_log, "[\n  { \"instance\": \"dummy\", \"type\": \"dummy\", \"value\": \"0\", \"time\": \"0\" }");
  end

  final
  begin
    $fwrite(f_log, "\n]");
    $fclose(f_log);
  end

  logic [31:0] read_addr_queue [$];

  string str;
  always_ff @(negedge clk_i or negedge rst_ni)
  begin : trace_outputs
    if(tb_neureka.i_dut.i_neureka_top.norm.valid & tb_neureka.i_dut.i_neureka_top.norm.ready) begin
      $sformat( str, ",\n  { \"instance\": \"norm\", \"type\": \"data\", \"value\": \"0x%072x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.norm.data, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
    end
    if(tb_neureka.i_dut.i_neureka_top.weight.valid & tb_neureka.i_dut.i_neureka_top.weight.ready) begin
      $sformat( str, ",\n  { \"instance\": \"weight\", \"type\": \"data\", \"value\": \"0x%072x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.weight.data, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
    end
    if(tb_neureka.i_dut.i_neureka_top.feat.valid & tb_neureka.i_dut.i_neureka_top.feat.ready) begin
      $sformat( str, ",\n  { \"instance\": \"feat\", \"type\": \"data\", \"value\": \"0x%072x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.feat.data, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
    end
    if(tb_neureka.i_dut.i_neureka_top.conv.valid & tb_neureka.i_dut.i_neureka_top.conv.ready) begin
      $sformat( str, ",\n  { \"instance\": \"conv\", \"type\": \"data\", \"value\": \"0x%072x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.conv.data, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
    end
    if(tb_neureka.i_dut.i_neureka_top.tcdm.req & tb_neureka.i_dut.i_neureka_top.tcdm.gnt) begin
      if(tb_neureka.i_dut.i_neureka_top.tcdm.wen)
        read_addr_queue.push_front(tb_neureka.i_dut.i_neureka_top.tcdm.add);
      else begin
        $sformat( str, ",\n  { \"instance\": \"tcdm_store\", \"type\": \"addr\", \"value\": \"0x%08x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.tcdm.add, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
        $sformat( str, ",\n  { \"instance\": \"tcdm_store\", \"type\": \"data\", \"value\": \"0x%072x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.tcdm.data, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
        $sformat( str, ",\n  { \"instance\": \"tcdm_store\", \"type\": \"be\", \"value\": \"0x%09x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.tcdm.be, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
      end
    end
    if(tb_neureka.i_dut.i_neureka_top.tcdm.r_valid & tb_neureka.i_dut.i_neureka_top.tcdm.r_ready) begin
      $sformat( str, ",\n  { \"instance\": \"tcdm_load\", \"type\": \"addr\", \"value\": \"0x%08x\", \"job\": \"%1d\", \"time\": \"%t\" }", read_addr_queue.pop_back(), tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
      $sformat( str, ",\n  { \"instance\": \"tcdm_load\", \"type\": \"r_data\", \"value\": \"0x%072x\", \"job\": \"%1d\", \"time\": \"%t\" }", tb_neureka.i_dut.i_neureka_top.tcdm.r_data, tb_neureka.i_dut.i_neureka_top.i_ctrl.i_slave.i_regfile.running_job_id, $time); $fwrite(f_log, str);
    end
  end

endmodule // tb_neureka
