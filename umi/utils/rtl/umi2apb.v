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
 * The module translates a SUMI request into a APB requester interface.
 * Read data is returned as SUMI response packets. Requests can occur
 * at a maximum rate of one transaction every two cycles.
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

module umi2apb #(
    parameter TARGET    = "DEFAULT",    // compile target
    parameter APB_AW    = 64,           // APB address width
    parameter AW        = 64,           // UMI address width
    parameter CW        = 32,           // UMI cmd width
    parameter DW        = 256,          // UMI data width
    parameter RW        = 64,           // register width
    parameter GRPOFFSET = 24,           // group address offset
    parameter GRPAW     = 0,            // group address width
    parameter GRPID     = 0             // group ID
)
(
    input                   clk,        //clk
    input                   nreset,     //async active low reset

    // UMI access
    input                   udev_req_valid,
    input [CW-1:0]          udev_req_cmd,
    input [AW-1:0]          udev_req_dstaddr,
    input [AW-1:0]          udev_req_srcaddr,
    input [DW-1:0]          udev_req_data,
    output                  udev_req_ready,

    output reg              udev_resp_valid,
    output     [CW-1:0]     udev_resp_cmd,
    output     [AW-1:0]     udev_resp_dstaddr,
    output     [AW-1:0]     udev_resp_srcaddr,
    output     [DW-1:0]     udev_resp_data,
    input                   udev_resp_ready,

    // Read/Write register interface
    output     [APB_AW-1:0] paddr,      // register address
    output     [2:0]        pprot,      // protection type
    output                  psel,       // select
    output reg              penable,    // enable
    output                  pwrite,     // 0=read, 1=write
    output     [RW-1:0]     pwdata,     // write data
    output     [(RW/8)-1:0] pstrb,      // strobe
    input                   pready,     // ready
    input      [RW-1:0]     prdata,     // read data
    input                   pslverr     // err
);

`include "umi_messages.vh"

    reg             udev_req_valid_r;
    reg  [CW-1:0]   udev_req_cmd_r;
    reg  [AW-1:0]   udev_req_dstaddr_r;
    reg  [AW-1:0]   udev_req_srcaddr_r;
    reg  [RW-1:0]   udev_req_data_r;

    wire            incoming_req;
    wire            outgoing_resp;
    wire            group_match;

    wire [4:0]      req_opcode;
    wire [2:0]      req_size;
    wire [7:0]      req_len;
    wire [7:0]      req_atype;
    wire [3:0]      req_qos;
    wire [1:0]      req_prot;
    wire            req_eom;
    wire            req_eof;
    wire            req_ex;
    wire [1:0]      req_user;
    wire [23:0]     req_user_extended;
    wire [1:0]      req_err;
    wire [4:0]      req_hostid;

    wire            cmd_invalid;
    wire            cmd_request;
    wire            cmd_response;
    wire            cmd_read;
    wire            cmd_write;
    wire            cmd_write_posted;
    wire            cmd_rdma;
    wire            cmd_atomic;
    wire            cmd_user0;
    wire            cmd_future0;
    wire            cmd_error;
    wire            cmd_link;
    wire            cmd_read_resp;
    wire            cmd_write_resp;
    wire            cmd_user0_resp;
    wire            cmd_user1_resp;
    wire            cmd_future0_resp;
    wire            cmd_future1_resp;
    wire            cmd_link_resp;
    wire            cmd_atomic_add;
    wire            cmd_atomic_and;
    wire            cmd_atomic_or;
    wire            cmd_atomic_xor;
    wire            cmd_atomic_max;
    wire            cmd_atomic_min;
    wire            cmd_atomic_maxu;
    wire            cmd_atomic_minu;
    wire            cmd_atomic_swap;

    wire [CW-1:0]   packet_cmd;

    wire [4:0]      cmd_opcode;
    reg  [1:0]      pslverr_r;
    reg  [RW-1:0]   prdata_r;

    generate
        if (GRPAW != 0)
            assign group_match = (udev_req_dstaddr[GRPOFFSET+:GRPAW]==GRPID[GRPAW-1:0]);
        else
            assign group_match = 1'b1;
    endgenerate

    assign incoming_req  = udev_req_valid & udev_req_ready & group_match;
    assign outgoing_resp = (udev_resp_valid & udev_resp_ready) |
                           (penable & pready & cmd_write_posted);

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
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

    /* umi_unpack AUTO_TEMPLATE(
     .cmd_\(.*\)     (req_\1[]),
     );*/
    umi_unpack #(.CW(CW))
    umi_unpack(/*AUTOINST*/
               // Outputs
               .cmd_opcode       (req_opcode[4:0]),       // Templated
               .cmd_size         (req_size[2:0]),         // Templated
               .cmd_len          (req_len[7:0]),          // Templated
               .cmd_atype        (req_atype[7:0]),        // Templated
               .cmd_qos          (req_qos[3:0]),          // Templated
               .cmd_prot         (req_prot[1:0]),         // Templated
               .cmd_eom          (req_eom),               // Templated
               .cmd_eof          (req_eof),               // Templated
               .cmd_ex           (req_ex),                // Templated
               .cmd_user         (req_user[1:0]),         // Templated
               .cmd_user_extended(req_user_extended[23:0]), // Templated
               .cmd_err          (req_err[1:0]),          // Templated
               .cmd_hostid       (req_hostid[4:0]),       // Templated
               // Inputs
               .packet_cmd       (packet_cmd[CW-1:0])); // Templated

    /* umi_decode AUTO_TEMPLATE(
     .command (packet_cmd[]),
     );*/
    umi_decode #(.CW(CW))
    umi_decode(/*AUTOINST*/
               // Outputs
               .cmd_invalid      (cmd_invalid),
               .cmd_request      (cmd_request),
               .cmd_response     (cmd_response),
               .cmd_read         (cmd_read),
               .cmd_write        (cmd_write),
               .cmd_write_posted (cmd_write_posted),
               .cmd_rdma         (cmd_rdma),
               .cmd_atomic       (cmd_atomic),
               .cmd_user0        (cmd_user0),
               .cmd_future0      (cmd_future0),
               .cmd_error        (cmd_error),
               .cmd_link         (cmd_link),
               .cmd_read_resp    (cmd_read_resp),
               .cmd_write_resp   (cmd_write_resp),
               .cmd_user0_resp   (cmd_user0_resp),
               .cmd_user1_resp   (cmd_user1_resp),
               .cmd_future0_resp (cmd_future0_resp),
               .cmd_future1_resp (cmd_future1_resp),
               .cmd_link_resp    (cmd_link_resp),
               .cmd_atomic_add   (cmd_atomic_add),
               .cmd_atomic_and   (cmd_atomic_and),
               .cmd_atomic_or    (cmd_atomic_or),
               .cmd_atomic_xor   (cmd_atomic_xor),
               .cmd_atomic_max   (cmd_atomic_max),
               .cmd_atomic_min   (cmd_atomic_min),
               .cmd_atomic_maxu  (cmd_atomic_maxu),
               .cmd_atomic_minu  (cmd_atomic_minu),
               .cmd_atomic_swap  (cmd_atomic_swap),
               // Inputs
               .command          (packet_cmd[CW-1:0])); // Templated

    assign packet_cmd = incoming_req ? udev_req_cmd : udev_req_cmd_r;

    assign paddr      = incoming_req ?
                        udev_req_dstaddr[APB_AW-1:0] :
                        udev_req_dstaddr_r[APB_AW-1:0];
    assign pprot      = {1'b0, req_prot};
    assign pwrite     = cmd_write | cmd_write_posted;
    assign pwdata     = incoming_req ? udev_req_data[RW-1:0] : udev_req_data_r[RW-1:0];
    assign pstrb      = {(RW/8){1'b1}}; // TODO: Support strobe
    assign psel       = incoming_req | penable;

    always @(posedge clk or negedge nreset)
        if (~nreset)
            penable <= 1'b0;
        else if (incoming_req)
            penable <= 1'b1;
        else if (pready)
            penable <= 1'b0;

    assign udev_req_ready = ~penable;

    //############################
    //# UMI OUTPUT
    //############################
    assign udev_resp_dstaddr[AW-1:0] = udev_req_srcaddr_r[AW-1:0];
    assign udev_resp_srcaddr[AW-1:0] = udev_req_dstaddr_r[AW-1:0];
    assign udev_resp_data[DW-1:0]    = {{(DW-RW){1'b0}}, prdata_r[RW-1:0]};

    always @(posedge clk or negedge nreset)
        if (~nreset)
            prdata_r <= 'b0;
        else if (penable & pready)
            prdata_r <= prdata;

    always @(posedge clk or negedge nreset)
        if (~nreset)
            udev_resp_valid <= 1'b0;
        else if (penable & pready & ~cmd_write_posted)
            udev_resp_valid <= 1'b1;
        else if (outgoing_resp)
            udev_resp_valid <= 1'b0;

    assign cmd_opcode[4:0] = cmd_read ? UMI_RESP_READ : UMI_RESP_WRITE;

    always @(posedge clk or negedge nreset)
        if (~nreset)
            pslverr_r <= 'b0;
        else if (penable & pready)
            pslverr_r <= {pslverr, 1'b0};

    /*umi_pack AUTO_TEMPLATE(
     .packet_cmd (udev_resp_cmd[]),
     .cmd_\(.*\) (req_\1[]),
     .cmd_opcode (cmd_opcode[]),
     .cmd_err    (pslverr_r[]),
     );*/
    umi_pack #(.CW(CW))
    umi_pack(/*AUTOINST*/
             // Outputs
             .packet_cmd         (udev_resp_cmd[CW-1:0]),
             // Inputs
             .cmd_opcode         (cmd_opcode[4:0]),       // Templated
             .cmd_size           (req_size[2:0]),         // Templated
             .cmd_len            (req_len[7:0]),          // Templated
             .cmd_atype          (req_atype[7:0]),        // Templated
             .cmd_prot           (req_prot[1:0]),         // Templated
             .cmd_qos            (req_qos[3:0]),          // Templated
             .cmd_eom            (req_eom),               // Templated
             .cmd_eof            (req_eof),               // Templated
             .cmd_user           (req_user[1:0]),         // Templated
             .cmd_err            (pslverr_r[1:0]),        // Templated
             .cmd_ex             (req_ex),                // Templated
             .cmd_hostid         (req_hostid[4:0]),       // Templated
             .cmd_user_extended  (req_user_extended[23:0])); // Templated

endmodule // umi2apb
