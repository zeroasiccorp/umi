/*******************************************************************************
 * Copyright 2024 Zero ASIC Corporation
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
 * NOTE: This module works on the apb_pclk clock domain. To connect
 * the module with a different clock domain, use the umi_fifo module.
 *
 * The module translates a SUMI request into a APB requester interface.
 * Read data is returned as SUMI response packets. Requests can occur
 * at a maximum rate of one transaction every two cycles!
 *
 * This module can also check if the incoming access is within the designated
 * address range by setting the GRPOFFSET, GRPAW, and GRPID parameter.
 * The address range [GRPOFFSET+:GRPAW] is checked against GRPID for a match.
 * To disable the check, set the GRPAW to 0.
 *
 * Only RW-aligned read/writes <= RW are supported.
 * SUMI Atomics are not supported. Atomic requests will be dropped silently.
 * SUMI RDMA is not supported. RDMA requests will be dropped silently.
 *
 ******************************************************************************/

module umi2apb #(parameter AW = 64,        // UMI address width
                 parameter CW = 32,        // UMI cmd width
                 parameter DW = 256,       // UMI data width
                 parameter RW = 64,        // APB register width
                 parameter RAW = 64,       // APB address width
                 parameter GRPOFFSET = 24, // group address offset
                 parameter GRPAW = 0,      // group address width
                 parameter GRPID = 0       // group ID
                 )
   (// module operates on apb clk domain
    input             apb_nreset,  // apb asycn nreset
    input             apb_pclk,    // apb clock
    // UMI interface
    input             udev_req_valid,
    input [CW-1:0]    udev_req_cmd,
    input [AW-1:0]    udev_req_dstaddr,
    input [AW-1:0]    udev_req_srcaddr,
    input [DW-1:0]    udev_req_data,
    output            udev_req_ready,
    output reg        udev_resp_valid,
    output [CW-1:0]   udev_resp_cmd,
    output [AW-1:0]   udev_resp_dstaddr,
    output [AW-1:0]   udev_resp_srcaddr,
    output [DW-1:0]   udev_resp_data,
    input             udev_resp_ready,
    // APB interface
    output reg        apb_penable, // enable
    output            apb_pwrite,  // 0=read, 1=write
    output [RAW-1:0]  apb_paddr,   // register address
    output [RW-1:0]   apb_pwdata,  // write data
    output [RW/8-1:0] apb_pstrb,   // strobe
    output [2:0]      apb_pprot,   // protection type
    output            apb_psel,    // select
    input             apb_pready,  // ready
    input [RW-1:0]    apb_prdata,  // read data
    input             apb_pslverr  // error
    );

`include "umi_messages.vh"

   reg [CW-1:0]    udev_req_cmd_r;
   reg [AW-1:0]    udev_req_dstaddr_r;
   reg [AW-1:0]    udev_req_srcaddr_r;
   reg [RW-1:0]    udev_req_data_r;

   wire            incoming_req;
   wire            outgoing_resp;
   wire            group_match;

   wire [CW-1:0]   cmd_packet;
   wire [4:0]      cmd_opcode;
   wire            cmd_read;
   wire            cmd_write;
   wire            cmd_posted;
   wire [1:0]      cmd_prot;


   reg [1:0]       pslverr_r;
   reg [RW-1:0]    prdata_r;

   //############################
   //# UMI Request
   //############################

   generate
      if (GRPAW != 0)
        assign group_match = (udev_req_dstaddr[GRPOFFSET+:GRPAW]==GRPID[GRPAW-1:0]);
      else
        assign group_match = 1'b1;
   endgenerate

   assign incoming_req  = udev_req_valid & udev_req_ready & group_match;

   always @(posedge apb_pclk or negedge apb_nreset) begin
      if (~apb_nreset) begin
         udev_req_cmd_r     <= {CW{1'b0}};
         udev_req_dstaddr_r <= {AW{1'b0}};
         udev_req_srcaddr_r <= {AW{1'b0}};
         udev_req_data_r    <= {RW{1'b0}};
      end
      else if (incoming_req) begin
         udev_req_cmd_r     <= udev_req_cmd;
         udev_req_dstaddr_r <= udev_req_dstaddr;
         udev_req_srcaddr_r <= udev_req_srcaddr;
         udev_req_data_r    <= udev_req_data[RW-1:0];
      end
   end

   assign cmd_packet = incoming_req ? udev_req_cmd : udev_req_cmd_r;
   assign cmd_opcode = cmd_packet[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

   assign cmd_read   = cmd_opcode==UMI_REQ_READ;
   assign cmd_write  = cmd_opcode==UMI_REQ_WRITE;
   assign cmd_posted = cmd_opcode==UMI_REQ_POSTED;
   assign cmd_prot   = cmd_packet[UMI_PROT_MSB:UMI_PROT_LSB];

   //############################
   //# APB Mapping
   //############################

   assign apb_paddr   = incoming_req ? udev_req_dstaddr[RAW-1:0] :
                                       udev_req_dstaddr_r[RAW-1:0];

   assign apb_pprot   = {1'b0, cmd_prot[1:0]};
   assign apb_pwrite  = cmd_write | cmd_posted;
   assign apb_pwdata  = incoming_req ? udev_req_data[RW-1:0] : udev_req_data_r[RW-1:0];
   assign apb_pstrb   = {(RW/8){1'b1}}; // TODO: Support strobe
   assign apb_psel    = incoming_req | apb_penable;

   always @(posedge apb_pclk or negedge apb_nreset)
     if (~apb_nreset)
       apb_penable <= 1'b0;
     else if (incoming_req)
       apb_penable <= 1'b1;
     else if (apb_pready)
       apb_penable <= 1'b0;

   assign udev_req_ready = ~apb_penable;

   //############################
   //# UMI Response
   //############################

   assign outgoing_resp = (udev_resp_valid & udev_resp_ready) |
                          (cmd_posted & apb_penable & apb_pready);

   always @(posedge apb_pclk or negedge apb_nreset)
     if (~apb_nreset)
       udev_resp_valid <= 1'b0;
     else if (apb_penable & apb_pready & ~cmd_posted)
       udev_resp_valid <= 1'b1;
     else if (outgoing_resp)
       udev_resp_valid <= 1'b0;

   always @(posedge apb_pclk or negedge apb_nreset)
     if (~apb_nreset)
       prdata_r <= 'b0;
     else if (apb_penable & apb_pready)
       prdata_r <= apb_prdata;

   always @(posedge apb_pclk or negedge apb_nreset)
     if (~apb_nreset)
       pslverr_r <= 'b0;
     else if (apb_penable & apb_pready)
       pslverr_r <= {apb_pslverr, 1'b0};

   assign udev_resp_cmd[4:0]   = cmd_read ? UMI_RESP_READ : UMI_RESP_WRITE;
   assign udev_resp_cmd[24:5]  = udev_req_cmd[24:5];
   assign udev_resp_cmd[26:25] = pslverr_r[1:0];
   assign udev_resp_cmd[31:27] = udev_req_cmd[31:27];

   assign udev_resp_dstaddr[AW-1:0] = udev_req_srcaddr_r[AW-1:0];

   assign udev_resp_srcaddr[AW-1:0] = udev_req_dstaddr_r[AW-1:0];

   assign udev_resp_data[DW-1:0]    = {{(DW-RW){1'b0}}, prdata_r[RW-1:0]};

endmodule
