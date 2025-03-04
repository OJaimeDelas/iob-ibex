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

  // IBEX Data Ports
  input logic                            ibex_data_req_i, // Request - LSU requests access to the memory
  input logic                            ibex_data_we_i,  // Write enable: 1 = write, 0 = read
  input logic [3:0]                      ibex_data_be_i,  // Byte enable - Refers which bytes to access. Allows half-word, etc
  input logic [IBEX_ADDR_W -2 -1:0]      ibex_data_addr_i, // Address from the LSU
  input logic [IBEX_DATA_W -1:0]         ibex_data_wdata_i, // Write data
  input logic [IBEX_INTG_DATA_W -1:0]    ibex_data_wdata_intg_i, // Extra parity/integrity bits

  output logic                            ibex_data_gnt_o, // Access Granted signal from memory
  output logic                            ibex_data_rvalid_o, // Read data valid - There's data in rdata and/or err
  output logic [IBEX_DATA_W -1:0]         ibex_data_rdata_o, // Read data output
  output logic [IBEX_INTG_DATA_W -1:0]    ibex_data_rdata_intg_o, // Integrity-protected read data
  output logic                            ibex_data_err_o, // Error signal for LSU

  // IBEX Instruction Ports
  input logic                            ibex_instr_req_i, // Request - LSU requests access to the memory
  input logic [IBEX_ADDR_W -2 -1:0]      ibex_instr_addr_i, // Address from the LSU

  output logic                            ibex_instr_gnt_o, // Access Granted signal from memory
  output logic                            ibex_instr_rvalid_o, // Read data valid - There's data in rdata and/or err
  output logic [IBEX_DATA_W -1:0]         ibex_instr_rdata_o, // Read data output
  output logic [IBEX_INTG_DATA_W -1:0]    ibex_instr_rdata_intg_o, // Integrity-protected read data
  output logic                            ibex_instr_err_o, // Error signal for LSU


  // AXI Data Ports
  // AW Channel
  input                       dbus_awready_i,
  output logic                dbus_awvalid_o, //It's an output because CPU sends the Addr
  output logic [AXI_ADDR_W-2 -1:0] dbus_awaddr_o,
  output logic [2:0]          dbus_awprot_o, 
  output logic [AXI_ID_W-1:0] dbus_awid_o,
  output logic [AXI_LEN_W-1:0] dbus_awlen_o,
  output logic [2:0]          dbus_awsize_o,
  output logic [1:0]          dbus_awburst_o,
  output logic                dbus_awlock_o,
  output logic [3:0]          dbus_awcache_o,
  output logic [3:0]          dbus_awqos_o,

  // W Channel
  input                       dbus_wready_i,
  output logic                dbus_wvalid_o, //It's an output because CPU sends the Data
  output logic [AXI_DATA_W-1:0] dbus_wdata_o,
  output logic [AXI_DATA_W/8-1:0] dbus_wstrb_o,
  output logic                dbus_wlast_o,

  // B Channel
  input                       dbus_bvalid_i,
  input [1:0]                 dbus_bresp_i,
  input [AXI_ID_W-1:0]        dbus_bid_i, 
  output logic                dbus_bready_o, 

  // AR Channel
  input                       dbus_arready_i,
  output logic                dbus_arvalid_o, //It's an output because CPU sends the Addr
  output logic [AXI_ADDR_W-2-1:0] dbus_araddr_o,
  output logic [2:0]          dbus_arprot_o,
  output logic [AXI_ID_W-1:0] dbus_arid_o,
  output logic [AXI_LEN_W-1:0] dbus_arlen_o,
  output logic [2:0]          dbus_arsize_o,
  output logic [1:0]          dbus_arburst_o,
  output logic                dbus_arlock_o,
  output logic [3:0]          dbus_arcache_o,
  output logic [3:0]          dbus_arqos_o,

  // R Channel
  input                       dbus_rvalid_i, //It's an input because Memory sends the Data
  input [AXI_DATA_W-1:0]      dbus_rdata_i,
  input [1:0]                 dbus_rresp_i,
  input [AXI_ID_W-1:0]        dbus_rid_i,
  input                       dbus_rlast_i,
  output logic                dbus_rready_o, 

  // AXI Instruction Ports
  // AR Channel
  input                       ibus_arready_i,
  output logic                ibus_arvalid_o, //It's an output because CPU sends the Addr
  output logic [AXI_ADDR_W-2-1:0] ibus_araddr_o,
  output logic [2:0]          ibus_arprot_o,
  output logic [AXI_ID_W-1:0] ibus_arid_o,
  output logic [AXI_LEN_W-1:0] ibus_arlen_o,
  output logic [2:0]          ibus_arsize_o,
  output logic [1:0]          ibus_arburst_o,
  output logic                ibus_arlock_o,
  output logic [3:0]          ibus_arcache_o,
  output logic [3:0]          ibus_arqos_o,

  // R Channel
  input                       ibus_rvalid_i, //It's an input because Memory sends the Data
  input [AXI_DATA_W-1:0]      ibus_rdata_i,
  input [1:0]                 ibus_rresp_i,
  input [AXI_ID_W-1:0]        ibus_rid_i,
  input                       ibus_rlast_i,
  output logic                ibus_rready_o  
);

  //IBEX
  wire [AXI_ADDR_W -1:0]    ibex_data_addr_int, ibex_instr_addr_int;
  wire [IBEX_INTG_DATA_W -1:0]    ibex_wdata_intg_wire;
  wire [IBEX_INTG_DATA_W -1:0]    ibex_rdata_intg_wire;

  assign arst_n = arst_i;

  assign ibex_data_addr_int = {ibex_data_addr_i,2'b0};
  assign ibex_instr_addr_int = {ibex_instr_addr_i,2'b0};
  assign ibex_data_wdata_intg_wire = ibex_data_wdata_intg_i; //not implemented
  
  
  // Assign final output 
   assign ibex_data_gnt_o = ibex_data_req_i & ((dbus_arready_i & ~ibex_data_we_i) | (dbus_wready_i & ibex_data_we_i));
   assign ibex_instr_gnt_o = ibus_arready_i & ibex_instr_req_i;

  // WRITE Operation  
  // Ibex wants to write something
  // In AXI, a write consists in 3 steps: AW, W and then B.
  // In Ibex, it all happens at once. req_o is set, alongside the write address, write data
  // and we=1.
  // So, in terms of the AXI interface, the CPU's signals are all ready/valid
  // 
  // The main thing to take into consideration is that the granted must take into consideration
  // both arready and rvalid, and they can happen in different moments. See "Grant Logic"
  assign dbus_wstrb_o = ibex_data_be_i;

  assign dbus_awaddr_o = ibex_data_addr_i;
  assign dbus_awvalid_o = (ibex_data_req_i & ibex_data_we_i);

  assign dbus_wdata_o = ibex_data_wdata_i;
  assign dbus_wvalid_o  = (ibex_data_req_i & ibex_data_we_i);

  assign dbus_bready_o = '1;
  

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
  assign dbus_arvalid_o = (ibex_data_req_i & ~ibex_data_we_i);
  assign ibus_arvalid_o = ibex_instr_req_i;

  assign dbus_araddr_o = ibex_data_addr_i;
  assign ibus_araddr_o = ibex_instr_addr_i;
  assign dbus_rready_o  = 1'b1;
  assign ibus_rready_o  = 1'b1;

  // IBEX rvalid, rdata and error handling
  // After the granted signal is sent, an ibex_rvalid signal should be set the next cycle, and be up for exactly 1 cycle.
  // Alongside with the ibex_rvalid signal, should go the read data or the ibex_error.

  // This ibex_rvalid signal must return to 0 if no other gnt signal was set, so that ibex_rvalid is only 1 for exactly 1 cycle.
  // In the case that there are multiple consecutive memory accesses, there will be consecutive gnt signals, and ibex_rvalid can't reset

  assign ibex_data_rdata_o = dbus_rdata_i;
  assign ibex_instr_rdata_o = ibus_rdata_i;

  assign ibex_data_rvalid_o = dbus_rvalid_i | dbus_bvalid_i; //In a write, ibex_rvalid_o is only 1 if there is an error
  assign ibex_instr_rvalid_o = ibus_rvalid_i;

  assign ibex_data_err_o =  dbus_rvalid_i & (| dbus_rresp_i) | dbus_bvalid_i & (| dbus_bresp_i);
  assign ibex_instr_err_o =  ibus_rvalid_i & (| ibus_rresp_i);

  assign ibex_rdata_intg_o = ibex_rdata_intg_wire; //not implemented


  // Default assignments for unused AXI signals
  assign dbus_awprot_o  = '0;
  assign dbus_awid_o    = '0;
  assign dbus_awlen_o   = '0;
  assign dbus_awsize_o  = '0;
  assign dbus_awburst_o = '0;
  assign dbus_awlock_o  = '0;
  assign dbus_awcache_o = '0;
  assign dbus_awqos_o   = '0;
  assign dbus_arprot_o  = '0;
  assign dbus_arid_o    = '0;
  assign dbus_arlen_o   = '0;
  assign dbus_arsize_o  = '0;
  assign dbus_arburst_o = '0;
  assign dbus_arlock_o  = '0;
  assign dbus_arcache_o = '0;
  assign dbus_arqos_o   = '0;
  assign dbus_wlast_o = '1;


  assign ibus_arprot_o  = '0;
  assign ibus_arid_o    = '0;
  assign ibus_arlen_o   = '0;
  assign ibus_arsize_o  = '0;
  assign ibus_arburst_o = '0;
  assign ibus_arlock_o  = '0;
  assign ibus_arcache_o = '0;
  assign ibus_arqos_o   = '0;

endmodule
