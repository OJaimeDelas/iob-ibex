// fatori_mon_wrap_alu.sv
//
// M-of-N hardened wrapper for ibex_alu.
// The ALU is mostly combinational (plus mult/div operand routing and
// intermediate results). We replicate ibex_alu N times, gather its
// outputs into per-replica structs, then run mon_vote_vec.



module fatori_mon_wrap_alu #(
  // Fault-tolerance knobs:
  parameter int N           = '1,
  parameter int M           = '0,
  parameter bit HOLD        = '0,

  // ibex_alu param(s):
  parameter ibex_pkg::rv32b_e RV32B    = ibex_pkg::RV32BNone
)(
  input  logic                         clk_i,
  input  logic                         rst_ni,

  // ---- ibex_alu inputs (broadcast)
  input  ibex_pkg::alu_op_e            operator_i,
  input  logic [31:0]                  operand_a_i,
  input  logic [31:0]                  operand_b_i,
  input  logic                         instr_first_cycle_i,
  input  logic [32:0]                  multdiv_operand_a_i,
  input  logic [32:0]                  multdiv_operand_b_i,
  input  logic                         multdiv_sel_i,
  input  logic [31:0]                  imd_val_q_i [2],

  // ---- voted outputs
  output logic [31:0]                  imd_val_d_o [2],
  output logic [1:0]                   imd_val_we_o,
  output logic [31:0]                  adder_result_o,
  output logic [33:0]                  adder_result_ext_o,
  output logic [31:0]                  result_o,
  output logic                         comparison_result_o,
  output logic                         is_equal_result_o,

  output logic                         min_err_o,
  output logic                         maj_err_o,
  output logic                         scrub_occurred_o
);

  // Bundle ALU outputs into a single packed struct.
  typedef struct packed {
    logic [31:0] imd_val_d0;
    logic [31:0] imd_val_d1;
    logic [1:0]  imd_val_we_o;
    logic [31:0] adder_result_o;
    logic [33:0] adder_result_ext_o;
    logic [31:0] result_o;
    logic        comparison_result_o;
    logic        is_equal_result_o;
  } alu_out_t;

  localparam int AW = $bits(alu_out_t);

  // Per-replica structs
  alu_out_t a_rep [N];

  // We also need per-replica intermediate nets for array ports.
  logic [N-1:0][31:0] imd_d0_rep;
  logic [N-1:0][31:0] imd_d1_rep;
  logic [N-1:0][1:0]  imd_we_rep;
  logic [N-1:0][31:0] add_rep;
  logic [N-1:0][33:0] addx_rep;
  logic [N-1:0][31:0] res_rep;
  logic [N-1:0]       cmp_rep;
  logic [N-1:0]       eq_rep;

  genvar g;
  generate
    for (genvar g = 0; g < N; g++) begin : gen_alu_reps
      // Temporary per-instance nets with the same shape as the port
      logic [31:0] imd_val_d_g [2];

      //`KEEP_ALU
      ibex_alu #(
        .RV32B (RV32B)
      ) u_alu (
        .operator_i           (operator_i),
        .operand_a_i          (operand_a_i),
        .operand_b_i          (operand_b_i),
        .instr_first_cycle_i  (instr_first_cycle_i),
        .multdiv_operand_a_i  (multdiv_operand_a_i),
        .multdiv_operand_b_i  (multdiv_operand_b_i),
        .multdiv_sel_i        (multdiv_sel_i),
        .imd_val_q_i          (imd_val_q_i),

        .imd_val_d_o          (imd_val_d_g),
        .imd_val_we_o         (imd_we_rep[g]),
        .adder_result_o       (add_rep[g]),
        .adder_result_ext_o   (addx_rep[g]),
        .result_o             (res_rep[g]),
        .comparison_result_o  (cmp_rep[g]),
        .is_equal_result_o    (eq_rep[g])
      );

      // Split to your per-replica signals
      assign imd_d0_rep[g] = imd_val_d_g[0];
      assign imd_d1_rep[g] = imd_val_d_g[1];

      // Map replica nets into this replica's struct bundle
      always_comb begin
        a_rep[g].imd_val_d0          = imd_d0_rep[g];
        a_rep[g].imd_val_d1          = imd_d1_rep[g];
        a_rep[g].imd_val_we_o        = imd_we_rep[g];
        a_rep[g].adder_result_o      = add_rep[g];
        a_rep[g].adder_result_ext_o  = addx_rep[g];
        a_rep[g].result_o            = res_rep[g];
        a_rep[g].comparison_result_o = cmp_rep[g];
        a_rep[g].is_equal_result_o   = eq_rep[g];
      end
    end
  endgenerate

  // Pack replicas into [N][AW] for the voter
  logic [N-1:0][AW-1:0] rep_bus;
  generate
    for (genvar g = 0; g < N; g++) begin : gen_pack
      assign rep_bus[g] = a_rep[g];
    end
  endgenerate

  // Vote
  logic [AW-1:0] voted_bus;
  logic          min_err_now, maj_err_now;

  logic logic_scrub_occurred;
  
  fatori_mon_voter #(
    .W       (AW),
    .N       (N),
    .M       (M),
    .HOLD    (HOLD)
  ) u_vote_alu (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .replicas_i (rep_bus),
    .y_o        (voted_bus),
    .min_err_o  (min_err_now),
    .maj_err_o  (maj_err_now),
    .scrub_occurred_o (logic_scrub_occurred)
  );

  alu_out_t voted;
  assign voted = alu_out_t'(voted_bus);

  // Drive voted outward
  assign imd_val_d_o[0]        = voted.imd_val_d0;
  assign imd_val_d_o[1]        = voted.imd_val_d1;
  assign imd_val_we_o          = voted.imd_val_we_o;
  assign adder_result_o        = voted.adder_result_o;
  assign adder_result_ext_o    = voted.adder_result_ext_o;
  assign result_o              = voted.result_o;
  assign comparison_result_o   = voted.comparison_result_o;
  assign is_equal_result_o     = voted.is_equal_result_o;

  assign min_err_o             = min_err_now;
  assign maj_err_o             = maj_err_now;
  
  // Only logic scrubbing (ALU has no registers, so no register scrubbing to aggregate)
  assign scrub_occurred_o      = logic_scrub_occurred;

endmodule
