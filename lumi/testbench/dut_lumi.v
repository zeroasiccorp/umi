/******************************************************************************
 * Function:  EBRICK_2D DUT
 * Author:    Andreas Olofsson
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *
 *****************************************************************************/

module dut_lumi
  #(parameter TARGET   = "DEFAULT", // synthesis target
    parameter NCLK     = 1,         // number of clk pins
    parameter NCTRL    = 1,         // number of ctrl pins
    parameter NSTATUS  = 1,         // number of status pins
    // for development
    parameter DW       = 128,       // umi width
    parameter AW       = 64,        // address width
    parameter CW       = 32,        // address width
    parameter IOW      = 16,        // data signals per clink
    parameter NMIO     = 80         // muxed io signals per clink
    )
   (// generic control interface
    input                nreset, // async active low reset
    input [NCLK-1:0]     clk,    //  clock vector, clk[0] used for interface
    input                go,     // go dut, go!
    output               error,  //dut  error
    output               done,   // dut done
    input [NCTRL-1:0]    ctrl,   // generic control vector (optional)
    output [NSTATUS-1:0] status, // generic status vector (optional)
    // out of band interface
    input                sb_in_valid,
    input [CW-1:0]       sb_in_cmd,
    input [AW-1:0]       sb_in_dstaddr,
    input [AW-1:0]       sb_in_srcaddr,
    input [DW-1:0]       sb_in_data,
    output               sb_in_ready,
    output               sb_out_valid,
    output [CW-1:0]      sb_out_cmd,
    output [AW-1:0]      sb_out_dstaddr,
    output [AW-1:0]      sb_out_srcaddr,
    output [DW-1:0]      sb_out_data,
    input                sb_out_ready,
    // umi interfaces
    input                umi_in_valid,
    input [CW-1:0]       umi_in_cmd,
    input [AW-1:0]       umi_in_dstaddr,
    input [AW-1:0]       umi_in_srcaddr,
    input [DW-1:0]       umi_in_data,
    output               umi_in_ready,
    output               umi_out_valid,
    output [CW-1:0]      umi_out_cmd,
    output [AW-1:0]      umi_out_dstaddr,
    output [AW-1:0]      umi_out_srcaddr,
    output [DW-1:0]      umi_out_data,
    input                umi_out_ready
    );

   /*AUTOINPUT*/

   //#################################
   //# LOCAL TB PARAMS
   //#################################

   localparam W        = 1;
   localparam H        = 1;
   localparam RAMDEPTH = 512;
   localparam CLINK_GRPID = 8'h70;

   //#################################
   //# WIRES
   //#################################

   wire [3:0]		 pad_clk;
   wire [3:0] 		 pad_ctrl;
   wire [15:0] 		 pad_gpio;
   wire                  pad_nreset;
   wire [3:0] 		 pad_rxctrl;
   wire [15:0] 		 pad_rxdata;
   wire [3:0] 		 pad_rxstatus;
   wire [3:0] 		 pad_status;
   wire [3:0] 		 pad_txctrl;
   wire [15:0] 		 pad_txdata;
   wire [3:0] 		 pad_txstatus;
   wire [7:0] 		 pad_analog;
   wire [15:0] 		 pad_pti;
   wire [15:0] 		 pad_pto;

   wire [3:0]            host_clk;
   wire [7:0] 		 vddio;
   wire [3:0] 		 vdda;
   wire  		 vddx;
   wire  		 vdd;
   wire  		 vss;

   wire [CW-1:0]        uhost_req_cmd;
   wire [DW-1:0]        uhost_req_data;
   wire [AW-1:0]        uhost_req_dstaddr;
   wire [W*H-1:0]       uhost_req_ready;
   wire [AW-1:0]        uhost_req_srcaddr;
   wire [W*H-1:0]       uhost_req_valid;
   wire [W*H*CW-1:0]    uhost_resp_cmd;
   wire [W*H*DW-1:0]    uhost_resp_data;
   wire [W*H*AW-1:0]    uhost_resp_dstaddr;
   wire [W*H-1:0]       uhost_resp_ready;
   wire [W*H*AW-1:0]    uhost_resp_srcaddr;
   wire [W*H-1:0]       uhost_resp_valid;

   /*AUTOWIRE*/

   //#################################
   //# HOST CLINK DRIVER
   //#################################

   /*clink  AUTO_TEMPLATE (
    .host_error		    (),
    .host_scanout	    (),
    .host_linkready	    (),
    .host_\(.*\)            ({@"vl-width"{1'b0}}),
    .device_ready           (1'b1),
    .device_\(.*\)          (),
    .io_txgpio\(.*\)	    (),
    .io_rxgpio_in	    ({NMIO{1'b0}}),
    .io_\(.*\)_out	    (pad_\1[]),
//    .uhost_resp_.*          ({@"vl-width"{1'b0}}),
//    .uhost_req_.*	    (),
//    .uhost_req_ready	    (1'b1),
//    .uhost_resp_ready       (),
    .udev_req_ready	    (umi_in_ready),
    .udev_resp_valid	    (umi_out_valid),
    .udev_resp_cmd	    (umi_out_cmd[CW-1:0]),
    .udev_resp_\(...\)addr  (umi_out_\1addr[AW-1:0]),
    .udev_resp_data	    (umi_out_data[DW-1:0]),
    .udev_req_valid	    (umi_in_valid),
    .udev_req_cmd	    (umi_in_cmd[CW-1:0]),
    .udev_req_\(...\)addr   (umi_in_\1addr[AW-1:0]),
    .udev_req_data	    (umi_in_data[DW-1:0]),
    .udev_resp_ready	    (umi_out_ready),
    );
    */

   clink #(.TARGET(TARGET),
	   .GRPID(CLINK_GRPID),
           .CW(CW),
           .AW(AW),
           .DW(DW),
	   .IOW(IOW))
   host(.host_nreset	        (nreset),
	.host_clk	        ({4{clk[0]}}),
	.vss			(1'b0),
	.vdd			(1'b1),
	.vddio			(1'b1),
	.devicemode	        (1'b0),
	.device_error	        (7'b0),
	.device_scanout	        (1'b0),
	.device_status		(64'h0),
	.io_nreset_in		(1'b0),
	.io_clk_in              (4'b0),
	.io_ctrl_in		(4'b0),
	.io_status_out		(),
	.io_status_in		(pad_status[3:0]),
	.io_clk_out		(pad_clk[3:0]),
	//TX/RX SWIZZLE
	.io_rxstatus_out	(pad_txstatus[3:0]),
	.io_rxctrl_in		(pad_txctrl[3:0]),
	.io_rxdata_in		(pad_txdata[15:0]),
	.io_txctrl_out		(pad_rxctrl[3:0]),
	.io_txdata_out		(pad_rxdata[15:0]),
	.io_txstatus_in 	(pad_rxstatus[3:0]),
	/*AUTOINST*/
        // Outputs
        .uhost_req_valid      (uhost_req_valid),
        .uhost_req_cmd        (uhost_req_cmd[CW-1:0]),
        .uhost_req_dstaddr    (uhost_req_dstaddr[AW-1:0]),
        .uhost_req_srcaddr    (uhost_req_srcaddr[AW-1:0]),
        .uhost_req_data       (uhost_req_data[DW-1:0]),
        .uhost_resp_ready     (uhost_resp_ready),
        .udev_req_ready       (umi_in_ready),          // Templated
        .udev_resp_valid      (umi_out_valid),         // Templated
        .udev_resp_cmd        (umi_out_cmd[CW-1:0]),   // Templated
        .udev_resp_dstaddr    (umi_out_dstaddr[AW-1:0]), // Templated
        .udev_resp_srcaddr    (umi_out_srcaddr[AW-1:0]), // Templated
        .udev_resp_data       (umi_out_data[DW-1:0]),  // Templated
        .sb_in_ready          (sb_in_ready),
        .sb_out_valid         (sb_out_valid),
        .sb_out_cmd           (sb_out_cmd[CW-1:0]),
        .sb_out_dstaddr       (sb_out_dstaddr[AW-1:0]),
        .sb_out_srcaddr       (sb_out_srcaddr[AW-1:0]),
        .sb_out_data          (sb_out_data[DW-1:0]),
        .io_nreset_out        (pad_nreset),            // Templated
        .io_ctrl_out          (pad_ctrl[3:0]),         // Templated
        .host_error           (),                      // Templated
        .host_linkready       (),                      // Templated
        .device_nreset        (),                      // Templated
        .device_clk           (),                      // Templated
        .device_go            (),                      // Templated
        .device_testmode      (),                      // Templated
        .device_ctrl          (),                      // Templated
        .device_chipid        (),                      // Templated
        .device_chipdir       (),                      // Templated
        .device_chipletmode   (),                      // Templated
        .host_scanout         (),                      // Templated
        .device_scanmode      (),                      // Templated
        .device_scanenable    (),                      // Templated
        .device_scanclk       (),                      // Templated
        .device_scanin        (),                      // Templated
        // Inputs
        .uhost_req_ready      (uhost_req_ready),
        .uhost_resp_valid     (uhost_resp_valid),
        .uhost_resp_cmd       (uhost_resp_cmd[CW-1:0]),
        .uhost_resp_dstaddr   (uhost_resp_dstaddr[AW-1:0]),
        .uhost_resp_srcaddr   (uhost_resp_srcaddr[AW-1:0]),
        .uhost_resp_data      (uhost_resp_data[DW-1:0]),
        .udev_req_valid       (umi_in_valid),          // Templated
        .udev_req_cmd         (umi_in_cmd[CW-1:0]),    // Templated
        .udev_req_dstaddr     (umi_in_dstaddr[AW-1:0]), // Templated
        .udev_req_srcaddr     (umi_in_srcaddr[AW-1:0]), // Templated
        .udev_req_data        (umi_in_data[DW-1:0]),   // Templated
        .udev_resp_ready      (umi_out_ready),         // Templated
        .sb_in_valid          (sb_in_valid),
        .sb_in_cmd            (sb_in_cmd[CW-1:0]),
        .sb_in_dstaddr        (sb_in_dstaddr[AW-1:0]),
        .sb_in_srcaddr        (sb_in_srcaddr[AW-1:0]),
        .sb_in_data           (sb_in_data[DW-1:0]),
        .sb_out_ready         (sb_out_ready),
        .host_calibrate       ({1{1'b0}}),             // Templated
        .device_ready         (1'b1),                  // Templated
        .host_scanmode        ({1{1'b0}}),             // Templated
        .host_scanenable      ({1{1'b0}}),             // Templated
        .host_scanclk         ({1{1'b0}}),             // Templated
        .host_scanin          ({1{1'b0}}));            // Templated

   //#################################
   //# DEVICE
   //#################################

   assign vdd        = 1'b1;
   assign vddx       = 1'b1;
   assign vddio      = 8'hFF;
   assign vdda       = 4'hF;
   assign vss        = 1'b0;
   assign done       = 1'b0;
   assign error      = 1'b0;
   assign pad_analog = 'b0;
   assign pad_pti    = 'b0;
   assign pad_gpio   = 'b0;

   ebrick_2d
     ebrick_2d(// Inouts
               .pad_nreset   ({3'b000,pad_nreset}),
	       .pad_clk	     (pad_clk[3:0]),
	       .pad_ctrl     (pad_ctrl[3:0]),
	       .pad_status   (pad_status[3:0]),
	       .pad_rxdata   (pad_rxdata[15:0]),
	       .pad_rxctrl   (pad_rxctrl[3:0]),
	       .pad_rxstatus (pad_rxstatus[3:0]),
	       .pad_txdata   (pad_txdata[15:0]),
	       .pad_txctrl   (pad_txctrl[3:0]),
	       .pad_txstatus (pad_txstatus[3:0]),
	       .pad_gpio     (pad_gpio[15:0]),
	       .pad_analog   (pad_analog[7:0]),
	       .pad_pti	     (pad_pti[7:0]),
	       .pad_pto	     (pad_pto[7:0]),
	       .vss	     (vss),
	       .vdd	     (vdd),
	       .vddx	     (vddx),
	       .vddio	     (vddio),
	       .vdda	     (vdda));

         /*ebrick_mem_agent AUTO_TEMPLATE(
          .udev_\(.*\) (uhost_\1[]),
          .clk         (clk[0]),
          );*/
         ebrick_mem_agent #(.W(W),
                            .H(H),
                            .DW(DW),
                            .AW(AW),
                            .CW(CW),
                            .RAMDEPTH(RAMDEPTH))
         mem_agent_i(/*AUTOINST*/);

endmodule // dut_ebrick_2d

// Local Variables:
// verilog-library-directories:("../rtl" "../../../clink/clink/rtl" "../../../umi/umi/rtl" "../../../oh/stdlib/testbench/")
// End:
