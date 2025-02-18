`timescale 1ns / 1ps
`include "iob_bsp.vh"
`include "iob_ibex_conf.vh"
`include "prim_assert.sv"

module iob_ibex import ibex_pkg::*; #(
   parameter AXI_ID_W         = `IOB_IBEX_AXI_ID_W,
   parameter AXI_ADDR_W       = `IOB_IBEX_AXI_ADDR_W,
   parameter AXI_DATA_W       = `IOB_IBEX_AXI_DATA_W,
   parameter AXI_LEN_W        = `IOB_IBEX_AXI_LEN_W,
   parameter IBEX_ADDR_W      = AXI_ADDR_W,
   parameter IBEX_DATA_W      = AXI_DATA_W,
   parameter IBEX_INTG_DATA_W = 7
) (
   // clk_en_rst_s
   input                       clk_i,
   input                       cke_i,
   input                       arst_i,
   // rst_i
   input                       rst_i,
   // i_bus_m
   output [AXI_ADDR_W - 2-1:0] ibus_axi_araddr_o,
   output [             3-1:0] ibus_axi_arprot_o,
   output                      ibus_axi_arvalid_o,
   input                       ibus_axi_arready_i,
   input  [    AXI_DATA_W-1:0] ibus_axi_rdata_i,
   input  [             2-1:0] ibus_axi_rresp_i,
   input                       ibus_axi_rvalid_i,
   output                      ibus_axi_rready_o,
   output [      AXI_ID_W-1:0] ibus_axi_arid_o,
   output [     AXI_LEN_W-1:0] ibus_axi_arlen_o,
   output [             3-1:0] ibus_axi_arsize_o,
   output [             2-1:0] ibus_axi_arburst_o,
   output                      ibus_axi_arlock_o,
   output [             4-1:0] ibus_axi_arcache_o,
   output [             4-1:0] ibus_axi_arqos_o,
   input  [      AXI_ID_W-1:0] ibus_axi_rid_i,
   input                       ibus_axi_rlast_i,
   output [AXI_ADDR_W - 2-1:0] ibus_axi_awaddr_o,
   output [             3-1:0] ibus_axi_awprot_o,
   output                      ibus_axi_awvalid_o,
   input                       ibus_axi_awready_i,
   output [    AXI_DATA_W-1:0] ibus_axi_wdata_o,
   output [  AXI_DATA_W/8-1:0] ibus_axi_wstrb_o,
   output                      ibus_axi_wvalid_o,
   input                       ibus_axi_wready_i,
   input  [             2-1:0] ibus_axi_bresp_i,
   input                       ibus_axi_bvalid_i,
   output                      ibus_axi_bready_o,
   output [      AXI_ID_W-1:0] ibus_axi_awid_o,
   output [     AXI_LEN_W-1:0] ibus_axi_awlen_o,
   output [             3-1:0] ibus_axi_awsize_o,
   output [             2-1:0] ibus_axi_awburst_o,
   output                      ibus_axi_awlock_o,
   output [             4-1:0] ibus_axi_awcache_o,
   output [             4-1:0] ibus_axi_awqos_o,
   output                      ibus_axi_wlast_o,
   input  [      AXI_ID_W-1:0] ibus_axi_bid_i,
   // d_bus_m
   output [AXI_ADDR_W - 2-1:0] dbus_axi_araddr_o,
   output [             3-1:0] dbus_axi_arprot_o,
   output                      dbus_axi_arvalid_o,
   input                       dbus_axi_arready_i,
   input  [    AXI_DATA_W-1:0] dbus_axi_rdata_i,
   input  [             2-1:0] dbus_axi_rresp_i,
   input                       dbus_axi_rvalid_i,
   output                      dbus_axi_rready_o,
   output [      AXI_ID_W-1:0] dbus_axi_arid_o,
   output [     AXI_LEN_W-1:0] dbus_axi_arlen_o,
   output [             3-1:0] dbus_axi_arsize_o,
   output [             2-1:0] dbus_axi_arburst_o,
   output                      dbus_axi_arlock_o,
   output [             4-1:0] dbus_axi_arcache_o,
   output [             4-1:0] dbus_axi_arqos_o,
   input  [      AXI_ID_W-1:0] dbus_axi_rid_i,
   input                       dbus_axi_rlast_i,
   output [AXI_ADDR_W - 2-1:0] dbus_axi_awaddr_o,
   output [             3-1:0] dbus_axi_awprot_o,
   output                      dbus_axi_awvalid_o,
   input                       dbus_axi_awready_i,
   output [    AXI_DATA_W-1:0] dbus_axi_wdata_o,
   output [  AXI_DATA_W/8-1:0] dbus_axi_wstrb_o,
   output                      dbus_axi_wvalid_o,
   input                       dbus_axi_wready_i,
   input  [             2-1:0] dbus_axi_bresp_i,
   input                       dbus_axi_bvalid_i,
   output                      dbus_axi_bready_o,
   output [      AXI_ID_W-1:0] dbus_axi_awid_o,
   output [     AXI_LEN_W-1:0] dbus_axi_awlen_o,
   output [             3-1:0] dbus_axi_awsize_o,
   output [             2-1:0] dbus_axi_awburst_o,
   output                      dbus_axi_awlock_o,
   output [             4-1:0] dbus_axi_awcache_o,
   output [             4-1:0] dbus_axi_awqos_o,
   output                      dbus_axi_wlast_o,
   input  [      AXI_ID_W-1:0] dbus_axi_bid_i
);
   // cpu_reset
   wire                        cpu_reset_neg;
   wire                        cpu_reset;
   // data_
   wire                        data_req_o;
   wire                        data_we_o;
   wire [               4-1:0] data_be_o;
   wire [     IBEX_ADDR_W-2 -1:0] data_addr_o;
   wire [     IBEX_ADDR_W -1:0] data_addr_int; //Ibex sets addr with 32bits, IOB with 30bits
   wire [     IBEX_DATA_W-1:0] data_wdata_o;
   wire [IBEX_INTG_DATA_W-1:0] data_wdata_intg_o;
   wire                        data_gnt_i;
   wire                        data_rvalid_i;
   wire [     IBEX_DATA_W-1:0] data_rdata_i;
   wire [IBEX_INTG_DATA_W-1:0] data_rdata_intg_i;
   wire                        data_err_i;
   // instr_
   wire                        instr_req_o;
   wire                        instr_gnt_i;
   wire [     IBEX_ADDR_W -2-1:0] instr_addr_o;
   wire [     IBEX_ADDR_W -1:0] instr_addr_int; //Ibex sets addr with 32bits, IOB with 30bits
   wire                        instr_rvalid_i;
   wire [     IBEX_DATA_W-1:0] instr_rdata_i;
   wire [IBEX_INTG_DATA_W-1:0] instr_rdata_intg_i;
   wire                        instr_err_i;

   // full addresses
   wire [AXI_ADDR_W -1:0] ibus_axi_araddr_o_int;
   wire [AXI_ADDR_W -1:0] ibus_axi_awaddr_o_int;
   wire [AXI_ADDR_W -1:0] dbus_axi_araddr_o_int;
   wire [AXI_ADDR_W -1:0] dbus_axi_awaddr_o_int;
   wire [1:0] curr_turn;
   wire stalling_wire, data_allow_wire;


   /*
 * AXI to Ibex LSU Protocol
 */

   // //Turn Order Module
   // //This allows for 2 modules to access the same memory
   // iob_ibex2axi_turn ibex2axi_turn (

   //    //Control
   //    .clk_i(clk_i),
   //    .cke_i(cke_i),
   //    .arst_i(arst_i),

   //    .req_1(instr_req_o),
   //    .gnt_1(instr_gnt_i),
   //    .req_0(data_req_o),
   //    .gnt_0(data_gnt_i),
   //    //.stalling_i('0), //if ibex stalls, this should too
   //    .stalling_i(stalling_wire), //if ibex stalls, this should too
   //    .data_allowed(data_allow_wire),
   //    .curr_turn(curr_turn) // 2-bit output to represent different turns
   // );

   // Data Bus
   iob_ibex2axi #(
      .AXI_ID_W        (AXI_ID_W),
      .AXI_ADDR_W      (AXI_ADDR_W),
      .AXI_DATA_W      (AXI_DATA_W),
      .AXI_LEN_W       (AXI_LEN_W),
      .IBEX_ADDR_W     (IBEX_ADDR_W),
      .IBEX_DATA_W     (IBEX_DATA_W),
      .IBEX_INTG_DATA_W(IBEX_INTG_DATA_W)
   ) data_iob2ibex (

      //Control
      .clk_i(clk_i),
      .cke_i(cke_i),
      .arst_i(arst_i),

      // IBEX Ports
      .ibex_req_i(data_req_o),  // Request - LSU requests access to the memory
      .ibex_we_i(data_we_o),  // Write enable: 1 = write, 0 = read
      .ibex_be_i(data_be_o),  // Byte enable - Refers which bytes to access. Allows half-word, etc
      .ibex_addr_i(data_addr_o),  // Address from the LSU
      .ibex_wdata_i(data_wdata_o),  // Write data
      .ibex_wdata_intg_i(data_wdata_intg_o),  // Extra parity/integrity bits

      .ibex_gnt_o       (data_gnt_i),         // Access Granted signal from memory
      .ibex_rvalid_o    (data_rvalid_i),      // Read data valid - There's data in rdata and/or err
      .ibex_rdata_o     (data_rdata_i),       // Read data output
      .ibex_rdata_intg_o(data_rdata_intg_i),  // Integrity-protected read data
      .ibex_err_o       (data_err_i),         // Error signal for LSU

      // AXI Ports
      // AW Channel
      .awready_i(dbus_axi_awready_i),
      .awvalid_o(dbus_axi_awvalid_o),  //It's an output because CPU sends the Addr
      .awaddr_o (dbus_axi_awaddr_o),
      .awprot_o (dbus_axi_awprot_o),
      .awid_o   (dbus_axi_awid_o),
      .awlen_o  (dbus_axi_awlen_o),
      .awsize_o (dbus_axi_awsize_o),
      .awburst_o(dbus_axi_awburst_o),
      .awlock_o (dbus_axi_awlock_o),
      .awcache_o(dbus_axi_awcache_o),
      .awqos_o  (dbus_axi_awqos_o),

      // W Channel
      .wready_i(dbus_axi_wready_i),
      .wvalid_o(dbus_axi_wvalid_o),  //It's an output because CPU sends the Data
      .wdata_o (dbus_axi_wdata_o),
      .wstrb_o (dbus_axi_wstrb_o),
      .wlast_o (dbus_axi_wlast_o),

      // B Channel
      .bvalid_i(dbus_axi_bvalid_i),
      .bresp_i (dbus_axi_bresp_i),
      .bid_i   (dbus_axi_bid_i),
      .bready_o(dbus_axi_bready_o),  //It's an input because Memory answers

      // AR Channel
      .arready_i(dbus_axi_arready_i),
      .arvalid_o(dbus_axi_arvalid_o),  //It's an output because CPU sends the Addr
      .araddr_o (dbus_axi_araddr_o),
      .arprot_o (dbus_axi_arprot_o),
      .arid_o   (dbus_axi_arid_o),
      .arlen_o  (dbus_axi_arlen_o),
      .arsize_o (dbus_axi_arsize_o),
      .arburst_o(dbus_axi_arburst_o),
      .arlock_o (dbus_axi_arlock_o),
      .arcache_o(dbus_axi_arcache_o),
      .arqos_o  (dbus_axi_arqos_o),

      // R Channel
      .rvalid_i(dbus_axi_rvalid_i),  //It's an input because Memory sends the Data
      .rdata_i (dbus_axi_rdata_i),
      .rresp_i (dbus_axi_rresp_i),
      .rid_i   (dbus_axi_rid_i),
      .rlast_i (dbus_axi_rlast_i),
      .rready_o(dbus_axi_rready_o)
   );

   // Instruction Bus
   iob_ibex2axi #(
      .AXI_ID_W        (AXI_ID_W),
      .AXI_ADDR_W      (AXI_ADDR_W),
      .AXI_DATA_W      (AXI_DATA_W),
      .AXI_LEN_W       (AXI_LEN_W),
      .IBEX_ADDR_W     (IBEX_ADDR_W),
      .IBEX_DATA_W     (IBEX_DATA_W),
      .IBEX_INTG_DATA_W(IBEX_INTG_DATA_W)
   ) instr_iob2ibex (

      //Control
      .clk_i(clk_i),
      .cke_i(cke_i),
      .arst_i(arst_i),

      // IBEX Ports
      .ibex_req_i(instr_req_o),  // Request - LSU requests access to the memory
      .ibex_we_i('0),  // Write enable: 1 = write, 0 = read
      .ibex_be_i('0),  // Byte enable - Refers which bytes to access. Allows half-word, etc
      .ibex_addr_i(instr_addr_o),  // Address from the LSU
      .ibex_wdata_i('0),  // Write data
      .ibex_wdata_intg_i('0),  // Extra parity/integrity bits

      .ibex_gnt_o       (instr_gnt_i),         // Access Granted signal from memory
      .ibex_rvalid_o    (instr_rvalid_i),      // Read data valid - There's data in rdata and/or err
      .ibex_rdata_o     (instr_rdata_i),       // Read data output
      .ibex_rdata_intg_o(instr_rdata_intg_i),  // Integrity-protected read data
      .ibex_err_o       (instr_err_i),         // Error signal for LSU

      // AXI Ports
      // AW Channel
      .awready_i('0),
      .awvalid_o(),     //It's an output because CPU sends the Addr
      .awaddr_o (),
      .awprot_o (),
      .awid_o   (),
      .awlen_o  (),
      .awsize_o (),
      .awburst_o(),
      .awlock_o (),
      .awcache_o(),
      .awqos_o  (),

      // W Channel
      .wready_i('0),
      .wvalid_o(),     //It's an output because CPU sends the Data
      .wdata_o (),
      .wstrb_o (),
      .wlast_o (),

      // B Channel
      .bvalid_i('0),
      .bresp_i ('0),
      .bid_i   ('0),
      .bready_o(),     //It's an input because Memory answers

      // AR Channel
      .arready_i(ibus_axi_arready_i),
      .arvalid_o(ibus_axi_arvalid_o),  //It's an output because CPU sends the Addr
      .araddr_o (ibus_axi_araddr_o),
      .arprot_o (ibus_axi_arprot_o),
      .arid_o   (ibus_axi_arid_o),
      .arlen_o  (ibus_axi_arlen_o),
      .arsize_o (ibus_axi_arsize_o),
      .arburst_o(ibus_axi_arburst_o),
      .arlock_o (ibus_axi_arlock_o),
      .arcache_o(ibus_axi_arcache_o),
      .arqos_o  (ibus_axi_arqos_o),

      // R Channel
      .rvalid_i(ibus_axi_rvalid_i),  //It's an input because Memory sends the Data
      .rdata_i (ibus_axi_rdata_i),
      .rresp_i (ibus_axi_rresp_i),
      .rid_i   (ibus_axi_rid_i),
      .rlast_i (ibus_axi_rlast_i),
      .rready_o(ibus_axi_rready_o)
   );


   /*
 * Some parameters' definitions
 */

   parameter bit                 RV32E                    = 1'b0;
   parameter ibex_pkg::rv32m_e   RV32M                    = ibex_pkg::RV32MSingleCycle;
   parameter ibex_pkg::rv32b_e   RV32B                    = ibex_pkg::RV32BOTEarlGrey;
   parameter ibex_pkg::regfile_e RegFile                  = ibex_pkg::RegFileFF;
   parameter bit                 BranchTargetALU          = 1'b1;
   parameter bit                 WritebackStage           = 1'b1;
   parameter bit                 ICache                   = 1'b0;
   parameter bit                 ICacheECC                = 1'b0;
   parameter bit                 ICacheScramble           = 1'b0;
   parameter bit                 BranchPredictor          = 1'b0;
   parameter bit                 DbgTriggerEn             = 1'b1;
   parameter bit                 SecureIbex               = 1'b1;
   parameter bit                 PMPEnable                = 1'b1;
   parameter int unsigned        PMPGranularity           = 0;
   parameter int unsigned        PMPNumRegions            = 16;
   parameter int unsigned        MHPMCounterNum           = 10;
   parameter int unsigned        MHPMCounterWidth         = 32;
   parameter                     SRAMInitFile             = "";

   /**
 * Top level module of the ibex RISC-V core
 */
   ibex_top #(
      .PMPEnable       (PMPEnable),
      .PMPGranularity  (PMPGranularity),
      .PMPNumRegions   (PMPNumRegions),
      .MHPMCounterNum  (MHPMCounterNum),
      .MHPMCounterWidth(MHPMCounterWidth),
      .RV32E           (RV32E),
      .RV32M           (RV32M),
      .RV32B           (RV32B),
      .RegFile         (RegFile),
      .BranchTargetALU (BranchTargetALU),
      .WritebackStage  (WritebackStage),
      .ICache          (ICache),
      .ICacheECC       (ICacheECC),
      .BranchPredictor (BranchPredictor),
      .DbgTriggerEn    (DbgTriggerEn),
      .SecureIbex      (SecureIbex),
      .ICacheScramble  (ICacheScramble),
      .DmHaltAddr      ('0),
      .DmExceptionAddr ('0)
   ) u_top (
      .stalling_o(stalling_wire),
      .clk_i (clk_i),
      .rst_ni(cpu_reset_neg),

      .test_en_i  ('0),
      .scan_rst_ni('1),
      .ram_cfg_i  ('0),

      .hart_id_i  ('0),
      // First instruction executed is at 0x7FFFFF80 + 0x80 = 0x80000000
      .boot_addr_i(32'h80000000),

      // Instruction memory interface
      .instr_req_o       (instr_req_o),
      .instr_gnt_i       (instr_gnt_i),
      .instr_rvalid_i    (instr_rvalid_i),
      .instr_addr_o      (instr_addr_int),
      .instr_rdata_i     (instr_rdata_i),
      .instr_rdata_intg_i(instr_rdata_intg_i),
      .instr_err_i       (instr_err_i),

      // Data memory interface
      .data_req_o       (data_req_o),
      .data_gnt_i       (data_gnt_i),
      .data_rvalid_i    (data_rvalid_i),
      .data_we_o        (data_we_o),
      .data_be_o        (data_be_o),
      .data_addr_o      (data_addr_int),
      .data_wdata_o     (data_wdata_o),
      .data_wdata_intg_o(data_wdata_intg_o),
      .data_rdata_i     (data_rdata_i),
      .data_rdata_intg_i(data_rdata_intg_i),
      .data_err_i       (data_err_i),

      .irq_software_i('0),
      .irq_timer_i   ('0),
      .irq_external_i('0),
      .irq_fast_i    ('0),
      .irq_nm_i      ('0),

      .scramble_key_valid_i('0),
      .scramble_key_i      ('0),
      .scramble_nonce_i    ('0),
      .scramble_req_o      (),

      .debug_req_i        ('0),
      .crash_dump_o       (),
      .double_fault_seen_o(),

      .fetch_enable_i        (ibex_pkg::IbexMuBiOn),
      .alert_minor_o         (),
      .alert_major_internal_o(),
      .alert_major_bus_o     (),
      .core_sleep_o          ()
   );

   assign instr_addr_o = instr_addr_int[31:2];
   assign data_addr_o = data_addr_int[31:2];

   assign cpu_reset         = (rst_i) | (arst_i);
   assign cpu_reset_neg          = !(cpu_reset);

   assign ibus_axi_awvalid_o = 1'b0;
   assign ibus_axi_awaddr_o  = {AXI_ADDR_W - 2{1'b0}};
   assign ibus_axi_awid_o    = 1'b0;
   assign ibus_axi_awlen_o   = {AXI_LEN_W{1'b0}};
   assign ibus_axi_awsize_o  = {3{1'b0}};
   assign ibus_axi_awburst_o = {2{1'b0}};
   assign ibus_axi_awlock_o  = 1'b0;
   assign ibus_axi_awcache_o = {4{1'b0}};
   assign ibus_axi_awqos_o   = {4{1'b0}};
   assign ibus_axi_awprot_o  = {3{1'b0}};
   assign ibus_axi_wvalid_o  = 1'b0;
   assign ibus_axi_wdata_o   = {AXI_DATA_W{1'b0}};
   assign ibus_axi_wstrb_o   = {AXI_DATA_W / 8{1'b0}};
   assign ibus_axi_wlast_o   = 1'b0;
   assign ibus_axi_bready_o  = 1'b0;

   //Integrer addresses
   assign ibus_axi_araddr_o_int = {ibus_axi_araddr_o, 2'b0};
   assign ibus_axi_awaddr_o_int = {ibus_axi_awaddr_o, 2'b0};
   assign dbus_axi_araddr_o_int = {dbus_axi_araddr_o, 2'b0};
   assign dbus_axi_awaddr_o_int = {dbus_axi_awaddr_o, 2'b0};






endmodule
