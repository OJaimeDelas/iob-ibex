// fatori_mon_wrap_controller.sv
// M-of-N wrapper for ibex_controller.
// Replicates the controller N times, votes all behaviourally-relevant outputs,
// and only the voted bundle drives outward (single-driver rule).

`include "fatori_logic_mon.svh"

module fatori_mon_wrap_controller #(
  // Fault-tolerance knobs (instantiate with `CONTROLLER_MON_*`)
  parameter int N    = 1,
  parameter int M    = 0,
  parameter bit HOLD = 1'b0,

  // Pass-through ibex_controller params
  parameter bit WritebackStage  = 1'b0,
  parameter bit BranchPredictor = 1'b0,
  parameter bit MemECC          = 1'b0
)(
  input  logic clk_i,
  input  logic rst_ni,

  // ---- exact ibex_controller inputs ----
  // decoder related signals
  input  logic illegal_insn_i,
  input  logic ecall_insn_i,
  input  logic mret_insn_i,
  input  logic dret_insn_i,
  input  logic wfi_insn_i,
  input  logic ebrk_insn_i,
  input  logic csr_pipe_flush_i,

  // from IF-ID pipeline
  input  logic         instr_valid_i,
  input  logic [31:0]  instr_i,
  input  logic [15:0]  instr_compressed_i,
  input  logic         instr_is_compressed_i,
  input  logic         instr_bp_taken_i,
  input  logic         instr_fetch_err_i,
  input  logic         instr_fetch_err_plus2_i,
  input  logic [31:0]  pc_id_i,

  // IF-ID / ID handshake
  input  logic instr_exec_i,

  // LSU
  input  logic [31:0] lsu_addr_last_i,
  input  logic        load_err_i,
  input  logic        mem_resp_intg_err_i,
  input  logic        store_err_i,

  // jump/branch control
  input  logic branch_set_i,
  input  logic branch_not_set_i,
  input  logic jump_set_i,

  // interrupt / CSR
  input  logic                 csr_mstatus_mie_i,
  input  logic                 irq_pending_i,
  input  ibex_pkg::irqs_t          irqs_i,
  input  logic                 irq_nm_ext_i,
  input  ibex_pkg::priv_lvl_e  priv_mode_i,

  // Debug
  input  logic debug_req_i,
  input  logic debug_single_step_i,
  input  logic debug_ebreakm_i,
  input  logic debug_ebreaku_i,
  input  logic trigger_match_i,

  // Pipeline control
  input  logic stall_id_i,
  input  logic stall_wb_i,
  input  logic ready_wb_i,

`ifdef FATORI_FI
  input  logic [7:0] fi_port,
`endif

  // ---- exact ibex_controller outputs (to be voted) ----
  output logic                  ctrl_busy_o,

  // to IF-ID pipeline
  output logic instr_valid_clear_o,
  output logic id_in_ready_o,
  output logic controller_run_o,

  // to prefetcher / PC control
  output logic                  instr_req_o,
  output logic                  pc_set_o,
  output ibex_pkg::pc_sel_e     pc_mux_o,
  output logic                  nt_branch_mispredict_o,
  output ibex_pkg::exc_pc_sel_e exc_pc_mux_o,
  output ibex_pkg::exc_cause_t  exc_cause_o,

  // LSU exceptions
  output logic wb_exception_o,
  output logic id_exception_o,

  // jump/branch / pipeline flush
  output logic flush_id_o,

  // NMI
  output logic nmi_mode_o,

  // CSR Controller Signals
  output logic        csr_save_if_o,
  output logic        csr_save_id_o,
  output logic        csr_save_wb_o,
  output logic        csr_restore_mret_id_o,
  output logic        csr_restore_dret_id_o,
  output logic        csr_save_cause_o,
  output logic [31:0] csr_mtval_o,

  // Debug Signals
  output logic                debug_mode_o,
  output logic                debug_mode_entering_o,
  output ibex_pkg::dbg_cause_e debug_cause_o,
  output logic                debug_csr_save_o,

  // Performance Counters
  output logic perf_jump_o,
  output logic perf_tbranch_o,

  // monitor status
  output logic min_err_o,
  output logic maj_err_o,
  
  // Child error aggregation outputs
  output logic controller_new_maj_err_o,
  output logic controller_new_min_err_o,
  output logic controller_scrub_occurred_o
);

  import ibex_pkg::*;

  // ---- Voted bundle ----
  typedef struct packed {
    logic                  ctrl_busy_o;

    logic                  instr_valid_clear_o;
    logic                  id_in_ready_o;
    logic                  controller_run_o;

    logic                  instr_req_o;
    logic                  pc_set_o;
    ibex_pkg::pc_sel_e     pc_mux_o;
    logic                  nt_branch_mispredict_o;
    ibex_pkg::exc_pc_sel_e exc_pc_mux_o;
    ibex_pkg::exc_cause_t  exc_cause_o;

    logic                  wb_exception_o;
    logic                  id_exception_o;

    logic                  flush_id_o;

    logic                  nmi_mode_o;

    logic                  csr_save_if_o;
    logic                  csr_save_id_o;
    logic                  csr_save_wb_o;
    logic                  csr_restore_mret_id_o;
    logic                  csr_restore_dret_id_o;
    logic                  csr_save_cause_o;
    logic [31:0]           csr_mtval_o;

    logic                  debug_mode_o;
    logic                  debug_mode_entering_o;
    ibex_pkg::dbg_cause_e  debug_cause_o;
    logic                  debug_csr_save_o;

    logic                  perf_jump_o;
    logic                  perf_tbranch_o;
    logic                  controller_new_maj_err_o;
    logic                  controller_new_min_err_o;
    logic                  controller_scrub_occurred_o;
  } controller_out_t;

  localparam int CW = $bits(controller_out_t);

  // Per-replica bundles
  controller_out_t c_rep [N];

  // Replicas
  generate
    for (genvar g = 0; g < N; g++) begin : gen_ctrl_reps
      
      // In order to actually use per-replica lockage, the clock has to slow down a bunch
      //`KEEP_CONTROLLER
      ibex_controller #(
        .WritebackStage (WritebackStage),
        .BranchPredictor(BranchPredictor),
        .MemECC         (MemECC)
      ) u_ctrl (
        .clk_i (clk_i),
        .rst_ni(rst_ni),

        .ctrl_busy_o(c_rep[g].ctrl_busy_o),

        // decoder related
        .illegal_insn_i  (illegal_insn_i),
        .ecall_insn_i    (ecall_insn_i),
        .mret_insn_i     (mret_insn_i),
        .dret_insn_i     (dret_insn_i),
        .wfi_insn_i      (wfi_insn_i),
        .ebrk_insn_i     (ebrk_insn_i),
        .csr_pipe_flush_i(csr_pipe_flush_i),

        // from IF-ID pipeline
        .instr_valid_i          (instr_valid_i),
        .instr_i                (instr_i),
        .instr_compressed_i     (instr_compressed_i),
        .instr_is_compressed_i  (instr_is_compressed_i),
        .instr_bp_taken_i       (instr_bp_taken_i),
        .instr_fetch_err_i      (instr_fetch_err_i),
        .instr_fetch_err_plus2_i(instr_fetch_err_plus2_i),
        .pc_id_i                (pc_id_i),

        // to IF-ID / handshake
        .instr_valid_clear_o(c_rep[g].instr_valid_clear_o),
        .id_in_ready_o      (c_rep[g].id_in_ready_o),
        .controller_run_o   (c_rep[g].controller_run_o),
        .instr_exec_i       (instr_exec_i),

        // to prefetcher / PC control
        .instr_req_o           (c_rep[g].instr_req_o),
        .pc_set_o              (c_rep[g].pc_set_o),
        .pc_mux_o              (c_rep[g].pc_mux_o),
        .nt_branch_mispredict_o(c_rep[g].nt_branch_mispredict_o),
        .exc_pc_mux_o          (c_rep[g].exc_pc_mux_o),
        .exc_cause_o           (c_rep[g].exc_cause_o),

        // LSU
        .lsu_addr_last_i    (lsu_addr_last_i),
        .load_err_i         (load_err_i),
        .mem_resp_intg_err_i(mem_resp_intg_err_i),
        .store_err_i        (store_err_i),
        .wb_exception_o     (c_rep[g].wb_exception_o),
        .id_exception_o     (c_rep[g].id_exception_o),

        // jump/branch control
        .branch_set_i    (branch_set_i),
        .branch_not_set_i(branch_not_set_i),
        .jump_set_i      (jump_set_i),

        // interrupt signals
        .csr_mstatus_mie_i(csr_mstatus_mie_i),
        .irq_pending_i    (irq_pending_i),
        .irqs_i           (irqs_i),
        .irq_nm_ext_i     (irq_nm_ext_i),
        .nmi_mode_o       (c_rep[g].nmi_mode_o),

        // CSR Controller Signals
        .csr_save_if_o        (c_rep[g].csr_save_if_o),
        .csr_save_id_o        (c_rep[g].csr_save_id_o),
        .csr_save_wb_o        (c_rep[g].csr_save_wb_o),
        .csr_restore_mret_id_o(c_rep[g].csr_restore_mret_id_o),
        .csr_restore_dret_id_o(c_rep[g].csr_restore_dret_id_o),
        .csr_save_cause_o     (c_rep[g].csr_save_cause_o),
        .csr_mtval_o          (c_rep[g].csr_mtval_o),
        .priv_mode_i          (priv_mode_i),

        // Debug
        .debug_mode_o         (c_rep[g].debug_mode_o),
        .debug_mode_entering_o(c_rep[g].debug_mode_entering_o),
        .debug_cause_o        (c_rep[g].debug_cause_o),
        .debug_csr_save_o     (c_rep[g].debug_csr_save_o),
        .debug_req_i          (debug_req_i),
        .debug_single_step_i  (debug_single_step_i),
        .debug_ebreakm_i      (debug_ebreakm_i),
        .debug_ebreaku_i      (debug_ebreaku_i),
        .trigger_match_i      (trigger_match_i),

        .stall_id_i(stall_id_i),
        .stall_wb_i(stall_wb_i),
        .flush_id_o(c_rep[g].flush_id_o),
        .ready_wb_i(ready_wb_i),

        // Performance Counters
        .perf_jump_o   (c_rep[g].perf_jump_o),
        .perf_tbranch_o(c_rep[g].perf_tbranch_o),
        
        // Child error aggregation outputs
        .controller_new_maj_err_o(c_rep[g].controller_new_maj_err_o),
        .controller_new_min_err_o(c_rep[g].controller_new_min_err_o),
        .controller_scrub_occurred_o(c_rep[g].controller_scrub_occurred_o)

  `ifdef FATORI_FI
        ,.fi_port(fi_port)
  `endif
    );
    end
  endgenerate

  // Pack & vote
  logic [N-1:0][CW-1:0] rep_bus;
  generate
    for (genvar i = 0; i < N; i++) begin : gen_pack
      assign rep_bus[i] = c_rep[i];
    end
  endgenerate
  logic [CW-1:0] voted_bus;
  logic          min_err_now, maj_err_now;

  logic logic_scrub_occurred;
  
  fatori_mon_voter #(
    .W              (CW),
    .N              (N),
    .M       (M),
    .HOLD (HOLD)
  ) u_vote_ctrl (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .replicas_i (rep_bus),
    .y_o        (voted_bus),
    .min_err_o  (min_err_now),
    .maj_err_o  (maj_err_now),
    .scrub_occurred_o (logic_scrub_occurred)
  );

