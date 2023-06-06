/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Unpack(er)
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * Higher priority write/response (packet[0]==1)
 *
 * 1. stores
 * 2. read (load) responses
 * 3. atomic response
 * 4. acks
 * 5. other responses
 *
 * Lower priority read/request (packet[0]==0)
 *
 * 1. loads
 * 2. atomic request
 * 3. stores/writes that need acks
 *
 ******************************************************************************/
module umi_unpack
  #(parameter CW = 32)
   (
    // Input packet
    input [CW-1:0] packet_cmd,

    // output fields
    output [2:0]   cmd_size,
    output [7:0]   cmd_len,
    output [1:0]   cmd_prot,
    output [3:0]   cmd_qos,
    output         cmd_eom,
    output         cmd_eof,
    output [22:0]  cmd_user,
    output [7:0]   cmd_err,
    output         cmd_ex
    );

`include "umi_messages.vh"

   // data field unpacker
   wire cmd_error;
   wire cmd_link;
   wire cmd_link_resp;

   /*umi_decode AUTO_TEMPLATE(
    .cmd_error      (cmd_error[]),
    .cmd_link\(.*\) (cmd_link\1[]),
    .command        (packet_cmd[]),
    .cmd_.*         (),
    );*/

   umi_decode #(.CW(CW))
   umi_decode(/*AUTOINST*/
              // Outputs
              .cmd_invalid      (),                      // Templated
              .cmd_request      (),                      // Templated
              .cmd_response     (),                      // Templated
              .cmd_link         (cmd_link),              // Templated
              .cmd_read         (),                      // Templated
              .cmd_write        (),                      // Templated
              .cmd_write_posted (),                      // Templated
              .cmd_rdma         (),                      // Templated
              .cmd_atomic       (),                      // Templated
              .cmd_user0        (),                      // Templated
              .cmd_future0      (),                      // Templated
              .cmd_error        (cmd_error),             // Templated
              .cmd_read_resp    (),                      // Templated
              .cmd_write_resp   (),                      // Templated
              .cmd_user0_resp   (),                      // Templated
              .cmd_user1_resp   (),                      // Templated
              .cmd_future0_resp (),                      // Templated
              .cmd_future1_resp (),                      // Templated
              .cmd_link_resp    (cmd_link_resp),         // Templated
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
              .command          (packet_cmd[CW-1:0]));   // Templated

   generate
      if(CW==32) begin : decode32
         // Command fiels - TODO: should we qualify these with the command type?
         assign cmd_size[2:0]  = packet_cmd[7:5];  // Ignore for error and link
         assign cmd_len        = packet_cmd[15:8]; // Ignore for Atomic, error and link
         assign cmd_prot[1:0]  = packet_cmd[17:16];// Ignore for link
         assign cmd_qos[3:0]   = packet_cmd[21:18];// Ignore for link
         assign cmd_eom        = packet_cmd[22];
         assign cmd_eof        = packet_cmd[23];   // Ignore for error and responses
         assign cmd_ex         = packet_cmd[24];   // Ignore for error and responses
         assign cmd_user[22:0] = (cmd_link | cmd_link_resp) ? {packet_cmd[31:25],packet_cmd[23:8]} :
                                 cmd_error                  ? {8'h00,packet_cmd[31:25],packet_cmd[15:8]} :
                                                              {16'h0000,packet_cmd[31:25]};
         assign cmd_err[7:0]   = packet_cmd[23:22];// Only for error and responses
      end
   endgenerate

endmodule // umi_unpack
