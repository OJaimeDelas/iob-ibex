`ifndef FATORI_FTM_SVH
`define FATORI_FTM_SVH

`include "fatori_macro_functions.svh"

// Cross-cutting MuBi guards for control paths (fetch_enable, core_busy, response acceptance)
`__FATORI_MACRO_DEF(FATORI_SECURE_GUARDS, 0)

// Dual-core lockstep (shadow core + compare). Big area/power, strongest FI detect.
`__FATORI_MACRO_DEF(FATORI_LOCKSTEP,              0)

// Data-independent timing: logic present; SW controls via cpuctrl.data_ind_timing.
`__FATORI_MACRO_DEF(FATORI_DATA_INDEP_TIMING,     0)

// Dummy instruction insertion: logic present; SW via cpuctrl.dummy_instr_en.
// WARNING -  RV32M != ibex_pkg::RV32MNone
`__FATORI_MACRO_DEF(FATORI_DUMMY_INSTR,           0)

// Bus integrity checking (checkbits alongside I/D buses).
// This one might be confusing, it switches to MemECC in the RTL
// --------------------------------------------------------------
// NOT WORKING - DO NOT TURN ON
`__FATORI_MACRO_DEF(FATORI_MEM_ECC,         0)
// --------------------------------------------------------------

// Register file ECC (detect-only; raises major alert).
`__FATORI_MACRO_DEF(FATORI_RF_ECC,                0)

// Regfile write-enable glitch detection (one-hot).
`__FATORI_MACRO_DEF(FATORI_RF_WE_GLITCH,          0)

// Regfile read-address glitch detection (one-hot).
`__FATORI_MACRO_DEF(FATORI_RF_RADDR_GLITCH,       0)

// Instruction cache ECC (if I$ present).
`__FATORI_MACRO_DEF(FATORI_ICACHE_ECC,            0)

// Hardened PC (sequential flow consistency check).
`__FATORI_MACRO_DEF(FATORI_HARDENED_PC,           0)

// Shadow CSRs (complement mirror + consistency check). Typically OFF with lockstep.
`__FATORI_MACRO_DEF(FATORI_SHADOW_CSRS,           0)


`__FATORI_MACRO_DEF(FATORI_PMP,                0)

`endif // FATORI_FTM_SVH