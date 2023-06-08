/*******************************************************************************
 * Function:  UMI Simple Endpoint
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_endpoint
  #(parameter REG  = 1,       // 1=insert register on read_data
    parameter TYPE = "LIGHT", // FULL, LIGHT
    // standard parameters
    parameter      CW = 32,
    parameter      AW = 64,
    parameter      DW = 256)
   (// ctrl
    input           nreset,
    input           clk,
    // Device port
    input           udev_req_valid,
    input [CW-1:0]  udev_req_cmd,
    input [AW-1:0]  udev_req_dstaddr,
    input [AW-1:0]  udev_req_srcaddr,
    input [DW-1:0]  udev_req_data,
    output          udev_req_ready,
    output reg      udev_resp_valid,
    output [CW-1:0] udev_resp_cmd,
    output [AW-1:0] udev_resp_dstaddr,
    output [AW-1:0] udev_resp_srcaddr,
    output [DW-1:0] udev_resp_data,
    input           udev_resp_ready,
    // Memory interface
    output [AW-1:0] loc_addr,    // memory address
    output          loc_write,   // write enable
    output          loc_read,    // read request
    output [7:0]    loc_opcode,  // opcode
    output [2:0]    loc_size,    // size
    output [7:0]    loc_len,     // len
    output [DW-1:0] loc_wrdata,  // data to write
    input [DW-1:0]  loc_rddata,  // data response
    input           loc_ready    // device is ready
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
   wire [7:0]           loc_atype;
   wire                 loc_eof;
   wire                 loc_eom;
   wire [1:0]           loc_err;
   wire                 loc_ex;
   wire [4:0]           loc_hostid;
   wire [1:0]           loc_prot;
   wire [3:0]           loc_qos;
   wire [22:0]          loc_user;
   wire [CW-1:0]        packet_cmd;
   // End of automatics

   // local regs
   reg [AW-1:0]         dstaddr_out;
   reg [AW-1:0]         srcaddr_out;
   reg [CW-1:0]         command_out;
   reg [DW-1:0]         data_out;

   // local wires
   wire [DW-1:0]        data_mux;
   wire                 loc_read;
   wire                 loc_write;
   wire                 loc_resp;
   wire [4:0]           cmd_opcode;

   //########################
   // UMI UNPACK
   //########################
   assign loc_addr[AW-1:0]    = udev_req_dstaddr[AW-1:0];
   assign loc_wrdata[DW-1:0]  = udev_req_data[DW-1:0];

   /* umi_unpack AUTO_TEMPLATE(
    .packet_\(.*\)   (udev_req_\1[]),
    .cmd_\(.*\)      (loc_\1[]),
    );
    */

   umi_unpack #(.CW(CW))
   umi_unpack(/*AUTOINST*/
              // Outputs
              .cmd_opcode       (loc_opcode[4:0]),       // Templated
              .cmd_size         (loc_size[2:0]),         // Templated
              .cmd_len          (loc_len[7:0]),          // Templated
              .cmd_atype        (loc_atype[7:0]),        // Templated
              .cmd_qos          (loc_qos[3:0]),          // Templated
              .cmd_prot         (loc_prot[1:0]),         // Templated
              .cmd_eom          (loc_eom),               // Templated
              .cmd_eof          (loc_eof),               // Templated
              .cmd_ex           (loc_ex),                // Templated
              .cmd_user         (loc_user[22:0]),        // Templated
              .cmd_err          (loc_err[1:0]),          // Templated
              .cmd_hostid       (loc_hostid[4:0]),       // Templated
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

   // TODO - implement atomic
   assign loc_read  = cmd_read & udev_req_valid & loc_ready;
   assign loc_write = (cmd_write | cmd_write_posted) & udev_req_valid & loc_ready;
   assign loc_resp  = (cmd_read | cmd_write) & udev_req_valid & loc_ready;

   //############################
   //# Outgoing Transaction
   //############################

   //1. Set on incoming valid read
   //2. Keep high as long as incoming read is set
   //3. If no incoming read and output is ready, clear
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       udev_resp_valid <= 1'b0;
     else if (loc_resp)
       udev_resp_valid <= loc_ready;
     else if (udev_resp_valid & udev_resp_ready)
       udev_resp_valid <= 1'b0;

   // Propagating wait signal
   // Amir - bug fix - request ready should not be gated by response ready
//   assign udev_req_ready = loc_ready & udev_resp_ready;
   assign udev_req_ready = loc_ready;

   //#############################
   //# Pipeline Packet
   //##############################
   // Amir - outputs should be sampled when the read command is accepted
   // Read data only arrives one cycle after the read is accepted

   assign cmd_opcode[4:0] = cmd_read ? UMI_RESP_READ : UMI_RESP_WRITE;

   /* umi_pack AUTO_TEMPLATE(
    .cmd_\(.*\) (loc_\1[]),
    .cmd_opcode (cmd_opcode[]),
    );
    */

   // pack up the packet
   umi_pack #(.CW(CW))
   umi_pack(/*AUTOINST*/
            // Outputs
            .packet_cmd         (packet_cmd[CW-1:0]),
            // Inputs
            .cmd_opcode         (cmd_opcode[4:0]),       // Templated
            .cmd_size           (loc_size[2:0]),         // Templated
            .cmd_len            (loc_len[7:0]),          // Templated
            .cmd_atype          (loc_atype[7:0]),        // Templated
            .cmd_prot           (loc_prot[1:0]),         // Templated
            .cmd_qos            (loc_qos[3:0]),          // Templated
            .cmd_eom            (loc_eom),               // Templated
            .cmd_eof            (loc_eof),               // Templated
            .cmd_user           (loc_user[18:0]),        // Templated
            .cmd_err            (loc_err[1:0]),          // Templated
            .cmd_ex             (loc_ex),                // Templated
            .cmd_hostid         (loc_hostid[4:0]));      // Templated

   always @ (posedge clk or negedge nreset)
     if (!nreset)
       begin
	  dstaddr_out[AW-1:0] <= {AW{1'b0}};
	  srcaddr_out[AW-1:0] <= {AW{1'b0}};
	  command_out[CW-1:0] <= {CW{1'b0}};
       end
     else if(loc_resp & loc_ready)
       begin
	  dstaddr_out[AW-1:0] <= udev_req_srcaddr[AW-1:0];
	  srcaddr_out[AW-1:0] <= loc_addr[AW-1:0];
	  command_out[CW-1:0] <= packet_cmd[CW-1:0];
       end

   // selectively add pipestage
   // In order to delay the data there is also a need to delay the valid
   // adding the same logic for the loc_valid
   always @(posedge clk or negedge nreset)
     if (!nreset)
       data_out[DW-1:0] <= {DW{1'b0}};
     else
       data_out[DW-1:0] <= loc_rddata[DW-1:0];

   assign data_mux[DW-1:0] = (REG) ? data_out[DW-1:0] :
			             loc_rddata[DW-1:0];

   // Final outputs
   assign udev_resp_cmd[CW-1:0]     = command_out[AW-1:0];
   assign udev_resp_dstaddr[AW-1:0] = dstaddr_out[AW-1:0];
   assign udev_resp_srcaddr[AW-1:0] = srcaddr_out[AW-1:0];
   assign udev_resp_data[DW-1:0]    = data_mux[DW-1:0];

endmodule // umi_endpoint
