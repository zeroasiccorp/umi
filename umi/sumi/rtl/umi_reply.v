/**************************************************************************
 * Copyright 2025 Zero ASIC Corporation
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
 * Documentation:
 *
 * - Simple combinatorial block that generates a response command based
 *   on a reqest.
 *
 *************************************************************************/

module umi_reply
  (
   input [31:0]  req_cmd, // request input
   input [1:0]   err,     // device error
   output [31:0] resp_cmd // response output
   );

`include "umi_messages.vh"

   // local wires
   wire       cmd_read;
   wire       cmd_write;
   wire       cmd_posted;
   wire       cmd_atomic;

   // request decode
   assign cmd_read   = (req_cmd[4:0] == UMI_REQ_READ);
   assign cmd_write  = (req_cmd[4:0] == UMI_REQ_WRITE);
   assign cmd_posted = (req_cmd[4:0] == UMI_REQ_POSTED);
   assign cmd_atomic = (req_cmd[4:0] == UMI_REQ_ATOMIC);

   // response
   assign resp_cmd[4:0] = (cmd_read | cmd_atomic) ? UMI_RESP_READ :
                          (cmd_write)             ? UMI_RESP_WRITE :
                                                    UMI_INVALID;
   assign resp_cmd[24:5] = req_cmd[24:5];
   assign resp_cmd[26:25] = err[1:0];
   assign resp_cmd[31:27] = req_cmd[31:27];

endmodule
