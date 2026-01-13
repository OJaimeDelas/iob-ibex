// SPDX-License-Identifier: MIT
// Fault manager for Ibex with M-of-N -wrapped state.
// - Records minor/major fault events (sticky flags and counters).
// - On any major event, deasserts fetch_enable_o (IbexMuBiOff) to halt new fetches.
// - Optionally requests a synchronous system reset after halting.

`include "prim_assert.sv"
  
//------------------------------------------------------
// INPUTS
//------------------------------------------------------
//
// ----Fault/event inputs
//
// alert_minor_i — pulse when a recoverable/monitor-only issue is detected.
// alert_major_internal_i — pulse when Ibex detects a non-recoverable internal issue.
// alert_major_bus_i — pulse when a non-recoverable bus integrity issue is detected.
// double_fault_seen_i — pulse when Ibex observes a double-fault condition.
//
// ----Core status / observability
//
// core_sleep_i — high when the core is in WFI and has no outstanding bus activity.
// crash_dump_i[31:0] — a snapshot from Ibex you may capture elsewhere if desired. This module doesn’t latch it.
//

//------------------------------------------------------
// OUTPUTS
//------------------------------------------------------
//
// ----CPU Control
//
// fetch_enable_o — Drives Ibex’s multi-bit “fetch enable”. When set to IbexMuBiOff, the core stops fetching new instructions. The pipeline then drains (in-flight instructions in ID/EX/WB complete) and the core halts cleanly. This is not a reset; it’s a “freeze fetch” control.
// 
// core_reset_req_o — Level signal requesting a system reset. Whether and when it asserts depends on the parameters (see below). Your top-level reset controller can OR this into the SoC reset request.
//
// ----Status for SW/SoC
// 
// fault_sticky_o — latched “a major event has happened since last reset”.
// minor_seen_o — latched “a minor event has happened since last reset”.
// minor_cnt_o[15:0], major_cnt_o[15:0] — running 16-bit counters (wrap on overflow).

module fatori_fault_mgr
  import ibex_pkg::*;
#(
  parameter bit RESET_ON_MAJOR               = 1'b0,  // 1: request reset after major fault
  parameter bit WAIT_CORE_SLEEP_BEFORE_RESET = 1'b1   // 1: wait for core_sleep_i before reset
) (
  input  logic        clk_i,
  input  logic        rst_ni,   // active-low

  // Fault indications (pulses unless otherwise documented).
  input  logic        alert_minor_i,
  input  logic        alert_major_internal_i,
  input  logic        alert_major_bus_i,
  input  logic        double_fault_seen_i,

  // Core status.
  input  logic        core_sleep_i,
  input  crash_dump_t crash_dump_i,  // optional visibility; not latched here

  // Control outputs to the core / SoC.
  output ibex_mubi_t  fetch_enable_o,
  output logic        core_reset_req_o,

  // Optional status for SW/SoC.
  output logic        fault_sticky_o,
  output logic        minor_seen_o,
  output logic [15:0] minor_cnt_o,
  output logic [15:0] major_cnt_o

  `ifdef FATORI_FI
    // Fault injection port
    ,input  logic [7:0] fi_port
  `endif
  
  // Layer 1+: MoN aggregated error pulses (gated by FATORI_FT_LAYER)
  `ifdef FATORI_FT_LAYER_1
    `ifdef FATORI_FI
      ,input  logic       agg_mon_new_min_err_i
      ,input  logic       agg_mon_new_maj_err_i
    `endif

    // Layer 2+: Correction tracking
    `ifdef FATORI_FT_LAYER_2
      `ifdef FATORI_FI
        ,input  logic       agg_mon_scrub_occurred_i
      `endif
      ,output logic [15:0] corrected_cnt_o

      // Layer 3+: Timing metrics (REQUIRES FATORI_FI for injection pulses)
      `ifdef FATORI_FT_LAYER_3
        `ifdef FATORI_FI
          ,input  logic       reg_injection_pulse_i
          ,input  logic       logic_injection_pulse_i
        `endif
        ,output logic [31:0] cycles_to_first_min_o
        ,output logic [31:0] cycles_to_first_maj_o
        ,output logic [15:0] last_detection_latency_o

        // Layer 4+: Averaged metrics
        `ifdef FATORI_FT_LAYER_4
          ,output logic [31:0] latency_sum_o
          ,output logic [15:0] latency_count_o
        `endif
      `endif
    `endif
  `endif
);

  // Multi-bit constants as packed logic for use in M-of-N  reset values.
  localparam ibex_mubi_t MUBI_ON_T  = ibex_pkg::IbexMuBiOn;
  localparam ibex_mubi_t MUBI_OFF_T = ibex_pkg::IbexMuBiOff;
  localparam logic [$bits(ibex_mubi_t)-1:0] MUBI_ON  = MUBI_ON_T;
  localparam logic [$bits(ibex_mubi_t)-1:0] MUBI_OFF = MUBI_OFF_T;

  // Reset FSM encodings (packed vectors for M-of-N ).
  localparam logic [1:0] S_IDLE       = 2'd0;
  localparam logic [1:0] S_WAIT_SLEEP = 2'd1;
  localparam logic [1:0] S_ASSERT_RST = 2'd2;

 // Event aggregation.
  logic minor_pulse, major_pulse;

  `ifdef FATORI_FT_LAYER_1
    `ifdef FATORI_FI
      // Include MoN error signals when FATORI_FT_LAYER_1 and FATORI_FI are enabled
      assign minor_pulse = alert_minor_i | agg_mon_new_min_err_i;
      assign major_pulse = alert_major_internal_i | alert_major_bus_i | 
                           double_fault_seen_i | agg_mon_new_maj_err_i;
    `else
      // Only Ibex native signals
      assign minor_pulse = alert_minor_i;
      assign major_pulse = alert_major_internal_i | alert_major_bus_i | double_fault_seen_i;
    `endif
  `else
    // FATORI_FT_LAYER 0: Only Ibex native signals
    assign minor_pulse = alert_minor_i;
    assign major_pulse = alert_major_internal_i | alert_major_bus_i | double_fault_seen_i;
  `endif

  // Bookkeeping next-state signals.
  logic [15:0] minor_cnt_d, major_cnt_d;
  logic        minor_seen_d, fault_sticky_d;

  assign minor_cnt_d    = minor_pulse ? (minor_cnt_o + 16'd1) : minor_cnt_o;
  assign major_cnt_d    = major_pulse ? (major_cnt_o + 16'd1) : major_cnt_o;
  assign minor_seen_d   = minor_seen_o   | minor_pulse;
  assign fault_sticky_d = fault_sticky_o | major_pulse;

  // MoN-wrapped registers (async reset asserted when !rst_ni).
  `FATORI_REG('0, !rst_ni, '1, minor_cnt_d,    minor_cnt_o, fi_port, 8'd1, '0, '0, minor_cnt_o)
  `FATORI_REG('0, !rst_ni, '1, major_cnt_d,    major_cnt_o, fi_port, 8'd2, '0, '0,    major_cnt_o)
  `FATORI_REG('0, !rst_ni, '1, minor_seen_d,   minor_seen_o, fi_port, 8'd3, '0, '0,   minor_seen_o)
  `FATORI_REG('0, !rst_ni, '1, fault_sticky_d, fault_sticky_o, fi_port, 8'd4, '0, '0, fault_sticky_o)

  // Fetch-enable control: sticky OFF after first major event.
  logic [$bits(ibex_mubi_t)-1:0] fetch_en_q, fetch_en_d;
  assign fetch_en_d = (major_pulse ? MUBI_OFF : fetch_en_q);
  `FATORI_REG(MUBI_ON, !rst_ni, '1, fetch_en_d, fetch_en_q, fi_port, 8'd5, '0, '0, fetch_en_q)
  assign fetch_enable_o = ibex_mubi_t'(fetch_en_q);

  // Optional reset request FSM.
  logic [1:0] state_q, state_d;
  always_comb begin
    state_d = state_q;
    unique case (state_q)
      S_IDLE: begin
        if (RESET_ON_MAJOR && major_pulse) begin
          state_d = (WAIT_CORE_SLEEP_BEFORE_RESET ? S_WAIT_SLEEP : S_ASSERT_RST);
        end
      end
      S_WAIT_SLEEP: begin
        if (core_sleep_i) state_d = S_ASSERT_RST;
      end
      S_ASSERT_RST: begin
        state_d = S_ASSERT_RST;
      end
      default: state_d = S_IDLE;
    endcase
  end

  `FATORI_REG(S_IDLE, !rst_ni, '1, state_d, state_q, fi_port, 8'd6, '0, '0, state_q)

  assign core_reset_req_o = (state_q == S_ASSERT_RST);

  // ============================================================================
  // LAYER 2: Correction Tracking
  // ============================================================================
  `ifdef FATORI_FT_LAYER_1
    `ifdef FATORI_FT_LAYER_2
        // Correction counter - increments when scrubbing occurs
        logic [15:0] corrected_cnt_q, corrected_cnt_d;
        
        // Increment on scrubbing pulse
        `ifdef FATORI_FI
          assign corrected_cnt_d = agg_mon_scrub_occurred_i ? 
                                   (corrected_cnt_q + 16'd1) : corrected_cnt_q;
        `else
          // Without FATORI_FI, scrubbing signals don't exist
          assign corrected_cnt_d = corrected_cnt_q;
        `endif

        `FATORI_REG('0, !rst_ni, '1, corrected_cnt_d, corrected_cnt_q, fi_port, 8'd187, '0, '0, corrected_cnt_q)

        
        assign corrected_cnt_o = corrected_cnt_q;
    `endif
  `endif

  // ============================================================================
  // LAYER 3: Timing Metrics
  // ============================================================================
  `ifdef FATORI_FT_LAYER_1
    `ifdef FATORI_FT_LAYER_2
      `ifdef FATORI_FT_LAYER_3
          // Free-running cycle counter
          logic [31:0] cycle_counter_q, cycle_counter_d;
          assign cycle_counter_d = cycle_counter_q + 32'd1;

          `FATORI_REG('0, !rst_ni, '1, cycle_counter_d, cycle_counter_q, fi_port, 8'd188, '0, '0, cycle_counter_q)

          
          // Cycles to first minor error
          logic [31:0] cycles_to_first_min_q, cycles_to_first_min_d;
          logic        first_min_latched_q, first_min_latched_d;
          
          assign first_min_latched_d = first_min_latched_q | minor_pulse;
          assign cycles_to_first_min_d = (minor_pulse && !first_min_latched_q) ? 
                                          cycle_counter_q : cycles_to_first_min_q;

          `FATORI_REG('0, !rst_ni, '1, first_min_latched_d, first_min_latched_q, fi_port, 8'd189, '0, '0, first_min_latched_q)
          `FATORI_REG('0, !rst_ni, '1, cycles_to_first_min_d, cycles_to_first_min_q, fi_port, 8'd190, '0, '0, cycles_to_first_min_q)

          
          assign cycles_to_first_min_o = cycles_to_first_min_q;
          
          // Cycles to first major error
          logic [31:0] cycles_to_first_maj_q, cycles_to_first_maj_d;
          logic        first_maj_latched_q, first_maj_latched_d;
          
          assign first_maj_latched_d = first_maj_latched_q | major_pulse;
          assign cycles_to_first_maj_d = (major_pulse && !first_maj_latched_q) ? 
                                          cycle_counter_q : cycles_to_first_maj_q;
          
          `FATORI_REG('0, !rst_ni, '1, first_maj_latched_d, first_maj_latched_q, fi_port, 8'd191, '0, '0, first_maj_latched_q)
          `FATORI_REG('0, !rst_ni, '1, cycles_to_first_maj_d, cycles_to_first_maj_q, fi_port, 8'd192, '0, '0, cycles_to_first_maj_q)

          assign cycles_to_first_maj_o = cycles_to_first_maj_q;
          
          // Detection latency tracking (REQUIRES FATORI_FI for injection pulses)
          `ifdef FATORI_FI
            logic [31:0] last_injection_cycle_q, last_injection_cycle_d;
            logic [15:0] last_detection_latency_q, last_detection_latency_d;
            logic        injection_seen;
            logic        error_detected;
            
            assign injection_seen = reg_injection_pulse_i | logic_injection_pulse_i;
            assign error_detected = minor_pulse | major_pulse;
            
            assign last_injection_cycle_d = injection_seen ? cycle_counter_q : last_injection_cycle_q;
            assign last_detection_latency_d = error_detected ? 
                                               (cycle_counter_q[15:0] - last_injection_cycle_q[15:0]) : 
                                               last_detection_latency_q;
            
            `FATORI_REG('0, !rst_ni, '1, last_injection_cycle_d, last_injection_cycle_q, fi_port, 8'd193, '0, '0, last_injection_cycle_q)
            `FATORI_REG('0, !rst_ni, '1, last_detection_latency_d, last_detection_latency_q, fi_port, 8'd194, '0, '0, last_detection_latency_q)
            
            assign last_detection_latency_o = last_detection_latency_q;
          `else
            // Without FATORI_FI, detection latency is unavailable
            assign last_detection_latency_o = 16'd0;
          `endif
      `endif
    `endif
  `endif

 // ============================================================================
  // LAYER 4: Averaged Metrics
  // ============================================================================
  `ifdef FATORI_FT_LAYER_1
    `ifdef FATORI_FT_LAYER_2
      `ifdef FATORI_FT_LAYER_3
        `ifdef FATORI_FT_LAYER_4
            logic [31:0] latency_sum_q, latency_sum_d;
            logic [15:0] latency_count_q, latency_count_d;
            logic        error_detected_l4;
            
            assign error_detected_l4 = minor_pulse | major_pulse;
            
            `ifdef FATORI_FI
              // Only accumulate if we have valid latency measurements (requires FATORI_FI)
              assign latency_sum_d = error_detected_l4 ? 
                                     (latency_sum_q + {16'd0, last_detection_latency_q}) : 
                                     latency_sum_q;
            `else
              // Without injection tracking, can't compute meaningful latency averages
              assign latency_sum_d = latency_sum_q;
            `endif
            
            assign latency_count_d = error_detected_l4 ? (latency_count_q + 16'd1) : latency_count_q;
            
            `FATORI_REG('0, !rst_ni, '1, latency_sum_d, latency_sum_q, fi_port, 8'd195, '0, '0, latency_sum_q)
            `FATORI_REG('0, !rst_ni, '1, latency_count_d, latency_count_q, fi_port, 8'd196, '0, '0, latency_count_q)
            
            assign latency_sum_o = latency_sum_q;
            assign latency_count_o = latency_count_q;
        `endif
      `endif
    `endif
  `endif

endmodule
