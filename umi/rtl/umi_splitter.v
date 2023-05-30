/*******************************************************************************
 * Function:  UMI Traffic Splitter
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Splits up traffic based on type.
 * - Responses (writes) has priority over requests (reads)
 * - Both outputs must be ready for input to go through.("blocking")
 *
 ******************************************************************************/
module umi_splitter
  #(// standard parameters
    parameter AW   = 64,
    parameter CW   = 32,
    parameter DW   = 256)
   (// UMI Input
    input 	    umi_in_valid,
    input [CW-1:0]  umi_in_cmd,
    input [AW-1:0]  umi_in_dstaddr,
    input [AW-1:0]  umi_in_srcaddr,
    input [DW-1:0]  umi_in_data,
    output 	    umi_in_ready,
    // UMI Output
    output 	    umi_resp_out_valid,
    output [CW-1:0] umi_resp_out_cmd,
    output [AW-1:0] umi_resp_out_dstaddr,
    output [AW-1:0] umi_resp_out_srcaddr,
    output [DW-1:0] umi_resp_out_data,
    input 	    umi_resp_out_ready,
    // UMI Output
    output 	    umi_req_out_valid,
    output [CW-1:0] umi_req_out_cmd,
    output [AW-1:0] umi_req_out_dstaddr,
    output [AW-1:0] umi_req_out_srcaddr,
    output [DW-1:0] umi_req_out_data,
    input 	    umi_req_out_ready
    );

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           command;
   wire [19:0]          options;
   wire [3:0]           size;
   // End of automatics

   //########################
   // UNPACK INPUT
   //########################

   /* umi_unpack AUTO_TEMPLATE(
    .packet_\(.*\) (umi_in_\1[]),
    );*/
   umi_unpack #(.DW(DW),
		.AW(AW))
   umi_unpack(/*AUTOINST*/
              // Outputs
              .command          (command[7:0]),
              .size             (size[3:0]),
              .options          (options[19:0]),
              // Inputs
              .packet_cmd       (umi_in_cmd[CW-1:0]));   // Templated

   // Detect Packet type (request or response)
   assign umi_resp_out_valid = umi_in_valid & command[0];
   assign umi_req_out_valid  = umi_in_valid & ~command[0];

   // Broadcasting packet
   assign umi_resp_out_cmd[CW-1:0]     = umi_in_cmd[CW-1:0];
   assign umi_resp_out_dstaddr[AW-1:0] = umi_in_dstaddr[AW-1:0];
   assign umi_resp_out_srcaddr[AW-1:0] = umi_in_srcaddr[AW-1:0];
   assign umi_resp_out_data[DW-1:0]    = umi_in_data[DW-1:0];

   assign umi_req_out_cmd[CW-1:0]     = umi_in_cmd[CW-1:0];
   assign umi_req_out_dstaddr[AW-1:0] = umi_in_dstaddr[AW-1:0];
   assign umi_req_out_srcaddr[AW-1:0] = umi_in_srcaddr[AW-1:0];
   assign umi_req_out_data[DW-1:0]    = umi_in_data[DW-1:0];

   // Globally blocking ready implementation
   assign umi_in_ready = ~(umi_resp_out_valid & ~umi_resp_out_ready) &
			 ~(umi_req_out_valid & ~umi_req_out_ready);

endmodule // umi_splitter
