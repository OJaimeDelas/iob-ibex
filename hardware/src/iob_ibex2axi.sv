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
  //AR
  wire arvalid_wire, arready_wire;
  wire [AXI_ADDR_W-2 -1:0] araddr_wire;
  wire [AXI_ADDR_W -1:0] araddr_int;

  //R
  wire rvalid_wire, rready_wire;
  wire [AXI_DATA_W-1:0] rdata_wire;
  wire [1:0] rresp_wire;

  //AW
  wire awvalid_wire, awready_wire;
  wire [AXI_ADDR_W-2 -1:0] awaddr_wire;
  wire [AXI_ADDR_W -1:0] awaddr_int;

  //W
  wire wvalid_wire, wready_wire;
  wire [AXI_DATA_W-1:0] wdata_wire;
  wire [AXI_DATA_W/8-1:0] wstrb_wire;

  //B
  wire bvalid_wire, bready_wire;
  wire [1:0] bresp_wire;

  //IBEX
  wire ibex_req_wire, ibex_we_wire; //inputs
  wire [AXI_ADDR_W-2 -1:0]  ibex_addr_wire;
  wire [AXI_ADDR_W -1:0]    ibex_addr_int;
  wire [IBEX_DATA_W -1:0]   ibex_wdata_wire;
  wire [IBEX_INTG_DATA_W -1:0]    ibex_wdata_intg_wire;
  wire ibex_gnt_wire, ibex_rvalid_wire, ibex_err_wire; // outputs
  wire [IBEX_DATA_W -1:0]   ibex_rdata_wire;
  wire [IBEX_INTG_DATA_W -1:0]    ibex_rdata_intg_wire;

  // Logic Signals
  wire arready_handshake, arready_handshake_next;
  wire rvalid_handshake, rvalid_handshake_next;
  wire wvalid_handshake, wvalid_handshake_next;
  wire awready_handshake, awready_handshake_next;
  wire bvalid_handshake, bvalid_handshake_next;

  wire ibex_rvalid_next;
  wire [IBEX_DATA_W -1:0] ibex_rdata_next;
  wire ibex_err_next;

  assign arst_n = arst_i;
  
  // AxiInputs2Wires
  assign arready_wire = arready_i;

  assign awready_wire = awready_i;

  assign wready_wire  = wready_i;

  assign rvalid_wire  = rvalid_i;
  assign rdata_wire   = rdata_i;
  assign rresp_wire   = rresp_i;

  assign bvalid_wire = bvalid_i;

  // IbexInputs2Wires
  assign ibex_req_wire = ibex_req_i;
  assign ibex_we_wire = ibex_we_i;

  assign ibex_addr_wire = ibex_addr_i;
  assign ibex_addr_int = {ibex_addr_wire,2'b0};

  assign ibex_wdata_wire = ibex_wdata_i;
  assign ibex_wdata_intg_wire = ibex_wdata_intg_i;

  assign araddr_wire = ibex_addr_wire;
  assign awaddr_wire = ibex_addr_wire;
  assign wdata_wire = ibex_wdata_wire;

  // READ Operation  
  // Ibex wants to read something
  // In AXI, a read consists in 2 steps: AR and R.
  // In Ibex, it all happens at once. req_o is set, alongside the read address, and we=0.
  // So, in terms of the AXI interface, the CPU's signals are all ready/valid
  // 
  // We have to consider that once each handshake is done, the intervening signals must be
  // turned off, or the memory will consider it a new interaction.
  //
  // The main thing to take into consideration is that the granted must take into consideration
  // both arready and rvalid, and they can happen in different moments. See "Grant Logic"
  assign arvalid_wire = (ibex_req_wire & ~ibex_we_wire);

  assign rready_wire  = 1'b1;


  // WRITE Operation  
  // Ibex wants to write something
  // In AXI, a write consists in 3 steps: AW, W and then B.
  // In Ibex, it all happens at once. req_o is set, alongside the write address, write data
  // and we=1.
  // So, in terms of the AXI interface, the CPU's signals are all ready/valid
  // 
  // The main thing to take into consideration is that the granted must take into consideration
  // both arready and rvalid, and they can happen in different moments. See "Grant Logic"
  assign wvalid_wire  = (ibex_req_wire & ibex_we_wire);
  
  assign awvalid_wire = (ibex_req_wire & ibex_we_wire);
  
  assign bready_wire = (ibex_req_wire & ibex_we_wire & ~bvalid_handshake);



  // Grant Logic
  //assign ibex_gnt_wire = (rvalid_handshake & arready_handshake) | (bvalid_handshake & wvalid_handshake & awready_handshake); // Read | Write
  
  assign ibex_gnt_wire = (arready_wire & ~ibex_we_wire) | (wready_wire & ibex_we_wire);
  // IBEX rvalid, rdata and error handling
  // After the granted signal is sent, an ibex_rvalid signal should be set the next cycle, and be up for exactly 1 cycle.
  // Alongside with the ibex_rvalid signal, should go the read data or the ibex_error.

  // This ibex_rvalid signal must return to 0 if no other gnt signal was set, so that ibex_rvalid is only 1 for exactly 1 cycle.
  // In the case that there are multiple consecutive memory accesses, there will be consecutive gnt signals, and ibex_rvalid can't reset

  assign ibex_rvalid_wire = rvalid_wire | bvalid_wire; // The valid consists of gnt signal, one cycle delayed
  // iob_reg_re #( // Set ibex_rvalid
  //   .DATA_W(1),
  //   .RST_VAL(0)
  // ) ibex_rvalid_reg (
  //   .clk_i(clk_i),
  //   .cke_i(cke_i),
  //   .arst_i(arst_n),
  //   .en_i('1),
  //   .rst_i('0),
  //   .data_i(ibex_rvalid_next),
  //   .data_o(ibex_rvalid_wire)
  // );

  assign ibex_rdata_wire = rdata_wire; // The valid consists of rdata signal, one cycle delayed
  // iob_reg_re #( // Set ibex_rdata
  //   .DATA_W(IBEX_DATA_W),
  //   .RST_VAL(0)
  // ) ibex_rdata_reg (
  //   .clk_i(clk_i),
  //   .cke_i(cke_i),
  //   .arst_i(arst_n),
  //   .en_i('1),
  //   .rst_i('0),
  //   .data_i(ibex_rdata_next),
  //   .data_o(ibex_rdata_wire)
  // );

  //assign ibex_err_wire = rvalid_wire & (rresp_wire != 2'b00) | bvalid_wire & (bresp_wire != 2'b00);
  assign ibex_err_wire = rvalid_wire & (| rresp_wire) | bvalid_wire & (| bresp_wire) ;
  // iob_reg_re #( // Set ibex_rdata
  //   .DATA_W(1),
  //   .RST_VAL(0)
  // ) ibex_err_reg (
  //   .clk_i(clk_i),
  //   .cke_i(cke_i),
  //   .arst_i(arst_n),
  //   .en_i('1),
  //   .rst_i('0),
  //   .data_i(ibex_err_next),
  //   .data_o(ibex_err_wire)
  // );   

  // Assign final output 
  assign wstrb_o = ibex_be_i;
  assign araddr_o = araddr_wire;
  assign arvalid_o = arvalid_wire;

  assign awaddr_o = awaddr_wire;
  assign awvalid_o = awvalid_wire;

  assign wdata_o = wdata_wire;
  assign wvalid_o  = wvalid_wire;
  
  assign rready_o  = rready_wire;

  assign bready_o = bready_wire;

  assign ibex_gnt_o = ibex_gnt_wire;
  assign ibex_rdata_o = ibex_rdata_wire;
  assign ibex_rdata_intg_o = ibex_rdata_intg_wire;
  assign ibex_rvalid_o = ibex_rvalid_wire;
  assign ibex_err_o = ibex_err_wire;


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
