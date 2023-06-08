/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Packer
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_pack #(parameter CW = 32)
   (
    // Command inputs
    input [4:0]     cmd_opcode,
    input [2:0]     cmd_size,
    input [7:0]     cmd_len,
    input [7:0]     cmd_atype,
    input [1:0]     cmd_prot,
    input [3:0]     cmd_qos,
    input           cmd_eom,
    input           cmd_eof,
    input [1:0]     cmd_user,
    input [1:0]     cmd_err,
    input           cmd_ex,
    input [4:0]     cmd_hostid,
    input [18:0]    cmd_user_extended,
    // Output packet
    output [CW-1:0] packet_cmd
    );

   wire [31:0] cmd_out;
   wire [31:0] cmd_in;
   wire        cmd_error;
   wire        cmd_response;
   wire        cmd_link;
   wire        cmd_link_resp;
   wire        cmd_atomic;
   wire        extended_user_sel;

   assign extended_user_sel = cmd_link | cmd_link_resp | cmd_err;

   // Take only the required fields for the decode
   assign cmd_in[31:0] = {24'h00_0000,cmd_size[2:0],cmd_opcode[4:0]};

   // command packer
   assign cmd_out[4:0]   = cmd_opcode[4:0];

   assign cmd_out[7:5]   = cmd_link      ? 3'h1 :
                           cmd_link_resp ? 3'h0 :
                           cmd_error     ? 3'h0 :
                                           cmd_size[2:0];

   assign cmd_out[15:8]  = cmd_atomic        ? cmd_atype[7:0] :
                           extended_user_sel ? cmd_user_extended[7:0]  :
                                               cmd_len[7:0];

   assign cmd_out[19:16] = extended_user_sel ? cmd_user_extended[11:8]  : cmd_qos[3:0];
   assign cmd_out[21:20] = extended_user_sel ? cmd_user_extended[13:12] : cmd_prot[1:0];
   assign cmd_out[24:22] = extended_user_sel ? cmd_user_extended[16:14] : {cmd_ex,cmd_eof,cmd_eom};
   assign cmd_out[26:25] = extended_user_sel ? cmd_user_extended[18:17] : cmd_user[1:0]   ;
   assign cmd_out[31:27] = cmd_hostid[4:0];

   /*umi_decode AUTO_TEMPLATE(
    .cmd_atomic     (cmd_atomic[]),
    .cmd_error      (cmd_error[]),
    .cmd_response   (cmd_response[]),
    .cmd_link\(.*\) (cmd_link\1[]),
    .command        (cmd_in[]),
    .cmd_.*         (),
    );*/

   // Command decode
   umi_decode #(.CW(CW))
   umi_decode(/*AUTOINST*/
              // Outputs
              .cmd_invalid      (),                      // Templated
              .cmd_request      (),                      // Templated
              .cmd_response     (cmd_response),          // Templated
              .cmd_read         (),                      // Templated
              .cmd_write        (),                      // Templated
              .cmd_write_posted (),                      // Templated
              .cmd_rdma         (),                      // Templated
              .cmd_atomic       (cmd_atomic),            // Templated
              .cmd_user0        (),                      // Templated
              .cmd_future0      (),                      // Templated
              .cmd_error        (cmd_error),             // Templated
              .cmd_link         (cmd_link),              // Templated
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
              .command          (cmd_in[CW-1:0]));       // Templated

   assign packet_cmd[31:0] = cmd_out[31:0];

endmodule

// Local Variables:
// verilog-library-directories:(".")
// End:
