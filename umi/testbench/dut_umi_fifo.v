
/******************************************************************************
 * Function:  UMI FIFO Device Under Test "DUT"
 * Author:    Andreas Olofsson
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *
 *****************************************************************************/

module dut_umi_fifo
  #(parameter TARGET   = "DEFAULT", // synthesis target
    parameter MONITOR  = 1,         // turn on umi monitor
    parameter NUMI     = 1,         // number of umi interfaces
    parameter NCLK     = 1,         // number of clk pins
    parameter NCTRL    = 1,         // number of ctrl pins
    parameter NSTATUS  = 1,         // number of status pins
    // for development
    parameter UW       = 256,       // umi width
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
    input [NUMI*UW-1:0]  umi_in_packet,
    output [NUMI-1:0] 	 umi_in_ready,
    input [NUMI-1:0] 	 umi_out_clk,
    input [NUMI-1:0] 	 umi_out_nreset,
    output [NUMI-1:0] 	 umi_out_valid,
    output [NUMI*UW-1:0] umi_out_packet,
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

   umi_fifo  #(.UW(UW),
	       .DEPTH(DEPTH),
	       .TARGET(TARGET))
   umi_fifo (.bypass			(1'b0),
	     .vdd			(1'b1),
	     .vss			(1'b0),
	     /*AUTOINST*/
	     // Outputs
	     .fifo_full			(fifo_full),
	     .fifo_empty		(fifo_empty),
	     .umi_in_ready		(umi_in_ready),
	     .umi_out_valid		(umi_out_valid),
	     .umi_out_packet		(umi_out_packet[UW-1:0]),
	     // Inputs
	     .umi_in_clk		(umi_in_clk),
	     .umi_in_nreset		(umi_in_nreset),
	     .umi_in_valid		(umi_in_valid),
	     .umi_in_packet		(umi_in_packet[UW-1:0]),
	     .umi_out_clk		(umi_out_clk),
	     .umi_out_nreset		(umi_out_nreset),
	     .umi_out_ready		(umi_out_ready));

endmodule // testbench
// Local Variables:
// verilog-library-directories:("../rtl" "../../../lambdalib/stdlib/rtl")
// End:
