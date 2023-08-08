/******************************************************************************
 * Function: CLINK FIFO
 * Author:   Andreas Olofsson
 * License:  (c) 2020 Zero ASIC Corporation
 *
 *****************************************************************************/
module clink_fifo
  #(parameter TARGET  = "DEFAULT", // implementation target
    parameter DEPTH   = 4,         // FIFO depth
    parameter DW      = 256        // UMI width
    )
   (// control/status signals
    input 	    bypass, // bypass FIFO
    output 	    fifo_full,
    output 	    fifo_empty,
    // Input
    input 	    umi_in_clk,
    input 	    umi_in_nreset,
    input 	    umi_in_valid,//per byte valid signal
    input [DW-1:0]  umi_in_data,
    output 	    umi_in_ready,
    // Output
    input 	    umi_out_clk,
    input 	    umi_out_nreset,
    output 	    umi_out_valid,
    output [DW-1:0] umi_out_data,
    input 	    umi_out_ready,
    // Supplies
    input 	    vdd,
    input 	    vss
    );

   // local state
   reg 		    fifo_out_valid;


   // local wires
   wire 	    fifo_full;
   wire 	    fifo_read;
   wire 	    fifo_write;
   wire 	    fifo_empty;
   wire [DW-1:0]    fifo_dout;

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
     else
       fifo_out_valid <= ~fifo_empty | (fifo_out_valid & ~umi_out_ready);

   // FIFO pushback
   assign fifo_in_ready = ~fifo_full;


   //#################################
   // Standard Dual Clock FIFO
   //#################################

   la_asyncfifo  #(.DW(DW),
		   .DEPTH(DEPTH))
   fifo  (// Outputs
	  .wr_full			(fifo_full),
	  .rd_dout			(fifo_dout[DW-1:0]),
	  .rd_empty			(fifo_empty),
	  // Inputs
	  .wr_clk			(umi_in_clk),
	  .wr_nreset			(umi_in_nreset),
	  .wr_din			(umi_in_data[DW-1:0]),
	  .wr_en			(umi_in_valid),
	  .rd_clk			(umi_out_clk),
	  .rd_nreset			(umi_out_nreset),
	  .rd_en			(fifo_read),
	  .vss				(vss),
	  .vdd				(vdd),
	  .ctrl				(1'b0),
	  .test				(1'b0));

   //#################################
   // FIFO Bypass
   //#################################

   assign umi_out_data[DW-1:0] = bypass ? umi_in_data[DW-1:0] : fifo_dout[DW-1:0];
   assign umi_out_valid        = bypass ? umi_in_valid        : fifo_out_valid;
   assign umi_in_ready         = bypass ? umi_out_ready       : fifo_in_ready;

endmodule // clink_fifo
// Local Variables:
// verilog-library-directories:("." "../../../lambdalib/ramlib/rtl")
// End:
