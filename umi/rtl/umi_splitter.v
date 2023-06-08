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
   wire                 cmd_request;
   wire                 cmd_response;
   // End of automatics

   //########################
   // UNPACK INPUT
   //########################

   wire [4:0]           cmd_opcode;
   /* umi_decode AUTO_TEMPLATE(
    .cmd_request  (cmd_request[]),
    .cmd_response (cmd_response[]),
    .command      (umi_in_cmd[]),
    ..*           (),
    );*/
   umi_decode #(.CW(CW))
   umi_decode(/*AUTOINST*/
              // Outputs
              .cmd_invalid      (),                      // Templated
              .cmd_request      (cmd_request),           // Templated
              .cmd_response     (cmd_response),          // Templated
              .cmd_read         (),                      // Templated
              .cmd_write        (),                      // Templated
              .cmd_write_posted (),                      // Templated
              .cmd_rdma         (),                      // Templated
              .cmd_atomic       (),                      // Templated
              .cmd_user0        (),                      // Templated
              .cmd_future0      (),                      // Templated
              .cmd_error        (),                      // Templated
              .cmd_link         (),                      // Templated
              .cmd_read_resp    (),                      // Templated
              .cmd_write_resp   (),                      // Templated
              .cmd_user0_resp   (),                      // Templated
              .cmd_user1_resp   (),                      // Templated
              .cmd_future0_resp (),                      // Templated
              .cmd_future1_resp (),                      // Templated
              .cmd_link_resp    (),                      // Templated
              .cmd_atomic_add   (),                      // Templated
              .cmd_atomic_and   (),                      // Templated
              .cmd_atomic_or    (),                      // Templated
              .cmd_atomic_xor   (),                      // Templated
              .cmd_atomic_max   (),                      // Templated
              .cmd_atomic_min   (),                      // Templated
              .cmd_atomic_maxu  (),                      // Templated
              .cmd_atomic_minu  (),                      // Templated
              .cmd_atomic_swap  (),                      // Templated
              // Inputs
              .command          (umi_in_cmd[CW-1:0]));   // Templated

   // Detect Packet type (request or response)
   assign umi_resp_out_valid = umi_in_valid & cmd_response;
   assign umi_req_out_valid  = umi_in_valid & cmd_request;

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
