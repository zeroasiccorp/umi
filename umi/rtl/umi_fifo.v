/*******************************************************************************
 * Function:  UMI FIFO
 * Author:    Andreas Olofsson
 * License:   (c) 2022 Zero ASIC Corporation
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_fifo
  #(parameter TARGET  = "DEFAULT", // implementation target
    parameter DEPTH   = 4,         // FIFO depth
    parameter UW      = 256        // UMI width
    )
   (// control/status signals
    input 	    bypass, // bypass FIFO
    input 	    chaosmode, // enable "random" fifo pushback
    output 	    fifo_full,
    output 	    fifo_empty,
    // Input
    input 	    umi_in_clk,
    input 	    umi_in_nreset,
    input 	    umi_in_valid,//per byte valid signal
    input [UW-1:0]  umi_in_packet,
    output 	    umi_in_ready,
    // Output
    input 	    umi_out_clk,
    input 	    umi_out_nreset,
    output 	    umi_out_valid,
    output [UW-1:0] umi_out_packet,
    input 	    umi_out_ready,
    // Supplies
    input 	    vdd,
    input 	    vss
    );

   // local state
   reg 		    fifo_out_valid;
   reg [UW-1:0]     fifo_out_data;

   // local wires
   wire 	    fifo_read;
   wire 	    fifo_write;
   wire [UW-1:0]    fifo_dout;
   wire 	    fifo_in_ready;

   //#################################
   // UMI Control Logic
   //#################################

   // Read FIFO when ready (blocked inside fifo when empty)
   assign fifo_read = umi_out_ready;

   // Write fifo when high (blocked inside fifo when full)
   assign fifo_write = umi_in_valid;

   //1. Set valid if FIFO is non empty
   //2. Keep valid high if READY is low
   always @ (posedge umi_out_clk or negedge umi_out_nreset)
     if (~umi_out_nreset)
       fifo_out_valid <= 1'b0;
     else if(umi_out_ready)
       fifo_out_valid <= ~fifo_empty;

   // Registering fifo output to align with valid/avoid timing issues
   always @ (posedge umi_out_clk)
     if(umi_out_ready)
       fifo_out_data[UW-1:0] <= fifo_dout[UW-1:0];

   // FIFO pushback
   assign fifo_in_ready = ~fifo_full;

   //#################################
   // Standard Dual Clock FIFO
   //#################################

   la_asyncfifo  #(.DW(UW),
		   .DEPTH(DEPTH))
   fifo  (// Outputs
	  .wr_full	(fifo_full),
	  .rd_dout	(fifo_dout[UW-1:0]),
	  .rd_empty	(fifo_empty),
	  // Inputs
	  .wr_clk	(umi_in_clk),
	  .wr_nreset	(umi_in_nreset),
	  .wr_din	(umi_in_packet[UW-1:0]),
	  .wr_en	(umi_in_valid),
	  .wr_chaosmode (chaosmode),
	  .rd_clk	(umi_out_clk),
	  .rd_nreset	(umi_out_nreset),
	  .rd_en	(fifo_read),
	  .vss		(vss),
	  .vdd		(vdd),
	  .ctrl		(1'b0),
	  .test		(1'b0));

   //#################################
   // FIFO Bypass
   //#################################

   assign umi_out_packet[UW-1:0] = bypass ? umi_in_packet[UW-1:0] : fifo_out_data[UW-1:0];
   assign umi_out_valid          = bypass ? umi_in_valid          : fifo_out_valid;
   assign umi_in_ready           = bypass ? umi_out_ready         : fifo_in_ready;

endmodule // clink_fifo
// Local Variables:
// verilog-library-directories:("." "../../../lambdalib/ramlib/rtl")
// End:
