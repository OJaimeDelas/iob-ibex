module iob_ibex2axi #(
  parameter AXI_ID_W         = 0,
  parameter AXI_ADDR_W       = 32,
  parameter AXI_DATA_W       = 32,
  parameter AXI_LEN_W        = 8,
  parameter IBEX_ADDR_W      = 32,
  parameter IBEX_DATA_W      = 32,
  parameter IBEX_INTG_DATA_W = 7
) (

  input logic data_allowed,
    
  // Genereral Ports
  input logic clk_i,
  input logic cke_i,
  input logic arst_i, 

  // Multiple Access Control    
  input logic                            DualModules, // Are two of these modules accessing the same memory? dbus and ibus, i.e.
  input logic [1:0]                           converter_id,
  input logic [1:0]                            turn_identifier,

  // IBEX Ports
  input logic                            ibex_req_i, // Request - LSU requests access to the memory
  input logic                            ibex_we_i,  // Write enable: 1 = write, 0 = read
  input logic [3:0]                      ibex_be_i,  // Byte enable - Refers which bytes to access. Allows half-word, etc
  input logic [IBEX_ADDR_W -2 -1:0]      ibex_addr_i, // Address from the LSU
  input logic [IBEX_DATA_W -1:0]         ibex_wdata_i, // Write data
  input logic [IBEX_INTG_DATA_W -1:0]    ibex_wdata_intg_i, // Extra parity/integrity bits

  output logic                            ibex_gnt_o, // Access Granted signal from memory
  output logic                            ibex_rvalid_o, // Read data valid - There's data in rdata and/or err
  output logic [IBEX_DATA_W -1:0]         ibex_rdata_o, // Read data output
  output logic [IBEX_INTG_DATA_W -1:0]    ibex_rdata_intg_o, // Integrity-protected read data
  output logic                            ibex_err_o, // Error signal for LSU

  // AXI Ports
  // AW Channel
  input                       awready_i,
  output logic                awvalid_o, //It's an output because CPU sends the Addr
  output logic [AXI_ADDR_W-2 -1:0] awaddr_o,
  output logic [2:0]          awprot_o, 
  output logic [AXI_ID_W-1:0] awid_o,
  output logic [AXI_LEN_W-1:0] awlen_o,
  output logic [2:0]          awsize_o,
  output logic [1:0]          awburst_o,
  output logic                awlock_o,
  output logic [3:0]          awcache_o,
  output logic [3:0]          awqos_o,

  // W Channel
  input                       wready_i,
  output logic                wvalid_o, //It's an output because CPU sends the Data
  output logic [AXI_DATA_W-1:0] wdata_o,
  output logic [AXI_DATA_W/8-1:0] wstrb_o,
  output logic                wlast_o,

  // B Channel
  input                       bvalid_i,
  input [1:0]                 bresp_i,
  input [AXI_ID_W-1:0]        bid_i, 
  output logic                bready_o, 

  // AR Channel
  input                       arready_i,
  output logic                arvalid_o, //It's an output because CPU sends the Addr
  output logic [AXI_ADDR_W-2-1:0] araddr_o,
  output logic [2:0]          arprot_o,
  output logic [AXI_ID_W-1:0] arid_o,
  output logic [AXI_LEN_W-1:0] arlen_o,
  output logic [2:0]          arsize_o,
  output logic [1:0]          arburst_o,
  output logic                arlock_o,
  output logic [3:0]          arcache_o,
  output logic [3:0]          arqos_o,

  // R Channel
  input                       rvalid_i, //It's an input because Memory sends the Data
  input [AXI_DATA_W-1:0]      rdata_i,
  input [1:0]                 rresp_i,
  input [AXI_ID_W-1:0]        rid_i,
  input                       rlast_i,
  output logic                rready_o 
);

  // Internal signals for stateful logic
  wire awvalid_internal, wvalid_internal, arvalid_internal, rvalid_internal;
  wire [AXI_ADDR_W-2 -1:0] awaddr_internal, araddr_internal;
  wire [AXI_ADDR_W -1:0] awaddr_int, araddr_int, ibex_addr_int;
  wire [AXI_DATA_W-1:0] wdata_internal, rdata_internal;
  wire [AXI_DATA_W/8-1:0] wstrb_internal;
  wire arst_n, awready_handshake, wready_handshake;
  reg ibex_granted, valid_turn, stall_turn;

  //DualModule functioning
  always_comb begin
    if ( DualModules == '1) begin
      if ( converter_id == turn_identifier | data_allowed) begin
        valid_turn = 1'b1;
        assign awvalid_o = awvalid_internal;
        assign wvalid_o  = wvalid_internal;
        assign arvalid_o = arvalid_internal;

        // The granted appears if ibex is requiring one (req + we) and the memory accepted (awready+wready or arready+rvalid)
        ibex_granted = ibex_req_i && ((awready_handshake && wready_handshake && ibex_we_i) | (arready_i && rvalid_i && ~ibex_we_i));   
      end else if ( 2'b11 == turn_identifier) begin
        // Some functionality needs to remain in a stall, so that the cpu leaves that state
        stall_turn = 1'b1;

        assign awvalid_o = awvalid_internal;
        assign wvalid_o  = wvalid_internal;
        assign arvalid_o = arvalid_internal;

        // The granted appears if ibex is requiring one (req + we) and the memory accepted (awready+wready or arready+rvalid)
        ibex_granted = ibex_req_i && ((awready_handshake && wready_handshake && ibex_we_i) | (arready_i && rvalid_i && ~ibex_we_i));   

      end else begin
        stall_turn = '0;
        valid_turn = '0;
        assign awvalid_o = '0;
        assign wvalid_o  = '0;
        assign arvalid_o = '0;
        ibex_granted = '0;
      end

    end else begin
      stall_turn = '1;
      valid_turn = '1;
      assign awvalid_o = awvalid_internal;
      assign wvalid_o  = wvalid_internal;
      assign arvalid_o = arvalid_internal;
      ibex_granted = ibex_req_i && ((awready_handshake && wready_handshake && ibex_we_i) | (arready_i && rvalid_i && ~ibex_we_i));
    end

  end

  assign ibex_gnt_value = ibex_granted ? 1'b1 : 1'b0;

  assign arst_n = arst_i;

  // Register Module for AWADDR Handshake
  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) awready_handshake_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n | (~ibex_req_i) | ibex_granted), // Reset this value if the operation is completed/dropped
    .en_i(awready_i & ibex_req_i & ibex_we_i & (valid_turn | stall_turn)),
    .rst_i('0),
    .data_i('1),
    .data_o(awready_handshake)
  );

  // Register Module for WDATA Handshake
  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) wready_handshake_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n | (~ibex_req_i) | ibex_granted), // Reset this value if the operation is completed/dropped
    .en_i(wready_i & ibex_req_i & ibex_we_i & (valid_turn | stall_turn)),
    .rst_i('0),
    .data_i('1),
    .data_o(wready_handshake)
  );

  // Register Module for AW Channel
  iob_reg_re #(
    .DATA_W(AXI_ADDR_W-2),
    .RST_VAL(0)
  ) awaddr_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i(ibex_req_i & ibex_we_i & valid_turn),
    .rst_i('0),
    .data_i(ibex_addr_i),
    .data_o(awaddr_internal)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) awvalid_next_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i((valid_turn | stall_turn)),
    .rst_i('0),
    .data_i(awvalid_next),
    .data_o(awvalid_internal)
  );

  // Register Module for W Channel
  iob_reg_re #(
    .DATA_W(AXI_DATA_W),
    .RST_VAL(0)
  ) wdata_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i(ibex_req_i & ibex_we_i & valid_turn),
    .rst_i('0),
    .data_i(ibex_wdata_i),
    .data_o(wdata_internal)
  );

  iob_reg_re #(
    .DATA_W(AXI_DATA_W/8),
    .RST_VAL(0)
  ) wstrb_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i(ibex_req_i & ibex_we_i & valid_turn),
    .rst_i('0),
    .data_i(ibex_be_i),
    .data_o(wstrb_internal)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) wvalid_next_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i((valid_turn | stall_turn)),
    .rst_i('0),
    .data_i(wvalid_next),
    .data_o(wvalid_internal)
  );

  // Register Module for AR Channel
  iob_reg_re #(
    .DATA_W(AXI_ADDR_W-2),
    .RST_VAL(0)
  ) araddr_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i(ibex_req_i & ~ibex_we_i & valid_turn),
    .rst_i('0),
    .data_i(ibex_addr_i),
    .data_o(araddr_internal)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) arvalid_next_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i(ibex_req_i & ~ibex_we_i & (valid_turn | stall_turn)),
    .rst_i('0),
    .data_i(arvalid_next),
    .data_o(arvalid_internal)
  );

  // Register Module for R Channel
  iob_reg_re #(
    .DATA_W(AXI_DATA_W),
    .RST_VAL(0)
  ) rdata_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i(rvalid_i),
    .rst_i('0),
    .data_i(rdata_i),
    .data_o(rdata_internal)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) rvalid_reg_2 (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i(valid_turn),
    .rst_i('0),
    .data_i(rvalid_next),
    .data_o(rvalid_internal)
  );
  
  // Assign next values
  assign rvalid_next  = rvalid_i? 1'b1 : 1'b0;
  assign arvalid_next = (ibex_req_i & ~ibex_we_i)?  1'b1 : 1'b0;
  assign wvalid_next  = (ibex_req_i & ibex_we_i)?  1'b1 : 1'b0;
  assign awvalid_next = (ibex_req_i & ibex_we_i)?  1'b1 : 1'b0;

  // Assign final output signals - Some signals depend on DualModules
  assign awaddr_o = awaddr_internal;
  
  assign wdata_o = wdata_internal;
  
  assign araddr_o = araddr_internal;
  
  assign rready_o  = 1'b1; // Always ready for read transactions
  
  assign ibex_rdata_o = rdata_internal;
  assign ibex_rvalid_o = rvalid_internal;

  // Make the full addresses available
  assign awaddr_int = {awaddr_internal, 2'b0};
  assign araddr_int = {araddr_internal , 2'b0};
  assign ibex_addr_int = {ibex_addr_i , 2'b0};

  // AXI Error Handling
  assign ibex_err_o = (bvalid_i && bresp_i != 2'b00) || (rvalid_i && rresp_i != 2'b00);

  // Grant Logic
  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) gnt_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_n),
    .en_i('1),
    .rst_i('0),
    .data_i(ibex_gnt_value),
    .data_o(ibex_gnt_o)
  );

  // Default assignments for unused AXI signals
  assign awprot_o  = '0;
  assign awid_o    = '0;
  assign awlen_o   = '0;
  assign awsize_o  = '0;
  assign awburst_o = '0;
  assign awlock_o  = '0;
  assign awcache_o = '0;
  assign awqos_o   = '0;
  assign arprot_o  = '0;
  assign arid_o    = '0;
  assign arlen_o   = '0;
  assign arsize_o  = '0;
  assign arburst_o = '0;
  assign arlock_o  = '0;
  assign arcache_o = '0;
  assign arqos_o   = '0;

endmodule
