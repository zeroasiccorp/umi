/*******************************************************************************
 * Function:  UMI Synthesizable Stimulus Driver
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/

module umi_stimulus
  #( parameter UW       = 256,       // stimulus packet width
     parameter CW       = 8,         // width of control words
     parameter DEPTH    = 8192,      // Memory depth
     parameter TARGET   = "DEFAULT" // pass through variable for hard macro
     )
   (
    // control
    input 	      nreset, // async reset
    input 	      load, // load  memory
    input 	      go, // drive stimulus from memory
    // external interface
    input 	      ext_clk,// External clock for write path
    input 	      ext_valid, // Valid packet for memory
    input [UW+CW-1:0] ext_packet, // packet for memory
    // dut feedback
    input 	      dut_clk, // DUT side clock
    input 	      dut_ready, // DUT ready signal
    // stimulus outputs
    output 	      stim_valid, // Packet valid
    output [UW-1:0]   stim_packet, // packet to DUT
    output 	      stim_done // Signals that stimulus is done
    );

   // memory parameters
   localparam MAW = $clog2(DEPTH); // Memory address width

   // state machine parameters
   localparam STIM_IDLE   = 2'b00;
   localparam STIM_ACTIVE = 2'b01;
   localparam STIM_PAUSE  = 2'b10;
   localparam STIM_DONE   = 2'b11;

   // Local values
   reg [UW+CW-1:0]  rd_reg;
   reg [1:0] 	    rd_state;
   reg [MAW-1:0]    wr_addr;
   reg [MAW-1:0]    rd_addr;
   reg [1:0] 	    sync_pipe;
   reg 		    mem_read;
   reg [CW-2:0]     rd_delay;
   wire 	    dut_start;
   wire 	    data_valid;

   reg [UW+CW-1:0]  ram[0:DEPTH-1];
   reg [UW+CW-1:0]  mem_data;

   wire 	    mem_valid;
   wire 	    mem_done;

   //#################################
   // Stimulus selector
   //#################################

   assign stim_valid          = mem_valid;
   assign stim_packet[UW-1:0] = mem_data[UW+CW-1:CW];
   assign stim_done           = mem_done;

   //#################################
   // Memory write port state machine
   //#################################

   always @ (posedge ext_clk or negedge nreset)
     if(!nreset)
       wr_addr[MAW-1:0] <= 'b0;
     else if(ext_valid & load)
       wr_addr[MAW-1:0] <= wr_addr[MAW-1:0] + 1;

   //Synchronize mode to dut_clk domain
   always @ (posedge dut_clk or negedge nreset)
     if(!nreset)
       sync_pipe[1:0] <= 'b0;
     else
       sync_pipe[1:0] <= {sync_pipe[0],go};

   assign dut_start = sync_pipe[1];

   //#################################
   // Memory read port state machine
   //#################################
   //1. Start on dut_start
   //2. Drive stimulus while dut is ready
   //3. Set end state on special end packet (bit 0)

   always @ (posedge dut_clk or negedge nreset)
     if(!nreset)
       begin
	  rd_state[1:0]    <= STIM_IDLE;
	  rd_addr[MAW-1:0] <= 'b0;
	  rd_delay         <= 'b0;
       end
     else
       case (rd_state[1:0])
	 STIM_IDLE :
	   rd_state[1:0] <= dut_start ? STIM_ACTIVE : STIM_IDLE;
	 STIM_ACTIVE :
	   begin
	      rd_state[1:0] <= (|rd_delay) ? STIM_PAUSE :
			       ~data_valid ? STIM_DONE  :
                                             STIM_ACTIVE;
	      rd_addr[MAW-1:0] <= (|rd_delay) ? rd_addr[MAW-1:0] :
						rd_addr[MAW-1:0] + dut_ready;
	      rd_delay         <= (CW > 1) ? mem_data[CW-1:1] : 'b0;
	   end
	 STIM_PAUSE :
	   begin
	      rd_state[1:0] <= (|rd_delay) ? STIM_PAUSE : STIM_ACTIVE;
	      rd_delay      <= (|rd_delay) ? rd_delay - 1'b1 : rd_delay;
	   end
       endcase // case (rd_state[1:0])

   // pipeline to match sram pipeline
   always @ (posedge dut_clk)
     mem_read <= (rd_state==STIM_ACTIVE) |
		 (rd_state==STIM_PAUSE);

   //  output drivesrs
   assign data_valid   = (CW==0) | mem_data[0];
   assign mem_done     = (rd_state[1:0] == STIM_DONE);
   assign mem_valid    = data_valid &
			 mem_read &
			 (rd_state==STIM_ACTIVE);

   //#################################
   // Dual Port RAM
   //#################################

   //write port
   always @(posedge ext_clk)
     if (ext_valid)
       ram[wr_addr[MAW-1:0]] <= ext_packet[UW+CW-1:0];

   //read port
   always @ (posedge dut_clk)
     if (dut_ready)
       mem_data[UW+CW-1:0] <= ram[rd_addr[MAW-1:0]];


endmodule // oh_stimulus