//   controller_out_t voted = controller_out_t'(voted_bus);
    // Cast back to the structured type
  controller_out_t voted;
  assign voted = controller_out_t'(voted_bus);

  // Drive outward only from voted bundle
  assign ctrl_busy_o            = voted.ctrl_busy_o;

  assign instr_valid_clear_o    = voted.instr_valid_clear_o;
  assign id_in_ready_o          = voted.id_in_ready_o;
  assign controller_run_o       = voted.controller_run_o;

  assign instr_req_o            = voted.instr_req_o;
  assign pc_set_o               = voted.pc_set_o;
  assign pc_mux_o               = voted.pc_mux_o;
  assign nt_branch_mispredict_o = voted.nt_branch_mispredict_o;
  assign exc_pc_mux_o           = voted.exc_pc_mux_o;
  assign exc_cause_o            = voted.exc_cause_o;

  assign wb_exception_o         = voted.wb_exception_o;
  assign id_exception_o         = voted.id_exception_o;

  assign flush_id_o             = voted.flush_id_o;

  assign nmi_mode_o             = voted.nmi_mode_o;

  assign csr_save_if_o          = voted.csr_save_if_o;
  assign csr_save_id_o          = voted.csr_save_id_o;
  assign csr_save_wb_o          = voted.csr_save_wb_o;
  assign csr_restore_mret_id_o  = voted.csr_restore_mret_id_o;
  assign csr_restore_dret_id_o  = voted.csr_restore_dret_id_o;
  assign csr_save_cause_o       = voted.csr_save_cause_o;
  assign csr_mtval_o            = voted.csr_mtval_o;

  assign debug_mode_o           = voted.debug_mode_o;
  assign debug_mode_entering_o  = voted.debug_mode_entering_o;
  assign debug_cause_o          = voted.debug_cause_o;
  assign debug_csr_save_o       = voted.debug_csr_save_o;

  assign perf_jump_o            = voted.perf_jump_o;
  assign perf_tbranch_o         = voted.perf_tbranch_o;

  assign controller_new_maj_err_o = voted.controller_new_maj_err_o;
  assign controller_new_min_err_o = voted.controller_new_min_err_o;
  
  // Aggregate register scrubbing (from child controller) with logic scrubbing (from voter)
  assign controller_scrub_occurred_o = voted.controller_scrub_occurred_o | logic_scrub_occurred;

  assign min_err_o              = min_err_now;
  assign maj_err_o              = maj_err_now;

endmodule
