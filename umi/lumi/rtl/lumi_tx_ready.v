/*******************************************************************************
 * Copyright 2023 Zero ASIC Corporation
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
 * - LUMI Transmit module
 *
 ******************************************************************************/

module lumi_tx_ready
  #(parameter TARGET = "DEFAULT", // implementation target
    // for development only (fixed )
    parameter IOW = 64,           // Lumi rx/tx width (SDR only, DDR is handled in the phy)
    parameter DW = 128,           // umi data width
    parameter CW = 32,            // umi data width
    parameter AW = 64             // address width
    )
   (// ctrl signls
    input             clk,         // clock for driving output data
    input             nreset,      // clk synced async active low reset
    input             csr_en,      // 1=enable outputs
    input [7:0]       csr_iowidth, // bus width
    input             vss,         // common ground
    input             vdd,         // core supply
    // Request (read/write)
    input             umi_req_in_valid,
    input [CW-1:0]    umi_req_in_cmd,
    input [AW-1:0]    umi_req_in_dstaddr,
    input [AW-1:0]    umi_req_in_srcaddr,
    input [DW-1:0]    umi_req_in_data,
    output            umi_req_in_ready,
    // Response (write)
    input             umi_resp_in_valid,
    input [CW-1:0]    umi_resp_in_cmd,
    input [AW-1:0]    umi_resp_in_dstaddr,
    input [AW-1:0]    umi_resp_in_srcaddr,
    input [DW-1:0]    umi_resp_in_data,
    output            umi_resp_in_ready,
    // phy interface
    output [IOW-1:0]  phy_txdata,  // Tx data to the phy
    output            phy_txvld,   // valid signal to the phy
    input             phy_txrdy,
    input             ioclk,
    input             ionreset
    );

    // local state
    reg  [2*DW+AW+AW+CW-1:0]                shiftreg;
    wire [2*DW+AW+AW+CW-1:0]                shiftreg_in;
    wire [2*DW+AW+AW+CW-1:0]                shiftreg_in_new;
    reg  [$clog2((2*DW+AW+AW+CW)/8)-1:0]    num_bytes;
    wire [$clog2((2*DW+AW+AW+CW)/8)-1:0]    num_bytes_start_value;
    wire [$clog2((2*DW+AW+AW+CW)/8)-1:0]    num_bytes_next;

    //########################################
    //# CTRL MODES
    //########################################
    wire [10:0]     iowidth;
    // Amir - byterate is used later as shifted 3 bits to the left so needs 3 more bits than the "pure" value
    wire [13:0]     byterate;

    // shift left size is the width of the operand so need to reserve space for shifts
    assign iowidth[10:0] = 11'h1 << csr_iowidth[7:0];

    // Bytes transferred per cycle
    assign byterate = {3'b0,iowidth[10:0]};

    //########################################
    //# UMI Transmit Arbiter
    //########################################
    wire            umi_out_valid;
    wire [CW-1:0]   umi_out_cmd;
    wire [AW-1:0]   umi_out_dstaddr;
    wire [AW-1:0]   umi_out_srcaddr;
    wire [DW-1:0]   umi_out_data;
    wire            umi_out_ready;

    umi_mux #(
        .DW(DW),
        .CW(CW),
        .AW(AW),
        .N(2)
    ) umi_mux (
        .clk            (clk),
        .nreset         (nreset),

        .arbmode        (2'b00),
        .arbmask        ({2{1'b0}}),

        .umi_in_valid   ({umi_req_in_valid,umi_resp_in_valid}),
        .umi_in_cmd     ({umi_req_in_cmd,umi_resp_in_cmd}),
        .umi_in_dstaddr ({umi_req_in_dstaddr,umi_resp_in_dstaddr}),
        .umi_in_srcaddr ({umi_req_in_srcaddr,umi_resp_in_srcaddr}),
        .umi_in_data    ({umi_req_in_data,umi_resp_in_data}),
        .umi_in_ready   ({umi_req_in_ready,umi_resp_in_ready}),

        .umi_out_valid  (umi_out_valid),
        .umi_out_cmd    (umi_out_cmd[CW-1:0]),
        .umi_out_dstaddr(umi_out_dstaddr[AW-1:0]),
        .umi_out_srcaddr(umi_out_srcaddr[AW-1:0]),
        .umi_out_data   (umi_out_data[DW-1:0]),
        .umi_out_ready  (umi_out_ready)
    );

    //########################################
    //# Transaction being transmitted
    //########################################
    reg [CW-1:0]    umi_out_cmd_r;
    reg [AW-1:0]    umi_out_dstaddr_r;
    reg [AW-1:0]    umi_out_srcaddr_r;

    always @(posedge clk or negedge nreset)
        if (umi_out_valid & umi_out_ready)
            umi_out_cmd_r <= umi_out_cmd;

    always @(posedge clk or negedge nreset)
        if (umi_out_valid & umi_out_ready)
            umi_out_dstaddr_r <= umi_out_dstaddr;

    always @(posedge clk or negedge nreset)
        if (umi_out_valid & umi_out_ready)
            umi_out_srcaddr_r <= umi_out_srcaddr;

    wire [4:0]      umi_out_cmd_opcode;
    wire [2:0]      umi_out_cmd_size;
    wire [7:0]      umi_out_cmd_len;
    wire [7:0]      umi_out_cmd_atype;
    wire [3:0]      umi_out_cmd_qos;
    wire [1:0]      umi_out_cmd_prot;
    wire            umi_out_cmd_eom;
    wire            umi_out_cmd_eof;
    wire            umi_out_cmd_ex;
    wire [1:0]      umi_out_cmd_user;
    wire [23:0]     umi_out_cmd_user_extended;
    wire [1:0]      umi_out_cmd_err;
    wire [4:0]      umi_out_cmd_hostid;

    wire [11:0]     umi_out_cmd_lenp1;
    wire [11:0]     umi_out_cmd_bytes;

    umi_unpack #(
        .CW(CW)
    ) umi_unpack_arb (
        // Outputs
        .cmd_opcode         (umi_out_cmd_opcode[4:0]),
        .cmd_size           (umi_out_cmd_size[2:0]),
        .cmd_len            (umi_out_cmd_len[7:0]),
        .cmd_atype          (umi_out_cmd_atype[7:0]),
        .cmd_qos            (umi_out_cmd_qos[3:0]),
        .cmd_prot           (umi_out_cmd_prot[1:0]),
        .cmd_eom            (umi_out_cmd_eom),
        .cmd_eof            (umi_out_cmd_eof),
        .cmd_ex             (umi_out_cmd_ex),
        .cmd_user           (umi_out_cmd_user[1:0]),
        .cmd_user_extended  (umi_out_cmd_user_extended[23:0]),
        .cmd_err            (umi_out_cmd_err[1:0]),
        .cmd_hostid         (umi_out_cmd_hostid[4:0]),
        // Inputs
        .packet_cmd         (umi_out_cmd_r[CW-1:0])
    );

    assign umi_out_cmd_lenp1 = {4'h0, umi_out_cmd_len} + 12'b1;
    assign umi_out_cmd_bytes = umi_out_cmd_lenp1 << umi_out_cmd_size;

    wire            umi_out_cmd_invalid;

    wire            umi_out_cmd_request;
    wire            umi_out_cmd_response;

    wire            umi_out_cmd_read;
    wire            umi_out_cmd_write;

    wire            umi_out_cmd_write_posted;
    wire            umi_out_cmd_rdma;
    wire            umi_out_cmd_atomic;
    wire            umi_out_cmd_user0;
    wire            umi_out_cmd_future0;
    wire            umi_out_cmd_error;
    wire            umi_out_cmd_link;

    wire            umi_out_cmd_read_resp;
    wire            umi_out_cmd_write_resp;
    wire            umi_out_cmd_user0_resp;
    wire            umi_out_cmd_user1_resp;
    wire            umi_out_cmd_future0_resp;
    wire            umi_out_cmd_future1_resp;
    wire            umi_out_cmd_link_resp;

    wire            umi_out_cmd_atomic_add;
    wire            umi_out_cmd_atomic_and;
    wire            umi_out_cmd_atomic_or;
    wire            umi_out_cmd_atomic_xor;
    wire            umi_out_cmd_atomic_max;
    wire            umi_out_cmd_atomic_min;
    wire            umi_out_cmd_atomic_maxu;
    wire            umi_out_cmd_atomic_minu;
    wire            umi_out_cmd_atomic_swap;

    umi_decode #(
        .CW(CW)
    ) umi_decode_arb (
        // Packet Command
        .command            (umi_out_cmd_r[CW-1:0]),
        .cmd_invalid        (umi_out_cmd_invalid),
        // request/response/link
        .cmd_request        (umi_out_cmd_request),
        .cmd_response       (umi_out_cmd_response),
        // requests
        .cmd_read           (umi_out_cmd_read),
        .cmd_write          (umi_out_cmd_write),
        .cmd_write_posted   (umi_out_cmd_write_posted),
        .cmd_rdma           (umi_out_cmd_rdma),
        .cmd_atomic         (umi_out_cmd_atomic),
        .cmd_user0          (umi_out_cmd_user0),
        .cmd_future0        (umi_out_cmd_future0),
        .cmd_error          (umi_out_cmd_error),
        .cmd_link           (umi_out_cmd_link),
        // Response (device -> host)
        .cmd_read_resp      (umi_out_cmd_read_resp),
        .cmd_write_resp     (umi_out_cmd_write_resp),
        .cmd_user0_resp     (umi_out_cmd_user0_resp),
        .cmd_user1_resp     (umi_out_cmd_user1_resp),
        .cmd_future0_resp   (umi_out_cmd_future0_resp),
        .cmd_future1_resp   (umi_out_cmd_future1_resp),
        .cmd_link_resp      (umi_out_cmd_link_resp),
        // Atomic operations
        .cmd_atomic_add     (umi_out_cmd_atomic_add),
        .cmd_atomic_and     (umi_out_cmd_atomic_and),
        .cmd_atomic_or      (umi_out_cmd_atomic_or),
        .cmd_atomic_xor     (umi_out_cmd_atomic_xor),
        .cmd_atomic_max     (umi_out_cmd_atomic_max),
        .cmd_atomic_min     (umi_out_cmd_atomic_min),
        .cmd_atomic_maxu    (umi_out_cmd_atomic_maxu),
        .cmd_atomic_minu    (umi_out_cmd_atomic_minu),
        .cmd_atomic_swap    (umi_out_cmd_atomic_swap)
    );

    //#################################
    //# Request Packet
    //#################################
    wire [4:0]      umi_req_in_cmd_opcode;
    wire [2:0]      umi_req_in_cmd_size;
    wire [7:0]      umi_req_in_cmd_len;
    wire [7:0]      umi_req_in_cmd_atype;
    wire [3:0]      umi_req_in_cmd_qos;
    wire [1:0]      umi_req_in_cmd_prot;
    wire            umi_req_in_cmd_eom;
    wire            umi_req_in_cmd_eof;
    wire            umi_req_in_cmd_ex;
    wire [1:0]      umi_req_in_cmd_user;
    wire [23:0]     umi_req_in_cmd_user_extended;
    wire [1:0]      umi_req_in_cmd_err;
    wire [4:0]      umi_req_in_cmd_hostid;

    wire [11:0]     umi_req_in_cmd_lenp1;
    wire [11:0]     umi_req_in_cmd_bytes;

    wire            umi_req_in_mergeable;
    wire            req_cmd_only;
    wire            req_no_data;
    reg  [11:0]     req_packet_bytes;

    umi_unpack #(
        .CW(CW)
    ) umi_unpack_req (
        // Outputs
        .cmd_opcode         (umi_req_in_cmd_opcode[4:0]),
        .cmd_size           (umi_req_in_cmd_size[2:0]),
        .cmd_len            (umi_req_in_cmd_len[7:0]),
        .cmd_atype          (umi_req_in_cmd_atype[7:0]),
        .cmd_qos            (umi_req_in_cmd_qos[3:0]),
        .cmd_prot           (umi_req_in_cmd_prot[1:0]),
        .cmd_eom            (umi_req_in_cmd_eom),
        .cmd_eof            (umi_req_in_cmd_eof),
        .cmd_ex             (umi_req_in_cmd_ex),
        .cmd_user           (umi_req_in_cmd_user[1:0]),
        .cmd_user_extended  (umi_req_in_cmd_user_extended[23:0]),
        .cmd_err            (umi_req_in_cmd_err[1:0]),
        .cmd_hostid         (umi_req_in_cmd_hostid[4:0]),
        // Inputs
        .packet_cmd         (umi_req_in_cmd[CW-1:0])
    );

    assign umi_req_in_cmd_lenp1 = {4'h0, umi_req_in_cmd_len} + 12'b1;
    assign umi_req_in_cmd_bytes = umi_req_in_cmd_lenp1 << umi_req_in_cmd_size;

    wire            umi_req_in_cmd_invalid;

    wire            umi_req_in_cmd_request;
    wire            umi_req_in_cmd_response;

    wire            umi_req_in_cmd_read;
    wire            umi_req_in_cmd_write;

    wire            umi_req_in_cmd_write_posted;
    wire            umi_req_in_cmd_rdma;
    wire            umi_req_in_cmd_atomic;
    wire            umi_req_in_cmd_user0;
    wire            umi_req_in_cmd_future0;
    wire            umi_req_in_cmd_error;
    wire            umi_req_in_cmd_link;

    wire            umi_req_in_cmd_read_resp;
    wire            umi_req_in_cmd_write_resp;
    wire            umi_req_in_cmd_user0_resp;
    wire            umi_req_in_cmd_user1_resp;
    wire            umi_req_in_cmd_future0_resp;
    wire            umi_req_in_cmd_future1_resp;
    wire            umi_req_in_cmd_link_resp;

    umi_decode #(
        .CW(CW))
    umi_decode_req (
        .command             (umi_req_in_cmd[CW-1:0]),
        .cmd_invalid         (umi_req_in_cmd_invalid),

        .cmd_request         (umi_req_in_cmd_request),
        .cmd_response        (umi_req_in_cmd_response),

        .cmd_read            (umi_req_in_cmd_read),
        .cmd_write           (umi_req_in_cmd_write),
        .cmd_write_posted    (umi_req_in_cmd_write_posted),
        .cmd_rdma            (umi_req_in_cmd_rdma),
        .cmd_atomic          (umi_req_in_cmd_atomic),
        .cmd_user0           (umi_req_in_cmd_user0),
        .cmd_future0         (umi_req_in_cmd_future0),
        .cmd_error           (umi_req_in_cmd_error),
        .cmd_link            (umi_req_in_cmd_link),

        .cmd_read_resp       (umi_req_in_cmd_read_resp),
        .cmd_write_resp      (umi_req_in_cmd_write_resp),
        .cmd_user0_resp      (umi_req_in_cmd_user0_resp),
        .cmd_user1_resp      (umi_req_in_cmd_user1_resp),
        .cmd_future0_resp    (umi_req_in_cmd_future0_resp),
        .cmd_future1_resp    (umi_req_in_cmd_future1_resp),
        .cmd_link_resp       (umi_req_in_cmd_link_resp),

        .cmd_atomic_add      (),
        .cmd_atomic_and      (),
        .cmd_atomic_or       (),
        .cmd_atomic_xor      (),
        .cmd_atomic_max      (),
        .cmd_atomic_min      (),
        .cmd_atomic_maxu     (),
        .cmd_atomic_minu     (),
        .cmd_atomic_swap     ()
    );

    // Check Request Mergeability
    assign umi_req_in_mergeable = (umi_out_cmd_write | umi_out_cmd_write_posted) &
                                  // Test command fields for mergeability
                                  (umi_out_cmd_hostid == umi_req_in_cmd_hostid) &
                                  (umi_out_cmd_err == umi_req_in_cmd_err) &
                                  (umi_out_cmd_eof == umi_req_in_cmd_eof) &
                                  (umi_out_cmd_prot == umi_req_in_cmd_prot) &
                                  (umi_out_cmd_qos == umi_req_in_cmd_qos) &
                                  (umi_out_cmd_size == umi_req_in_cmd_size) &
                                  (umi_out_cmd_opcode == umi_req_in_cmd_opcode)  &
                                  (umi_out_cmd_user == umi_req_in_cmd_user) &
                                  // Previous tx was not EOM
                                  !umi_out_cmd_eom &
                                  // source and destination addresses are contiguous
                                  ((umi_out_dstaddr_r + (DW/8)) == umi_req_in_dstaddr) &
                                  ((umi_out_srcaddr_r + (DW/8)) == umi_req_in_srcaddr) &
                                  // All byte lanes in the data are being used
                                  (umi_out_cmd_bytes == (DW/8)) &
                                  (umi_req_in_cmd_bytes == (DW/8)) &
                                  // There is still more than IOW worth of valid data
                                  (num_bytes_next > 0) &
                                  // There is DW worth of register space available
                                  (num_bytes_next <= $clog2((DW+AW+AW+CW)/8)) &
                                  // Only incoming request is valid and not response
                                  (umi_req_in_valid & !umi_resp_in_valid);

    // Only send the required number of bits
    assign req_cmd_only = umi_req_in_cmd_invalid    |
                          umi_req_in_cmd_link       |
                          umi_req_in_cmd_link_resp  ;
    assign req_no_data  = umi_req_in_cmd_read       |
                          umi_req_in_cmd_rdma       |
                          umi_req_in_cmd_error      |
                          umi_req_in_cmd_write_resp |
                          umi_req_in_cmd_user0      |
                          umi_req_in_cmd_future0    ;

    always @(*)
        case ({umi_req_in_mergeable,req_cmd_only,req_no_data})
            3'b100:  req_packet_bytes[11:0] = DW/8;
            3'b010:  req_packet_bytes[11:0] = CW/8;
            3'b001:  req_packet_bytes[11:0] = (AW+AW+CW)/8;
            default: req_packet_bytes[11:0] = (AW+AW+CW)/8 + umi_req_in_cmd_bytes[11:0];
        endcase

    //#################################
    //# Response Packet
    //#################################
    wire [4:0]      umi_resp_in_cmd_opcode;
    wire [2:0]      umi_resp_in_cmd_size;
    wire [7:0]      umi_resp_in_cmd_len;
    wire [7:0]      umi_resp_in_cmd_atype;
    wire [3:0]      umi_resp_in_cmd_qos;
    wire [1:0]      umi_resp_in_cmd_prot;
    wire            umi_resp_in_cmd_eom;
    wire            umi_resp_in_cmd_eof;
    wire            umi_resp_in_cmd_ex;
    wire [1:0]      umi_resp_in_cmd_user;
    wire [23:0]     umi_resp_in_cmd_user_extended;
    wire [1:0]      umi_resp_in_cmd_err;
    wire [4:0]      umi_resp_in_cmd_hostid;

    wire [11:0]     umi_resp_in_cmd_lenp1;
    wire [11:0]     umi_resp_in_cmd_bytes;

    wire            umi_resp_in_mergeable;
    wire            resp_cmd_only;
    wire            resp_no_data;
    reg  [11:0]     resp_packet_bytes;

    umi_unpack #(
        .CW(CW)
    ) umi_unpack_resp (
        // Outputs
        .cmd_opcode         (umi_resp_in_cmd_opcode[4:0]),
        .cmd_size           (umi_resp_in_cmd_size[2:0]),
        .cmd_len            (umi_resp_in_cmd_len[7:0]),
        .cmd_atype          (umi_resp_in_cmd_atype[7:0]),
        .cmd_qos            (umi_resp_in_cmd_qos[3:0]),
        .cmd_prot           (umi_resp_in_cmd_prot[1:0]),
        .cmd_eom            (umi_resp_in_cmd_eom),
        .cmd_eof            (umi_resp_in_cmd_eof),
        .cmd_ex             (umi_resp_in_cmd_ex),
        .cmd_user           (umi_resp_in_cmd_user[1:0]),
        .cmd_user_extended  (umi_resp_in_cmd_user_extended[23:0]),
        .cmd_err            (umi_resp_in_cmd_err[1:0]),
        .cmd_hostid         (umi_resp_in_cmd_hostid[4:0]),
        // Inputs
        .packet_cmd         (umi_resp_in_cmd[CW-1:0])
    );

    assign umi_resp_in_cmd_lenp1 = {4'h0, umi_resp_in_cmd_len} + 12'b1;
    assign umi_resp_in_cmd_bytes = umi_resp_in_cmd_lenp1 << umi_resp_in_cmd_size;

    wire            umi_resp_in_cmd_invalid;

    wire            umi_resp_in_cmd_request;
    wire            umi_resp_in_cmd_response;

    wire            umi_resp_in_cmd_read;
    wire            umi_resp_in_cmd_write;

    wire            umi_resp_in_cmd_write_posted;
    wire            umi_resp_in_cmd_rdma;
    wire            umi_resp_in_cmd_atomic;
    wire            umi_resp_in_cmd_user0;
    wire            umi_resp_in_cmd_future0;
    wire            umi_resp_in_cmd_error;
    wire            umi_resp_in_cmd_link;

    wire            umi_resp_in_cmd_read_resp;
    wire            umi_resp_in_cmd_write_resp;
    wire            umi_resp_in_cmd_user0_resp;
    wire            umi_resp_in_cmd_user1_resp;
    wire            umi_resp_in_cmd_future0_resp;
    wire            umi_resp_in_cmd_future1_resp;
    wire            umi_resp_in_cmd_link_resp;

    umi_decode #(
        .CW(CW))
    umi_decode_resp (
        .command             (umi_resp_in_cmd[CW-1:0]),
        .cmd_invalid         (umi_resp_in_cmd_invalid),

        .cmd_request         (umi_resp_in_cmd_request),
        .cmd_response        (umi_resp_in_cmd_response),

        .cmd_read            (umi_resp_in_cmd_read),
        .cmd_write           (umi_resp_in_cmd_write),
        .cmd_write_posted    (umi_resp_in_cmd_write_posted),
        .cmd_rdma            (umi_resp_in_cmd_rdma),
        .cmd_atomic          (umi_resp_in_cmd_atomic),
        .cmd_user0           (umi_resp_in_cmd_user0),
        .cmd_future0         (umi_resp_in_cmd_future0),
        .cmd_error           (umi_resp_in_cmd_error),
        .cmd_link            (umi_resp_in_cmd_link),

        .cmd_read_resp       (umi_resp_in_cmd_read_resp),
        .cmd_write_resp      (umi_resp_in_cmd_write_resp),
        .cmd_user0_resp      (umi_resp_in_cmd_user0_resp),
        .cmd_user1_resp      (umi_resp_in_cmd_user1_resp),
        .cmd_future0_resp    (umi_resp_in_cmd_future0_resp),
        .cmd_future1_resp    (umi_resp_in_cmd_future1_resp),
        .cmd_link_resp       (umi_resp_in_cmd_link_resp),

        .cmd_atomic_add      (),
        .cmd_atomic_and      (),
        .cmd_atomic_or       (),
        .cmd_atomic_xor      (),
        .cmd_atomic_max      (),
        .cmd_atomic_min      (),
        .cmd_atomic_maxu     (),
        .cmd_atomic_minu     (),
        .cmd_atomic_swap     ()
    );

    // Check Response Mergeability
    assign umi_resp_in_mergeable = umi_out_cmd_read_resp &
                                   // Test command fields for mergeability
                                   (umi_out_cmd_hostid == umi_resp_in_cmd_hostid) &
                                   (umi_out_cmd_err == umi_resp_in_cmd_err) &
                                   (umi_out_cmd_eof == umi_resp_in_cmd_eof) &
                                   (umi_out_cmd_prot == umi_resp_in_cmd_prot) &
                                   (umi_out_cmd_qos == umi_resp_in_cmd_qos) &
                                   (umi_out_cmd_size == umi_resp_in_cmd_size) &
                                   (umi_out_cmd_opcode == umi_resp_in_cmd_opcode)  &
                                   (umi_out_cmd_user == umi_resp_in_cmd_user) &
                                   // Previous tx was not EOM
                                   !umi_out_cmd_eom &
                                   // source and destination addresses are contiguous
                                   ((umi_out_dstaddr_r + (DW/8)) == umi_resp_in_dstaddr) &
                                   ((umi_out_srcaddr_r + (DW/8)) == umi_resp_in_srcaddr) &
                                   // All byte lanes in the data are being used
                                   (umi_out_cmd_bytes == (DW/8)) &
                                   (umi_resp_in_cmd_bytes == (DW/8)) &
                                   // There is still more than IOW worth of valid data
                                   (num_bytes_next > 0) &
                                   // There is DW worth of register space available
                                   (num_bytes_next <= $clog2((DW+AW+AW+CW)/8)) &
                                   // Response is valid
                                   umi_resp_in_valid;

    // Only send the required number of bits
    assign resp_cmd_only = umi_resp_in_cmd_invalid    |
                           umi_resp_in_cmd_link       |
                           umi_resp_in_cmd_link_resp  ;
    assign resp_no_data  = umi_resp_in_cmd_read       |
                           umi_resp_in_cmd_rdma       |
                           umi_resp_in_cmd_error      |
                           umi_resp_in_cmd_write_resp |
                           umi_resp_in_cmd_user0      |
                           umi_resp_in_cmd_future0    ;

    always @(*)
        case ({umi_resp_in_mergeable,resp_cmd_only,resp_no_data})
            3'b100:  resp_packet_bytes[11:0] = DW/8;
            3'b010:  resp_packet_bytes[11:0] = CW/8;
            3'b001:  resp_packet_bytes[11:0] = (AW+AW+CW)/8;
            default: resp_packet_bytes[11:0] = (AW+AW+CW)/8 + umi_resp_in_cmd_bytes[11:0];
        endcase

    //########################################
    //# FLOW CONTROL
    //########################################

    // sample input controls to avoid timing issues
    always @ (posedge clk or negedge nreset)
        if(~nreset)
            num_bytes <= 'b0;
        else if ((umi_out_valid & umi_out_ready) & (phy_txvld & phy_txrdy))
            num_bytes <= num_bytes_next + num_bytes_start_value;
        else if (umi_out_valid & umi_out_ready)
            num_bytes <= num_bytes_start_value;
        else if (phy_txvld & phy_txrdy)
            num_bytes <= num_bytes_next;

    assign num_bytes_next = (num_bytes > byterate) ?
                            (num_bytes - byterate) :
                            'b0;

    assign num_bytes_start_value = umi_resp_in_valid & umi_resp_in_ready ?
                                   resp_packet_bytes                     :
                                   req_packet_bytes;

    //########################################
    // Data shift register
    //########################################

    // Second step - push all to the right, this is only needed when you skip a field
    assign shiftreg_in_new = (umi_req_in_mergeable | umi_resp_in_mergeable) ?
                             umi_out_data :
                             {umi_out_data,umi_out_srcaddr,umi_out_dstaddr,umi_out_cmd};

    // TX is done as lsb first
    // adding indication to the packet type in the shift register for crdt management
    always @ (posedge clk or negedge nreset)
        if (~nreset)
            shiftreg <= 'b0;
        else if ((umi_out_valid & umi_out_ready) & (phy_txvld & phy_txrdy))
            shiftreg <= shiftreg_in | (shiftreg_in_new << (num_bytes_next << 3));
        else if (umi_out_valid & umi_out_ready)
            shiftreg <= shiftreg_in_new;
        else if (phy_txvld & phy_txrdy)
            shiftreg <= shiftreg_in;

    assign shiftreg_in[(DW+AW+AW+CW)-1:0] = shiftreg[(DW+AW+AW+CW)-1:0] >>
                                            (byterate[$clog2(DW+AW+AW+CW)-1:0] << 3);

    assign phy_txdata[IOW-1:0] = shiftreg[IOW-1:0];

    //#################################
    //# Request/Reponse commit
    //#################################
    // Req cant follow Resp in the immediate next cycle and vice versa
    assign umi_out_ready = csr_en &
                           phy_txrdy &
                           ((num_bytes == 0) |
                           (umi_req_in_mergeable | umi_resp_in_mergeable));

    //########################################
    //# Output data - no need for masking or by anymore
    //########################################

    wire        ionreset_sync;

    la_rsync la_rsync(.clk(ioclk),
                      .nrst_in(ionreset),
                      .nrst_out(ionreset_sync));

    assign phy_txvld = csr_en & (num_bytes > 0) & ionreset_sync;

endmodule
// Local Variables:
// verilog-library-directories:("." "../../umi/rtl/")
// End:
