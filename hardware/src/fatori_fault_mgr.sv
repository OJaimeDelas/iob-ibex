// SPDX-License-Identifier: MIT
// Fault manager for Ibex with TMR-wrapped state.
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
);

  // Multi-bit constants as packed logic for use in TMR reset values.
  localparam ibex_mubi_t MUBI_ON_T  = ibex_pkg::IbexMuBiOn;
  localparam ibex_mubi_t MUBI_OFF_T = ibex_pkg::IbexMuBiOff;
  localparam logic [$bits(ibex_mubi_t)-1:0] MUBI_ON  = MUBI_ON_T;
  localparam logic [$bits(ibex_mubi_t)-1:0] MUBI_OFF = MUBI_OFF_T;

  // Reset FSM encodings (packed vectors for TMR).
  localparam logic [1:0] S_IDLE       = 2'd0;
  localparam logic [1:0] S_WAIT_SLEEP = 2'd1;
  localparam logic [1:0] S_ASSERT_RST = 2'd2;

  // Event aggregation.
  logic minor_pulse, major_pulse;
  assign minor_pulse = alert_minor_i;
  assign major_pulse = alert_major_internal_i | alert_major_bus_i | double_fault_seen_i;

  // Bookkeeping next-state signals.
  logic [15:0] minor_cnt_d, major_cnt_d;
  logic        minor_seen_d, fault_sticky_d;

  assign minor_cnt_d    = minor_pulse ? (minor_cnt_o + 16'd1) : minor_cnt_o;
  assign major_cnt_d    = major_pulse ? (major_cnt_o + 16'd1) : major_cnt_o;
  assign minor_seen_d   = minor_seen_o   | minor_pulse;
  assign fault_sticky_d = fault_sticky_o | major_pulse;

  // TMR-wrapped registers (async reset asserted when !rst_ni).
  `IOB_REG_TMR($bits(minor_cnt_o),    '0, '0, !rst_ni, '1, minor_cnt_d,    minor_cnt_o,    minor_cnt_o)
  `IOB_REG_TMR($bits(major_cnt_o),    '0, '0, !rst_ni, '1, major_cnt_d,    major_cnt_o,    major_cnt_o)
  `IOB_REG_TMR($bits(minor_seen_o),   '0, '0, !rst_ni, '1, minor_seen_d,   minor_seen_o,   minor_seen_o)
  `IOB_REG_TMR($bits(fault_sticky_o), '0, '0, !rst_ni, '1, fault_sticky_d, fault_sticky_o, fault_sticky_o)

  // Fetch-enable control: sticky OFF after first major event.
  logic [$bits(ibex_mubi_t)-1:0] fetch_en_q, fetch_en_d;
  assign fetch_en_d = (major_pulse ? MUBI_OFF : fetch_en_q);
  `IOB_REG_TMR($bits(fetch_en_q), MUBI_ON, '0, !rst_ni, '1, fetch_en_d, fetch_en_q, fetch_en_q)
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

  `IOB_REG_TMR($bits(state_q), S_IDLE, '0, !rst_ni, '1, state_d, state_q, state_q)

  assign core_reset_req_o = (state_q == S_ASSERT_RST);

endmodule
