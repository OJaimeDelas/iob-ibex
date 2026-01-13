// fatori_mon_wrap_decoder.sv
//
// M-of-N hardened wrapper for ibex_decoder.
// Replicates ibex_decoder N times and votes all behaviourally-relevant outputs.
//

`include "prim_assert.sv"

module fatori_mon_wrap_decoder #(
  // Fault-tolerance knobs:
  parameter int N        = '1,
  parameter int M        = '0,
  parameter bit HOLD     = 1'b0,

  // Pass-through ibex_decoder parameters:
  parameter bit                     RV32E           = 1'b0,
  parameter ibex_pkg::rv32m_e       RV32M           = ibex_pkg::RV32MFast,
  parameter ibex_pkg::rv32b_e       RV32B           = ibex_pkg::RV32BNone,
  parameter bit                     BranchTargetALU = 1'b0
) (
  input  logic clk_i,
  input  logic rst_ni,

  // -------- ibex_decoder inputs (broadcast) --------
  // to/from controller
  input  logic                 branch_taken_i,

  // from IF-ID pipeline register
  input  logic                 instr_first_cycle_i,
  input  logic [31:0]          instr_rdata_i,
  input  logic [31:0]          instr_rdata_alu_i,
  input  logic                 illegal_c_insn_i,

`ifdef FATORI_FI
  // optional fault injection bus; forwarded to child when available
  input  logic [7:0] fi_port,
`endif

  // -------- voted outputs (mirror ibex_decoder interface) --------
  // to/from controller
  output logic                 illegal_insn_o,
  output logic                 ebrk_insn_o,
  output logic                 mret_insn_o,
  output logic                 dret_insn_o,
  output logic                 ecall_insn_o,
  output logic                 wfi_insn_o,
  output logic                 jump_set_o,
  output logic                 icache_inval_o,

  // immediates
  output ibex_pkg::imm_a_sel_e imm_a_mux_sel_o,
  output ibex_pkg::imm_b_sel_e imm_b_mux_sel_o,
  output ibex_pkg::op_a_sel_e  bt_a_mux_sel_o,
  output ibex_pkg::imm_b_sel_e bt_b_mux_sel_o,
  output logic [31:0]          imm_i_type_o,
  output logic [31:0]          imm_s_type_o,
  output logic [31:0]          imm_b_type_o,
  output logic [31:0]          imm_u_type_o,
  output logic [31:0]          imm_j_type_o,
  output logic [31:0]          zimm_rs1_type_o,

  // register file
  output ibex_pkg::rf_wd_sel_e rf_wdata_sel_o,
  output logic                 rf_we_o,
  output logic [4:0]           rf_raddr_a_o,
  output logic [4:0]           rf_raddr_b_o,
  output logic [4:0]           rf_waddr_o,
  output logic                 rf_ren_a_o,
  output logic                 rf_ren_b_o,

  // ALU
  output ibex_pkg::alu_op_e    alu_operator_o,
  output ibex_pkg::op_a_sel_e  alu_op_a_mux_sel_o,
  output ibex_pkg::op_b_sel_e  alu_op_b_mux_sel_o,
  output logic                 alu_multicycle_o,

  // MULT & DIV
  output logic                 mult_en_o,
  output logic                 div_en_o,
  output logic                 mult_sel_o,
  output logic                 div_sel_o,
  output ibex_pkg::md_op_e     multdiv_operator_o,
  output logic [1:0]           multdiv_signed_mode_o,

  // CSRs
  output logic                 csr_access_o,
  output ibex_pkg::csr_op_e    csr_op_o,

  // LSU
  output logic                 data_req_o,
  output logic                 data_we_o,
  output logic [1:0]           data_type_o,
  output logic                 data_sign_extension_o,

  // jump/branches
  output logic                 jump_in_dec_o,
  output logic                 branch_in_dec_o,

  // monitor status
  output logic                 min_err_o,
  output logic                 maj_err_o,
  
  // Child error aggregation outputs
  output logic                 decoder_new_maj_err_o,
  output logic                 decoder_new_min_err_o,
  output logic                 decoder_scrub_occurred_o
);

  import ibex_pkg::*;

  // ---- Bundle voted outputs into a packed struct ----
  typedef struct packed {
    // controller
    logic                 illegal_insn_o;
    logic                 ebrk_insn_o;
    logic                 mret_insn_o;
    logic                 dret_insn_o;
    logic                 ecall_insn_o;
    logic                 wfi_insn_o;
    logic                 jump_set_o;
    logic                 icache_inval_o;

    // immediates
    ibex_pkg::imm_a_sel_e imm_a_mux_sel_o;
    ibex_pkg::imm_b_sel_e imm_b_mux_sel_o;
    ibex_pkg::op_a_sel_e  bt_a_mux_sel_o;
    ibex_pkg::imm_b_sel_e bt_b_mux_sel_o;
    logic [31:0]          imm_i_type_o;
    logic [31:0]          imm_s_type_o;
    logic [31:0]          imm_b_type_o;
    logic [31:0]          imm_u_type_o;
    logic [31:0]          imm_j_type_o;
    logic [31:0]          zimm_rs1_type_o;

    // register file
    ibex_pkg::rf_wd_sel_e rf_wdata_sel_o;
    logic                 rf_we_o;
    logic [4:0]           rf_raddr_a_o;
    logic [4:0]           rf_raddr_b_o;
    logic [4:0]           rf_waddr_o;
    logic                 rf_ren_a_o;
    logic                 rf_ren_b_o;

    // ALU
    ibex_pkg::alu_op_e    alu_operator_o;
    ibex_pkg::op_a_sel_e  alu_op_a_mux_sel_o;
    ibex_pkg::op_b_sel_e  alu_op_b_mux_sel_o;
    logic                 alu_multicycle_o;

    // MULT & DIV
    logic                 mult_en_o;
    logic                 div_en_o;
    logic                 mult_sel_o;
    logic                 div_sel_o;
    ibex_pkg::md_op_e     multdiv_operator_o;
    logic [1:0]           multdiv_signed_mode_o;

    // CSRs
    logic                 csr_access_o;
    ibex_pkg::csr_op_e    csr_op_o;

    // LSU
    logic                 data_req_o;
    logic                 data_we_o;
    logic [1:0]           data_type_o;
    logic                 data_sign_extension_o;

    // jump/branches
    logic                 jump_in_dec_o;
    logic                 branch_in_dec_o;
    logic                 decoder_new_maj_err_o;
    logic                 decoder_new_min_err_o;
    logic                 decoder_scrub_occurred_o;
  } decoder_out_t;

  localparam int DW = $bits(decoder_out_t);

  // Per-replica bundles
  decoder_out_t d_rep [N];

  // Instantiate N replicas
  for (genvar g = 0; g < N; g++) begin : gen_dec_reps
    
    //`KEEP_DECODER
    ibex_decoder #(
      .RV32E          (RV32E),
      .RV32M          (RV32M),
      .RV32B          (RV32B),
      .BranchTargetALU(BranchTargetALU)
    ) u_dec (
      .clk_i (clk_i),
      .rst_ni(rst_ni),

      // controller
      .illegal_insn_o(d_rep[g].illegal_insn_o),
      .ebrk_insn_o   (d_rep[g].ebrk_insn_o),
      .mret_insn_o   (d_rep[g].mret_insn_o),
      .dret_insn_o   (d_rep[g].dret_insn_o),
      .ecall_insn_o  (d_rep[g].ecall_insn_o),
      .wfi_insn_o    (d_rep[g].wfi_insn_o),
      .jump_set_o    (d_rep[g].jump_set_o),
      .branch_taken_i(branch_taken_i),
      .icache_inval_o(d_rep[g].icache_inval_o),

      // IF-ID
      .instr_first_cycle_i(instr_first_cycle_i),
      .instr_rdata_i      (instr_rdata_i),
      .instr_rdata_alu_i  (instr_rdata_alu_i),
      .illegal_c_insn_i   (illegal_c_insn_i),

      // immediates
      .imm_a_mux_sel_o(d_rep[g].imm_a_mux_sel_o),
      .imm_b_mux_sel_o(d_rep[g].imm_b_mux_sel_o),
      .bt_a_mux_sel_o (d_rep[g].bt_a_mux_sel_o),
      .bt_b_mux_sel_o (d_rep[g].bt_b_mux_sel_o),
      .imm_i_type_o   (d_rep[g].imm_i_type_o),
      .imm_s_type_o   (d_rep[g].imm_s_type_o),
      .imm_b_type_o   (d_rep[g].imm_b_type_o),
      .imm_u_type_o   (d_rep[g].imm_u_type_o),
      .imm_j_type_o   (d_rep[g].imm_j_type_o),
      .zimm_rs1_type_o(d_rep[g].zimm_rs1_type_o),

      // register file
      .rf_wdata_sel_o(d_rep[g].rf_wdata_sel_o),
      .rf_we_o       (d_rep[g].rf_we_o),
      .rf_raddr_a_o  (d_rep[g].rf_raddr_a_o),
      .rf_raddr_b_o  (d_rep[g].rf_raddr_b_o),
      .rf_waddr_o    (d_rep[g].rf_waddr_o),
      .rf_ren_a_o    (d_rep[g].rf_ren_a_o),
      .rf_ren_b_o    (d_rep[g].rf_ren_b_o),

      // ALU
      .alu_operator_o    (d_rep[g].alu_operator_o),
      .alu_op_a_mux_sel_o(d_rep[g].alu_op_a_mux_sel_o),
      .alu_op_b_mux_sel_o(d_rep[g].alu_op_b_mux_sel_o),
      .alu_multicycle_o  (d_rep[g].alu_multicycle_o),

      // MULT & DIV
      .mult_en_o            (d_rep[g].mult_en_o),
      .div_en_o             (d_rep[g].div_en_o),
      .mult_sel_o           (d_rep[g].mult_sel_o),
      .div_sel_o            (d_rep[g].div_sel_o),
      .multdiv_operator_o   (d_rep[g].multdiv_operator_o),
      .multdiv_signed_mode_o(d_rep[g].multdiv_signed_mode_o),

      // CSRs
      .csr_access_o(d_rep[g].csr_access_o),
      .csr_op_o    (d_rep[g].csr_op_o),

      // LSU
      .data_req_o           (d_rep[g].data_req_o),
      .data_we_o            (d_rep[g].data_we_o),
      .data_type_o          (d_rep[g].data_type_o),
      .data_sign_extension_o(d_rep[g].data_sign_extension_o),

      // jump/branches
      .jump_in_dec_o  (d_rep[g].jump_in_dec_o),
      .branch_in_dec_o(d_rep[g].branch_in_dec_o),
      
      // Child error aggregation outputs
      .decoder_new_maj_err_o(d_rep[g].decoder_new_maj_err_o),
      .decoder_new_min_err_o(d_rep[g].decoder_new_min_err_o),
      .decoder_scrub_occurred_o(d_rep[g].decoder_scrub_occurred_o)

`ifdef FATORI_FI
      ,.fi_port(fi_port)
`endif
    );
  end

  // Pack replicas into a bus for bitwise voting
  logic [N-1:0][DW-1:0] rep_bus;
  for (genvar g = 0; g < N; g++) begin : gen_pack
    assign rep_bus[g] = d_rep[g];
  end

  // Vote
  logic [DW-1:0] voted_bus;
  logic          min_err_now, maj_err_now;

  logic logic_scrub_occurred;
  
  fatori_mon_voter #(
    .W              (DW),
    .N              (N),
    .M       (M),
    .HOLD (HOLD)
  ) u_vote_dec (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .replicas_i (rep_bus),
    .y_o        (voted_bus),
    .min_err_o  (min_err_now),
    .maj_err_o  (maj_err_now),
    .scrub_occurred_o (logic_scrub_occurred)
  );

  // Cast back to the structured type
  decoder_out_t voted;
  assign voted = decoder_out_t'(voted_bus);

  // Drive outward only from the voted bundle
  // controller
  assign illegal_insn_o = voted.illegal_insn_o;
  assign ebrk_insn_o    = voted.ebrk_insn_o;
  assign mret_insn_o    = voted.mret_insn_o;
  assign dret_insn_o    = voted.dret_insn_o;
  assign ecall_insn_o   = voted.ecall_insn_o;
  assign wfi_insn_o     = voted.wfi_insn_o;
  assign jump_set_o     = voted.jump_set_o;
  assign icache_inval_o = voted.icache_inval_o;

  // immediates
  assign imm_a_mux_sel_o = voted.imm_a_mux_sel_o;
  assign imm_b_mux_sel_o = voted.imm_b_mux_sel_o;
  assign bt_a_mux_sel_o  = voted.bt_a_mux_sel_o;
  assign bt_b_mux_sel_o  = voted.bt_b_mux_sel_o;
  assign imm_i_type_o    = voted.imm_i_type_o;
  assign imm_s_type_o    = voted.imm_s_type_o;
  assign imm_b_type_o    = voted.imm_b_type_o;
  assign imm_u_type_o    = voted.imm_u_type_o;
  assign imm_j_type_o    = voted.imm_j_type_o;
  assign zimm_rs1_type_o = voted.zimm_rs1_type_o;

  // register file
  assign rf_wdata_sel_o = voted.rf_wdata_sel_o;
  assign rf_we_o        = voted.rf_we_o;
  assign rf_raddr_a_o   = voted.rf_raddr_a_o;
  assign rf_raddr_b_o   = voted.rf_raddr_b_o;
  assign rf_waddr_o     = voted.rf_waddr_o;
  assign rf_ren_a_o     = voted.rf_ren_a_o;
  assign rf_ren_b_o     = voted.rf_ren_b_o;

  // ALU
  assign alu_operator_o     = voted.alu_operator_o;
  assign alu_op_a_mux_sel_o = voted.alu_op_a_mux_sel_o;
  assign alu_op_b_mux_sel_o = voted.alu_op_b_mux_sel_o;
  assign alu_multicycle_o   = voted.alu_multicycle_o;

  // MULT & DIV
  assign mult_en_o             = voted.mult_en_o;
  assign div_en_o              = voted.div_en_o;
  assign mult_sel_o            = voted.mult_sel_o;
  assign div_sel_o             = voted.div_sel_o;
  assign multdiv_operator_o    = voted.multdiv_operator_o;
  assign multdiv_signed_mode_o = voted.multdiv_signed_mode_o;

  // CSRs
  assign csr_access_o = voted.csr_access_o;
  assign csr_op_o     = voted.csr_op_o;

  // LSU
  assign data_req_o            = voted.data_req_o;
  assign data_we_o             = voted.data_we_o;
  assign data_type_o           = voted.data_type_o;
  assign data_sign_extension_o = voted.data_sign_extension_o;

  // jump/branches
  assign jump_in_dec_o   = voted.jump_in_dec_o;
  assign branch_in_dec_o = voted.branch_in_dec_o;

  assign decoder_new_maj_err_o = voted.decoder_new_maj_err_o;
  assign decoder_new_min_err_o = voted.decoder_new_min_err_o;
  
  // Aggregate register scrubbing (from child decoder) with logic scrubbing (from voter)
  assign decoder_scrub_occurred_o = voted.decoder_scrub_occurred_o | logic_scrub_occurred;

  // monitor flags
  assign min_err_o = min_err_now;
  assign maj_err_o = maj_err_now;

endmodule
