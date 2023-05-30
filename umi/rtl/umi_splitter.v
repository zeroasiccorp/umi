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
    parameter UW   = 256)
   (// UMI Input
    input 	    umi_in_valid,
    input [CW-1:0]  umi_in_cmd,
    input [AW-1:0]  umi_in_dst_addr,
    input [AW-1:0]  umi_in_src_addr,
    input [UW-1:0]  umi_in_payload,
    output 	    umi_in_ready,
    // UMI Output
    output 	    umi_resp_out_valid,
    output [CW-1:0] umi_resp_out_cmd,
    output [AW-1:0] umi_resp_out_dst_addr,
    output [AW-1:0] umi_resp_out_src_addr,
    output [UW-1:0] umi_resp_out_payload,
    input 	    umi_resp_out_ready,
    // UMI Output
    output 	    umi_req_out_valid,
    output [CW-1:0] umi_req_out_cmd,
    output [AW-1:0] umi_req_out_dst_addr,
    output [AW-1:0] umi_req_out_src_addr,
    output [UW-1:0] umi_req_out_payload,
    input 	    umi_req_out_ready
    );

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           command;
   wire [UW-1:0]        data;
   wire [AW-1:0]        dstaddr;
   wire [19:0]          options;
   wire [3:0]           size;
   wire [AW-1:0]        srcaddr;
   // End of automatics

   //########################
   // UNPACK INPUT
   //########################

   /* umi_unpack AUTO_TEMPLATE(
    .packet_\(.*\) (umi_in_\1[]),
    );*/
   umi_unpack #(.UW(UW),
		.AW(AW))
   umi_unpack(/*AUTOINST*/
              // Outputs
              .command          (command[7:0]),
              .size             (size[3:0]),
              .options          (options[19:0]),
              .dstaddr          (dstaddr[AW-1:0]),
              .srcaddr          (srcaddr[AW-1:0]),
              .data             (data[UW-1:0]),
              // Inputs
              .packet_cmd       (umi_in_cmd[CW-1:0]),    // Templated
              .packet_src_addr  (umi_in_src_addr[AW-1:0]), // Templated
              .packet_dst_addr  (umi_in_dst_addr[AW-1:0]), // Templated
              .packet_payload   (umi_in_payload[UW-1:0])); // Templated

   // Detect Packet type (request or response)
   assign umi_resp_out_valid = umi_in_valid & command[0];
   assign umi_req_out_valid  = umi_in_valid & ~command[0];

   // Broadcasting packet
   assign umi_resp_out_cmd[CW-1:0]      = umi_in_cmd[CW-1:0];
   assign umi_resp_out_dst_addr[AW-1:0] = umi_in_dst_addr[AW-1:0];
   assign umi_resp_out_src_addr[AW-1:0] = umi_in_src_addr[AW-1:0];
   assign umi_resp_out_payload[UW-1:0]  = umi_in_payload[UW-1:0];

   assign umi_req_out_cmd[CW-1:0]      = umi_in_cmd[CW-1:0];
   assign umi_req_out_dst_addr[AW-1:0] = umi_in_dst_addr[AW-1:0];
   assign umi_req_out_src_addr[AW-1:0] = umi_in_src_addr[AW-1:0];
   assign umi_req_out_payload[UW-1:0]  = umi_in_payload[UW-1:0];

   // Globally blocking ready implementation
   assign umi_in_ready = ~(umi_resp_out_valid & ~umi_resp_out_ready) &
			 ~(umi_req_out_valid & ~umi_req_out_ready);

endmodule // umi_splitter
