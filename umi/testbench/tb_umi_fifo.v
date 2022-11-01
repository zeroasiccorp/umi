/******************************************************************************
 * Function:  UMI FIFO Testbench
 * Author:    Andreas Olofsson
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *
 *
 *****************************************************************************/

module tb_umi_fifo
  #(parameter TARGET     = "DEFAULT",   // pass through variable for hard macro
    parameter TIMEOUT    = 5000,        // timeout value (cycles)
    parameter PERIOD_CLK = 10,          // clock period
    parameter FIFODEPTH  = 4,           // fifo depth
    parameter UW         = 256          // UMI width
    )
   ();

   //####################
   // LOCAL PARAMS
   //####################

   localparam STIMDEPTH = 1024;
   localparam CW        = 8;
   localparam AW        = 64;
   localparam DW        = 64;

   //#####################
   //# SIMCTRL
   //#####################
   reg umi_dut2check_ready;

   reg [128*8-1:0] memhfile;
   reg 		   slowclk;
   reg 		   clk;
   reg 		   load;
   reg 		   nreset;
   reg 		   go;
   integer 	   r;

   // reset initialization
   initial
     begin
	#(1)
	nreset   = 1'b0;
	clk      = 1'b0;
	load     = 1'b0;
	go       = 1'b0;
	#(PERIOD_CLK * 10)
	nreset   = 1'b1;
	#(PERIOD_CLK * 10)
	go       = 1'b1;
     end // initial begin

   // clocks
   always
     #(PERIOD_CLK/2) clk = ~clk;

   // control block
   initial
     begin
	r = $value$plusargs("MEMHFILE=%s", memhfile);
	$readmemh(memhfile, umi_stimulus.ram);
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("waveform.vcd");
        $dumpvars();
	#(TIMEOUT)
        $finish;
     end

   always @ (posedge slowclk or negedge nreset)
     if(~nreset)
       umi_dut2check_ready <= 1'b0;
     else
       umi_dut2check_ready <= ~umi_dut2check_ready;

   // clock divider
   always @ (posedge clk or negedge nreset)
     if (~nreset)
       slowclk <= 1'b0;
     else
       slowclk <= ~slowclk;

   la_rsync la_rsync (// Outputs
		      .nrst_out		(slownreset),
		      // Inputs
		      .clk		(slowclk),
		      .nrst_in		(nreset));


   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire			done;			// From dut_umi_fifo of dut_umi_fifo.v
   wire			error;			// From dut_umi_fifo of dut_umi_fifo.v
   wire			stim_done;		// From umi_stimulus of umi_stimulus.v
   wire [UW-1:0]	umi_dut2check_packet;	// From dut_umi_fifo of dut_umi_fifo.v
   wire			umi_dut2check_valid;	// From dut_umi_fifo of dut_umi_fifo.v
   wire [UW-1:0]	umi_stim2dut_packet;	// From umi_stimulus of umi_stimulus.v
   wire			umi_stim2dut_ready;	// From dut_umi_fifo of dut_umi_fifo.v
   wire			umi_stim2dut_valid;	// From umi_stimulus of umi_stimulus.v
   // End of automatics

   //################################################
   //# DUT
   //#################################################

   /*dut_umi_fifo AUTO_TEMPLATE (
    .clk                (clk),
    .ctrl               (1'b0),
    .status             (),
    .umi_out_clk	(slowclk),
    .umi_out_nreset     (slownreset),
    .umi_out_valid	(umi_dut2check_valid),
    .umi_out_packet	(umi_dut2check_packet[UW-1:0]),
    .umi_out_ready	(1'b1),
    .umi_in_clk	        (clk),
    .umi_in_nreset      (nreset),
    .umi_in_valid	(umi_stim2dut_valid),
    .umi_in_packet	(umi_stim2dut_packet[UW-1:0]),
    .umi_in_ready	(umi_stim2dut_ready),
    );
    */

   dut_umi_fifo #(.UW(UW),
		  .DEPTH(FIFODEPTH))
   dut_umi_fifo (.umi_out_ready		(umi_dut2check_ready),
		 /*AUTOINST*/
		 // Outputs
		 .error			(error),
		 .done			(done),
		 .status		(),			 // Templated
		 .umi_in_ready		(umi_stim2dut_ready),	 // Templated
		 .umi_out_valid		(umi_dut2check_valid),	 // Templated
		 .umi_out_packet	(umi_dut2check_packet[UW-1:0]), // Templated
		 // Inputs
		 .nreset		(nreset),
		 .clk			(clk),			 // Templated
		 .go			(go),
		 .ctrl			(1'b0),			 // Templated
		 .umi_in_clk		(clk),			 // Templated
		 .umi_in_nreset		(nreset),		 // Templated
		 .umi_in_valid		(umi_stim2dut_valid),	 // Templated
		 .umi_in_packet		(umi_stim2dut_packet[UW-1:0]), // Templated
		 .umi_out_clk		(slowclk),		 // Templated
		 .umi_out_nreset	(slownreset));		 // Templated

   //##################################################
   //# UMI STIMULUS DRIVER (CLK)
   //##################################################

   /*umi_stimulus AUTO_TEMPLATE (
    // Outputs
    .stim_valid		(umi_stim2dut_valid),
    .stim_packet	(umi_stim2dut_packet[UW-1:0]),
    .dut_ready          (umi_stim2dut_ready),
    .ext_valid		(1'b0),
    .ext_packet		({(UW+CW){1'b0}}),
    .\(.*\)_clk         (clk),
    );
    */

   umi_stimulus #(.DEPTH(STIMDEPTH),
		  .TARGET(TARGET),
		  .UW(UW),
		  .CW(CW))
   umi_stimulus (/*AUTOINST*/
		 // Outputs
		 .stim_valid		(umi_stim2dut_valid),	 // Templated
		 .stim_packet		(umi_stim2dut_packet[UW-1:0]), // Templated
		 .stim_done		(stim_done),
		 // Inputs
		 .nreset		(nreset),
		 .load			(load),
		 .go			(go),
		 .ext_clk		(clk),			 // Templated
		 .ext_valid		(1'b0),			 // Templated
		 .ext_packet		({(UW+CW){1'b0}}),	 // Templated
		 .dut_clk		(clk),			 // Templated
		 .dut_ready		(umi_stim2dut_ready));	 // Templated

   //###################################################
   //# TRAFFIC MONITOR (SLOWCLK)
   //###################################################

   always @ (negedge slowclk)
     if(umi_dut2check_valid & umi_dut2check_ready)
       $display("dut result: = %h", umi_dut2check_packet[UW-1:0]);


endmodule // testbench
// Local Variables:
// verilog-library-directories:("." "../rtl" "../../../umi/umi/rtl" "../../../oh/stdlib/rtl/" "../../../oh/stdlib/testbench/")
// End:
