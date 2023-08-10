/******************************************************************************
 * Function:  Link UMI ("LUMI") Top Level Module
 * Author:    Amir Volk
 * Copyright: 2023 Zero ASIC Corporation. All rights reserved.
 *
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * Version history:
 *
 * 1. convert from CLINK
 *
 *****************************************************************************/
module lumi
  #(parameter TARGET = "DEFAULT", // compiler target
    parameter IDOFFSET = 24,      // chip ID address offset
    parameter GRPOFFSET = 24,     // group address offset
    parameter GRPAW = 8,          // group address width
    parameter GRPID = 0,          // group ID
    // for development
    parameter DW = 128,           // umi packet width
    parameter CW = 32,            // umi packet width
    parameter AW = 64,            // address width
    parameter RW = 64,            // register width
    parameter IDW = 16,           // chipid width
    parameter IOW = 64,           // phy IO width
    parameter CRDTFIFOD = 64      // Fifo size need to account for 64B over 2B link
    )
   (// host/device selector
    input            devicemode,     // 1=device, 0=host
    // UMI host port
    output           uhost_req_valid,
    output [CW-1:0]  uhost_req_cmd,
    output [AW-1:0]  uhost_req_dstaddr,
    output [AW-1:0]  uhost_req_srcaddr,
    output [DW-1:0]  uhost_req_data,
    input            uhost_req_ready,
    input            uhost_resp_valid,
    input [CW-1:0]   uhost_resp_cmd,
    input [AW-1:0]   uhost_resp_dstaddr,
    input [AW-1:0]   uhost_resp_srcaddr,
    input [DW-1:0]   uhost_resp_data,
    output           uhost_resp_ready,
    // UMI device port
    input            udev_req_valid,
    input [CW-1:0]   udev_req_cmd,
    input [AW-1:0]   udev_req_dstaddr,
    input [AW-1:0]   udev_req_srcaddr,
    input [DW-1:0]   udev_req_data,
    output           udev_req_ready,
    output           udev_resp_valid,
    output [CW-1:0]  udev_resp_cmd,
    output [AW-1:0]  udev_resp_dstaddr,
    output [AW-1:0]  udev_resp_srcaddr,
    output [DW-1:0]  udev_resp_data,
    input            udev_resp_ready,
    // LinkHost sideband interface - register access
    input            sb_in_valid,    // host-request, device-response
    input [CW-1:0]   sb_in_cmd,
    input [AW-1:0]   sb_in_dstaddr,
    input [AW-1:0]   sb_in_srcaddr,
    input [RW-1:0]   sb_in_data,
    output           sb_in_ready,
    output           sb_out_valid,   // device-request, host-response
    output [CW-1:0]  sb_out_cmd,
    output [AW-1:0]  sb_out_dstaddr,
    output [AW-1:0]  sb_out_srcaddr,
    output [RW-1:0]  sb_out_data,
    input            sb_out_ready,
    // phy sideband interface - paththrough based on address
    input            phy_in_valid,   // host-response, device-request
    input [CW-1:0]   phy_in_cmd,
    input [AW-1:0]   phy_in_dstaddr,
    input [AW-1:0]   phy_in_srcaddr,
    input [RW-1:0]   phy_in_data,
    output           phy_in_ready,
    output           phy_out_valid,  // host-request, device-response
    output [CW-1:0]  phy_out_cmd,
    output [AW-1:0]  phy_out_dstaddr,
    output [AW-1:0]  phy_out_srcaddr,
    output [RW-1:0]  phy_out_data,
    input            phy_out_ready,
    // phy data interface (LUMI)
    input [IOW-1:0]  phy_rxdata,
    input            phy_rxvld,
    output           phy_rxrdy,
    output [IOW-1:0] phy_txdata,
    output           phy_txvld,
    input            phy_txrdy,
    // phy control interface
    input            phy_linkactive,
    // Host control interface
    input            nreset,         // host driven reset
    input            clk,            // host driven clock
    input            devicready,
    output           host_linkactive, // link is locked/ready
    // supplies
    input            vss,            // common ground
    input            vdd,            // core supply
    input            vddio,          // io voltage
    /*AUTOINPUT*/
    // Beginning of automatic inputs (from unused autoinst inputs)
    input               cb2serial_ready,
    input [CW-1:0]      serial2cb_cmd,
    input [DW-1:0]      serial2cb_data,
    input [AW-1:0]      serial2cb_dstaddr,
    input [AW-1:0]      serial2cb_srcaddr,
    input               serial2cb_valid,
    // End of automatics
    /*AUTOOUTPUT*/
    // Beginning of automatic outputs (from unused autoinst outputs)
    output [CW-1:0]     cb2serial_cmd,
    output [DW-1:0]     cb2serial_data,
    output [AW-1:0]     cb2serial_dstaddr,
    output [AW-1:0]     cb2serial_srcaddr,
    output              cb2serial_valid,
    output              serial2cb_ready
    // End of automatics
    );

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        cb2regs_cmd;
   wire [DW-1:0]        cb2regs_data;
   wire [AW-1:0]        cb2regs_dstaddr;
   wire                 cb2regs_ready;
   wire [AW-1:0]        cb2regs_srcaddr;
   wire                 cb2regs_valid;
   wire [15:0]          csr_rxcrdt_req_init;
   wire [15:0]          csr_rxcrdt_resp_init;
   wire                 csr_rxen;
   wire [7:0]           csr_rxiowidth;
   wire                 csr_txcrdt_en;
   wire [15:0]          csr_txcrdt_intrvl;
   wire [31:0]          csr_txcrdt_status;
   wire                 csr_txen;
   wire [7:0]           csr_txiowidth;
   wire [15:0]          loc_crdt_req;
   wire [15:0]          loc_crdt_resp;
   wire [CW-1:0]        regs2cb_cmd;
   wire [DW-1:0]        regs2cb_data;
   wire [AW-1:0]        regs2cb_dstaddr;
   wire                 regs2cb_ready;
   wire [AW-1:0]        regs2cb_srcaddr;
   wire                 regs2cb_valid;
   wire [15:0]          rmt_crdt_req;
   wire [15:0]          rmt_crdt_resp;
   // End of automatics

   //##########################
   // Central CLINK controller
   //##########################

   /*lumi_regs  AUTO_TEMPLATE (
    .udev_resp_\(.*\)    (regs2cb_\1[]),
    .udev_req_\(.*\)     (cb2regs_\1[]),
    .csr_rxarbmode       (),
    .csr_arbmode         (),
    .csr_test.*          (),
    )
    */

   lumi_regs #(.TARGET(TARGET),
                .GRPOFFSET(GRPOFFSET),
                .GRPAW(GRPAW),
		.GRPID(GRPID),
                .DW(DW),
                .RW(RW),
                .CW(CW),
		.AW(AW),
                .CRDTFIFOD(CRDTFIFOD))
   lumi_regs(/*AUTOINST*/
             // Outputs
             .nreset            (nreset),
             .clk               (clk),
             .udev_req_ready    (cb2regs_ready),         // Templated
             .udev_resp_valid   (regs2cb_valid),         // Templated
             .udev_resp_cmd     (regs2cb_cmd[CW-1:0]),   // Templated
             .udev_resp_dstaddr (regs2cb_dstaddr[AW-1:0]), // Templated
             .udev_resp_srcaddr (regs2cb_srcaddr[AW-1:0]), // Templated
             .udev_resp_data    (regs2cb_data[DW-1:0]),  // Templated
             .host_linkactive   (host_linkactive),
             .csr_arbmode       (),                      // Templated
             .csr_txen          (csr_txen),
             .csr_txcrdt_en     (csr_txcrdt_en),
             .csr_txiowidth     (csr_txiowidth[7:0]),
             .csr_rxen          (csr_rxen),
             .csr_rxiowidth     (csr_rxiowidth[7:0]),
             .csr_txcrdt_intrvl (csr_txcrdt_intrvl[15:0]),
             .csr_rxcrdt_req_init(csr_rxcrdt_req_init[15:0]),
             .csr_rxcrdt_resp_init(csr_rxcrdt_resp_init[15:0]),
             // Inputs
             .devicemode        (devicemode),
             .devicready        (devicready),
             .udev_req_valid    (cb2regs_valid),         // Templated
             .udev_req_cmd      (cb2regs_cmd[CW-1:0]),   // Templated
             .udev_req_dstaddr  (cb2regs_dstaddr[AW-1:0]), // Templated
             .udev_req_srcaddr  (cb2regs_srcaddr[AW-1:0]), // Templated
             .udev_req_data     (cb2regs_data[DW-1:0]),  // Templated
             .udev_resp_ready   (regs2cb_ready),         // Templated
             .phy_linkactive    (phy_linkactive),
             .csr_txcrdt_status (csr_txcrdt_status[31:0]));

   //###########################
   // Register Crossbar
   //###########################

   /*lumi_crossbar  AUTO_TEMPLATE (
    .regs_out_\(.*\)    (cb2regs_\1[]),
    .regs_in_\(.*\)     (regs2cb_\1[]),
    .serial_out_\(.*\)  (cb2serial_\1[]),
    .serial_in_\(.*\)   (serial2cb_\1[]),
    .core_out_\(.*\)    (sb_out_\1[]),
    .core_in_\(.*\)     (sb_in_\1[]),
    )
    */

   lumi_crossbar #(.AW(AW),
                    .CW(CW),
                    .DW(DW),
                    .IDOFFSET(IDOFFSET),
                    .GRPOFFSET(GRPOFFSET),
                    .GRPAW(GRPAW),
                    .GRPID(GRPID))
   lumi_crossbar(/*AUTOINST*/
                 // Outputs
                 .core_in_ready         (sb_in_ready),           // Templated
                 .core_out_valid        (sb_out_valid),          // Templated
                 .core_out_cmd          (sb_out_cmd[CW-1:0]),    // Templated
                 .core_out_dstaddr      (sb_out_dstaddr[AW-1:0]), // Templated
                 .core_out_srcaddr      (sb_out_srcaddr[AW-1:0]), // Templated
                 .core_out_data         (sb_out_data[DW-1:0]),   // Templated
                 .serial_in_ready       (serial2cb_ready),       // Templated
                 .serial_out_valid      (cb2serial_valid),       // Templated
                 .serial_out_cmd        (cb2serial_cmd[CW-1:0]), // Templated
                 .serial_out_dstaddr    (cb2serial_dstaddr[AW-1:0]), // Templated
                 .serial_out_srcaddr    (cb2serial_srcaddr[AW-1:0]), // Templated
                 .serial_out_data       (cb2serial_data[DW-1:0]), // Templated
                 .regs_in_ready         (regs2cb_ready),         // Templated
                 .regs_out_valid        (cb2regs_valid),         // Templated
                 .regs_out_cmd          (cb2regs_cmd[CW-1:0]),   // Templated
                 .regs_out_dstaddr      (cb2regs_dstaddr[AW-1:0]), // Templated
                 .regs_out_srcaddr      (cb2regs_srcaddr[AW-1:0]), // Templated
                 .regs_out_data         (cb2regs_data[DW-1:0]),  // Templated
                 // Inputs
                 .nreset                (nreset),
                 .clk                   (clk),
                 .devicemode            (devicemode),
                 .core_in_valid         (sb_in_valid),           // Templated
                 .core_in_cmd           (sb_in_cmd[CW-1:0]),     // Templated
                 .core_in_dstaddr       (sb_in_dstaddr[AW-1:0]), // Templated
                 .core_in_srcaddr       (sb_in_srcaddr[AW-1:0]), // Templated
                 .core_in_data          (sb_in_data[DW-1:0]),    // Templated
                 .core_out_ready        (sb_out_ready),          // Templated
                 .serial_in_valid       (serial2cb_valid),       // Templated
                 .serial_in_cmd         (serial2cb_cmd[CW-1:0]), // Templated
                 .serial_in_dstaddr     (serial2cb_dstaddr[AW-1:0]), // Templated
                 .serial_in_srcaddr     (serial2cb_srcaddr[AW-1:0]), // Templated
                 .serial_in_data        (serial2cb_data[DW-1:0]), // Templated
                 .serial_out_ready      (cb2serial_ready),       // Templated
                 .regs_in_valid         (regs2cb_valid),         // Templated
                 .regs_in_cmd           (regs2cb_cmd[CW-1:0]),   // Templated
                 .regs_in_dstaddr       (regs2cb_dstaddr[AW-1:0]), // Templated
                 .regs_in_srcaddr       (regs2cb_srcaddr[AW-1:0]), // Templated
                 .regs_in_data          (regs2cb_data[DW-1:0]),  // Templated
                 .regs_out_ready        (cb2regs_ready));        // Templated

   //########################
   // RX
   //########################

   /*lumi_rx  AUTO_TEMPLATE (
    .csr_rx\(.*\)        (csr_rx\1),
    .csr_\(.*\)          (csr_@"(substring vl-cell-name 5 7)"\1[]),
    .umi_resp_out_\(.*\) (udev_resp_\1[]),
    .umi_req_out_\(.*\)  (uhost_req_\1[]),
    .clkfb               (),
    )
    */

   lumi_rx #(.TARGET(TARGET),
	     .IOW(IOW),
             .CW(CW),
             .AW(AW),
	     .DW(DW),
             .CRDTFIFOD(CRDTFIFOD))
   lumi_rx(/*AUTOINST*/
           // Outputs
           .phy_rxrdy           (phy_rxrdy),
           .umi_resp_out_cmd    (udev_resp_cmd[CW-1:0]), // Templated
           .umi_resp_out_dstaddr(udev_resp_dstaddr[AW-1:0]), // Templated
           .umi_resp_out_srcaddr(udev_resp_srcaddr[AW-1:0]), // Templated
           .umi_resp_out_data   (udev_resp_data[DW-1:0]), // Templated
           .umi_resp_out_valid  (udev_resp_valid),       // Templated
           .umi_req_out_cmd     (uhost_req_cmd[CW-1:0]), // Templated
           .umi_req_out_dstaddr (uhost_req_dstaddr[AW-1:0]), // Templated
           .umi_req_out_srcaddr (uhost_req_srcaddr[AW-1:0]), // Templated
           .umi_req_out_data    (uhost_req_data[DW-1:0]), // Templated
           .umi_req_out_valid   (uhost_req_valid),       // Templated
           .loc_crdt_req        (loc_crdt_req[15:0]),
           .loc_crdt_resp       (loc_crdt_resp[15:0]),
           .rmt_crdt_req        (rmt_crdt_req[15:0]),
           .rmt_crdt_resp       (rmt_crdt_resp[15:0]),
           // Inputs
           .clk                 (clk),
           .nreset              (nreset),
           .csr_en              (csr_rxen),              // Templated
           .csr_iowidth         (csr_rxiowidth[7:0]),    // Templated
           .vss                 (vss),
           .vdd                 (vdd),
           .vddio               (vddio),
           .phy_rxdata          (phy_rxdata[IOW-1:0]),
           .phy_rxvld           (phy_rxvld),
           .umi_resp_out_ready  (udev_resp_ready),       // Templated
           .umi_req_out_ready   (uhost_req_ready),       // Templated
           .csr_crdt_req_init   (csr_rxcrdt_req_init[15:0]), // Templated
           .csr_crdt_resp_init  (csr_rxcrdt_resp_init[15:0])); // Templated

   //########################
   // TX
   //########################

   /*lumi_tx  AUTO_TEMPLATE (
    .csr_tx\(.*\)        (csr_tx\1),
    .csr_\(.*\)          (csr_@"(substring vl-cell-name 5 7)"\1[]),
    .umi_resp_in_\(.*\)  (uhost_resp_\1[]),
    .umi_req_in_\(.*\)   (udev_req_\1[]),
    )
    */

   lumi_tx #(.TARGET(TARGET),
	      .IOW(IOW),
              .CW(CW),
              .AW(AW),
	      .DW(DW))
   lumi_tx(/*AUTOINST*/
           // Outputs
           .umi_req_in_ready    (udev_req_ready),        // Templated
           .umi_resp_in_ready   (uhost_resp_ready),      // Templated
           .phy_txdata          (phy_txdata[IOW-1:0]),
           .phy_txvld           (phy_txvld),
           .csr_crdt_status     (csr_txcrdt_status[31:0]), // Templated
           // Inputs
           .clk                 (clk),
           .nreset              (nreset),
           .csr_en              (csr_txen),              // Templated
           .csr_crdt_en         (csr_txcrdt_en),         // Templated
           .csr_iowidth         (csr_txiowidth[7:0]),    // Templated
           .vss                 (vss),
           .vdd                 (vdd),
           .vddio               (vddio),
           .umi_req_in_valid    (udev_req_valid),        // Templated
           .umi_req_in_cmd      (udev_req_cmd[CW-1:0]),  // Templated
           .umi_req_in_dstaddr  (udev_req_dstaddr[AW-1:0]), // Templated
           .umi_req_in_srcaddr  (udev_req_srcaddr[AW-1:0]), // Templated
           .umi_req_in_data     (udev_req_data[DW-1:0]), // Templated
           .umi_resp_in_valid   (uhost_resp_valid),      // Templated
           .umi_resp_in_cmd     (uhost_resp_cmd[CW-1:0]), // Templated
           .umi_resp_in_dstaddr (uhost_resp_dstaddr[AW-1:0]), // Templated
           .umi_resp_in_srcaddr (uhost_resp_srcaddr[AW-1:0]), // Templated
           .umi_resp_in_data    (uhost_resp_data[DW-1:0]), // Templated
           .phy_txrdy           (phy_txrdy),
           .csr_crdt_intrvl     (csr_txcrdt_intrvl[15:0]), // Templated
           .rmt_crdt_req        (rmt_crdt_req[15:0]),
           .rmt_crdt_resp       (rmt_crdt_resp[15:0]),
           .loc_crdt_req        (loc_crdt_req[15:0]),
           .loc_crdt_resp       (loc_crdt_resp[15:0]));

endmodule // clink
// Local Variables:
// verilog-library-directories:("." "../../../oh/stdlib/rtl" "../../umi/umi/rtl")
// End:
