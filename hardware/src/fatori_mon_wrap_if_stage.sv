// fatori_mon_wrap_if_stage.sv
//
// Fault-Tolerant M-of-N Wrapper for ibex_if_stage
// ================================================
//
// This module implements spatial redundancy for the Ibex IF (Instruction Fetch) stage.
// It instantiates N replicas of ibex_if_stage, broadcasts all inputs to each replica,
// and votes on their outputs using a configurable M-of-N majority voter.
//
// Architecture Overview:
// ----------------------
//   Inputs → [Broadcast] → Replica 0 ┐
//                        → Replica 1 ├→ [Voter] → Voted Outputs
//                        → Replica N-1┘
//
// Key Features:
// - N replicas execute in parallel on identical inputs
// - M-of-N voting tolerates up to (N-M)/2 faults
// - Outputs are bit-level voted for maximum granularity
// - Error signals indicate detected discrepancies (min_err, maj_err)

module fatori_mon_wrap_if_stage import ibex_pkg::*; #(
  // === Fault Tolerance Parameters ===
  // N: Number of replicas (must be ≥ 1)
  parameter int N    = `IFSTAGE_MON_N,
  
  // M: Voting threshold (M-of-N voting)
  //    - M=0: majority voting (default, tolerates floor((N-1)/2) faults)
  //    - M>0: at least M replicas must agree
  parameter int M    = `IFSTAGE_MON_M,
  
  // HOLD: Error latch behavior
  //    - 0: errors are combinational (reflect current disagreement)
  //    - 1: errors latch and hold until reset
  parameter bit HOLD = `IFSTAGE_MON_HOLD,

  // === ibex_if_stage Pass-Through Parameters ===
  // These configure the behavior of each IF stage replica
  parameter int unsigned DmHaltAddr        = 32'h1A110800,
  parameter int unsigned DmExceptionAddr   = 32'h1A110808,
  parameter bit          DummyInstructions = 1'b0,
  parameter bit          ICache            = 1'b0,
  parameter bit          ICacheECC         = 1'b0,
  parameter int unsigned BusSizeECC        = BUS_SIZE,
  parameter int unsigned TagSizeECC        = IC_TAG_SIZE,
  parameter int unsigned LineSizeECC       = IC_LINE_SIZE,
  parameter bit          PCIncrCheck       = 1'b0,
  parameter bit          ResetAll          = 1'b0,
  parameter lfsr_seed_t  RndCnstLfsrSeed   = RndCnstLfsrSeedDefault,
  parameter lfsr_perm_t  RndCnstLfsrPerm   = RndCnstLfsrPermDefault,
  parameter bit          BranchPredictor   = 1'b0,
  parameter bit          MemECC            = 1'b0,
  parameter int unsigned MemDataWidth      = MemECC ? 32 + 7 : 32
) (
  // === Clock and Reset (broadcast to all replicas) ===
  input  logic                         clk_i,
  input  logic                         rst_ni,

  // === Boot Address and Fetch Request (broadcast) ===
  input  logic [31:0]                  boot_addr_i,
  input  logic                         req_i,

  // === Instruction Memory Interface (broadcast) ===
  // These signals connect to the instruction memory/cache
  input  logic                         instr_gnt_i,        // Memory grant
  input  logic                         instr_rvalid_i,     // Read data valid
  input  logic [MemDataWidth-1:0]      instr_rdata_i,      // Instruction data
  input  logic                         instr_bus_err_i,    // Bus error flag

  // === ICache Tag/Data Read Ports (broadcast) ===
  // Used when ICache=1; arrays indexed by way number
  input  logic [TagSizeECC-1:0]        ic_tag_rdata_i [IC_NUM_WAYS],
  input  logic [LineSizeECC-1:0]       ic_data_rdata_i [IC_NUM_WAYS],
  input  logic                         ic_scr_key_valid_i,

  // === Control and Exception Signals (broadcast) ===
  input  logic                         pmp_err_if_i,              // PMP violation
  input  logic                         pmp_err_if_plus2_i,        // PMP violation for PC+2
  input  logic                         instr_valid_clear_i,       // Clear instruction valid
  input  logic                         pc_set_i,                  // Set PC to new value
  input  pc_sel_e                      pc_mux_i,                  // PC source select
  input  logic                         nt_branch_mispredict_i,    // Branch misprediction
  input  logic [31:0]                  nt_branch_addr_i,          // Branch target address
  input  exc_pc_sel_e                  exc_pc_mux_i,              // Exception PC select
  input  exc_cause_t                   exc_cause,                 // Exception cause
  input  logic                         dummy_instr_en_i,          // Enable dummy instructions
  input  logic [2:0]                   dummy_instr_mask_i,        // Dummy instruction mask
  input  logic                         dummy_instr_seed_en_i,     // Seed enable
  input  logic [31:0]                  dummy_instr_seed_i,        // LFSR seed
  input  logic                         icache_enable_i,           // ICache enable
  input  logic                         icache_inval_i,            // ICache invalidate
  input  logic [31:0]                  branch_target_ex_i,        // Branch target from EX
  input  logic [31:0]                  csr_mepc_i,                // CSR: exception PC
  input  logic [31:0]                  csr_depc_i,                // CSR: debug PC
  input  logic [31:0]                  csr_mtvec_i,               // CSR: trap vector base
  input  logic                         id_in_ready_i,             // ID stage ready

`ifdef FATORI_FI
  // === Optional Fault Injection Port (broadcast) ===
  input  logic [7:0]                   fi_port,
`endif

  // === Instruction Memory Interface Outputs (voted) ===
  // These signals are voted across all replicas before driving outward
  output logic                         instr_req_o,               // Memory request
  output logic [31:0]                  instr_addr_o,              // Fetch address
  output logic                         instr_intg_err_o,          // Integrity error

  // === ICache Tag/Data Write Ports (voted) ===
  output logic [IC_NUM_WAYS-1:0]       ic_tag_req_o,              // Tag request per way
  output logic                         ic_tag_write_o,            // Tag write enable
  output logic [IC_INDEX_W-1:0]        ic_tag_addr_o,             // Tag address
  output logic [TagSizeECC-1:0]        ic_tag_wdata_o,            // Tag write data
  output logic [IC_NUM_WAYS-1:0]       ic_data_req_o,             // Data request per way
  output logic                         ic_data_write_o,           // Data write enable
  output logic [IC_INDEX_W-1:0]        ic_data_addr_o,            // Data address
  output logic [LineSizeECC-1:0]       ic_data_wdata_o,           // Data write data
  output logic                         ic_scr_key_req_o,          // Scrambling key request

  // === Outputs to ID Stage (voted) ===
  output logic                         instr_valid_id_o,          // Instruction valid
  output logic                         instr_new_id_o,            // New instruction flag
  output logic [31:0]                  instr_rdata_id_o,          // Instruction data
  output logic [31:0]                  instr_rdata_alu_id_o,      // Pre-decoded immediate for ALU
  output logic [15:0]                  instr_rdata_c_id_o,        // Compressed instruction
  output logic                         instr_is_compressed_id_o,  // Is compressed flag
  output logic                         instr_bp_taken_o,          // Branch predicted taken
  output logic                         instr_fetch_err_o,         // Fetch error
  output logic                         instr_fetch_err_plus2_o,   // Fetch error at PC+2
  output logic                         illegal_c_insn_id_o,       // Illegal compressed instruction
  output logic                         dummy_instr_id_o,          // Dummy instruction flag
  output logic [31:0]                  pc_if_o,                   // Program counter (IF stage)
  output logic [31:0]                  pc_id_o,                   // Program counter (ID stage)

  // === Status and Alert Outputs (voted) ===
  output logic                         icache_ecc_error_o,        // ICache ECC error detected
  output logic                         csr_mtvec_init_o,          // mtvec initialized
  output logic                         pc_mismatch_alert_o,       // PC mismatch alert
  output logic                         if_busy_o,                 // IF stage busy

  // === Fault Detection Outputs ===
  // These signals indicate when replicas disagree
  output logic                         min_err_o,                 // Minority error (at least one disagrees)
  output logic                         maj_err_o,                 // Majority error (more than half disagree)
  
  // === Child Error Aggregation Outputs ===
  // Error aggregation from ibex_if_stage's internal registers and children
  output logic                         if_stage_new_maj_err_o,
  output logic                         if_stage_new_min_err_o,
  output logic                         if_stage_scrub_occurred_o
);

  // ===========================================================================
  // Output Bundle Structure
  // ===========================================================================
  // We pack all IF stage outputs into a single struct for efficient voting.
  // This allows the voter to compare all outputs bit-by-bit in parallel.
  
  typedef struct packed {
    // Memory interface outputs
    logic                         instr_req_o;
    logic [31:0]                  instr_addr_o;
    logic                         instr_intg_err_o;
    
    // ICache tag interface
    logic [IC_NUM_WAYS-1:0]       ic_tag_req_o;
    logic                         ic_tag_write_o;
    logic [IC_INDEX_W-1:0]        ic_tag_addr_o;
    logic [TagSizeECC-1:0]        ic_tag_wdata_o;
    
    // ICache data interface
    logic [IC_NUM_WAYS-1:0]       ic_data_req_o;
    logic                         ic_data_write_o;
    logic [IC_INDEX_W-1:0]        ic_data_addr_o;
    logic [LineSizeECC-1:0]       ic_data_wdata_o;
    logic                         ic_scr_key_req_o;

    // ID stage interface
    logic                         instr_valid_id_o;
    logic                         instr_new_id_o;
    logic [31:0]                  instr_rdata_id_o;
    logic [31:0]                  instr_rdata_alu_id_o;
    logic [15:0]                  instr_rdata_c_id_o;
    logic                         instr_is_compressed_id_o;
    logic                         instr_bp_taken_o;
    logic                         instr_fetch_err_o;
    logic                         instr_fetch_err_plus2_o;
    logic                         illegal_c_insn_id_o;
    logic                         dummy_instr_id_o;
    logic [31:0]                  pc_if_o;
    logic [31:0]                  pc_id_o;

    // Status outputs
    logic                         icache_ecc_error_o;
    logic                         csr_mtvec_init_o;
    logic                         pc_mismatch_alert_o;
    logic                         if_busy_o;
    logic                         if_stage_new_maj_err_o;
    logic                         if_stage_new_min_err_o;
  } if_stage_out_t;

  // Total width of the output bundle in bits
  localparam int W = $bits(if_stage_out_t);

  // Array to hold output bundles from each replica
  if_stage_out_t rep [N];

  // ===========================================================================
  // Replica Instantiation
  // ===========================================================================
  // Generate N parallel instances of ibex_if_stage.
  // All replicas receive identical inputs (broadcast), but we capture
  // their outputs separately for voting.
  
  generate
    for (genvar g = 0; g < N; g++) begin : gen_reps
    
      // In order to actually use per-replica lockage, the clock has to slow down a bunch
      //`KEEP_IF_STAGE
      ibex_if_stage #(
        // Forward all configuration parameters to each replica
        .DmHaltAddr       (DmHaltAddr),
        .DmExceptionAddr  (DmExceptionAddr),
        .DummyInstructions(DummyInstructions),
        .ICache           (ICache),
        .ICacheECC        (ICacheECC),
        .BusSizeECC       (BusSizeECC),
        .TagSizeECC       (TagSizeECC),
        .LineSizeECC      (LineSizeECC),
        .PCIncrCheck      (PCIncrCheck),
        .ResetAll         (ResetAll),
        .RndCnstLfsrSeed  (RndCnstLfsrSeed),
        .RndCnstLfsrPerm  (RndCnstLfsrPerm),
        .BranchPredictor  (BranchPredictor),
        .MemECC           (MemECC),
        .MemDataWidth     (MemDataWidth)
      ) u_if (
        // === Broadcast Inputs ===
        // All replicas receive the same clock, reset, and control signals
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .boot_addr_i(boot_addr_i),
        .req_i      (req_i),

        // Memory interface inputs (broadcast)
        .instr_gnt_i   (instr_gnt_i),
        .instr_rvalid_i(instr_rvalid_i),
        .instr_rdata_i (instr_rdata_i),
        .instr_bus_err_i(instr_bus_err_i),

        // ICache read data inputs (broadcast)
        .ic_tag_rdata_i (ic_tag_rdata_i),
        .ic_data_rdata_i(ic_data_rdata_i),
        .ic_scr_key_valid_i(ic_scr_key_valid_i),

        // Control/exception inputs (broadcast)
        .pmp_err_if_i        (pmp_err_if_i),
        .pmp_err_if_plus2_i  (pmp_err_if_plus2_i),
        .instr_valid_clear_i (instr_valid_clear_i),
        .pc_set_i            (pc_set_i),
        .pc_mux_i            (pc_mux_i),
        .nt_branch_mispredict_i(nt_branch_mispredict_i),
        .nt_branch_addr_i    (nt_branch_addr_i),
        .exc_pc_mux_i        (exc_pc_mux_i),
        .exc_cause           (exc_cause),
        .dummy_instr_en_i    (dummy_instr_en_i),
        .dummy_instr_mask_i  (dummy_instr_mask_i),
        .dummy_instr_seed_en_i(dummy_instr_seed_en_i),
        .dummy_instr_seed_i  (dummy_instr_seed_i),
        .icache_enable_i     (icache_enable_i),
        .icache_inval_i      (icache_inval_i),
        .branch_target_ex_i  (branch_target_ex_i),
        .csr_mepc_i          (csr_mepc_i),
        .csr_depc_i          (csr_depc_i),
        .csr_mtvec_i         (csr_mtvec_i),
        .id_in_ready_i       (id_in_ready_i),

        // === Per-Replica Outputs ===
        // Each replica's outputs are captured into its own struct
        
        // Memory interface outputs
        .instr_req_o            (rep[g].instr_req_o),
        .instr_addr_o           (rep[g].instr_addr_o),
        .instr_intg_err_o       (rep[g].instr_intg_err_o),
        
        // ICache tag outputs
        .ic_tag_req_o           (rep[g].ic_tag_req_o),
        .ic_tag_write_o         (rep[g].ic_tag_write_o),
        .ic_tag_addr_o          (rep[g].ic_tag_addr_o),
        .ic_tag_wdata_o         (rep[g].ic_tag_wdata_o),
        
        // ICache data outputs
        .ic_data_req_o          (rep[g].ic_data_req_o),
        .ic_data_write_o        (rep[g].ic_data_write_o),
        .ic_data_addr_o         (rep[g].ic_data_addr_o),
        .ic_data_wdata_o        (rep[g].ic_data_wdata_o),
        .ic_scr_key_req_o       (rep[g].ic_scr_key_req_o),

        // ID stage outputs
        .instr_valid_id_o        (rep[g].instr_valid_id_o),
        .instr_new_id_o          (rep[g].instr_new_id_o),
        .instr_rdata_id_o        (rep[g].instr_rdata_id_o),
        .instr_rdata_alu_id_o    (rep[g].instr_rdata_alu_id_o),
        .instr_rdata_c_id_o      (rep[g].instr_rdata_c_id_o),
        .instr_is_compressed_id_o(rep[g].instr_is_compressed_id_o),
        .instr_bp_taken_o        (rep[g].instr_bp_taken_o),
        .instr_fetch_err_o       (rep[g].instr_fetch_err_o),
        .instr_fetch_err_plus2_o (rep[g].instr_fetch_err_plus2_o),
        .illegal_c_insn_id_o     (rep[g].illegal_c_insn_id_o),
        .dummy_instr_id_o        (rep[g].dummy_instr_id_o),
        .pc_if_o                 (rep[g].pc_if_o),
        .pc_id_o                 (rep[g].pc_id_o),

        // Status outputs
        .icache_ecc_error_o(rep[g].icache_ecc_error_o),
        .csr_mtvec_init_o  (rep[g].csr_mtvec_init_o),
        .pc_mismatch_alert_o(rep[g].pc_mismatch_alert_o),
        .if_busy_o         (rep[g].if_busy_o),
        
        // Child error aggregation outputs
        .if_stage_new_maj_err_o(rep[g].if_stage_new_maj_err_o),
        .if_stage_new_min_err_o(rep[g].if_stage_new_min_err_o)

`ifdef FATORI_FI
        // Optional fault injection port (broadcast)
        ,.fi_port(fi_port)
`endif
      );
    end
  endgenerate

  // ===========================================================================
  // Output Bundle Packing
  // ===========================================================================
  // Convert the array of output structs into a 2D packed array [N][W]
  // that the voter can process. Each replica's struct is flattened into
  // a W-bit vector.
  
  logic [N-1:0][W-1:0] replicas_bus;
  generate
    for (genvar g = 0; g < N; g++) begin : gen_pack
      assign replicas_bus[g] = rep[g];
    end
  endgenerate

  // ===========================================================================
  // Voting Logic
  // ===========================================================================
  // The voter compares all N replica outputs bit-by-bit.
  // - For M=0 (default): uses majority voting
  // - For M>0: requires at least M replicas to agree on each bit
  //
  // Error Outputs:
  // - min_err: Set when ANY replica disagrees (minority error)
  // - maj_err: Set when MORE THAN HALF of replicas disagree (majority error)
  
  logic [W-1:0] voted_bus;      // Voted output (W-bit vector)
  logic         min_err_now;    // Current minority error flag
  logic         maj_err_now;    // Current majority error flag

  logic logic_scrub_occurred;
  
  fatori_mon_voter #(
    .W(W),           // Width: total bits in output bundle
    .N(N),           // Number of replicas
    .M(M),           // Voting threshold (0 = majority)
    .HOLD(HOLD)      // Error latch behavior
  ) u_vote (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .replicas_i(replicas_bus),  // [N][W] array of replica outputs
    .y_o(voted_bus),            // [W] voted result
    .min_err_o(min_err_now),    // Minority error flag
    .maj_err_o(maj_err_now),    // Majority error flag
    .scrub_occurred_o(logic_scrub_occurred)  // Logic scrubbing occurred
  );

  // ===========================================================================
  // Cast Voted Result Back to Struct
  // ===========================================================================
  // The voter produces a flat W-bit vector. We cast it back to the
  // structured type to extract individual signals cleanly.
  
  if_stage_out_t voted;
  assign voted = if_stage_out_t'(voted_bus);

  // ===========================================================================
  // Drive Module Outputs from Voted Bundle
  // ===========================================================================
  // All outputs are driven from the voted bundle to ensure single-driver
  // semantics. This prevents any replica from directly influencing the
  // output - only the voted consensus is visible externally.
  
  // Memory interface
  assign instr_req_o             = voted.instr_req_o;
  assign instr_addr_o            = voted.instr_addr_o;
  assign instr_intg_err_o        = voted.instr_intg_err_o;
  
  // ICache tag interface
  assign ic_tag_req_o            = voted.ic_tag_req_o;
  assign ic_tag_write_o          = voted.ic_tag_write_o;
  assign ic_tag_addr_o           = voted.ic_tag_addr_o;
  assign ic_tag_wdata_o          = voted.ic_tag_wdata_o;
  
  // ICache data interface
  assign ic_data_req_o           = voted.ic_data_req_o;
  assign ic_data_write_o         = voted.ic_data_write_o;
  assign ic_data_addr_o          = voted.ic_data_addr_o;
  assign ic_data_wdata_o         = voted.ic_data_wdata_o;
  assign ic_scr_key_req_o        = voted.ic_scr_key_req_o;

  // ID stage interface
  assign instr_valid_id_o        = voted.instr_valid_id_o;
  assign instr_new_id_o          = voted.instr_new_id_o;
  assign instr_rdata_id_o        = voted.instr_rdata_id_o;
  assign instr_rdata_alu_id_o    = voted.instr_rdata_alu_id_o;
  assign instr_rdata_c_id_o      = voted.instr_rdata_c_id_o;
  assign instr_is_compressed_id_o= voted.instr_is_compressed_id_o;
  assign instr_bp_taken_o        = voted.instr_bp_taken_o;
  assign instr_fetch_err_o       = voted.instr_fetch_err_o;
  assign instr_fetch_err_plus2_o = voted.instr_fetch_err_plus2_o;
  assign illegal_c_insn_id_o     = voted.illegal_c_insn_id_o;
  assign dummy_instr_id_o        = voted.dummy_instr_id_o;
  assign pc_if_o                 = voted.pc_if_o;
  assign pc_id_o                 = voted.pc_id_o;

  // Status outputs
  assign icache_ecc_error_o      = voted.icache_ecc_error_o;
  assign csr_mtvec_init_o        = voted.csr_mtvec_init_o;
  assign pc_mismatch_alert_o     = voted.pc_mismatch_alert_o;
  assign if_busy_o               = voted.if_busy_o;

  // Fault detection outputs
  assign min_err_o               = min_err_now;
  assign maj_err_o               = maj_err_now;

  assign if_busy_o               = voted.if_busy_o;
  
  assign if_stage_new_maj_err_o  = voted.if_stage_new_maj_err_o;
  assign if_stage_new_min_err_o  = voted.if_stage_new_min_err_o;
  
  // Aggregate register scrubbing (from child if_stage) with logic scrubbing (from voter)
  assign if_stage_scrub_occurred_o = voted.if_stage_scrub_occurred_o | logic_scrub_occurred;

endmodule