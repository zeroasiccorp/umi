/*******************************************************************************
 * Function:  UMI Register Interface
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * The module translates a UMI request into a simple register interface.
 * Read data is returned as UMI response packets. Reads requests can occur
 * at a maximum rate of one transaction every two cycles.
 *
 * This module can also check if the incoming access is within the designated
 * address range by setting the GRPOFFSET, GRPAW, and GRPID parameter.
 * The address range [GRPOFFSET+:GRPAW] is checked against GRPID for a match.
 * To disable the check, set the GRPAW to 0.
 *
 * Only read/writes <= DW is supported.
 *
 ******************************************************************************/
module umi_regif
  #(parameter TARGET = "DEFAULT", // compile target
    parameter AW = 64,            // address width
    parameter CW = 32,            // address width
    parameter DW = 256,           // data width
    parameter RW = 64,            // register width
    parameter GRPOFFSET = 24,     // group address offset
    parameter GRPAW = 4,          // group address width
    parameter GRPID = 0           // group ID
    )
   (// clk, reset
    input               clk,        //clk
    input               nreset,     //async active low reset
    // UMI access
    input               udev_req_valid,
    input [CW-1:0]      udev_req_cmd,
    input [AW-1:0]      udev_req_dstaddr,
    input [AW-1:0]      udev_req_srcaddr,
    input [DW-1:0]      udev_req_data,
    output reg          udev_req_ready,
    output reg          udev_resp_valid,
    output reg [CW-1:0] udev_resp_cmd,
    output reg [AW-1:0] udev_resp_dstaddr,
    output reg [AW-1:0] udev_resp_srcaddr,
    output [DW-1:0]     udev_resp_data,
    input               udev_resp_ready,
    // Read/Write register interface
    output [AW-1:0]     reg_addr,   // memory address
    output              reg_write,  // register write
    output              reg_read,   // register read
    output [4:0]        reg_opcode, // command (eg. atomics)
    output [2:0]        reg_size,   // size (byte, etc)
    output [7:0]        reg_len,    // size (byte, etc)
    output [RW-1:0]     reg_wrdata, // data to write
    input [RW-1:0]      reg_rddata  // readback data
    );

`include "umi_messages.vh"

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire                 cmd_atomic;
   wire                 cmd_atomic_add;
   wire                 cmd_atomic_and;
   wire                 cmd_atomic_max;
   wire                 cmd_atomic_maxu;
   wire                 cmd_atomic_min;
   wire                 cmd_atomic_minu;
   wire                 cmd_atomic_or;
   wire                 cmd_atomic_swap;
   wire                 cmd_atomic_xor;
   wire                 cmd_error;
   wire                 cmd_future0;
   wire                 cmd_future0_resp;
   wire                 cmd_future1_resp;
   wire                 cmd_invalid;
   wire                 cmd_link;
   wire                 cmd_link_resp;
   wire                 cmd_rdma;
   wire                 cmd_read;
   wire                 cmd_read_resp;
   wire                 cmd_request;
   wire                 cmd_response;
   wire                 cmd_user0;
   wire                 cmd_user0_resp;
   wire                 cmd_user1_resp;
   wire                 cmd_write;
   wire                 cmd_write_posted;
   wire                 cmd_write_resp;
   wire [CW-1:0]        packet_cmd;
   wire [7:0]           reg_atype;
   wire                 reg_eof;
   wire                 reg_eom;
   wire [1:0]           reg_err;
   wire                 reg_ex;
   wire [4:0]           reg_hostid;
   wire [1:0]           reg_prot;
   wire [3:0]           reg_qos;
   wire [1:0]           reg_user;
   wire [23:0]          reg_user_extended;
   // End of automatics

   wire [4:0]           cmd_opcode;
   wire                 cmd_resp;
   wire                 group_match;
   wire                 reg_resp;

   //########################
   // UMI INPUT
   //########################

   assign reg_addr[AW-1:0]   = udev_req_dstaddr[AW-1:0];
   assign reg_wrdata[RW-1:0] = udev_req_data[RW-1:0];

   /* umi_unpack AUTO_TEMPLATE(
    .cmd_\(.*\)     (reg_\1[]),
    .packet_cmd (udev_req_cmd[]),
    );*/
   umi_unpack #(.CW(CW))
   umi_unpack(/*AUTOINST*/
              // Outputs
              .cmd_opcode       (reg_opcode[4:0]),       // Templated
              .cmd_size         (reg_size[2:0]),         // Templated
              .cmd_len          (reg_len[7:0]),          // Templated
              .cmd_atype        (reg_atype[7:0]),        // Templated
              .cmd_qos          (reg_qos[3:0]),          // Templated
              .cmd_prot         (reg_prot[1:0]),         // Templated
              .cmd_eom          (reg_eom),               // Templated
              .cmd_eof          (reg_eof),               // Templated
              .cmd_ex           (reg_ex),                // Templated
              .cmd_user         (reg_user[1:0]),         // Templated
              .cmd_user_extended(reg_user_extended[23:0]), // Templated
              .cmd_err          (reg_err[1:0]),          // Templated
              .cmd_hostid       (reg_hostid[4:0]),       // Templated
              // Inputs
              .packet_cmd       (udev_req_cmd[CW-1:0])); // Templated

   /* umi_decode AUTO_TEMPLATE(
    .command (udev_req_cmd[]),
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
              .command          (udev_req_cmd[CW-1:0])); // Templated

   generate
     if (GRPAW != 0)
       assign group_match = (udev_req_dstaddr[GRPOFFSET+:GRPAW]==GRPID[GRPAW-1:0]);
     else
       assign group_match = 1'b1;
   endgenerate

   // TODO - implement atomic
   assign reg_read  = cmd_read & udev_req_valid & udev_req_ready & group_match;
   assign reg_write = (cmd_write | cmd_write_posted) & udev_req_valid & udev_req_ready & group_match;
   assign reg_resp  = (cmd_read | cmd_write) & udev_req_valid & udev_req_ready & group_match;

   // single cycle stall on every ready
   // Amir - BUG - there is no guarantee that in the next cycle after the
   // read req the ready will be high, need to hold the data in that case

//   always @ (posedge clk or negedge nreset)
//     if(!nreset)
//       udev_req_ready <= 1'b0;
//     else if (udev_req_valid & udev_resp_ready)
//       udev_req_ready <= ~udev_req_ready;
//     else
//       udev_req_ready <= 1'b0;

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       udev_req_ready <= 1'b0;
     else if (udev_req_valid & udev_req_ready)
       udev_req_ready <= 1'b0;
     else
       udev_req_ready <= 1'b1;

   //############################
   //# UMI OUTPUT
   //############################

   //1. Set on incoming valid read
   //2. Keep high as long as incoming read is set
   //3. If no incoming read and output is ready, clear
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       udev_resp_valid <= 1'b0;
     else if (reg_resp & udev_req_ready)
       udev_resp_valid <= 1'b1;
     else if (udev_resp_valid & udev_resp_ready)
       udev_resp_valid <= 1'b0;

   // Amir - for now all resp bits except for the opcode will return from the request
   assign cmd_opcode[4:0] = reg_read ? UMI_RESP_READ : UMI_RESP_WRITE;

   /*umi_pack AUTO_TEMPLATE(
    .cmd_\(.*\) (reg_\1[]),
    .cmd_opcode (cmd_opcode[]),
    );*/
   umi_pack #(.CW(CW))
   umi_pack(/*AUTOINST*/
            // Outputs
            .packet_cmd         (packet_cmd[CW-1:0]),
            // Inputs
            .cmd_opcode         (cmd_opcode[4:0]),       // Templated
            .cmd_size           (reg_size[2:0]),         // Templated
            .cmd_len            (reg_len[7:0]),          // Templated
            .cmd_atype          (reg_atype[7:0]),        // Templated
            .cmd_prot           (reg_prot[1:0]),         // Templated
            .cmd_qos            (reg_qos[3:0]),          // Templated
            .cmd_eom            (reg_eom),               // Templated
            .cmd_eof            (reg_eof),               // Templated
            .cmd_user           (reg_user[1:0]),         // Templated
            .cmd_err            (reg_err[1:0]),          // Templated
            .cmd_ex             (reg_ex),                // Templated
            .cmd_hostid         (reg_hostid[4:0]),       // Templated
            .cmd_user_extended  (reg_user_extended[23:0])); // Templated

   // Amir - response fields cannot assume that the request will be help
   // Therefore they need to be sampled when the request is acknowledged
//   assign udev_resp_dstaddr[AW-1:0] = udev_req_srcaddr[AW-1:0];
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       begin
          udev_resp_dstaddr[AW-1:0] <= {AW{1'b0}};
          udev_resp_cmd[CW-1:0]     <= {CW{1'b0}};
          udev_resp_srcaddr[AW-1:0] <= {AW{1'b0}};
       end
     else if (reg_resp & udev_req_ready)
       begin
          udev_resp_dstaddr[AW-1:0] <= udev_req_srcaddr[AW-1:0];
          udev_resp_cmd[CW-1:0]     <= packet_cmd[CW-1:0];
          udev_resp_srcaddr[AW-1:0] <= udev_req_dstaddr[AW-1:0];
       end

//   assign udev_resp_srcaddr[AW-1:0] = {(AW){1'b0}};
   assign udev_resp_data[DW-1:0]    = {(DW/RW){reg_rddata[RW-1:0]}};

endmodule // umi_regif
