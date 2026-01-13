// fatori_features.svh
// SPDX-License-Identifier: MIT
//
// Centralized build-time switches for Ibex security / fault-tolerance features.
//

`ifndef FATORI_FEATURES_SVH
`define FATORI_FEATURES_SVH

`include "fatori_macro_functions.svh"

`define FATORI_FI

`__FATORI_MACRO_DEF(FATORI_ICACHE,              1)
`__FATORI_MACRO_DEF(FATORI_WSTAGE,              0)
`__FATORI_MACRO_DEF(FATORI_BRANCH_TALU,              1)
`__FATORI_MACRO_DEF(FATORI_BRANCH_PRED,              0)
`__FATORI_MACRO_DEF(FATORI_REGFILE,    ibex_pkg::RegFileFPGA)
//`__FATORI_MACRO_DEF(FATORI_REGFILE,    ibex_pkg::RegFileFF)

`__FATORI_MACRO_DEF(FATORI_RV32B,              ibex_pkg::RV32BFull)
`__FATORI_MACRO_DEF(FATORI_RV32M,              ibex_pkg::RV32MFast)
`__FATORI_MACRO_DEF(FATORI_RV32E,              0)

`__FATORI_MACRO_DEF(FATORI_MHPMCOUNTER_NUM,              10)
`__FATORI_MACRO_DEF(FATORI_MHPMCOUNTER_W,              32)


// Fault manager block: captures alerts, halts fetch on major, optional reset request.
// Kept ON by default independent of groups, but still overrideable.
`__FATORI_MACRO_DEF(FATORI_RESET_ON_MAJOR,              0) // request sync reset on any major alert
`__FATORI_MACRO_DEF(FATORI_WAIT_SLEEP_BEFORE_RESET,     0) // wait for core sleep before requesting reset
`__FATORI_MACRO_DEF(FATORI_FAULT_MGR,             1)

// METRIC_LAYER Selection
// 0 = Baseline (mcycle, minstret only)
// 1 = + HPM counters (mhpmcounter3-12)
// 2 = + Basic error counters (min_cnt, maj_cnt) - requires FATORI_FT_LAYER_1
// 3 = + Correction tracking (corrected_cnt) - requires FATORI_FT_LAYER_2
// 4 = + Timing analysis (cycles_to_first_*, detect_latency) - requires FATORI_FT_LAYER_3
// 5 = + Latency statistics (latency_sum, latency_cnt) - requires FATORI_FT_LAYER_4
`define FATORI_FT_LAYER_1
`define FATORI_FT_LAYER_2
`define FATORI_FT_LAYER_3
// `define FATORI_FT_LAYER_4


`endif // FATORI_FEATURES_SVH
