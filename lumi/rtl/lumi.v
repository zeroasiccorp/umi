/******************************************************************************
 * Function:  Chiplet Link ("CLINK") Top Level Module
 * Author:    Andreas Olofsson
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 *
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * Documentation:
 *
 * 1. Use devicemode to configure clink in device or host mode
 *
 *
 *****************************************************************************/
module clink
  #(parameter TARGET = "DEFAULT", // compiler target
    parameter RXDEPTH = 4,        // RX fifo depth
    parameter TXDEPTH = 4,        // TX fifo depth
    parameter IDOFFSET = 24,      // chip ID address offset
    parameter GRPOFFSET = 24,     // group address offset
    parameter GRPAW = 8,          // group address width
    parameter GRPID = 0,          // group ID
    // for development
    parameter DW = 256,           // umi packet width
    parameter CW = 32,            // umi packet width
    parameter AW = 64,            // address width
    parameter IDW = 16,           // chipid width
    parameter IOW = 64,           // data pins per clink
    parameter NMIO = 80,          // muxed io per clink
    parameter CRDTFIFOD = 64      // Fifo size need to account for 64B over 2B link
    )
   (// host/device selector
    input            devicemode,         // 1=device, 0=host
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
    // Link siddeband
    input            sb_in_valid,       // host-request, device-response
    input [CW-1:0]   sb_in_cmd,
    input [AW-1:0]   sb_in_dstaddr,
    input [AW-1:0]   sb_in_srcaddr,
    input [DW-1:0]   sb_in_data,
    output           sb_in_ready,
    output           sb_out_valid,      // device-request, host-response
    output [CW-1:0]  sb_out_cmd,
    output [AW-1:0]  sb_out_dstaddr,
    output [AW-1:0]  sb_out_srcaddr,
    output [DW-1:0]  sb_out_data,
    input            sb_out_ready,
    // io pins
    input            io_nreset_in,       // reset input (device)
    output           io_nreset_out,      // reset input (host)
    input [3:0]      io_clk_in,          // clock input (device)
    output [3:0]     io_clk_out,         // clock output (host)
    input [3:0]      io_ctrl_in,         // ctrl input (device)
    output [3:0]     io_ctrl_out,        // ctrl output (host)
    input [3:0]      io_status_in,       // status input (host)
    output [3:0]     io_status_out,      // status output (device)
    input [3:0]      io_rxctrl_in,       // rx data valid
    input [IOW-1:0]  io_rxdata_in,       // rx data
    output [3:0]     io_rxstatus_out,    // rx ready
    output [3:0]     io_txctrl_out,      // tx data valid
    output [IOW-1:0] io_txdata_out,      // tx data
    input [3:0]      io_txstatus_in,     // tx ready
    // Host side interface
    input            host_nreset,        // host driven reset
    input [3:0]      host_clk,           // host driven clock
    input            host_calibrate,     // start link calibration
    output [6:0]     host_error,         // errors
    output           host_linkready,     // link is locked/ready
    // Device side interface
    input [AW-1:0]   device_status,      // device status (to reg)
    input            device_ready,       // device is ready
    input [6:0]      device_error,       // device errors to I/O
    output           device_nreset,      // device reset from I/O
    output [3:0]     device_clk,         // device clks from I/O
    output           device_go,          // 1 = start (boot), 0 = wait
    output           device_testmode,    // puts device in testmode
    output [AW-1:0]  device_ctrl,        // generic ctrl signals (from reg)
    output [IDW-1:0] device_chipid,      // device chipid ("whoami")
    output [1:0]     device_chipdir,     // rotation (00=0, 01=90,10=180,11=270)
    output [1:0]     device_chipletmode, // 00=1X,01=4X,10=16X,11=1024X
    // scan interface
    input            host_scanmode,
    input            host_scanenable,
    input            host_scanclk,
    input            host_scanin,
    output           host_scanout,
    output           device_scanmode,
    output           device_scanenable,
    output           device_scanclk,
    output           device_scanin,
    input            device_scanout,
    // supplies
    input            vss,                // common ground
    input            vdd,                // core supply
    input            vddio               // io voltage
    /*AUTOINPUT*/
    /*AUTOOUTPUT*/
    );

   localparam RW = 64;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        cb2regs_cmd;
   wire [DW-1:0]        cb2regs_data;
   wire [AW-1:0]        cb2regs_dstaddr;
   wire                 cb2regs_ready;
   wire [AW-1:0]        cb2regs_srcaddr;
   wire                 cb2regs_valid;
   wire [CW-1:0]        cb2serial_cmd;
   wire [DW-1:0]        cb2serial_data;
   wire [AW-1:0]        cb2serial_dstaddr;
   wire                 cb2serial_ready;
   wire [AW-1:0]        cb2serial_srcaddr;
   wire                 cb2serial_valid;
   wire [1:0]           chipdir;
   wire                 clk;
   wire                 csr_rxbpfifo;
   wire                 csr_rxbpio;
   wire                 csr_rxbpprotocol;
   wire                 csr_rxchaos;
   wire                 csr_rxclkchange;
   wire [7:0]           csr_rxclkdiv;
   wire                 csr_rxclken;
   wire [15:0]          csr_rxclkphase;
   wire [15:0]          csr_rxcrdt_req_init;
   wire [15:0]          csr_rxcrdt_resp_init;
   wire                 csr_rxddrmode;
   wire [3:0]           csr_rxeccmode;
   wire                 csr_rxen;
   wire [7:0]           csr_rxiowidth;
   wire [3:0]           csr_rxprotocol;
   wire                 csr_rxreqempty;
   wire                 csr_rxreqfull;
   wire                 csr_rxrespempty;
   wire                 csr_rxrespfull;
   wire [7:0]           csr_spidiv;
   wire [31:0]          csr_spitimeout;
   wire [1:0]           csr_txarbmode;
   wire                 csr_txbpfifo;
   wire                 csr_txbpio;
   wire                 csr_txbpprotocol;
   wire                 csr_txchaos;
   wire                 csr_txclkchange;
   wire [7:0]           csr_txclkdiv;
   wire                 csr_txclken;
   wire [15:0]          csr_txclkphase;
   wire                 csr_txcrdt_en;
   wire [15:0]          csr_txcrdt_intrvl;
   wire [31:0]          csr_txcrdt_status;
   wire                 csr_txddrmode;
   wire [3:0]           csr_txeccmode;
   wire                 csr_txen;
   wire [7:0]           csr_txiowidth;
   wire [3:0]           csr_txprotocol;
   wire                 csr_txreqempty;
   wire                 csr_txreqfull;
   wire                 csr_txrespempty;
   wire                 csr_txrespfull;
   wire                 device_sck;
   wire                 device_scsn;
   wire                 device_sdi;
   wire                 device_sdo;
   wire                 host_sck;
   wire                 host_scsn;
   wire                 host_sdi;
   wire                 host_sdo;
   wire [15:0]          loc_crdt_req;
   wire [15:0]          loc_crdt_resp;
   wire                 nreset;
   wire [CW-1:0]        regs2cb_cmd;
   wire [DW-1:0]        regs2cb_data;
   wire [AW-1:0]        regs2cb_dstaddr;
   wire                 regs2cb_ready;
   wire [AW-1:0]        regs2cb_srcaddr;
   wire                 regs2cb_valid;
   wire [15:0]          rmt_crdt_req;
   wire [15:0]          rmt_crdt_resp;
   wire                 rxclk;
   wire                 rxnreset;
   wire [CW-1:0]        serial2cb_cmd;
   wire [DW-1:0]        serial2cb_data;
   wire [AW-1:0]        serial2cb_dstaddr;
   wire                 serial2cb_ready;
   wire [AW-1:0]        serial2cb_srcaddr;
   wire                 serial2cb_valid;
   wire                 txclk;
   wire                 txnreset;
   // End of automatics

   //##########################
   // Central CLINK controller
   //##########################

   /*clink_regs  AUTO_TEMPLATE (
    .udev_resp_\(.*\)    (regs2cb_\1[]),
    .udev_req_\(.*\)     (cb2regs_\1[]),
    .csr_rxarbmode       (),
    .csr_arbmode         (),
    .csr_test.*          (),
    )
    */

   clink_regs #(.TARGET(TARGET),
                .GRPOFFSET(GRPOFFSET),
                .GRPAW(GRPAW),
		.GRPID(GRPID),
                .DW(DW),
                .RW(RW),
                .CW(CW),
		.AW(AW),
                .CRDTFIFOD(CRDTFIFOD))
   clink_regs(/*AUTOINST*/
              // Outputs
              .chipdir          (chipdir[1:0]),
              .nreset           (nreset),
              .clk              (clk),
              .udev_req_ready   (cb2regs_ready),         // Templated
              .udev_resp_valid  (regs2cb_valid),         // Templated
              .udev_resp_cmd    (regs2cb_cmd[CW-1:0]),   // Templated
              .udev_resp_dstaddr(regs2cb_dstaddr[AW-1:0]), // Templated
              .udev_resp_srcaddr(regs2cb_srcaddr[AW-1:0]), // Templated
              .udev_resp_data   (regs2cb_data[DW-1:0]),  // Templated
              .io_nreset_out    (io_nreset_out),
              .io_clk_out       (io_clk_out[3:0]),
              .io_ctrl_out      (io_ctrl_out[3:0]),
              .io_status_out    (io_status_out[3:0]),
              .host_error       (host_error[6:0]),
              .device_nreset    (device_nreset),
              .device_clk       (device_clk[3:0]),
              .device_go        (device_go),
              .device_testmode  (device_testmode),
              .device_ctrl      (device_ctrl[AW-1:0]),
              .device_chipid    (device_chipid[IDW-1:0]),
              .device_chipdir   (device_chipdir[1:0]),
              .device_chipletmode(device_chipletmode[1:0]),
              .host_scanout     (host_scanout),
              .device_scanenable(device_scanenable),
              .device_scanclk   (device_scanclk),
              .device_scanin    (device_scanin),
              .host_sdi         (host_sdi),
              .device_scsn      (device_scsn),
              .device_sck       (device_sck),
              .device_sdi       (device_sdi),
              .csr_arbmode      (),                      // Templated
              .csr_txen         (csr_txen),
              .csr_txcrdt_en    (csr_txcrdt_en),
              .csr_txddrmode    (csr_txddrmode),
              .csr_txiowidth    (csr_txiowidth[7:0]),
              .csr_txprotocol   (csr_txprotocol[3:0]),
              .csr_txeccmode    (csr_txeccmode[3:0]),
              .csr_txarbmode    (csr_txarbmode[1:0]),
              .csr_rxen         (csr_rxen),
              .csr_rxddrmode    (csr_rxddrmode),
              .csr_rxiowidth    (csr_rxiowidth[7:0]),
              .csr_rxprotocol   (csr_rxprotocol[3:0]),
              .csr_rxeccmode    (csr_rxeccmode[3:0]),
              .csr_rxarbmode    (),                      // Templated
              .csr_spidiv       (csr_spidiv[7:0]),
              .csr_spitimeout   (csr_spitimeout[31:0]),
              .csr_testmode     (),                      // Templated
              .csr_testlfsr     (),                      // Templated
              .csr_testinject   (),                      // Templated
              .csr_testpattern  (),                      // Templated
              .csr_txbpprotocol (csr_txbpprotocol),
              .csr_txbpfifo     (csr_txbpfifo),
              .csr_txbpio       (csr_txbpio),
              .csr_rxbpprotocol (csr_rxbpprotocol),
              .csr_rxbpfifo     (csr_rxbpfifo),
              .csr_rxbpio       (csr_rxbpio),
              .csr_txchaos      (csr_txchaos),
              .csr_rxchaos      (csr_rxchaos),
              .csr_rxclkchange  (csr_rxclkchange),
              .csr_rxclken      (csr_rxclken),
              .csr_rxclkdiv     (csr_rxclkdiv[7:0]),
              .csr_rxclkphase   (csr_rxclkphase[15:0]),
              .csr_txclkchange  (csr_txclkchange),
              .csr_txclken      (csr_txclken),
              .csr_txclkdiv     (csr_txclkdiv[7:0]),
              .csr_txclkphase   (csr_txclkphase[15:0]),
              .csr_txcrdt_intrvl(csr_txcrdt_intrvl[15:0]),
              .csr_rxcrdt_req_init(csr_rxcrdt_req_init[15:0]),
              .csr_rxcrdt_resp_init(csr_rxcrdt_resp_init[15:0]),
              // Inputs
              .devicemode       (devicemode),
              .udev_req_valid   (cb2regs_valid),         // Templated
              .udev_req_cmd     (cb2regs_cmd[CW-1:0]),   // Templated
              .udev_req_dstaddr (cb2regs_dstaddr[AW-1:0]), // Templated
              .udev_req_srcaddr (cb2regs_srcaddr[AW-1:0]), // Templated
              .udev_req_data    (cb2regs_data[DW-1:0]),  // Templated
              .udev_resp_ready  (regs2cb_ready),         // Templated
              .io_nreset_in     (io_nreset_in),
              .io_clk_in        (io_clk_in[3:0]),
              .io_ctrl_in       (io_ctrl_in[3:0]),
              .io_status_in     (io_status_in[3:0]),
              .host_nreset      (host_nreset),
              .host_clk         (host_clk[3:0]),
              .host_scanmode    (host_scanmode),
              .device_status    (device_status[AW-1:0]),
              .device_ready     (device_ready),
              .device_error     (device_error[6:0]),
              .host_scanenable  (host_scanenable),
              .host_scanclk     (host_scanclk),
              .host_scanin      (host_scanin),
              .device_scanout   (device_scanout),
              .host_scsn        (host_scsn),
              .host_sck         (host_sck),
              .host_sdo         (host_sdo),
              .device_sdo       (device_sdo),
              .csr_rxrespfull   (csr_rxrespfull),
              .csr_rxrespempty  (csr_rxrespempty),
              .csr_rxreqfull    (csr_rxreqfull),
              .csr_rxreqempty   (csr_rxreqempty),
              .csr_txrespfull   (csr_txrespfull),
              .csr_txrespempty  (csr_txrespempty),
              .csr_txreqfull    (csr_txreqfull),
              .csr_txreqempty   (csr_txreqempty),
              .csr_txcrdt_status(csr_txcrdt_status[31:0]));

   //###########################
   // Register Crossbar
   //###########################

   /*clink_crossbar  AUTO_TEMPLATE (
    .regs_out_\(.*\)    (cb2regs_\1[]),
    .regs_in_\(.*\)     (regs2cb_\1[]),
    .serial_out_\(.*\)  (cb2serial_\1[]),
    .serial_in_\(.*\)   (serial2cb_\1[]),
    .core_out_\(.*\)    (sb_out_\1[]),
    .core_in_\(.*\)     (sb_in_\1[]),
    )
    */

   clink_crossbar #(.AW(AW),
                    .CW(CW),
                    .DW(DW),
                    .IDOFFSET(IDOFFSET),
                    .GRPOFFSET(GRPOFFSET),
                    .GRPAW(GRPAW),
                    .GRPID(GRPID))
   clink_crossbar(/*AUTOINST*/
                  // Outputs
                  .core_in_ready        (sb_in_ready),           // Templated
                  .core_out_valid       (sb_out_valid),          // Templated
                  .core_out_cmd         (sb_out_cmd[CW-1:0]),    // Templated
                  .core_out_dstaddr     (sb_out_dstaddr[AW-1:0]), // Templated
                  .core_out_srcaddr     (sb_out_srcaddr[AW-1:0]), // Templated
                  .core_out_data        (sb_out_data[DW-1:0]),   // Templated
                  .serial_in_ready      (serial2cb_ready),       // Templated
                  .serial_out_valid     (cb2serial_valid),       // Templated
                  .serial_out_cmd       (cb2serial_cmd[CW-1:0]), // Templated
                  .serial_out_dstaddr   (cb2serial_dstaddr[AW-1:0]), // Templated
                  .serial_out_srcaddr   (cb2serial_srcaddr[AW-1:0]), // Templated
                  .serial_out_data      (cb2serial_data[DW-1:0]), // Templated
                  .regs_in_ready        (regs2cb_ready),         // Templated
                  .regs_out_valid       (cb2regs_valid),         // Templated
                  .regs_out_cmd         (cb2regs_cmd[CW-1:0]),   // Templated
                  .regs_out_dstaddr     (cb2regs_dstaddr[AW-1:0]), // Templated
                  .regs_out_srcaddr     (cb2regs_srcaddr[AW-1:0]), // Templated
                  .regs_out_data        (cb2regs_data[DW-1:0]),  // Templated
                  // Inputs
                  .nreset               (nreset),
                  .clk                  (clk),
                  .devicemode           (devicemode),
                  .core_in_valid        (sb_in_valid),           // Templated
                  .core_in_cmd          (sb_in_cmd[CW-1:0]),     // Templated
                  .core_in_dstaddr      (sb_in_dstaddr[AW-1:0]), // Templated
                  .core_in_srcaddr      (sb_in_srcaddr[AW-1:0]), // Templated
                  .core_in_data         (sb_in_data[DW-1:0]),    // Templated
                  .core_out_ready       (sb_out_ready),          // Templated
                  .serial_in_valid      (serial2cb_valid),       // Templated
                  .serial_in_cmd        (serial2cb_cmd[CW-1:0]), // Templated
                  .serial_in_dstaddr    (serial2cb_dstaddr[AW-1:0]), // Templated
                  .serial_in_srcaddr    (serial2cb_srcaddr[AW-1:0]), // Templated
                  .serial_in_data       (serial2cb_data[DW-1:0]), // Templated
                  .serial_out_ready     (cb2serial_ready),       // Templated
                  .regs_in_valid        (regs2cb_valid),         // Templated
                  .regs_in_cmd          (regs2cb_cmd[CW-1:0]),   // Templated
                  .regs_in_dstaddr      (regs2cb_dstaddr[AW-1:0]), // Templated
                  .regs_in_srcaddr      (regs2cb_srcaddr[AW-1:0]), // Templated
                  .regs_in_data         (regs2cb_data[DW-1:0]),  // Templated
                  .regs_out_ready       (cb2regs_ready));        // Templated


   //########################
   // Clock Divider
   //########################

   clink_clocks #(.TARGET(TARGET))
   clink_clocks (/*AUTOINST*/
                 // Outputs
                 .txclk                 (txclk),
                 .txnreset              (txnreset),
                 .rxclk                 (rxclk),
                 .rxnreset              (rxnreset),
                 // Inputs
                 .clk                   (clk),
                 .nreset                (nreset),
                 .csr_rxclkchange       (csr_rxclkchange),
                 .csr_rxclken           (csr_rxclken),
                 .csr_rxclkdiv          (csr_rxclkdiv[7:0]),
                 .csr_rxclkphase        (csr_rxclkphase[15:0]),
                 .csr_txclkchange       (csr_txclkchange),
                 .csr_txclken           (csr_txclken),
                 .csr_txclkdiv          (csr_txclkdiv[7:0]),
                 .csr_txclkphase        (csr_txclkphase[15:0]));

   //########################
   // Serial Interface
   //########################

   /*clink_serial  AUTO_TEMPLATE (
    .ioclk             (spiclk),
    .umi_in_\(.*\)     (cb2serial_\1[]),
    .umi_out_\(.*\)    (serial2cb_\1[]),
    )
    */

   clink_serial #(.DW(DW),
		  .CW(CW),
		  .AW(AW),
		  .TARGET(TARGET))
   clink_serial(/*AUTOINST*/
                // Outputs
                .host_scsn      (host_scsn),
                .host_sck       (host_sck),
                .host_sdo       (host_sdo),
                .device_sdo     (device_sdo),
                .umi_in_ready   (cb2serial_ready),       // Templated
                .umi_out_valid  (serial2cb_valid),       // Templated
                .umi_out_cmd    (serial2cb_cmd[CW-1:0]), // Templated
                .umi_out_dstaddr(serial2cb_dstaddr[AW-1:0]), // Templated
                .umi_out_srcaddr(serial2cb_srcaddr[AW-1:0]), // Templated
                .umi_out_data   (serial2cb_data[DW-1:0]), // Templated
                // Inputs
                .clk            (clk),
                .nreset         (nreset),
                .devicemode     (devicemode),
                .csr_spidiv     (csr_spidiv[7:0]),
                .csr_spitimeout (csr_spitimeout[31:0]),
                .host_sdi       (host_sdi),
                .device_scsn    (device_scsn),
                .device_sck     (device_sck),
                .device_sdi     (device_sdi),
                .umi_in_valid   (cb2serial_valid),       // Templated
                .umi_in_cmd     (cb2serial_cmd[CW-1:0]), // Templated
                .umi_in_dstaddr (cb2serial_dstaddr[AW-1:0]), // Templated
                .umi_in_srcaddr (cb2serial_srcaddr[AW-1:0]), // Templated
                .umi_in_data    (cb2serial_data[DW-1:0]), // Templated
                .umi_out_ready  (serial2cb_ready));      // Templated

   //########################
   // RX
   //########################

   /*clink_rx  AUTO_TEMPLATE (
    .csr_chipid          (device_chipid[IDW-1:0]),
    .csr_chipletmode     (device_chipletmode[1:0]),
    .csr_rx\(.*\)        (csr_rx\1),
    .csr_\(.*\)          (csr_@"(substring vl-cell-name  6 8)"\1[]),
    .io_rxdata	         (io_rxdata_in[IOW-1:0]),
    .io_rxctrl	         (io_rxctrl_in[3:0]),
    .io_rxstatus         (io_rxstatus_out[3:0]),
    .ioclk               (rxclk),
    .ionreset            (rxnreset),
    .umi_resp_out_\(.*\) (udev_resp_\1[]),
    .umi_req_out_\(.*\)  (uhost_req_\1[]),
    .clkfb               (),
    )
    */

   clink_rx #(.TARGET(TARGET),
	      .FIFODEPTH(RXDEPTH),
	      .IOW(IOW),
              .CW(CW),
              .AW(AW),
	      .DW(DW),
              .CRDTFIFOD(CRDTFIFOD))
   clink_rx(/*AUTOINST*/
            // Outputs
            .csr_respfull       (csr_rxrespfull),        // Templated
            .csr_respempty      (csr_rxrespempty),       // Templated
            .csr_reqfull        (csr_rxreqfull),         // Templated
            .csr_reqempty       (csr_rxreqempty),        // Templated
            .clkfb              (),                      // Templated
            .io_rxstatus        (io_rxstatus_out[3:0]),  // Templated
            .umi_resp_out_valid (udev_resp_valid),       // Templated
            .umi_resp_out_cmd   (udev_resp_cmd[CW-1:0]), // Templated
            .umi_resp_out_dstaddr(udev_resp_dstaddr[AW-1:0]), // Templated
            .umi_resp_out_srcaddr(udev_resp_srcaddr[AW-1:0]), // Templated
            .umi_resp_out_data  (udev_resp_data[DW-1:0]), // Templated
            .umi_req_out_valid  (uhost_req_valid),       // Templated
            .umi_req_out_cmd    (uhost_req_cmd[CW-1:0]), // Templated
            .umi_req_out_dstaddr(uhost_req_dstaddr[AW-1:0]), // Templated
            .umi_req_out_srcaddr(uhost_req_srcaddr[AW-1:0]), // Templated
            .umi_req_out_data   (uhost_req_data[DW-1:0]), // Templated
            .loc_crdt_req       (loc_crdt_req[15:0]),
            .loc_crdt_resp      (loc_crdt_resp[15:0]),
            .rmt_crdt_req       (rmt_crdt_req[15:0]),
            .rmt_crdt_resp      (rmt_crdt_resp[15:0]),
            // Inputs
            .clk                (clk),
            .ioclk              (rxclk),                 // Templated
            .nreset             (nreset),
            .ionreset           (rxnreset),              // Templated
            .vss                (vss),
            .vdd                (vdd),
            .vddio              (vddio),
            .devicemode         (devicemode),
            .chipdir            (chipdir[1:0]),
            .csr_en             (csr_rxen),              // Templated
            .csr_chipletmode    (device_chipletmode[1:0]), // Templated
            .csr_ddrmode        (csr_rxddrmode),         // Templated
            .csr_iowidth        (csr_rxiowidth[7:0]),    // Templated
            .csr_eccmode        (csr_rxeccmode[3:0]),    // Templated
            .csr_protocol       (csr_rxprotocol[3:0]),   // Templated
            .csr_chaos          (csr_rxchaos),           // Templated
            .csr_bpio           (csr_rxbpio),            // Templated
            .csr_bpfifo         (csr_rxbpfifo),          // Templated
            .csr_bpprotocol     (csr_rxbpprotocol),      // Templated
            .io_rxdata          (io_rxdata_in[IOW-1:0]), // Templated
            .io_rxctrl          (io_rxctrl_in[3:0]),     // Templated
            .umi_resp_out_ready (udev_resp_ready),       // Templated
            .umi_req_out_ready  (uhost_req_ready),       // Templated
            .csr_crdt_req_init  (csr_rxcrdt_req_init[15:0]), // Templated
            .csr_crdt_resp_init (csr_rxcrdt_resp_init[15:0])); // Templated

   //########################
   // TX
   //########################

   /*clink_tx  AUTO_TEMPLATE (
    .csr_chipid          (device_chipid[IDW-1:0]),
    .csr_chipletmode     (device_chipletmode[1:0]),
    .csr_tx\(.*\)        (csr_tx\1),
    .csr_\(.*\)          (csr_@"(substring vl-cell-name  6 8)"\1[]),
    .io_txdata	         (io_txdata_out[IOW-1:0]),
    .io_txctrl	         (io_txctrl_out[3:0]),
    .io_txstatus         (io_txstatus_in[3:0]),
    .ioclk               (txclk),
    .ionreset            (txnreset),
    .umi_resp_in_\(.*\)  (uhost_resp_\1[]),
    .umi_req_in_\(.*\)   (udev_req_\1[]),
    )
    */

   clink_tx #(.TARGET(TARGET),
	      .FIFODEPTH(TXDEPTH),
	      .IOW(IOW),
              .CW(CW),
              .AW(AW),
	      .DW(DW))
   clink_tx(/*AUTOINST*/
            // Outputs
            .csr_respfull       (csr_txrespfull),        // Templated
            .csr_respempty      (csr_txrespempty),       // Templated
            .csr_reqfull        (csr_txreqfull),         // Templated
            .csr_reqempty       (csr_txreqempty),        // Templated
            .io_txdata          (io_txdata_out[IOW-1:0]), // Templated
            .io_txctrl          (io_txctrl_out[3:0]),    // Templated
            .umi_resp_in_ready  (uhost_resp_ready),      // Templated
            .umi_req_in_ready   (udev_req_ready),        // Templated
            .csr_crdt_status    (csr_txcrdt_status[31:0]), // Templated
            // Inputs
            .clk                (clk),
            .ioclk              (txclk),                 // Templated
            .nreset             (nreset),
            .ionreset           (txnreset),              // Templated
            .vss                (vss),
            .vdd                (vdd),
            .vddio              (vddio),
            .chipdir            (chipdir[1:0]),
            .devicemode         (devicemode),
            .csr_en             (csr_txen),              // Templated
            .csr_crdt_en        (csr_txcrdt_en),         // Templated
            .csr_ddrmode        (csr_txddrmode),         // Templated
            .csr_chipletmode    (device_chipletmode[1:0]), // Templated
            .csr_iowidth        (csr_txiowidth[7:0]),    // Templated
            .csr_protocol       (csr_txprotocol[3:0]),   // Templated
            .csr_eccmode        (csr_txeccmode[3:0]),    // Templated
            .csr_arbmode        (csr_txarbmode[1:0]),    // Templated
            .csr_chaos          (csr_txchaos),           // Templated
            .csr_bpfifo         (csr_txbpfifo),          // Templated
            .csr_bpprotocol     (csr_txbpprotocol),      // Templated
            .csr_bpio           (csr_txbpio),            // Templated
            .io_txstatus        (io_txstatus_in[3:0]),   // Templated
            .umi_resp_in_valid  (uhost_resp_valid),      // Templated
            .umi_resp_in_cmd    (uhost_resp_cmd[CW-1:0]), // Templated
            .umi_resp_in_dstaddr(uhost_resp_dstaddr[AW-1:0]), // Templated
            .umi_resp_in_srcaddr(uhost_resp_srcaddr[AW-1:0]), // Templated
            .umi_resp_in_data   (uhost_resp_data[DW-1:0]), // Templated
            .umi_req_in_valid   (udev_req_valid),        // Templated
            .umi_req_in_cmd     (udev_req_cmd[CW-1:0]),  // Templated
            .umi_req_in_dstaddr (udev_req_dstaddr[AW-1:0]), // Templated
            .umi_req_in_srcaddr (udev_req_srcaddr[AW-1:0]), // Templated
            .umi_req_in_data    (udev_req_data[DW-1:0]), // Templated
            .csr_crdt_intrvl    (csr_txcrdt_intrvl[15:0]), // Templated
            .loc_crdt_req       (loc_crdt_req[15:0]),
            .loc_crdt_resp      (loc_crdt_resp[15:0]),
            .rmt_crdt_req       (rmt_crdt_req[15:0]),
            .rmt_crdt_resp      (rmt_crdt_resp[15:0]));

endmodule // clink
// Local Variables:
// verilog-library-directories:("." "../../../oh/stdlib/rtl" "../../../umi/umi/rtl")
// End:
