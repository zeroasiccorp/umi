/*******************************************************************************
 * Copyright 2020 Zero ASIC Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ----
 *
 * ##Documentation##
 *
 * - Unpacks 32b command into separate ctrl fields
 *
 ******************************************************************************/

module umi_unpack
  #(parameter CW = 32)
   (
    // Input packet
    input [CW-1:0] packet_cmd,
    // output fields
    output [4:0]   cmd_opcode,
    output [2:0]   cmd_size,
    output [7:0]   cmd_len,
    output [7:0]   cmd_atype,
    output [3:0]   cmd_qos,
    output [1:0]   cmd_prot,
    output         cmd_eom,
    output         cmd_eof,
    output         cmd_ex,
    output [1:0]   cmd_user,
    output [23:0]  cmd_user_extended,
    output [1:0]   cmd_err,
    output [4:0]   cmd_hostid
    );

`include "umi_messages.vh"

   // local wires
   wire cmd_response;
   wire cmd_atomic;

   assign cmd_response = ~packet_cmd[0] & (packet_cmd[7:0]!=UMI_INVALID);
   assign cmd_atomic   = (packet_cmd[3:0]==UMI_REQ_ATOMIC[3:0]);

   // outputs
   assign cmd_opcode[4:0] = packet_cmd[4:0];
   assign cmd_size[2:0]   = packet_cmd[7:5];
   assign cmd_len[7:0]    = {8{cmd_atomic}} & packet_cmd[15:8];
   assign cmd_atype[7:0]  = packet_cmd[15:8];
   assign cmd_qos[3:0]    = packet_cmd[19:16];
   assign cmd_prot[1:0]   = packet_cmd[21:20];
   assign cmd_eom         = packet_cmd[22];
   assign cmd_eof         = packet_cmd[23];
   assign cmd_ex          = packet_cmd[24];
   assign cmd_hostid[4:0] = packet_cmd[31:27];
   assign cmd_user[1:0]   = packet_cmd[26:25];
   assign cmd_err[1:0]    = {2{cmd_response}} & packet_cmd[26:25];

   // TODO: remove?
   assign cmd_user_extended[23:0] = packet_cmd[31:8];

endmodule
