/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Command Decoder
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_decode #(parameter CW = 32)
   (
    // Packet Command
    input [CW-1:0] command,
    output         cmd_invalid,

    // request/response/link
    output         cmd_request,
    output         cmd_response,

    // requests
    output         cmd_read,
    output         cmd_write,

    output         cmd_write_posted,
    output         cmd_rdma,
    output         cmd_atomic,
    output         cmd_user0,
    output         cmd_future0,
    output         cmd_error,
    output         cmd_link,
    // Response (device -> host)
    output         cmd_read_resp,
    output         cmd_write_resp,
    output         cmd_user0_resp,
    output         cmd_user1_resp,
    output         cmd_future0_resp,
    output         cmd_future1_resp,
    output         cmd_link_resp,
    output         cmd_atomic_add,

    // Atomic operations
    output         cmd_atomic_and,
    output         cmd_atomic_or,
    output         cmd_atomic_xor,
    output         cmd_atomic_max,
    output         cmd_atomic_min,
    output         cmd_atomic_maxu,
    output         cmd_atomic_minu,
    output         cmd_atomic_swap

    );

`include "umi_messages.vh"

   assign cmd_invalid          = (command[7:0]==UMI_INVALID);

   // request/response/link
   assign cmd_request          =  command[0] & ~cmd_invalid;
   assign cmd_response         = ~command[0] & ~cmd_invalid;

   // requests
   assign cmd_read             = (command[3:0]==UMI_REQ_READ[3:0]);
   assign cmd_write            = (command[3:0]==UMI_REQ_WRITE[3:0]);
   assign cmd_write_posted     = (command[3:0]==UMI_REQ_POSTED[3:0]);
   assign cmd_rdma             = (command[3:0]==UMI_REQ_RDMA[3:0]);
   assign cmd_atomic           = (command[3:0]==UMI_REQ_ATOMIC[3:0]);
   assign cmd_user0            = (command[3:0]==UMI_REQ_USER0[3:0]);
   assign cmd_future0          = (command[3:0]==UMI_REQ_FUTURE0[3:0]);
   assign cmd_error            = (command[7:0]==UMI_REQ_ERROR[7:0]);
   assign cmd_link             = (command[7:0]==UMI_REQ_LINK[7:0]);
   // Response (device -> host)
   assign cmd_read_resp    = (command[3:0]==UMI_RESP_READ[3:0]);
   assign cmd_write_resp   = (command[3:0]==UMI_RESP_WRITE[3:0]);
   assign cmd_user0_resp   = (command[3:0]==UMI_RESP_USER0[3:0]);
   assign cmd_user1_resp   = (command[3:0]==UMI_RESP_USER1[3:0]);
   assign cmd_future0_resp = (command[3:0]==UMI_RESP_FUTURE0[3:0]);
   assign cmd_future1_resp = (command[3:0]==UMI_RESP_FUTURE1[3:0]);
   assign cmd_link_resp    = (command[7:0]==UMI_RESP_LINK[7:0]);

   // read modify writes
   assign cmd_atomic_add  = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICADD);
   assign cmd_atomic_and  = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICAND);
   assign cmd_atomic_or   = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICOR);
   assign cmd_atomic_xor  = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICXOR);
   assign cmd_atomic_max  = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICMAX);
   assign cmd_atomic_min  = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICMIN);
   assign cmd_atomic_maxu = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICMAXU);
   assign cmd_atomic_minu = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICMINU);
   assign cmd_atomic_swap = cmd_atomic & (command[15:8]==UMI_REQ_ATOMICSWAP);

endmodule // umi_decode
