// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Control / status register primitive
 */

`include "prim_assert.sv"

module ibex_csr #(
  parameter int unsigned    Width      = 32,
  parameter bit             ShadowCopy = 1'b0,
  parameter bit [Width-1:0] ResetValue = '0
 ) (
  input  logic             clk_i,
  input  logic             rst_ni,

  input  logic [Width-1:0] wr_data_i,
  input  logic             wr_en_i,
  output logic [Width-1:0] rd_data_o,

  output logic             rd_error_o,
  
  // Error aggregation outputs (for fault_mgr metrics)
  output logic             csr_new_maj_err_o,
  output logic             csr_new_min_err_o,
  output logic             csr_scrub_occurred_o
  
  `ifdef FATORI_FI
    // If Fault-Injection is activated create the FI Port
    ,input  logic [7:0]      fi_port 
  `endif
   
);

  logic [Width-1:0] rdata_q;
  `FATORI_REG(ResetValue, !rst_ni, wr_en_i, wr_data_i, rdata_q, fi_port, 8'd79, '0, '0, rdata)
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     rdata_q <= ResetValue;
  //   end else if (wr_en_i) begin
  //     rdata_q <= wr_data_i;
  //   end
  // end

  assign rd_data_o = rdata_q;

  if (ShadowCopy) begin : gen_shadow
    logic [Width-1:0] shadow_q;
    `FATORI_REG(~ResetValue, !rst_ni, wr_en_i, ~wr_data_i, shadow_q, fi_port, 8'd80, '0, '0, shadow)
    // always_ff @(posedge clk_i or negedge rst_ni) begin
    //   if (!rst_ni) begin
    //     shadow_q <= ~ResetValue;
    //   end else if (wr_en_i) begin
    //     shadow_q <= ~wr_data_i;
    //   end
    // end

    assign rd_error_o = rdata_q != ~shadow_q;

  end else begin : gen_no_shadow
    assign rd_error_o = 1'b0;
  end

  `ASSERT_KNOWN(IbexCSREnValid, wr_en_i)

// ============================================================
  // Error Aggregation (OR all register error pulses in this module)
  // ============================================================
  generate
    if (ShadowCopy) begin : g_err_agg_with_shadow
      assign csr_new_maj_err_o = rdata_new_maj_err | gen_shadow.shadow_new_maj_err;
      assign csr_new_min_err_o = rdata_new_min_err | gen_shadow.shadow_new_min_err;
      assign csr_scrub_occurred_o = rdata_scrub_occurred | gen_shadow.shadow_scrub_occurred;
    end else begin : g_err_agg_no_shadow
      assign csr_new_maj_err_o = rdata_new_maj_err;
      assign csr_new_min_err_o = rdata_new_min_err;
      assign csr_scrub_occurred_o = rdata_scrub_occurred;
    end
  endgenerate

endmodule
