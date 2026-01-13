// fatori_mon_wrap_lsu.sv
//
// M-of-N hardened wrapper for ibex_load_store_unit.
// Replicates LSU N times, feeds identical inputs (addr, we, type, bus
// return data, etc.), and votes the entire output bundle (bus request side
// + pipeline side).
//
// Any LSU output not included in lsu_out_t is not protected.


module fatori_mon_wrap_lsu #(
  // Fault-tolerance knobs
  parameter int N              = '1,
  parameter int M           = '0,
  parameter bit HOLD     = 1'b0,

  // ibex_load_store_unit params
  parameter bit MemECC             = 1'b0,
  parameter int unsigned MemDataWidth = (MemECC ? 32+7 : 32)
)(
  input  logic clk_i,
  input  logic rst_ni,

  // ---- bus handshake inputs (broadcast to all replicas)
  input  logic                    data_gnt_i,
  input  logic                    data_rvalid_i,
  input  logic                    data_bus_err_i,
  input  logic                    data_pmp_err_i,
  input  logic [MemDataWidth-1:0] data_rdata_i,

  // ---- pipeline/control inputs (broadcast)
  input  logic                    lsu_we_i,
  input  logic [1:0]              lsu_type_i,
  input  logic [31:0]             lsu_wdata_i,
  input  logic                    lsu_sign_ext_i,
  input  logic [31:0]             adder_result_ex_i,
  input  logic lsu_req_i,

  // ---- voted outputs
  output logic                    data_req_o,
  output logic [31:0]             data_addr_o,
  output logic                    data_we_o,
  output logic [3:0]              data_be_o,
  output logic [MemDataWidth-1:0] data_wdata_o,

  output logic [31:0]             lsu_rdata_o,
  output logic                    lsu_rdata_valid_o,
  output logic                    load_err_o,
  output logic                    store_err_o,
  output logic                    lsu_req_done_o,
  output logic                    addr_incr_req_o,
  output logic [31:0]             addr_last_o,
  output logic                    lsu_resp_valid_o,
  output logic                    load_resp_intg_err_o,
  output logic                    store_resp_intg_err_o,
  output logic                    busy_o,
  output logic                    perf_load_o,
  output logic                    perf_store_o,

  output logic                    min_err_o,
  output logic                    maj_err_o,
  
  // Child error aggregation outputs
  output logic                    lsu_new_maj_err_o,
  output logic                    lsu_new_min_err_o,
  output logic                    lsu_scrub_occurred_o

  `ifdef FATORI_FI
    // If Fault-Injection is activated create the FI Port
    ,input  logic [7:0]      fi_port 
  `endif  
);

  typedef struct packed {
    logic                     data_req_o;
    logic [31:0]     data_addr_o;
    logic                     data_we_o;
    logic [3:0]     data_be_o;
    logic [MemDataWidth-1:0]  data_wdata_o;

    logic [31:0]  lsu_rdata_o;
    logic                     lsu_rdata_valid_o;

    logic                     load_err_o;
    logic                     store_err_o;

    logic                     lsu_req_done_o;
    logic                     lsu_resp_valid_o;
    logic                     busy_o;

    logic                     addr_incr_req_o;
    logic [31:0]              addr_last_o;

    logic                     load_resp_intg_err_o;
    logic                     store_resp_intg_err_o;
    logic                     perf_load_o;
    logic                     perf_store_o;
    logic                     lsu_new_maj_err_o;
    logic                     lsu_new_min_err_o;
    logic                     lsu_scrub_occurred_o;
  } lsu_out_t;


  localparam int LW = $bits(lsu_out_t);

  lsu_out_t b_rep [N];


  // Replicate LSU
  generate
    for (genvar g = 0; g < N; g++) begin : gen_lsu_reps
      
      // In order to actually use per-replica lockage, the clock has to slow down a bunch
      //`KEEP_LSU
      ibex_load_store_unit #(
        .MemECC       (MemECC),
        .MemDataWidth (MemDataWidth)
      ) u_lsu (
        .clk_i (clk_i),
        .rst_ni(rst_ni),

        // data interface
        .data_req_o    (b_rep[g].data_req_o),
        .data_gnt_i    (data_gnt_i),
        .data_rvalid_i (data_rvalid_i),
        .data_bus_err_i(data_bus_err_i),
        .data_pmp_err_i(data_pmp_err_i),

        .data_addr_o      (b_rep[g].data_addr_o),
        .data_we_o        (b_rep[g].data_we_o),
        .data_be_o        (b_rep[g].data_be_o),
        .data_wdata_o     (b_rep[g].data_wdata_o),
        .data_rdata_i     (data_rdata_i),

        // signals to/from ID/EX stage
        .lsu_we_i      (lsu_we_i),
        .lsu_type_i    (lsu_type_i),
        .lsu_wdata_i   (lsu_wdata_i),
        .lsu_sign_ext_i(lsu_sign_ext_i),

        .lsu_rdata_o      (b_rep[g].lsu_rdata_o),
        .lsu_rdata_valid_o(b_rep[g].lsu_rdata_valid_o),
        .lsu_req_i        (lsu_req_i),
        .lsu_req_done_o   (b_rep[g].lsu_req_done_o),

        .adder_result_ex_i(adder_result_ex_i),

        .addr_incr_req_o(b_rep[g].addr_incr_req_o),
        .addr_last_o    (b_rep[g].addr_last_o),


        .lsu_resp_valid_o(b_rep[g].lsu_resp_valid_o),

        // exception signals
        .load_err_o           (b_rep[g].load_err_o),
        .load_resp_intg_err_o (b_rep[g].load_resp_intg_err_o),
        .store_err_o          (b_rep[g].store_err_o),
        .store_resp_intg_err_o(b_rep[g].store_resp_intg_err_o),

        .busy_o(b_rep[g].busy_o),

        .perf_load_o (b_rep[g].perf_load_o),
        .perf_store_o(b_rep[g].perf_store_o),
        
        // Child error aggregation outputs
        .lsu_new_maj_err_o(b_rep[g].lsu_new_maj_err_o),
        .lsu_new_min_err_o(b_rep[g].lsu_new_min_err_o),
        .lsu_scrub_occurred_o(b_rep[g].lsu_scrub_occurred_o)

        `ifdef FATORI_FI
        ,.fi_port(fi_port)
        `endif
        );
    end
  endgenerate

  // Build bus array for voter
  logic [N-1:0][LW-1:0] rep_bus;
  generate
    for (genvar g = 0; g < N; g++) begin : gen_pack
      assign rep_bus[g] = b_rep[g];
    end
  endgenerate

  // Vote
  logic [LW-1:0] voted_bus;
  logic          min_err_now, maj_err_now;

  logic logic_scrub_occurred;
  
  fatori_mon_voter #(
    .W              (LW),
    .N              (N),
    .M       (M),
    .HOLD (HOLD)
  ) u_vote_lsu (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .replicas_i (rep_bus),
    .y_o        (voted_bus),
    .min_err_o  (min_err_now),
    .maj_err_o  (maj_err_now),
    .scrub_occurred_o (logic_scrub_occurred)
  );

  lsu_out_t voted;
  assign voted = lsu_out_t'(voted_bus);

  assign data_req_o         = voted.data_req_o;
  assign data_addr_o        = voted.data_addr_o;
  assign data_we_o          = voted.data_we_o;
  assign data_be_o          = voted.data_be_o;
  assign data_wdata_o       = voted.data_wdata_o;

  assign lsu_rdata_o        = voted.lsu_rdata_o;
  assign lsu_rdata_valid_o  = voted.lsu_rdata_valid_o;
  assign load_err_o         = voted.load_err_o;
  assign store_err_o        = voted.store_err_o;
  assign lsu_req_done_o = voted.lsu_req_done_o;
  assign addr_incr_req_o = voted.addr_incr_req_o;
  assign addr_last_o = voted.addr_last_o;
  assign lsu_resp_valid_o = voted.lsu_resp_valid_o;
  assign load_resp_intg_err_o = voted.load_resp_intg_err_o;
  assign store_resp_intg_err_o = voted.store_resp_intg_err_o;
  assign busy_o = voted.busy_o;
  assign perf_load_o = voted.perf_load_o;
  assign perf_store_o = voted.perf_store_o;

  assign lsu_new_maj_err_o = voted.lsu_new_maj_err_o;
  assign lsu_new_min_err_o = voted.lsu_new_min_err_o;
  
  // Aggregate register scrubbing (from child lsu) with logic scrubbing (from voter)
  assign lsu_scrub_occurred_o = voted.lsu_scrub_occurred_o | logic_scrub_occurred;

  assign min_err_o          = min_err_now;
  assign maj_err_o          = maj_err_now;

endmodule
