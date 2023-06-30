
/******************************************************************************
 * Function:  UMI FIFO Device Under Test "DUT"
 * Author:    Andreas Olofsson
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *
 *****************************************************************************/

module dut_umi_fifo_width
  #(parameter TARGET   = "DEFAULT", // synthesis target
    parameter MONITOR  = 1,         // turn on umi monitor
    parameter NUMI     = 1,         // number of umi interfaces
    parameter NCLK     = 1,         // number of clk pins
    parameter NCTRL    = 1,         // number of ctrl pins
    parameter NSTATUS  = 1,         // number of status pins
    // for development
    parameter CW       = 32,       // umi width
    parameter IAW       = 64,       // umi width
    parameter IDW       = 512,       // umi width
    parameter OAW       = 64,       // umi width
    parameter ODW       = 512,       // umi width
    parameter DEPTH    = 4          // fifo depth
    )
   (// generic control interface
    input 		 nreset, // common async active low reset
    input [NCLK-1:0] 	 clk, //  generic set of clocks
    input 		 go, // go dut, go!
    output 		 error, //dut  error
    output 		 done, // dut done
    input [NCTRL-1:0] 	 ctrl, // generic control vector (optional)
    output [NSTATUS-1:0] status, // generic status vector (optional)
    // umi interfaces
    input [NUMI-1:0] 	 umi_in_clk,
    input [NUMI-1:0] 	 umi_in_nreset,
    input [NUMI-1:0] 	 umi_in_valid,
    input [NUMI*CW-1:0]  umi_in_cmd,
    input [NUMI*IAW-1:0]  umi_in_dstaddr,
    input [NUMI*IAW-1:0]  umi_in_srcaddr,
    input [NUMI*IDW-1:0]  umi_in_data,
    output [NUMI-1:0] 	 umi_in_ready,
    input [NUMI-1:0] 	 umi_out_clk,
    input [NUMI-1:0] 	 umi_out_nreset,
    output [NUMI-1:0] 	 umi_out_valid,
    output [NUMI*CW-1:0] umi_out_cmd,
    output [NUMI*OAW-1:0] umi_out_dstaddr,
    output [NUMI*OAW-1:0] umi_out_srcaddr,
    output [NUMI*ODW-1:0] umi_out_data,
    input [NUMI-1:0] 	 umi_out_ready
    );

   // Local wires
   reg 		slowclk;
   wire 	fifo_empty;
   wire 	fifo_full;

   /*AUTOINPUT*/
   /*AUTOWIRE*/

   //#################################
   //# HOST
   //#################################

   /* umi_fifo_width AUTO_TEMPLATE(
    .chaosmode (1'b0),
    );*/
   umi_fifo_width  #(.CW(CW),
	             .IAW(IAW),
	             .IDW(IDW),
	             .OAW(OAW),
	             .ODW(ODW),
	             .DEPTH(DEPTH),
	             .TARGET(TARGET))
   umi_fifo_width (.bypass			(1'b0),
	           .vdd			(1'b1),
	           .vss			(1'b0),
	           /*AUTOINST*/
                   // Outputs
                   .fifo_full           (fifo_full),
                   .fifo_empty          (fifo_empty),
                   .umi_in_ready        (umi_in_ready),
                   .umi_out_valid       (umi_out_valid),
                   .umi_out_cmd         (umi_out_cmd[CW-1:0]),
                   .umi_out_dstaddr     (umi_out_dstaddr[OAW-1:0]),
                   .umi_out_srcaddr     (umi_out_srcaddr[OAW-1:0]),
                   .umi_out_data        (umi_out_data[ODW-1:0]),
                   // Inputs
                   .chaosmode           (1'b0),                  // Templated
                   .umi_in_clk          (umi_in_clk),
                   .umi_in_nreset       (umi_in_nreset),
                   .umi_in_valid        (umi_in_valid),
                   .umi_in_cmd          (umi_in_cmd[CW-1:0]),
                   .umi_in_dstaddr      (umi_in_dstaddr[IAW-1:0]),
                   .umi_in_srcaddr      (umi_in_srcaddr[IAW-1:0]),
                   .umi_in_data         (umi_in_data[IDW-1:0]),
                   .umi_out_clk         (umi_out_clk),
                   .umi_out_nreset      (umi_out_nreset),
                   .umi_out_ready       (umi_out_ready));

endmodule // testbench
// Local Variables:
// verilog-library-directories:("../rtl" "../../../lambdalib/stdlib/rtl")
// End:
