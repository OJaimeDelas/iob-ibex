// fatori_mon_voter.sv
// Generic M-of-N voter for replicated logic bundles.
//
// Parameters:
//   W               : width of each replica bundle (bits)
//   N               : number of replicas to consider
//   M               : quorum threshold M. If M == 0, we use strict
//                     majority = floor(N/2)+1.
//   HOLD            : if 1, when no unique quorum winner exists we hold the
//                     last known good output instead of forcing '0.
//
// Interface:
//   replicas_i[i] is the full output bundle from replica i (width W).
//   We search for a unique "winner" value V such that V appears in >= QUORUM
//   replicas and *no different value* also appears in >= QUORUM replicas.
//   If such a unique winner exists:
//     - y_o = V
//     - maj_err_o = 0
//     - min_err_o = 1 iff any replica != V
//   Otherwise (tie or nobody hits quorum):
//     - maj_err_o = 1
//     - y_o = '0 unless HOLD==1, in which case we output the last
//       known good y_o observed when there *was* a valid winner.
//
// Notes:
//   - N and W are parameters, so this elaborates statically for synthesis.
//   - Complexity ~O(N^2 * W) due to pairwise equality checks.
//

module fatori_mon_voter #(
  parameter int W               = 32,
  parameter int N               = 1,
  parameter int M        = 0,     // 0 => strict majority
  parameter bit HOLD  = 1'b0
)(
  input  logic                   clk_i,
  input  logic                   rst_ni,

  input  logic [N-1:0][W-1:0]    replicas_i,  // N copies of bundle

  output logic [W-1:0]           y_o,         // voted output bundle
  output logic                   min_err_o,   // some disagreement but we still had a unique quorum winner
  output logic                   maj_err_o,   // no unique quorum winner (tie or no quorum)
  output logic                   scrub_occurred_o  // logic scrubbing occurred (HOLD substitution)
);

  // Compute effective quorum.
  localparam int STRICT_MAJ = (N >> 1) + 1; // floor(N/2)+1
  localparam int QUORUM     = (M == 0) ? STRICT_MAJ : M;

  // match_count[i] = how many replicas match replicas_i[i]
  localparam int CNTW = $clog2(N+1);
  logic [N-1:0][CNTW-1:0] match_count;

  always_comb begin
    for (int i = 0; i < N; i++) begin
      match_count[i] = '0;
      for (int j = 0; j < N; j++) begin
        if (replicas_i[j] == replicas_i[i]) begin
          match_count[i] = match_count[i] + 1'b1;
        end
      end
    end
  end

  // prelim_*: first value we find that meets quorum
  logic              prelim_found;
  logic [W-1:0]      prelim_value;
  logic              prelim_valid; // unique quorum winner?

  always_comb begin
    prelim_found = 1'b0;
    prelim_value = '0;
    prelim_valid = 1'b0;

    // find FIRST candidate whose match_count >= QUORUM
    for (int i = 0; i < N; i++) begin
      if (!prelim_found && (match_count[i] >= QUORUM)) begin
        prelim_found = 1'b1;
        prelim_value = replicas_i[i];
      end
    end

    // Check for uniqueness: no other *different* value also reaches QUORUM.
    if (prelim_found) begin
      prelim_valid = 1'b1;
      for (int k = 0; k < N; k++) begin
        if ((replicas_i[k] != prelim_value) &&
            (match_count[k] >= QUORUM)) begin
          prelim_valid = 1'b0; // tie/ambiguous
        end
      end
    end
  end

  // Build voted_now / err flags combinationally
  logic [W-1:0] voted_now;
  logic         min_err_now;
  logic         maj_err_now;

  always_comb begin
    if (prelim_valid) begin
      voted_now    = prelim_value;
      maj_err_now  = 1'b0;

      // min_err_now means we had to correct disagreement
      min_err_now  = 1'b0;
      for (int i = 0; i < N; i++) begin
        if (replicas_i[i] != prelim_value) begin
          min_err_now = 1'b1;
        end
      end
    end else begin
      voted_now    = '0;   // can be overridden by HOLD
      maj_err_now  = 1'b1;
      min_err_now  = 1'b0; // not a "minor" error, it's a full no-winner
    end
  end

  // Optional sticky "last good" latch.
  logic [W-1:0] last_good_q;
  logic [W-1:0] last_good_d;

  generate
    if (HOLD) begin : g_hold
      always_comb begin
        last_good_d = last_good_q;
        if (prelim_valid) begin
          last_good_d = voted_now;
        end
      end

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          last_good_q <= '0;
        end else begin
          last_good_q <= last_good_d;
        end
      end

      always_comb begin
        if (prelim_valid) begin
          y_o = voted_now;
        end else begin
          y_o = last_good_q;
        end
      end
      
      // Signal when logic scrubbing occurs (using last_good instead of voted)
      assign scrub_occurred_o = !prelim_valid;
      
    end else begin : g_no_hold
      always_comb begin
        y_o = voted_now;
      end
      
      // No scrubbing when HOLD is disabled
      assign scrub_occurred_o = 1'b0;
    end
  endgenerate

  assign min_err_o = min_err_now;
  assign maj_err_o = maj_err_now;

endmodule
