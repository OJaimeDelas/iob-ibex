`ifndef FATORI_MACRO_FUNCTIONS_SVH
`define FATORI_MACRO_FUNCTIONS_SVH


// -----------------------------------------------------------------------------
// Define helper
// define a macro only if it’s still undefined.
// -----------------------------------------------------------------------------
`define __FATORI_MACRO_DEF(name, val) \
  `ifndef name \
    `define name val \
  `endif

`include "fatori_features.svh"

// -----------------------------------------------------------------------------
// Register Wrappers
// _MON_N, _MON_M and _HOLD_LAST_GOOD are driven from fatori_reg_mon.svh
// -----------------------------------------------------------------------------

// Wrapper for common datatypes
// UN_0 and UN_1 are unused ports, are meant to ease future implementations   
`define FATORI_REG(RST_VALUE, RST, EN, DIN, DOUT, FI_PORT, ID_N, UN_0, UN_1, PREFIX)    \
  logic PREFIX``_new_maj_err;                                                         \
  logic PREFIX``_new_min_err;                                                         \
  logic PREFIX``_scrub_occurred;                                                      \
  logic PREFIX``_maj_err;                                                             \
  logic PREFIX``_min_err;                                                             \
  localparam int PREFIX``_ERR_W = ((`PREFIX``_MON_N) < 2) ? 1 : (`PREFIX``_MON_N);    \
  logic [PREFIX``_ERR_W-1:0] PREFIX``_err_loc;                                        \
  localparam int PREFIX``_DW = $bits(DOUT);                                           \
  logic [PREFIX``_DW-1:0] PREFIX``_din_raw;                                           \
  logic [PREFIX``_DW-1:0] PREFIX``_dout_raw;                                          \
  assign PREFIX``_din_raw = DIN;                                                      \
  `ifdef FATORI_FI                                                                    \
    fatori_reg_mon_fi #(.DATA_W(PREFIX``_DW),                                         \
                        .RST_VAL(RST_VALUE),                                          \
                        .M(`PREFIX``_MON_M),                                          \
                        .N(`PREFIX``_MON_N),                                          \
                        .HOLD_LAST_GOOD(`PREFIX``_HOLD_LAST_GOOD),                    \
                        .ID(ID_N))                                                      \
    PREFIX``_reg_wrapper_fi (                                                         \
      .clk_i     (clk_i),                                                             \
      .arst_i    (RST),                                                               \
      .en_i      (EN),                                                                \
      .rst_i     (RST),                                                               \
      .data_i    (PREFIX``_din_raw),                                                  \
      .data_o    (PREFIX``_dout_raw),                                                 \
      .fi_port   (FI_PORT),                                                           \
      .maj_err_o (PREFIX``_maj_err),                                                  \
      .min_err_o (PREFIX``_min_err),                                                  \
      .new_maj_err_o (PREFIX``_new_maj_err),                                          \
      .new_min_err_o (PREFIX``_new_min_err),                                          \
      .scrub_occurred_o (PREFIX``_scrub_occurred),                                    \
      .err_loc_o (PREFIX``_err_loc)                                                   \
    );                                                                                \
  `else                                                                               \
    fatori_reg_mon #(.DATA_W(PREFIX``_DW),                                            \
                     .RST_VAL(RST_VALUE),                                             \
                     .M(`PREFIX``_MON_M),                                             \
                     .N(`PREFIX``_MON_N),                                             \
                     .HOLD_LAST_GOOD(`PREFIX``_HOLD_LAST_GOOD))                       \
    PREFIX``_reg_wrapper (                                                            \
      .clk_i     (clk_i),                                                             \
      .arst_i    (RST),                                                               \
      .en_i      (EN),                                                                \
      .rst_i     (RST),                                                               \
      .data_i    (PREFIX``_din_raw),                                                  \
      .data_o    (PREFIX``_dout_raw),                                                 \
      .maj_err_o (PREFIX``_maj_err),                                                  \
      .min_err_o (PREFIX``_min_err),                                                  \
      .new_maj_err_o (PREFIX``_new_maj_err),                                          \
      .new_min_err_o (PREFIX``_new_min_err),                                          \
      .scrub_occurred_o (PREFIX``_scrub_occurred),                                    \
      .err_loc_o (PREFIX``_err_loc)                                                   \
    );                                                                                \
  `endif                                                                              \
  assign DOUT = PREFIX``_dout_raw;


// Wrapper for uncommon datatypes
// UN_0 and UN_1 are unused ports, are meant to ease future implementations   
`define FATORI_REG_ENUM(ENUM_T, RST_VALUE, RST, EN, DIN, DOUT, FI_PORT, ID_N, UN_0, UN_1, PREFIX) \
  logic PREFIX``_new_maj_err;                                                         \
  logic PREFIX``_new_min_err;                                                         \
  logic PREFIX``_scrub_occurred;                                                      \
  logic PREFIX``_maj_err;                                                              \
  logic PREFIX``_min_err;                                                              \
  localparam int PREFIX``_ERR_W = ((`PREFIX``_MON_N) < 2) ? 1 : (`PREFIX``_MON_N);   \
  logic [PREFIX``_ERR_W-1:0] PREFIX``_err_loc;                                        \
  localparam int PREFIX``_DW = $bits(ENUM_T);                                         \
  typedef logic [PREFIX``_DW-1:0] PREFIX``_raw_t;                                     \
  localparam PREFIX``_raw_t PREFIX``_RST_RAW = PREFIX``_raw_t'(RST_VALUE);            \
  PREFIX``_raw_t PREFIX``_din_raw;                                                    \
  PREFIX``_raw_t PREFIX``_dout_raw;                                                   \
  assign PREFIX``_din_raw = PREFIX``_raw_t'(DIN);                                     \
  `ifdef FATORI_FI                                                                    \
    fatori_reg_mon_fi #(.DATA_W(PREFIX``_DW),                                         \
                        .RST_VAL(PREFIX``_RST_RAW),                                   \
                        .M(`PREFIX``_MON_M),                                          \
                        .N(`PREFIX``_MON_N),                                          \
                        .HOLD_LAST_GOOD(`PREFIX``_HOLD_LAST_GOOD),                    \
                        .ID(ID_N))                                                      \
    PREFIX``_reg_wrapper_fi (                                                         \
      .clk_i     (clk_i),                                                             \
      .arst_i    (RST),                                                               \
      .en_i      (EN),                                                                \
      .rst_i     (RST),                                                               \
      .data_i    (PREFIX``_din_raw),                                                  \
      .data_o    (PREFIX``_dout_raw),                                                 \
      .fi_port   (FI_PORT),                                                           \
      .maj_err_o (PREFIX``_maj_err),                                                  \
      .min_err_o (PREFIX``_min_err),                                                  \
      .new_maj_err_o (PREFIX``_new_maj_err),                                          \
      .new_min_err_o (PREFIX``_new_min_err),                                          \
      .scrub_occurred_o (PREFIX``_scrub_occurred),                                    \
      .err_loc_o (PREFIX``_err_loc)                                                   \
    );                                                                                \
  `else                                                                               \
    fatori_reg_mon #(.DATA_W(PREFIX``_DW),                                            \
                     .RST_VAL(PREFIX``_RST_RAW),                                      \
                     .M(`PREFIX``_MON_M),                                             \
                     .N(`PREFIX``_MON_N),                                             \
                     .HOLD_LAST_GOOD(`PREFIX``_HOLD_LAST_GOOD))                       \
    PREFIX``_reg_wrapper (                                                            \
      .clk_i     (clk_i),                                                             \
      .arst_i    (RST),                                                               \
      .en_i      (EN),                                                                \
      .rst_i     (RST),                                                               \
      .data_i    (PREFIX``_din_raw),                                                  \
      .data_o    (PREFIX``_dout_raw),                                                 \
      .maj_err_o (PREFIX``_maj_err),                                                  \
      .min_err_o (PREFIX``_min_err),                                                  \
      .new_maj_err_o (PREFIX``_new_maj_err),                                          \
      .new_min_err_o (PREFIX``_new_min_err),                                          \
      .scrub_occurred_o (PREFIX``_scrub_occurred),                                    \
      .err_loc_o (PREFIX``_err_loc)                                                   \
    );                                                                                \
  `endif                                                                              \
  assign DOUT = ENUM_T'(PREFIX``_dout_raw);


`endif // FATORI_MACRO_FUNCTIONS_SVH