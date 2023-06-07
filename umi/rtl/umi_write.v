/*******************************************************************************
 * Function:  UMI Write Decoder
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_write #(parameter CW = 32)
   (
    input [7:0] command,     // Packet Command
    output      write,       // write indicator
    output      write_posted // write indicator
    );

   /*umi_decode AUTO_TEMPLATE(
    .cmd_write        (write[]),
    .cmd_write_posted (write_posted[]),
    .cmd_.*    (),
    .command   ({24'h00_0000,command[7:0]}),
    );*/

   // Command decode
   umi_decode #(.CW(CW))
   umi_decode(/*AUTOINST*/
              // Outputs
              .cmd_invalid      (),                      // Templated
              .cmd_request      (),                      // Templated
              .cmd_response     (),                      // Templated
              .cmd_read         (),                      // Templated
              .cmd_write        (write),                 // Templated
              .cmd_write_posted (write_posted),          // Templated
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
              .command          ({24'h00_0000,command[7:0]})); // Templated

endmodule
