// =============================================================
// File: fatori_reg_mon_fi.sv
// Desc: M-of-N redundancy wrapper for iob_reg_re with SEU-like
//       Fault Injection (FI).
//
// Same interface/semantics as fatori_reg_mon.sv, with one extra
// input port (fi_port) and one extra parameter (ID).
//
// FI behavior:
//   - When (fi_port == ID) on a rising match AND en_i==0,
//     the wrapper performs a read-modify-write that flips the LSB
//     in storage.
//   - For N==1: flip the single register.
//   - For N>=2: flip exactly one replica, chosen deterministically
//     as (ID % N).
//   - If en_i==1 in the hit cycle, do nothing (normal write wins).
//
// Voting, HOLD_LAST_GOOD, and error flags match fatori_reg_mon.sv.
// =============================================================
`timescale 1ns/1ps

module fatori_reg_mon_fi #(
  // Leaf register shape
  parameter int unsigned DATA_W  = 32,
  parameter logic [DATA_W-1:0] RST_VAL = '0,

  // Redundancy parameters
  parameter int unsigned N       = 1,   // replicas (N<2 => no redundancy)
  parameter int unsigned M       = 0,   // quorum (0 => majority = N/2+1)

  // Output holding policy when no quorum
  parameter bit          HOLD_LAST_GOOD = 1'b0,

  // FI sizing + instance ID
  parameter int unsigned ID_W    = 8,               // Up to 256 IDs - width of fi_port/ID compare 
  parameter logic [ID_W-1:0] ID  = '0               // unique per-instance ID
) (
  // Clock/control
  input  logic                 clk_i,
  input  logic                 arst_i,
  input  logic                 en_i,
  input  logic                 rst_i,

  // Data
  input  logic [DATA_W-1:0]    data_i,
  output logic [DATA_W-1:0]    data_o,

  // FI broadcast compare
  input  logic [ID_W-1:0]      fi_port,

  // Status
  output logic                 maj_err_o,
  output logic                 min_err_o,
  output logic [ (N<2?1:N)-1:0 ] err_loc_o,
  
  // Edge-detected error pulses (for fault counting)
  output logic                 new_maj_err_o,
  output logic                 new_min_err_o,
  
  // Scrubbing pulse (for correction counting in Layer 2)
  output logic                 scrub_occurred_o
);

  // ---- Effective parameters and checks
  localparam int unsigned N_EFF = (N < 1) ? 1 : N;
  localparam int unsigned M_DEF = (N_EFF/2) + 1;         // strict majority
  localparam int unsigned M_EFF = (M == 0) ? M_DEF : M;

  initial begin
    if (M_EFF < 1 || M_EFF > N_EFF) begin
      $fatal(1, "fatori_reg_mon_fi: M (%0d) must be in [1..N=%0d]", M_EFF, N_EFF);
    end
  end
// ============================================================
  // FI trigger: latch flip request when ID matches, clear when applied
  // ============================================================
  wire match = (fi_port == ID);
  logic flip_required;
  
  always_ff @(posedge clk_i or posedge arst_i) begin
    if (arst_i) 
      flip_required <= 1'b0;
    else if (match)
      flip_required <= 1'b1;  // Set when ID matches
    else if (flip_required && !en_i)
      flip_required <= 1'b0;  // Clear after flip applied
  end

  // Apply flip whenever flip_required is set AND no write occurring
  wire do_flip = flip_required && !en_i;

 // Middle bit mask (bit position DATA_W/2)
  localparam int MID_BIT = DATA_W / 2;
  wire [DATA_W-1:0] mid_mask = (1'b1 << MID_BIT);

  // ============================================================
  // Cycling replica selector for M-of-N case
  // ============================================================
  // For N>=2, cycle through replicas 0,1,2,...,N-1 on successive faults
  localparam int NLOG = (N_EFF > 1) ? $clog2(N_EFF) : 1;
  logic [NLOG-1:0] fault_counter;
  
  always_ff @(posedge clk_i or posedge arst_i) begin
    if (arst_i)
      fault_counter <= '0;
    else if (do_flip)
      fault_counter <= (fault_counter == (N_EFF-1)) ? '0 : fault_counter + 1'b1;
  end

  // ============================================================
  // Case A: No redundancy (N<2) - passthrough leaf register,
  //         with FI read-modify-write when do_flip==1
  // ============================================================
  generate
    if (N_EFF < 2) begin : gen_passthrough

      logic [DATA_W-1:0] q_raw;

      // Build effective EN/D:
      // - If do_flip: force a write of (q_raw ^ lsb_mask)
      // - Else      : normal en_i/data_i
      logic              en_eff;
      logic [DATA_W-1:0] d_eff;

      assign en_eff = do_flip ? 1'b1 : en_i;
      assign d_eff  = do_flip ? (q_raw ^ mid_mask) : data_i;

      iob_reg_re #(
        .DATA_W (DATA_W),
        .RST_VAL(RST_VAL)
      ) u_reg (
        .clk_i (clk_i),
        .cke_i ('1),
        .arst_i(arst_i),
        .en_i  (en_eff),
        .rst_i (rst_i),
        .data_i(d_eff),
        .data_o(q_raw)
      );

      assign data_o   = q_raw;
      assign maj_err_o = 1'b0;
      assign min_err_o = 1'b0;
      assign err_loc_o = '0;
      
      // No errors in passthrough mode
      assign new_maj_err_o = 1'b0;
      assign new_min_err_o = 1'b0;

    end else begin : gen_mofn
  // ============================================================
  // Case B: Active M-of-N (N>=2)
  // ============================================================

     // ---------------------
      // Replicated registers
      // ---------------------
      logic [DATA_W-1:0] r [N_EFF];

      // Use cycling fault counter to select which replica gets flipped
      wire [NLOG-1:0] rep_idx = fault_counter;

      // Forward declarations for scrubbing (if enabled)
      logic [DATA_W-1:0] voted_data_for_scrub;
      logic              unique_quorum_for_scrub;
      logic [N_EFF-1:0]  err_loc_for_scrub;
      
      // Track scrubbing events for correction counting
      logic [N_EFF-1:0]  scrubbed_this_cycle;

      for (genvar i = 0; i < N_EFF; i++) begin : g_regs
        // For the selected replica on do_flip, force write of (r[i] ^ mid_mask)
        wire sel_flip = do_flip && (i[NLOG-1:0] == rep_idx);
        
        logic en_eff_i;
        logic [DATA_W-1:0] d_eff_i;

        if (HOLD_LAST_GOOD) begin : gen_with_scrubbing
          // Priority: FI > Normal write > Scrubbing
          wire sel_scrub = !en_i && !sel_flip && unique_quorum_for_scrub && err_loc_for_scrub[i];
          
          always_comb begin
            if (sel_flip) begin
              en_eff_i = 1'b1;
              d_eff_i  = r[i] ^ mid_mask;           // Fault injection
            end else if (sel_scrub) begin
              en_eff_i = 1'b1;
              d_eff_i  = voted_data_for_scrub;      // Scrub with good value
            end else begin
              en_eff_i = en_i;
              d_eff_i  = data_i;                    // Normal write
            end
          end
          
          // Track if this replica was scrubbed this cycle
          always_ff @(posedge clk_i or posedge arst_i) begin
            if (arst_i)
              scrubbed_this_cycle[i] <= 1'b0;
            else
              scrubbed_this_cycle[i] <= sel_scrub;
          end
          
        end else begin : gen_no_scrubbing
          // No scrubbing: replica never scrubbed
          assign scrubbed_this_cycle[i] = 1'b0;
          // No scrubbing: only FI or normal write
          assign en_eff_i = sel_flip ? 1'b1 : en_i;
          assign d_eff_i  = sel_flip ? (r[i] ^ mid_mask) : data_i;
        end

        iob_reg_re #(
          .DATA_W (DATA_W),
          .RST_VAL(RST_VAL)
        ) u_reg (
          .clk_i (clk_i),
          .cke_i ('1),
          .arst_i(arst_i),
          .en_i  (en_eff_i),
          .rst_i (rst_i),
          .data_i(d_eff_i),
          .data_o(r[i])
        );
      end

      // -------------------------------
      // Word-equality voter (O(N^2))
      // -------------------------------
      int unsigned counts [N_EFF];

      logic [DATA_W-1:0] voted_data;
      logic              found_candidate;
      int                cand_idx;
      logic              unique_quorum;

      // Last known "good" voted value (for HOLD_LAST_GOOD)
      // (Declared/used only when HOLD_LAST_GOOD==1 via generate below)

      // Count equalities and pick the lowest-index candidate that reaches M_EFF
      always_comb begin
        for (int i = 0; i < N_EFF; i++) counts[i] = 0;
        found_candidate = 1'b0;
        cand_idx        = -1;
        voted_data      = r[0];

        for (int i = 0; i < N_EFF; i++) begin
          for (int j = 0; j < N_EFF; j++) begin
            counts[i] += (r[i] == r[j]);
          end
          if (!found_candidate && (counts[i] >= M_EFF)) begin
            found_candidate = 1'b1;
            cand_idx        = i;
            voted_data      = r[i];
          end
        end
      end

      // Ensure the quorum is UNIQUE (no other distinct word also meets M_EFF)
      always_comb begin
        unique_quorum = found_candidate;
        if (found_candidate) begin
          for (int k = 0; k < N_EFF; k++) begin
            if (k != cand_idx && (counts[k] >= M_EFF) && (r[k] != voted_data)) begin
              unique_quorum = 1'b0; // ambiguous: two distinct clusters >= M_EFF
            end
          end
        end
      end

      // Connect voter outputs to scrubbing inputs (if scrubbing enabled)
      assign voted_data_for_scrub = voted_data;
      assign unique_quorum_for_scrub = unique_quorum;

      // Hold-last-good logic (optional) - synthesize ONLY when enabled
      if (HOLD_LAST_GOOD) begin : gen_hold_last_good
        logic [DATA_W-1:0] last_good_q, last_good_d;

        always_comb begin
          last_good_d = last_good_q;
          if (unique_quorum) last_good_d = voted_data;
        end
        always_ff @(posedge clk_i or posedge arst_i) begin
          if (arst_i)       last_good_q <= RST_VAL;
          else              last_good_q <= last_good_d;
        end

        // Output selection when HOLD_LAST_GOOD is enabled
        always_comb begin
          if (unique_quorum)            data_o = voted_data;
          else                          data_o = last_good_q;
        end
      end else begin : gen_no_hold_last_good
        // Output selection when HOLD_LAST_GOOD is disabled (no extra storage)
        always_comb begin
          if (unique_quorum)            data_o = voted_data;
          else                          data_o = r[0]; // deterministic fallback
        end
      end

      // Error flags and locations
      always_comb begin
        maj_err_o = ~unique_quorum;

        // Mark any replica that differs from the chosen output word
        for (int i = 0; i < N_EFF; i++) begin
          err_loc_o[i] = (r[i] != data_o);
          err_loc_for_scrub[i] = (r[i] != data_o);  // Also feed scrubbing logic
        end

        // Minor error if any discrepancy exists
        min_err_o = |err_loc_o;
      end

      // ============================================================
      // Edge-detected error signals (for fault injection counting)
      // ============================================================
      logic maj_err_q, min_err_q;
      logic [N_EFF-1:0] err_loc_q;
      
      always_ff @(posedge clk_i or posedge arst_i) begin
        if (arst_i) begin
          maj_err_q <= 1'b0;
          min_err_q <= 1'b0;
          err_loc_q <= '0;
        end else begin
          maj_err_q <= maj_err_o;
          min_err_q <= min_err_o;
          err_loc_q <= err_loc_o;
        end
      end
      
      // Edge detectors for pulse generation
      logic maj_err_pulse, min_err_pulse;
      assign maj_err_pulse = maj_err_o & ~maj_err_q;  // Rising edge: 0→1
      assign min_err_pulse = min_err_o & ~min_err_q;  // Rising edge: 0→1
      
      // Pulse on rising edge (0→1 transition)
      assign new_maj_err_o = maj_err_pulse;
      assign new_min_err_o = min_err_pulse;
      
      // Scrubbing occurred if any replica was scrubbed
      assign scrub_occurred_o = |scrubbed_this_cycle;
      

      // ---------------------- Corner cases (intended) ----------------------
      // N=2, M=2 : DMR (require equality). If r0!=r1 -> maj_err_o=1 (detect only).
      // N=4, M=2 : A,A,B,B -> tie => maj_err_o=1 (no unique quorum).
      // N=5, M=4 : A,A,A,A,B -> quorum OK (min_err_o=1); A,A,A,B,B -> no quorum.
      // M=1      : only unanimous replicas form a unique quorum; else major.
     // --------------------------------------------------------------------

    end
  endgenerate

endmodule
