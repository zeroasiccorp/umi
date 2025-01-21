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
 * Documentation:
 *
 * - The module translates a UMI request into a simple register interface.
 * - Reads requests consume two cycles.
 * - Read data must return on same cycle immediately (no pipeline)
 * - Only read/writes/posted <= DW is supported.
 * - No atomics support
 * - This module can also check if the incoming access is within the designated
 *   address range by setting the GRPOFFSET, GRPAW, and GRPID parameter.
 *   The address range [GRPOFFSET+:GRPAW] is checked against GRPID for a match.
 *   To disable the check, set the GRPAW to 0.
 *
 ******************************************************************************/

module umi_regif
  #(parameter RW = 32,        // register width
    parameter GRPOFFSET = 24, // group address offset
    parameter GRPAW = 0,      // group address width
    parameter GRPID = 0,      // group ID
    // umi standard parameters
    parameter CW = 32,        // command width
    parameter AW = 64,        // address width
    parameter DW = 32         // data width
    )
   (// clk, reset
    input               clk,        //clk
    input               nreset,     //async active low reset
    // UMI transaction
    input               udev_req_valid,
    input [CW-1:0]      udev_req_cmd,
    input [AW-1:0]      udev_req_dstaddr,
    input [AW-1:0]      udev_req_srcaddr,
    input [DW-1:0]      udev_req_data,
    output              udev_req_ready,
    output reg          udev_resp_valid,
    output reg [CW-1:0] udev_resp_cmd,
    output reg [AW-1:0] udev_resp_dstaddr,
    output reg [AW-1:0] udev_resp_srcaddr,
    output reg [DW-1:0] udev_resp_data,
    input               udev_resp_ready,
    // register interface
    output              reg_write,  // write enable
    output              reg_read,   // read request
    output [AW-1:0]     reg_addr,   // address
    output [RW-1:0]     reg_wrdata, // write data
    output [1:0]        reg_prot,   // protection
    input               reg_ready,  // device is ready
    input [RW-1:0]      reg_rddata, // read data
    input [1:0]         reg_err     // device error
    );

`include "umi_messages.vh"

   // local wires
   wire [CW-1:0] resp_cmd;
   wire          cmd_read;
   wire          cmd_write;
   wire          cmd_posted;
   wire          cmd_atomic;

   //######################################
   // UMI Request
   //######################################

   generate
     if (GRPAW != 0)
       assign match = (udev_req_dstaddr[GRPOFFSET+:GRPAW]==GRPID[GRPAW-1:0]);
     else
       assign match = 1'b1;
   endgenerate

   assign cmd_read = (udev_req_cmd[4:0]==UMI_REQ_READ);
   assign cmd_write = (udev_req_cmd[4:0]==UMI_REQ_WRITE);
   assign cmd_posted = (udev_req_cmd[4:0]==UMI_REQ_POSTED);
   assign cmd_atomic = (udev_req_cmd[4:0]==UMI_REQ_ATOMIC);

   // back pressure (note feedback from resp-->req ready)
   assign udev_req_ready = reg_ready & udev_resp_ready;
   assign beat = udev_req_valid & udev_req_ready;

   //######################################
   // Register Interface
   //######################################

   assign reg_write = (cmd_write | cmd_posted) & udev_req_valid;
   assign reg_read = cmd_read & udev_req_valid;
   assign reg_addr[AW-1:0] = udev_req_dstaddr[AW-1:0];
   assign reg_wrdata[RW-1:0] = udev_req_data[RW-1:0];
   assign reg_prot[1:0] = udev_req_cmd[21:20];

   //######################################
   // UMI Response
   //######################################

   // keep valid high while there is an input beat
   always @(posedge clk or negedge nreset)
     if (!nreset)
       udev_resp_valid <= 1'b0;
     else if (beat & (cmd_write | cmd_read))
       udev_resp_valid <= 1'b1;
     else if (udev_resp_ready)
       udev_resp_valid <= 1'b0;

   // read/write responses
   assign resp_cmd[4:0] = (cmd_read)  ? UMI_RESP_READ :
                          (cmd_write) ? UMI_RESP_WRITE :
                                        UMI_INVALID;

   assign resp_cmd[24:5] = udev_req_cmd[24:5];
   assign resp_cmd[26:25] = reg_err[1:0];
   assign resp_cmd[31:27] = udev_req_cmd[31:27];

   // sample data on read/write
   always @ (posedge clk)
     if (beat & (cmd_write | cmd_read))
       begin
          udev_resp_cmd[CW-1:0]     <= resp_cmd;
          udev_resp_dstaddr[AW-1:0] <= udev_req_srcaddr;
          udev_resp_srcaddr[AW-1:0] <= udev_req_dstaddr;
          udev_resp_data[DW-1:0]    <= {{(DW-RW){1'b0}},
                                        reg_rddata[RW-1:0]};
       end

endmodule
