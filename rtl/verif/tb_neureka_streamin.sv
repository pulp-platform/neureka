/*
 * tb_neureka_streamin.sv
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
 * Standalone regression for the STREAMIN -> STREAMOUT path of
 * neureka_accumulator_normquant (default parameters). For every output channel
 * count 1..32 it streams accumulators in (8-bit, sign-extended, or 32-bit),
 * streams them out (8-bit or 32-bit) and checks data, strobes, beat counts and
 * FSM progression. Source bubbles and sink back-pressure are applied
 * deterministically; successive jobs are separated by ctrl_i.clear as done by
 * neureka_ctrl, and a mid-job clear_i and rst_ni are also exercised.
 */

timeunit 1ps;
timeprecision 1ps;

module tb_neureka_streamin;

  import neureka_package::*;

  localparam int unsigned NCH          = NEUREKA_TP_OUT;            // accumulators per column
  localparam int unsigned BW           = NEUREKA_MEM_BANDWIDTH;      // stream width in bits
  localparam int unsigned WORDS        = BW / NEUREKA_ACCUM_SIZE;    // 32-bit words per beat
  localparam int unsigned PHASE_CYCLES = 200;                        // per-phase watchdog
  localparam time         CLK_HALF     = 5;
  localparam time         T_DRIVE      = 2;                          // input skew after posedge

  logic clk, rst_ni, clear;
  logic [31:0] lfsr = 32'hace1_2024;

  ctrl_aq_t  ctrl;
  flags_aq_t flags;

  hwpe_stream_intf_stream #( .DATA_WIDTH ( 32 ) ) conv           ( .clk ( clk ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( 32 ) ) conv_dw [NEUREKA_BLOCK_SIZE-1:0] ( .clk ( clk ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( BW ) ) norm           ( .clk ( clk ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( BW ) ) streamin       ( .clk ( clk ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( BW ) ) conv_out       ( .clk ( clk ) );

  // unused inputs: no partial sums, no normalization parameters
  assign conv.valid = 1'b0;
  assign conv.data  = '0;
  assign conv.strb  = '0;
  assign norm.valid = 1'b0;
  assign norm.data  = '0;
  assign norm.strb  = '0;
  for (genvar ii = 0; ii < NEUREKA_BLOCK_SIZE; ii++) begin : conv_dw_tie_gen
    assign conv_dw[ii].valid = 1'b0;
    assign conv_dw[ii].data  = '0;
    assign conv_dw[ii].strb  = '0;
  end

  neureka_accumulator_normquant i_dut (
    .clk_i       ( clk      ),
    .rst_ni      ( rst_ni   ),
    .test_mode_i ( 1'b0     ),
    .enable_i    ( 1'b1     ),
    .clear_i     ( clear    ),
    .conv_i      ( conv     ),
    .conv_dw_i   ( conv_dw  ),
    .norm_i      ( norm     ),
    .streamin_i  ( streamin ),
    .conv_o      ( conv_out ),
    .ctrl_i      ( ctrl     ),
    .flags_o     ( flags    )
  );

  initial begin
    clk = 1'b0;
    forever #CLK_HALF clk = ~clk;
  end

  // ------------------------------------------------------------------------
  // Bookkeeping
  // ------------------------------------------------------------------------

  int unsigned n_jobs, n_checks, n_in_beats, n_out_beats, n_bubbles, n_stalls;
  logic [NCH-1:0][31:0] acc_exp;  // expected accumulator content after STREAMIN

  function automatic logic [31:0] next_rand();
    lfsr ^= lfsr << 13;
    lfsr ^= lfsr >> 17;
    lfsr ^= lfsr << 5;
    return lfsr;
  endfunction

  task automatic check(input bit cond, input string what);
    n_checks++;
    if (!cond)
      $fatal(1, "[tb_neureka_streamin] FAIL @%0t job %0d: %s", $time, n_jobs, what);
  endtask

  task automatic drive_edge();
    @(posedge clk);
    #T_DRIVE;
  endtask

  // one-cycle control pulse, as neureka_ctrl does with state_change
  task automatic pulse_goto(input bit to_streamin);
    drive_edge();
    ctrl.goto_streamin  = to_streamin;
    ctrl.goto_streamout = ~to_streamin;
    drive_edge();
    ctrl.goto_streamin  = 1'b0;
    ctrl.goto_streamout = 1'b0;
  endtask

  task automatic pulse_ctrl_clear();
    drive_edge();
    ctrl.clear = 1'b1;
    drive_edge();
    ctrl.clear = 1'b0;
  endtask

  // ------------------------------------------------------------------------
  // STREAMIN: 8-bit mode sends one beat of 32 bytes (each sign-extended into
  // an accumulator); 32-bit mode sends ceil(len/8) beats of 8 words.
  // ------------------------------------------------------------------------

  task automatic run_streamin(input int unsigned len, input bit si32, input int unsigned max_beats = 0);
    logic [BW-1:0] beat [];
    int unsigned nbeats, b, cycles;
    bit hs;

    nbeats = si32 ? (len + WORDS - 1) / WORDS : 1;
    beat   = new [nbeats];
    for (int unsigned i = 0; i < nbeats; i++)
      for (int unsigned w = 0; w < WORDS; w++)
        beat[i][w*32 +: 32] = next_rand();
    // corner values on the first lanes
    if (si32) begin
      beat[0][  0 +: 32] = 32'h8000_0000;
      beat[0][ 32 +: 32] = 32'h7fff_ffff;
      beat[0][ 64 +: 32] = 32'hffff_ffff;
      beat[0][ 96 +: 32] = 32'h0000_0001;
    end else begin
      beat[0][ 0 +: 8] = 8'h80;
      beat[0][ 8 +: 8] = 8'h7f;
      beat[0][16 +: 8] = 8'hff;
      beat[0][24 +: 8] = 8'h01;
    end
    // only the first len channels are ever compared
    acc_exp = '0;
    for (int unsigned c = 0; c < len; c++)
      acc_exp[c] = si32 ? beat[c / WORDS][(c % WORDS)*32 +: 32] :
                          {{24{beat[0][c*8+7]}}, beat[0][c*8 +: 8]};

    ctrl.streamin_mode = si32 ? NEUREKA_STREAMIN_MODE_32B : NEUREKA_STREAMIN_MODE_8B;
    pulse_goto(1'b1);
    if (max_beats != 0 && max_beats < nbeats)
      nbeats = max_beats; // partial job, interrupted by the caller

    b = 0;
    cycles = 0;
    while (b < nbeats) begin
      if (!streamin.valid) begin
        if (next_rand() % 4 == 0) begin
          n_bubbles++;
        end else begin
          streamin.valid = 1'b1;
          streamin.data  = beat[b];
          streamin.strb  = '1;
        end
      end
      @(negedge clk);
      check(flags.state == AQ_STREAMIN, $sformatf("STREAMIN state expected before beat %0d, got %s", b, flags.state.name()));
      hs = streamin.valid & streamin.ready;
      drive_edge();
      if (hs) begin
        b++;
        n_in_beats++;
        streamin.valid = 1'b0;
      end
      check(++cycles < PHASE_CYCLES, "STREAMIN watchdog");
    end
    if (max_beats == 0) begin
      @(negedge clk);
      check(flags.state == AQ_STREAMIN_DONE, $sformatf("STREAMIN_DONE expected after %0d beats, got %s", nbeats, flags.state.name()));
    end
  endtask

  // ------------------------------------------------------------------------
  // STREAMOUT: 8-bit mode sends one beat (byte c = low byte of accumulator c);
  // 32-bit mode sends ceil(len/8) beats of 8 words. Only the first len
  // channels are strobed and compared.
  // ------------------------------------------------------------------------

  task automatic run_streamout(input int unsigned len, input bit q32);
    int unsigned nbeats, b, cycles, ch;
    logic [BW-1:0]   prev_data;
    logic [BW/8-1:0] prev_strb, exp_strb;
    bit stalled;

    ctrl.quant_mode = q32 ? NEUREKA_MODE_32B : NEUREKA_MODE_8B;
    nbeats  = q32 ? (len + WORDS - 1) / WORDS : 1;
    pulse_goto(1'b0);

    b = 0;
    cycles = 0;
    stalled = 1'b0;
    while (b < nbeats) begin
      // first cycle of every beat is back-pressured, then random
      conv_out.ready = stalled ? (next_rand() % 3 != 0) : 1'b0;
      @(negedge clk);
      check(flags.state == AQ_STREAMOUT, $sformatf("STREAMOUT state expected before beat %0d, got %s", b, flags.state.name()));
      check(conv_out.valid === 1'b1, $sformatf("valid low before beat %0d", b));
      if (stalled) begin
        check(conv_out.data === prev_data, $sformatf("data changed while stalled, beat %0d", b));
        check(conv_out.strb === prev_strb, $sformatf("strb changed while stalled, beat %0d", b));
      end
      if (conv_out.ready) begin
        for (int unsigned i = 0; i < BW/8; i++) begin
          ch = q32 ? b*WORDS + i/4 : i;
          exp_strb[i] = (ch < len);
        end
        check(conv_out.strb === exp_strb, $sformatf("beat %0d strb %h, expected %h", b, conv_out.strb, exp_strb));
        if (q32) begin
          for (int unsigned w = 0; w < WORDS; w++)
            if (b*WORDS + w < len)
              check(conv_out.data[w*32 +: 32] === acc_exp[b*WORDS + w],
                    $sformatf("ch %0d: got %h, expected %h", b*WORDS + w, conv_out.data[w*32 +: 32], acc_exp[b*WORDS + w]));
        end else begin
          for (int unsigned c = 0; c < len; c++)
            check(conv_out.data[c*8 +: 8] === acc_exp[c][7:0],
                  $sformatf("ch %0d: got %h, expected %h", c, conv_out.data[c*8 +: 8], acc_exp[c][7:0]));
        end
        b++;
        n_out_beats++;
        stalled = 1'b0;
      end else begin
        n_stalls++;
        stalled   = 1'b1;
        prev_data = conv_out.data;
        prev_strb = conv_out.strb;
      end
      drive_edge();
      check(++cycles < PHASE_CYCLES, "STREAMOUT watchdog");
    end
    conv_out.ready = 1'b0;
    @(negedge clk);
    check(flags.state == AQ_STREAMOUT_DONE, $sformatf("STREAMOUT_DONE expected after %0d beats, got %s", nbeats, flags.state.name()));
    check(conv_out.valid === 1'b0, "valid still high after last beat");
  endtask

  task automatic run_job(input int unsigned len, input bit si32, input bit q32);
    ctrl.streamout_len = len;
    ctrl.last_pe       = n_jobs[0]; // cover both the last and a non-last column
    ctrl.clock_gating  = 1'b1;
    run_streamin(len, si32);
    run_streamout(len, q32);
    pulse_ctrl_clear(); // as on entry to STREAMOUT_DONE in neureka_ctrl
    drive_edge();
    ctrl.clock_gating  = 1'b0;
    n_jobs++;
  endtask

  // abort a STREAMIN job halfway through (source idle), then check that the
  // next job starts from a clean state
  task automatic interrupt_streamin(input bit use_reset);
    ctrl.streamout_len = NCH;
    ctrl.clock_gating  = 1'b1;
    run_streamin(NCH, 1'b1, 2);
    drive_edge();
    if (use_reset) rst_ni = 1'b0;
    else           clear  = 1'b1;
    drive_edge();
    rst_ni = 1'b1;
    clear  = 1'b0;
    @(negedge clk);
    check(flags.state == AQ_IDLE, $sformatf("IDLE expected after %s, got %s", use_reset ? "rst_ni" : "clear_i", flags.state.name()));
    drive_edge();
    ctrl.clock_gating = 1'b0;
  endtask

  initial begin : watchdog
    #(2 * CLK_HALF * 200_000);
    $fatal(1, "[tb_neureka_streamin] FAIL: global timeout");
  end

  initial begin : stimuli
    n_jobs      = 0;
    n_checks    = 0;
    n_in_beats  = 0;
    n_out_beats = 0;
    n_bubbles   = 0;
    n_stalls    = 0;
    ctrl           = '0;
    ctrl.enable_streamout = 1'b1;
    streamin.valid = 1'b0;
    streamin.data  = '0;
    streamin.strb  = '0;
    conv_out.ready = 1'b0;
    clear          = 1'b0;
    rst_ni         = 1'b0;
    repeat (4) drive_edge();
    rst_ni = 1'b1;
    pulse_ctrl_clear(); // as on entry to IDLE in neureka_ctrl

    for (int unsigned len = 1; len <= NCH; len++)
      for (int unsigned mode = 0; mode < 4; mode++) begin
        run_job(len, mode[1], mode[0]);
        if (len == NCH/2 && mode == 3) begin
          interrupt_streamin(1'b0);
          run_job(NCH, 1'b1, 1'b1);
          interrupt_streamin(1'b1);
          run_job(NCH, 1'b0, 1'b1);
        end
      end

    check(n_bubbles > 0 && n_stalls > 0, "no source bubbles or sink stalls were generated");
    $display("[tb_neureka_streamin] PASS: %0d jobs, %0d checks, %0d input beats, %0d output beats, %0d bubbles, %0d stalls",
             n_jobs, n_checks, n_in_beats, n_out_beats, n_bubbles, n_stalls);
    $finish;
  end

endmodule // tb_neureka_streamin
