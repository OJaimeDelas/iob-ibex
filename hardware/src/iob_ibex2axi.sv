module iob_ibex2axi #(
  parameter AXI_ID_W         = 0,
  parameter AXI_ADDR_W       = 32,
  parameter AXI_DATA_W       = 32,
  parameter AXI_LEN_W        = 8,
  parameter IBEX_ADDR_W      = 32,
  parameter IBEX_DATA_W      = 32,
  parameter IBEX_INTG_DATA_W = 7
) (
    
  // Genereral Ports
  input logic clk_i,
  input logic cke_i,
  input logic arst_i, 

  // IBEX Ports
  input logic                            ibex_req_i, // Request - LSU requests access to the memory
  input logic                            ibex_we_i,  // Write enable: 1 = write, 0 = read
  input logic [3:0]                      ibex_be_i,  // Byte enable - Refers which bytes to access. Allows half-word, etc
  input logic [IBEX_ADDR_W -2 -1:0]         ibex_addr_i, // Address from the LSU
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
  wire awvalid_int, wvalid_int, arvalid_int, rvalid_int;
  wire [AXI_ADDR_W-2 -1:0] awaddr_int, araddr_int, ibex_addr_int;
  wire [AXI_DATA_W-1:0] wdata_int, rdata_int;
  wire [AXI_DATA_W/8-1:0] wstrb_int;

  // Register Module for AW Channel
  iob_reg_re #(
    .DATA_W(AXI_ADDR_W-2),
    .RST_VAL(0)
  ) awvalid_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i(ibex_req_i & ibex_we_i),
    .rst_i('0),
    .data_i(ibex_addr_int),
    .data_o(awaddr_int)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) awvalid_reg_2 (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i('1),
    .rst_i('0),
    .data_i(awvalid_next),
    .data_o(awvalid_int)
  );

  // Register Module for W Channel
  iob_reg_re #(
    .DATA_W(AXI_DATA_W),
    .RST_VAL(0)
  ) wdata_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i(ibex_req_i & ibex_we_i),
    .rst_i('0),
    .data_i(ibex_wdata_i),
    .data_o(wdata_int)
  );

  iob_reg_re #(
    .DATA_W(AXI_DATA_W/8),
    .RST_VAL(0)
  ) wstrb_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i(ibex_req_i & ibex_we_i),
    .rst_i('0),
    .data_i(ibex_be_i),
    .data_o(wstrb_int)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) wvalid_reg_2 (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i('1),
    .rst_i('0),
    .data_i(wvalid_next),
    .data_o(wvalid_int)
  );

  // Register Module for AR Channel
  iob_reg_re #(
    .DATA_W(AXI_ADDR_W-2),
    .RST_VAL(0)
  ) arvalid_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i(ibex_req_i & ~ibex_we_i),
    .rst_i('0),
    .data_i(ibex_addr_i),
    .data_o(araddr_int)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) arvalid_reg_2 (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i(ibex_req_i & ~ibex_we_i),
    .rst_i('0),
    .data_i(arvalid_next),
    .data_o(arvalid_int)
  );

  // Register Module for R Channel
  iob_reg_re #(
    .DATA_W(AXI_DATA_W),
    .RST_VAL(0)
  ) rdata_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i(rvalid_i),
    .rst_i('0),
    .data_i(rdata_i),
    .data_o(rdata_int)
  );

  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) rvalid_reg_2 (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i('1),
    .rst_i('0),
    .data_i(rvalid_next),
    .data_o(rvalid_int)
  );
  
  // Assign next values
  assign rvalid_next  = rvalid_i? 1'b1 : 1'b0;
  assign arvalid_next = (ibex_req_i & ~ibex_we_i)?  1'b1 : 1'b0;
  assign wvalid_next  = (ibex_req_i & ibex_we_i)?  1'b1 : 1'b0;
  assign awvalid_next = (ibex_req_i & ibex_we_i)?  1'b1 : 1'b0;

  // Assign final output signals
  assign awvalid_o = awvalid_int;
  assign awaddr_o = awaddr_int;
  
  assign wvalid_o  = wvalid_int;
  assign wdata_o = wdata_int;
  
  assign arvalid_o = arvalid_int;
  assign araddr_o = araddr_int;
  
  assign rready_o  = 1'b1; // Always ready for read transactions
  
  assign ibex_rdata_o = rdata_int;
  assign ibex_rvalid_o = rvalid_int;

  // AXI Error Handling
  assign ibex_err_o = (bvalid_i && bresp_i != 2'b00) || (rvalid_i && rresp_i != 2'b00);

  // Grant Logic
  iob_reg_re #(
    .DATA_W(1),
    .RST_VAL(0)
  ) gnt_reg (
    .clk_i(clk_i),
    .cke_i(cke_i),
    .arst_i(arst_i),
    .en_i('1),
    .rst_i('0),
    .data_i(ibex_gnt_value),
    .data_o(ibex_gnt_o)
  );
  
  // The granted appears if ibex is requiring one (req + we) and the memory accepted (awready+wready or arready+rvalid)
  assign ibex_granted = ibex_req_i && ((awready_i && wready_i && ibex_we_i) | (arready_i && rvalid_i && ~ibex_we_i));
  assign ibex_gnt_value = ibex_granted ? 1'b1 : 1'b0;
  
  
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
