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
   reg [1:0] 	    rd_state;
   reg [UW+CW-1:0]  ram[0:DEPTH-1];
   reg [UW+CW-1:0]  mem_data;
   reg [MAW-1:0]    wr_addr;
   reg [MAW-1:0]    rd_addr;
   reg [1:0] 	    sync_pipe;
   reg [CW-2:0]     rd_delay;
   reg 		    data_valid;

   wire 	    dut_start;
   wire [MAW-1:0]   rd_addr_nxt;
   wire [CW-2:0]    rd_delay_nxt;

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
   //2. Drive valid while active
   //3. Set end state on special end packet (bit 0)

   // control signals
   assign stim_done  = (rd_state[1:0]==STIM_DONE);
   assign stim_valid = (rd_state[1:0]==STIM_ACTIVE);
   assign beat       = stim_valid & dut_ready;
   assign pause      = data_valid & dut_ready & (|rd_delay_nxt);

   always @ (posedge dut_clk or negedge nreset)
     if(!nreset)
       rd_state[1:0]  <= STIM_IDLE;
     else
       case (rd_state[1:0])
	 STIM_IDLE :
	   rd_state[1:0] <= (dut_start & data_valid)  ? STIM_ACTIVE :
			    (dut_start & ~data_valid) ? STIM_DONE :
                                                        STIM_IDLE;
	 STIM_ACTIVE :
	   rd_state[1:0] <= pause      ? STIM_PAUSE :
			    data_valid ? STIM_ACTIVE :
			                 STIM_DONE;
	 STIM_PAUSE :
	   rd_state[1:0] <= (|rd_delay) ? STIM_PAUSE :
			    data_valid  ? STIM_ACTIVE :
			                  STIM_DONE;
	 STIM_DONE  :
	   rd_state[1:0] <= STIM_DONE;

       endcase // case (rd_state[1:0])

   always @ (posedge dut_clk)
     data_valid <= ((CW==0) | mem_data[0]);

   // Read address updates on every beat

   assign rd_addr_nxt = rd_addr[MAW-1:0] + beat;

   always @ (posedge dut_clk or negedge nreset)
     if(!nreset)
       rd_addr[MAW-1:0] <= 'b0;
     else
       rd_addr[MAW-1:0] <= rd_addr_nxt;

   assign rd_delay_nxt = (CW > 1) ? mem_data[CW-1:1] : 'b0;

   // Update delay when in pause or when active
   always @ (posedge dut_clk or negedge nreset)
     if(!nreset)
       rd_delay   <= 'b0;
     else if(rd_state[1:0]==STIM_PAUSE)
       rd_delay   <= rd_delay - 1'b1;
     else
       rd_delay <= rd_delay_nxt;

   //#################################
   // Dual Port RAM
   //#################################

   //write port
   always @(posedge ext_clk)
     if (ext_valid)
       ram[wr_addr[MAW-1:0]] <= ext_packet[UW+CW-1:0];

   //read port
   always @ (posedge dut_clk)
     mem_data[UW+CW-1:0] <= ram[rd_addr_nxt[MAW-1:0]];

   // Remove extra CW information from stimulus
   assign stim_packet[UW-1:0] = mem_data[UW+CW-1:CW];

endmodule // umi_stimulus
