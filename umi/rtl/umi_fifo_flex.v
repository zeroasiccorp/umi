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
 * - Converts UMI transactions between different width options.
 *
 * Future enhancements:
 * 1. do not split large->small transactions in case they carry no data
 *
 * Known limitation/bugs:
 * - Does not handle cases where SIZE>ODW (does not manipulate SIZE)
 * - When ODW>IDW, incoming transaction is merged only if merged transaction
 *   does not cross ODW boundary (num_merged_bits + IDW)<=ODW
 *
 ******************************************************************************/

module umi_fifo_flex
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter ASYNC = 0,
    parameter SPLIT = 0,
    parameter DEPTH = 4,          // FIFO depth
    parameter CW = 32,            // UMI width
    parameter AW = 64,            // input UMI AW
    parameter IDW = 512,          // input UMI DW
    parameter ODW = 512           // input UMI DW
    )
   (// control/status signals
    input            bypass,       // bypass FIFO
    input            chaosmode,    // enable "random" fifo pushback
    output           fifo_full,
    output           fifo_empty,
    // Input
    input            umi_in_clk,
    input            umi_in_nreset,
    input            umi_in_valid, //per byte valid signal
    input [CW-1:0]   umi_in_cmd,
    input [AW-1:0]   umi_in_dstaddr,
    input [AW-1:0]   umi_in_srcaddr,
    input [IDW-1:0]  umi_in_data,
    output           umi_in_ready,
    // Output
    input            umi_out_clk,
    input            umi_out_nreset,
    output           umi_out_valid,
    output [CW-1:0]  umi_out_cmd,
    output [AW-1:0]  umi_out_dstaddr,
    output [AW-1:0]  umi_out_srcaddr,
    output [ODW-1:0] umi_out_data,
    input            umi_out_ready,
    // Supplies
    input            vdd,
    input            vss
    );

   // Local FIFO
   wire [ODW+AW+AW+CW-1:0] fifo_dout;
   wire [ODW+AW+AW+CW-1:0] fifo_din;
   wire                    fifo_full_raw;
   wire                    fifo_empty_raw;
   wire                    fifo_read;
   wire                    fifo_write;

   // Split/merge packet latch
   reg                     packet_latch_valid;
   wire                    packet_latch_en;
   reg [CW-1:0]            packet_cmd_latch;
   reg [AW-1:0]            packet_dstaddr_latch;
   reg [AW-1:0]            packet_srcaddr_latch;
   wire [CW-1:0]           packet_cmd;
   wire [AW-1:0]           latch_dstaddr;
   wire [AW-1:0]           latch_srcaddr;
   wire [IDW-1:0]          latch_data;

   localparam MAX_DW = (ODW > IDW) ? ODW : IDW;

   // Split/merge to fifo
   wire [AW-1:0]           latch2fifo_dstaddr;
   wire [AW-1:0]           latch2fifo_srcaddr;
   wire [MAX_DW-1:0]       latch2fifo_data;
   wire [7:0]              latch2fifo_len;
   wire                    latch2fifo_eom;
   wire                    latch2fifo_valid;
   wire                    latch2fifo_ready;
   wire                    latch2in_ready;

   // local wires
   wire                    umi_out_beat;
   wire                    fifo_in_ready;
   wire [7:0]              latch_len;
   wire [8:0]              cmd_len_plus_one;
   wire                    fifo_out_of_reset;
   wire [AW-1:0]           addr_mask;
   wire [AW-1:0]           dstaddr_masked;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           cmd_atype;
   wire                 cmd_eof;
   wire                 cmd_eom;
   wire [1:0]           cmd_err;
   wire                 cmd_ex;
   wire [4:0]           cmd_hostid;
   wire [7:0]           cmd_len;
   wire [4:0]           cmd_opcode;
   wire [1:0]           cmd_prot;
   wire [3:0]           cmd_qos;
   wire [2:0]           cmd_size;
   wire [1:0]           cmd_user;
   wire [23:0]          cmd_user_extended;
   wire [CW-1:0]        latch2fifo_cmd;
   wire [CW-1:0]        latch_cmd;
   // End of automatics

   //#################################
   // Input decoding
   //#################################
   wire [4:0]           umi_in_cmd_opcode;
   wire [2:0]           umi_in_cmd_size;
   wire [7:0]           umi_in_cmd_len;
   wire [7:0]           umi_in_cmd_atype;
   wire [3:0]           umi_in_cmd_qos;
   wire [1:0]           umi_in_cmd_prot;
   wire                 umi_in_cmd_eom;
   wire                 umi_in_cmd_eof;
   wire                 umi_in_cmd_ex;
   wire [1:0]           umi_in_cmd_user;
   wire [23:0]          umi_in_cmd_user_extended;
   wire [1:0]           umi_in_cmd_err;
   wire [4:0]           umi_in_cmd_hostid;

   umi_unpack #(.CW(CW))
   umi_unpack_i(
                // Outputs
                .cmd_opcode         (umi_in_cmd_opcode[4:0]),
                .cmd_size           (umi_in_cmd_size[2:0]),
                .cmd_len            (umi_in_cmd_len[7:0]),
                .cmd_atype          (umi_in_cmd_atype[7:0]),
                .cmd_qos            (umi_in_cmd_qos[3:0]),
                .cmd_prot           (umi_in_cmd_prot[1:0]),
                .cmd_eom            (umi_in_cmd_eom),
                .cmd_eof            (umi_in_cmd_eof),
                .cmd_ex             (umi_in_cmd_ex),
                .cmd_user           (umi_in_cmd_user[1:0]),
                .cmd_user_extended  (umi_in_cmd_user_extended[23:0]),
                .cmd_err            (umi_in_cmd_err[1:0]),
                .cmd_hostid         (umi_in_cmd_hostid[4:0]),
                // Inputs
                .packet_cmd         (umi_in_cmd[CW-1:0]));

   wire                 umi_in_cmd_invalid;

   wire                 umi_in_cmd_request;
   wire                 umi_in_cmd_response;

   wire                 umi_in_cmd_read;
   wire                 umi_in_cmd_write;

   wire                 umi_in_cmd_write_posted;
   wire                 umi_in_cmd_rdma;
   wire                 umi_in_cmd_atomic;
   wire                 umi_in_cmd_user0;
   wire                 umi_in_cmd_future0;
   wire                 umi_in_cmd_error;
   wire                 umi_in_cmd_link;

   wire                 umi_in_cmd_read_resp;
   wire                 umi_in_cmd_write_resp;
   wire                 umi_in_cmd_user0_resp;
   wire                 umi_in_cmd_user1_resp;
   wire                 umi_in_cmd_future0_resp;
   wire                 umi_in_cmd_future1_resp;
   wire                 umi_in_cmd_link_resp;

   wire                 umi_in_cmd_atomic_add;
   wire                 umi_in_cmd_atomic_and;
   wire                 umi_in_cmd_atomic_or;
   wire                 umi_in_cmd_atomic_xor;
   wire                 umi_in_cmd_atomic_max;
   wire                 umi_in_cmd_atomic_min;
   wire                 umi_in_cmd_atomic_maxu;
   wire                 umi_in_cmd_atomic_minu;
   wire                 umi_in_cmd_atomic_swap;

   umi_decode #(.CW(CW))
   umi_decode_i(
                // Packet Command
                .command            (umi_in_cmd[CW-1:0]),
                .cmd_invalid        (umi_in_cmd_invalid),
                // request/response/link
                .cmd_request        (umi_in_cmd_request),
                .cmd_response       (umi_in_cmd_response),
                // requests
                .cmd_read           (umi_in_cmd_read),
                .cmd_write          (umi_in_cmd_write),
                .cmd_write_posted   (umi_in_cmd_write_posted),
                .cmd_rdma           (umi_in_cmd_rdma),
                .cmd_atomic         (umi_in_cmd_atomic),
                .cmd_user0          (umi_in_cmd_user0),
                .cmd_future0        (umi_in_cmd_future0),
                .cmd_error          (umi_in_cmd_error),
                .cmd_link           (umi_in_cmd_link),
                // Response (device -> host)
                .cmd_read_resp      (umi_in_cmd_read_resp),
                .cmd_write_resp     (umi_in_cmd_write_resp),
                .cmd_user0_resp     (umi_in_cmd_user0_resp),
                .cmd_user1_resp     (umi_in_cmd_user1_resp),
                .cmd_future0_resp   (umi_in_cmd_future0_resp),
                .cmd_future1_resp   (umi_in_cmd_future1_resp),
                .cmd_link_resp      (umi_in_cmd_link_resp),
                // Atomic operations
                .cmd_atomic_add     (umi_in_cmd_atomic_add),
                .cmd_atomic_and     (umi_in_cmd_atomic_and),
                .cmd_atomic_or      (umi_in_cmd_atomic_or),
                .cmd_atomic_xor     (umi_in_cmd_atomic_xor),
                .cmd_atomic_max     (umi_in_cmd_atomic_max),
                .cmd_atomic_min     (umi_in_cmd_atomic_min),
                .cmd_atomic_maxu    (umi_in_cmd_atomic_maxu),
                .cmd_atomic_minu    (umi_in_cmd_atomic_minu),
                .cmd_atomic_swap    (umi_in_cmd_atomic_swap));

   //#################################
   // Packet manipulation
   //#################################
   umi_unpack #(.CW(CW))
   umi_unpack_packet(/*AUTOINST*/
                // Outputs
                .cmd_opcode     (cmd_opcode[4:0]),
                .cmd_size       (cmd_size[2:0]),
                .cmd_len        (cmd_len[7:0]),
                .cmd_atype      (cmd_atype[7:0]),
                .cmd_qos        (cmd_qos[3:0]),
                .cmd_prot       (cmd_prot[1:0]),
                .cmd_eom        (cmd_eom),
                .cmd_eof        (cmd_eof),
                .cmd_ex         (cmd_ex),
                .cmd_user       (cmd_user[1:0]),
                .cmd_user_extended(cmd_user_extended[23:0]),
                .cmd_err        (cmd_err[1:0]),
                .cmd_hostid     (cmd_hostid[4:0]),
                // Inputs
                .packet_cmd     (packet_cmd[CW-1:0]));

   // Valid will be set when the current command (from latch or new) is bigger than the output bus
   assign cmd_len_plus_one[8:0] = cmd_len[7:0] + 8'h01;

   // cmd manipulation - at each cycle need to remove the bytes sent out
   // SPLIT will also split based on crossing DW boundary and not only size

   generate if (ODW > IDW)
     begin

        reg  [ODW-1:0]  packet_data_latch;

        //#################################
        // Merged byte counter
        //#################################
        reg  [8:0]      latch_bytes;
        wire [8:0]      latch_in_bytes;
        wire [8:0]      latch_out_bytes;

        wire [ODW-1:0]  umi_in_data_shifted;

        assign latch_in_bytes = ((umi_in_cmd_len + 8'h01) << umi_in_cmd_size);

        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
               latch_bytes <= 'b0;
          else if (umi_in_valid & umi_in_ready & fifo_write)
               latch_bytes <= latch_in_bytes;
           else if (umi_in_valid & umi_in_ready)
               latch_bytes <= latch_bytes + latch_in_bytes;
          else if (fifo_write)
               latch_bytes <= 'b0;

        //#################################
        // Check Mergeability
        //#################################
        wire            opcode_mergeable;
        wire            misc_mergeable;
        wire            dstaddr_mergeable;
        wire            srcaddr_mergeable;
        wire            len_mergeable;
        wire            tx_mergeable;

        // Check opcode type and ensure opcode match across cycles
        assign opcode_mergeable = (umi_in_cmd_read | umi_in_cmd_write |
                                  umi_in_cmd_write_posted | umi_in_cmd_rdma |
                                  umi_in_cmd_read_resp | umi_in_cmd_write_resp) &
                                  !umi_in_cmd_ex & (umi_in_cmd_opcode == cmd_opcode);

        assign misc_mergeable = (umi_in_cmd_size == cmd_size) &
                                (umi_in_cmd_qos == cmd_qos) &
                                (umi_in_cmd_prot == cmd_prot) &
                                (umi_in_cmd_eof == cmd_eof) &
                                (umi_in_cmd_user == cmd_user) &
                                (umi_in_cmd_err == cmd_err) &
                                (umi_in_cmd_hostid == cmd_hostid);

        assign dstaddr_mergeable = (umi_in_dstaddr == (packet_dstaddr_latch + {{(AW-9){1'b0}}, latch_bytes}));
        assign srcaddr_mergeable = (umi_in_srcaddr == (packet_srcaddr_latch + {{(AW-9){1'b0}}, latch_bytes})) |
                                   umi_in_cmd_response;
        assign len_mergeable = (latch_bytes + latch_in_bytes) <= (ODW >> 3);

        assign tx_mergeable = opcode_mergeable & misc_mergeable &
                              dstaddr_mergeable & srcaddr_mergeable &
                              len_mergeable;

        reg             packet_latch_eom;
        wire            packet_boundary;
        reg             packet_boundary_latch;

        assign packet_cmd[CW-1:0] = packet_latch_valid ?
                                    packet_cmd_latch[CW-1:0] :
                                    umi_in_cmd[CW-1:0] & {CW{umi_in_valid}};

        // Fifo signal - current command going out
        assign latch2fifo_dstaddr = packet_dstaddr_latch;
        assign latch2fifo_srcaddr = packet_srcaddr_latch;
        assign latch2fifo_data    = packet_data_latch;
        // cmd manipulation - at each cycle need to remove the bytes sent out
        assign latch2fifo_eom     = packet_latch_eom;
        /* verilator lint_off WIDTHTRUNC */
        assign latch2fifo_len     = (latch_bytes >> cmd_size) - 8'h1;
        /* verilator lint_on WIDTHTRUNC */
        assign latch2fifo_valid   = (packet_boundary | packet_boundary_latch) & (latch_bytes > 0);
        assign latch2fifo_ready   = (tx_mergeable & !packet_latch_eom) |
                                    (tx_mergeable & packet_latch_eom & (latch_bytes == 0)) |
                                    (!tx_mergeable & (latch_bytes == 0));
        assign latch2in_ready     = latch2fifo_ready;

        // Latched command for next split
        // Unused for merge
        assign latch_dstaddr = 'b0;
        assign latch_srcaddr = 'b0;
        assign latch_data    = 'b0;
        assign latch_len     = 'b0;

        assign packet_boundary    = packet_latch_eom | !tx_mergeable | !umi_in_valid;
        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
            packet_boundary_latch <= 1'b1;
          else if (umi_in_valid & umi_in_ready)
            packet_boundary_latch <= 1'b0;
          else if (packet_boundary)
            packet_boundary_latch <= 1'b1;

        // Packet latch
        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
            begin
               packet_latch_valid   <= 1'b0;
               packet_dstaddr_latch <= {AW{1'b0}};
               packet_srcaddr_latch <= {AW{1'b0}};
            end
          else if ((umi_in_ready & umi_in_valid) & (packet_boundary | fifo_write))
            begin
               packet_latch_valid   <= 1'b1;
               packet_dstaddr_latch <= umi_in_dstaddr;
               packet_srcaddr_latch <= umi_in_srcaddr;
            end
          else if (fifo_write)
            begin
               packet_latch_valid   <= 1'b0;
            end

        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
            packet_cmd_latch     <= {CW{1'b0}};
          else if (umi_in_ready & umi_in_valid)
            packet_cmd_latch     <= latch_cmd;

        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
            packet_latch_eom     <= 1'b1;
          else if (umi_in_ready & umi_in_valid)
            packet_latch_eom     <= umi_in_cmd_eom;

        // NOTE: Here, the correct shift would be
        // (latch_bytes - latch_out_bytes) << 3
        // However, if latch_out_bytes is non zero then the first 'else if'
        // in the always block will be hit and umi_in_data_shifted will not
        // be used. So to simplify we can use (latch_bytes << 3).
        /* verilator lint_off WIDTHEXPAND */
        assign umi_in_data_shifted = umi_in_data << (latch_bytes << 3);
        /* verilator lint_on WIDTHEXPAND */

        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
               packet_data_latch    <= {ODW{1'b0}};
          else if ((umi_in_ready & umi_in_valid) & (packet_boundary | fifo_write))
               packet_data_latch    <= {{ODW-IDW{1'b0}}, umi_in_data};
          else if (umi_in_ready & umi_in_valid)
               packet_data_latch    <= packet_data_latch | umi_in_data_shifted;

     end
   else if (SPLIT == 1)
     begin
        reg  [IDW-1:0]  packet_data_latch;

        assign addr_mask[AW-1:0] = {{AW-$clog2(ODW/8){1'b0}},{$clog2(ODW/8){1'b1}}};
        assign dstaddr_masked[AW-1:0] = latch2fifo_dstaddr[AW-1:0] & addr_mask[AW-1:0];
        assign packet_latch_en = (cmd_len_plus_one + (dstaddr_masked[9:0] >> cmd_size)) >
                                 (ODW >> cmd_size >> 3);

        assign packet_cmd[CW-1:0] = packet_latch_valid ?
                                    packet_cmd_latch[CW-1:0] :
                                    umi_in_cmd[CW-1:0] & {CW{umi_in_valid}};

        // Fifo signal - current command going out
        assign latch2fifo_dstaddr = packet_latch_valid ? packet_dstaddr_latch : umi_in_dstaddr;
        assign latch2fifo_srcaddr = packet_latch_valid ? packet_srcaddr_latch : umi_in_srcaddr;
        assign latch2fifo_data    = packet_latch_valid ? packet_data_latch    : umi_in_data;
        // cmd manipulation - at each cycle need to remove the bytes sent out
        assign latch2fifo_eom     = packet_latch_en    ? 1'b0                 : cmd_eom;
        assign latch2fifo_len     = packet_latch_en    ?
                              (((ODW[10:3]) - dstaddr_masked[7:0]) >> cmd_size) - 1'b1 :
                              cmd_len[7:0];
        assign latch2fifo_valid   = umi_in_valid | packet_latch_valid;
        assign latch2fifo_ready   = ~packet_latch_valid;
        assign latch2in_ready     = ~packet_latch_valid & umi_out_ready;

        // Latched command for next split
        assign latch_dstaddr = latch2fifo_dstaddr + ((ODW/8) - dstaddr_masked[AW-1:0]);
        assign latch_srcaddr = latch2fifo_srcaddr + ((ODW/8) - dstaddr_masked[AW-1:0]);
        assign latch_data    = latch2fifo_data >> (ODW - (dstaddr_masked[9:0] << 3));
        assign latch_len     = cmd_len -
                               ((ODW[10:3] - dstaddr_masked[7:0]) >> cmd_size);

        // Packet latch
        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
            begin
               packet_latch_valid   <= 1'b0;
               packet_cmd_latch     <= {CW{1'b0}};
               packet_dstaddr_latch <= {AW{1'b0}};
               packet_srcaddr_latch <= {AW{1'b0}};
               packet_data_latch    <= {IDW{1'b0}};
            end
          else if (fifo_write)
            begin
               packet_latch_valid   <= packet_latch_en;
               packet_cmd_latch     <= latch_cmd;
               packet_dstaddr_latch <= latch_dstaddr;
               packet_srcaddr_latch <= latch_srcaddr;
               packet_data_latch    <= latch_data;
            end
     end
   else
     begin // split only based on (LEN-1)*(2^SIZE) > DW
        reg  [IDW-1:0]  packet_data_latch;

        assign packet_latch_en = cmd_len_plus_one > (ODW[11:3] >> cmd_size);

        assign packet_cmd[CW-1:0] = packet_latch_valid ?
                                    packet_cmd_latch[CW-1:0] :
                                    umi_in_cmd[CW-1:0] & {CW{umi_in_valid}};

        // Fifo signal - current command going out
        assign latch2fifo_dstaddr = packet_latch_valid ? packet_dstaddr_latch : umi_in_dstaddr;
        assign latch2fifo_srcaddr = packet_latch_valid ? packet_srcaddr_latch : umi_in_srcaddr;
        assign latch2fifo_data    = packet_latch_valid ? packet_data_latch    : umi_in_data;
        // cmd manipulation - at each cycle need to remove the bytes sent out
        assign latch2fifo_eom     = packet_latch_en    ? 1'b0                            : cmd_eom;
        assign latch2fifo_len     = packet_latch_en    ? ((ODW[10:3] >> cmd_size) - 1'b1) : cmd_len;
        assign latch2fifo_valid   = umi_in_valid | packet_latch_valid;
        assign latch2fifo_ready   = ~packet_latch_valid;
        assign latch2in_ready     = ~packet_latch_valid & umi_out_ready;

        // Latched command for next split
        assign latch_dstaddr = latch2fifo_dstaddr + (ODW/8);
        assign latch_srcaddr = latch2fifo_srcaddr + (ODW/8);
        assign latch_data    = latch2fifo_data >> ODW;
        assign latch_len     = cmd_len - (ODW[10:3] >> cmd_size);

        // Packet latch
        always @(posedge umi_in_clk or negedge umi_in_nreset)
          if (~umi_in_nreset)
            begin
               packet_latch_valid   <= 1'b0;
               packet_cmd_latch     <= {CW{1'b0}};
               packet_dstaddr_latch <= {AW{1'b0}};
               packet_srcaddr_latch <= {AW{1'b0}};
               packet_data_latch    <= {IDW{1'b0}};
            end
          else if (fifo_write)
            begin
               packet_latch_valid   <= packet_latch_en;
               packet_cmd_latch     <= latch_cmd;
               packet_dstaddr_latch <= latch_dstaddr;
               packet_srcaddr_latch <= latch_srcaddr;
               packet_data_latch    <= latch_data;
            end
     end
   endgenerate

   /* umi_pack AUTO_TEMPLATE(
    .packet_cmd (latch_cmd[]),
    .cmd_len    (latch_len),
    );*/

   umi_pack #(.CW(CW))
   umi_pack_latch(/*AUTOINST*/
                  // Outputs
                  .packet_cmd           (latch_cmd[CW-1:0]),     // Templated
                  // Inputs
                  .cmd_opcode           (cmd_opcode[4:0]),
                  .cmd_size             (cmd_size[2:0]),
                  .cmd_len              (latch_len),             // Templated
                  .cmd_atype            (cmd_atype[7:0]),
                  .cmd_prot             (cmd_prot[1:0]),
                  .cmd_qos              (cmd_qos[3:0]),
                  .cmd_eom              (cmd_eom),
                  .cmd_eof              (cmd_eof),
                  .cmd_user             (cmd_user[1:0]),
                  .cmd_err              (cmd_err[1:0]),
                  .cmd_ex               (cmd_ex),
                  .cmd_hostid           (cmd_hostid[4:0]),
                  .cmd_user_extended    (cmd_user_extended[23:0]));

   /* umi_pack AUTO_TEMPLATE(
    .packet_cmd (latch2fifo_cmd[]),
    .cmd_len    (latch2fifo_len),
    .cmd_eom    (latch2fifo_eom),
    );*/

   umi_pack #(.CW(CW))
   umi_pack_fifo(/*AUTOINST*/
                 // Outputs
                 .packet_cmd            (latch2fifo_cmd[CW-1:0]),      // Templated
                 // Inputs
                 .cmd_opcode            (cmd_opcode[4:0]),
                 .cmd_size              (cmd_size[2:0]),
                 .cmd_len               (latch2fifo_len),              // Templated
                 .cmd_atype             (cmd_atype[7:0]),
                 .cmd_prot              (cmd_prot[1:0]),
                 .cmd_qos               (cmd_qos[3:0]),
                 .cmd_eom               (latch2fifo_eom),              // Templated
                 .cmd_eof               (cmd_eof),
                 .cmd_user              (cmd_user[1:0]),
                 .cmd_err               (cmd_err[1:0]),
                 .cmd_ex                (cmd_ex),
                 .cmd_hostid            (cmd_hostid[4:0]),
                 .cmd_user_extended     (cmd_user_extended[23:0]));

   // Read FIFO when ready (blocked inside fifo when empty)
   assign fifo_read = ~fifo_empty & umi_out_ready;

   // Write fifo when high (blocked inside fifo when full)
   assign fifo_write = ~fifo_full & fifo_out_of_reset & latch2fifo_valid;

   // FIFO pushback
   assign fifo_in_ready = ~fifo_full & latch2fifo_ready;

   assign fifo_din[AW+AW+CW+:ODW] = latch2fifo_data[ODW-1:0];

   assign fifo_din[AW+CW+:AW]     = latch2fifo_srcaddr[AW-1:0];
   assign fifo_din[CW+:AW]        = latch2fifo_dstaddr[AW-1:0];
   assign fifo_din[0+:CW]         = latch2fifo_cmd[CW-1:0];

   //#################################
   // Standard Dual Clock FIFO
   //#################################
   generate if (|ASYNC)
     begin
        la_asyncfifo  #(.DW(CW+AW+AW+ODW),
                        .DEPTH(DEPTH))
        fifo  (// Outputs
               .wr_full      (fifo_full_raw),
               .rd_dout      (fifo_dout[ODW+AW+AW+CW-1:0]),
               .rd_empty     (fifo_empty_raw),
               // Inputs
               .wr_clk       (umi_in_clk),
               .wr_nreset    (umi_in_nreset),
               .wr_din       (fifo_din[ODW+AW+AW+CW-1:0]),
               .wr_en        (fifo_write),
               .wr_chaosmode (chaosmode),
               .rd_clk       (umi_out_clk),
               .rd_nreset    (umi_out_nreset),
               .rd_en        (fifo_read),
               .vss          (vss),
               .vdd          (vdd),
               .ctrl         (1'b0),
               .test         (1'b0));
     end
   else if (|DEPTH)
     begin
        la_syncfifo  #(.DW(CW+AW+AW+ODW),
                       .DEPTH(DEPTH))
        fifo  (// Outputs
               .wr_full      (fifo_full_raw),
               .rd_dout      (fifo_dout[ODW+AW+AW+CW-1:0]),
               .rd_empty     (fifo_empty_raw),
               // Inputs
               .clk          (umi_in_clk),
               .nreset       (umi_in_nreset),
               .wr_din       (fifo_din[ODW+AW+AW+CW-1:0]),
               .wr_en        (fifo_write),
               .chaosmode    (chaosmode),
               .rd_en        (fifo_read),
               .vss          (vss),
               .vdd          (vdd),
               .ctrl         (1'b0),
               .test         (1'b0));
     end
   else
     begin
        assign fifo_full_raw  = 'b0;
        assign fifo_empty_raw = 'b0;
        assign fifo_dout      = 'b0;
     end
   endgenerate

   la_drsync la_drsync_i (
       .clk     (umi_in_clk),
       .nreset  (umi_in_nreset),
       .in      (1'b1),
       .out     (fifo_out_of_reset)
   );

   //#################################
   // FIFO Bypass
   //#################################

   assign fifo_full               = (bypass | ~(|DEPTH)) ? ~umi_out_ready       : fifo_full_raw;
   assign fifo_empty              = (bypass | ~(|DEPTH)) ? 1'b1                 : fifo_empty_raw;

   assign umi_out_cmd[CW-1:0]     = (bypass | ~(|DEPTH)) ? latch2fifo_cmd[CW-1:0]     : fifo_dout[CW-1:0];
   assign umi_out_dstaddr[AW-1:0] = (bypass | ~(|DEPTH)) ? latch2fifo_dstaddr[AW-1:0] : fifo_dout[CW+:AW] & 64'hFFFF_FFFF_FFFF_FFFF;
   assign umi_out_srcaddr[AW-1:0] = (bypass | ~(|DEPTH)) ? latch2fifo_srcaddr[AW-1:0] : fifo_dout[CW+AW+:AW];
   assign umi_out_data[ODW-1:0]   = (bypass | ~(|DEPTH)) ? latch2fifo_data[ODW-1:0] : fifo_dout[CW+AW+AW+:ODW];

   assign umi_out_valid           = ~fifo_out_of_reset ? 1'b0 :
                                    (bypass | ~(|DEPTH)) ? latch2fifo_valid : ~fifo_empty;
   assign umi_in_ready            = ~fifo_out_of_reset ? 1'b0 :
                                    (bypass | ~(|DEPTH)) ? latch2in_ready : fifo_in_ready;

   // debug signals
   assign umi_out_beat = umi_out_valid & umi_out_ready;

endmodule // clink_fifo
// Local Variables:
// verilog-library-directories:(".")
// End:
