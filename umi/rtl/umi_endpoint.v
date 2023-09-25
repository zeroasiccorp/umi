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
  #(parameter REG  = 0,       // 1=insert register on read_data
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
    output          udev_resp_valid,
    output [CW-1:0] udev_resp_cmd,
    output [AW-1:0] udev_resp_dstaddr,
    output [AW-1:0] udev_resp_srcaddr,
    output [DW-1:0] udev_resp_data,
    input           udev_resp_ready,
    // Memory interface
    output [AW-1:0] loc_addr,   // memory address
    output          loc_write,  // write enable
    output          loc_read,   // read request
    output [7:0]    loc_opcode, // opcode
    output [2:0]    loc_size,   // size
    output [7:0]    loc_len,    // len
    output [DW-1:0] loc_wrdata, // data to write
    input [DW-1:0]  loc_rddata, // data response
    input           loc_ready   // device is ready
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
   wire [1:0]           loc_user;
   wire [23:0]          loc_user_extended;
   wire [CW-1:0]        packet_cmd;
   // End of automatics

   // local regs
   reg                  loc_resp_vld;
   wire                 loc_vld_out;
   reg                  loc_vld_keep;
   reg [CW-1:0]         loc_cmd_out;
   reg [AW-1:0]         loc_dstaddr_out;
   reg [AW-1:0]         loc_srcaddr_out;
   reg [DW-1:0]         loc_data_keep;
   wire [DW-1:0]        loc_data_out;

   reg                  vld_pipe;
   reg [CW-1:0]         cmd_pipe;
   reg [AW-1:0]         dstaddr_pipe;
   reg [AW-1:0]         srcaddr_pipe;
   reg [DW-1:0]         data_pipe;
   wire                 ready_gated;

   // local wires
   wire                 request_stall;
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
              .cmd_user         (loc_user[1:0]),         // Templated
              .cmd_user_extended(loc_user_extended[23:0]), // Templated
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
   assign loc_read  = ready_gated & cmd_read & udev_req_valid & ~request_stall;
   assign loc_write = ready_gated & (cmd_write | cmd_write_posted) & udev_req_valid & ~request_stall;
   assign loc_resp  = ready_gated & (cmd_read | cmd_write) & udev_req_valid & loc_ready;

   //############################
   //# Outgoing Transaction
   //############################

   // Propagating wait signal
   // Since this is a pipeline we hold the request if we cannot respond
   la_rsync la_rsync(.nrst_out          (ready_gated),
                     .clk               (clk),
                     .nrst_in           (nreset));

   assign udev_req_ready = ready_gated & loc_ready & ~request_stall;

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
            .cmd_user           (loc_user[1:0]),         // Templated
            .cmd_err            (loc_err[1:0]),          // Templated
            .cmd_ex             (loc_ex),                // Templated
            .cmd_hostid         (loc_hostid[4:0]),       // Templated
            .cmd_user_extended  (loc_user_extended[23:0])); // Templated

   // Response pipeline
   // If a request was accepted the local device will respond the next cycle
   // When response ready is de-asserted need to latch the response and block
   // additional requests
   always @(posedge clk or negedge nreset)
     if (!nreset)
       loc_resp_vld <= 1'b0;
     else
       loc_resp_vld <= loc_resp & loc_ready & ~request_stall;

   always @ (posedge clk or negedge nreset)
     if (!nreset)
       begin
          loc_cmd_out[CW-1:0]     <= {CW{1'b0}};
          loc_dstaddr_out[AW-1:0] <= {AW{1'b0}};
          loc_srcaddr_out[AW-1:0] <= {AW{1'b0}};
       end
     else if (loc_resp & loc_ready & ~request_stall)
       begin
          loc_cmd_out[CW-1:0]     <= packet_cmd[CW-1:0];
          loc_dstaddr_out[AW-1:0] <= udev_req_srcaddr[AW-1:0];
          loc_srcaddr_out[AW-1:0] <= loc_addr[AW-1:0];
       end

   // Data storage in case ready is low (at the response cycle)
   always @(posedge clk or negedge nreset)
     if (!nreset)
       loc_data_keep[DW-1:0] <= {DW{1'b0}};
     else if (loc_resp_vld)
       loc_data_keep[DW-1:0] <= loc_rddata[DW-1:0];

   // Valid set-clear
   always @(posedge clk or negedge nreset)
     if (!nreset)
       loc_vld_keep <= 1'b0;
     else if (loc_resp_vld & ~udev_resp_ready)
       loc_vld_keep <= 1'b1;
     else if (udev_resp_ready)
       loc_vld_keep <= 1'b0;

   assign loc_vld_out = loc_resp_vld | loc_vld_keep;

   assign loc_data_out[DW-1:0] = loc_resp_vld ? loc_rddata[DW-1:0] : loc_data_keep[DW-1:0];

   assign request_stall = (REG) ?
                          (vld_pipe | loc_vld_out) & ~udev_resp_ready :
                          loc_vld_out & ~udev_resp_ready;

   // Additional pipe stage based on (REG)
   always @(posedge clk or negedge nreset)
     if (!nreset)
       begin
          vld_pipe             <= 1'b0;
          cmd_pipe[CW-1:0]     <= {CW{1'b0}};
          dstaddr_pipe[AW-1:0] <= {AW{1'b0}};
          srcaddr_pipe[AW-1:0] <= {AW{1'b0}};
          data_pipe[DW-1:0]    <= {DW{1'b0}};
       end
     else if (udev_resp_ready)
       begin
          vld_pipe             <= loc_vld_out;
          cmd_pipe[CW-1:0]     <= loc_cmd_out[CW-1:0];
          dstaddr_pipe[AW-1:0] <= loc_dstaddr_out[AW-1:0];
          srcaddr_pipe[AW-1:0] <= loc_srcaddr_out[AW-1:0];
          data_pipe[DW-1:0]    <= loc_data_out[DW-1:0];
       end

   // Final outputs
   assign udev_resp_valid           = (REG) ? vld_pipe     : loc_vld_out;
   assign udev_resp_cmd[CW-1:0]     = (REG) ? cmd_pipe     : loc_cmd_out;
   assign udev_resp_dstaddr[AW-1:0] = (REG) ? dstaddr_pipe : loc_dstaddr_out;
   assign udev_resp_srcaddr[AW-1:0] = (REG) ? srcaddr_pipe : loc_srcaddr_out;
   assign udev_resp_data[DW-1:0]    = (REG) ? data_pipe    : loc_data_out;

`ifndef SYNTHESIS
   // Poor man's coverage points
   wire req_no_rdy = (loc_read | loc_write) & ~request_stall & ~udev_resp_ready;
   wire resp_no_rdy = loc_resp_vld & ~udev_resp_ready;
   wire b2b = (loc_read | loc_write) & ~request_stall & loc_resp_vld;
   wire b2b_stall = (loc_read | loc_write) & request_stall & loc_resp_vld;
`endif

endmodule // umi_endpoint
// Local Variables:
// verilog-library-directories:("." "../../submodules/lambdalib/stdlib/rtl")
// End:
