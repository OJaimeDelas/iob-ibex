// fatori_features.svh
// SPDX-License-Identifier: MIT
//
// Centralized build-time switches for Ibex security / fault-tolerance features.
//


`ifndef FATORI_FEATURES_SVH
`define FATORI_FEATURES_SVH

// -----------------------------------------------------------------------------
// Small helper: define a macro only if it’s still undefined.
// -----------------------------------------------------------------------------
`define __FTM_DEF_IF_UNDEF(name, val) \
  `ifndef name \
    `define name val \
  `endif

// -----------------------------------------------------------------------------
// PER-FEATURE TOGGLES (edit/add features here)
// -----------------------------------------------------------------------------
// Each feature gets a default fallback (used only if not set by groups or CLI).

// Cross-cutting MuBi guards for control paths (fetch_enable, core_busy, response acceptance)
`__FTM_DEF_IF_UNDEF(FTM_SECURE_GUARDS, 1)

// Dual-core lockstep (shadow core + compare). Big area/power, strongest FI detect.
`__FTM_DEF_IF_UNDEF(FTM_LOCKSTEP,              1)

// Data-independent timing: logic present; SW controls via cpuctrl.data_ind_timing.
`__FTM_DEF_IF_UNDEF(FTM_DATA_INDEP_TIMING,     1)

// Dummy instruction insertion: logic present; SW via cpuctrl.dummy_instr_en.
// WARNING -  RV32M != ibex_pkg::RV32MNone
`__FTM_DEF_IF_UNDEF(FTM_DUMMY_INSTR,           1)

// Bus integrity checking (checkbits alongside I/D buses).
// This one might be confusing, it switches to MemECC in the RTL
// --------------------------------------------------------------
// NOT WORKING - DO NOT TURN ON
`__FTM_DEF_IF_UNDEF(FTM_BUS_INTEGRITY,         0)
// --------------------------------------------------------------

// Register file ECC (detect-only; raises major alert).
`__FTM_DEF_IF_UNDEF(FTM_RF_ECC,                1)

// Regfile write-enable glitch detection (one-hot).
`__FTM_DEF_IF_UNDEF(FTM_RF_WE_GLITCH,          1)

// Regfile read-address glitch detection (one-hot).
`__FTM_DEF_IF_UNDEF(FTM_RF_RADDR_GLITCH,       1)

// Instruction cache ECC (if I$ present).
`__FTM_DEF_IF_UNDEF(FTM_ICACHE_ECC,            1)

// Hardened PC (sequential flow consistency check).
`__FTM_DEF_IF_UNDEF(FTM_HARDENED_PC,           1)

// Shadow CSRs (complement mirror + consistency check). Typically OFF with lockstep.
`__FTM_DEF_IF_UNDEF(FTM_SHADOW_CSRS,           1)

// Fault manager block: captures alerts, halts fetch on major, optional reset request.
// Kept ON by default independent of groups, but still overrideable.
`__FTM_DEF_IF_UNDEF(FTM_RESET_ON_MAJOR,              1) // request sync reset on any major alert
`__FTM_DEF_IF_UNDEF(FTM_WAIT_SLEEP_BEFORE_RESET,     1) // wait for core sleep before requesting reset
`__FTM_DEF_IF_UNDEF(FTM_FAULT_MGR,             1)


// -----------------------------------------------------------------------------
// Cleanup local helper
// -----------------------------------------------------------------------------
`undef __FTM_DEF_IF_UNDEF

`endif // FATORI_FEATURES_SVH
