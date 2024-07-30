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
 * -TL-UH to UMI converter
 *
 * The umi_srcaddr for requests uses User Defined Bits as follows:
 * [63:56]  : Reserved
 * [55:40]  : Chip ID
 * [39:24]  : Local routing address
 * [23:20]  : ml_tx_first_one (Left Shift for resp data < TileLink data (64b))
 * [19:16]  : tl_a_size (TileLink Size)
 * [15:8]   : tl_a_source (TileLink Source)
 * [7:0]    : 0000_0000b
 *
 ******************************************************************************/


`default_nettype wire
`include "tl-uh.vh"

module tl2umi_np #(
    parameter CW    = 32,   // command width
    parameter AW    = 64,   // address width
    parameter DW    = 64,   // umi packet width
    parameter IDW   = 16    // brick ID width
)
(
    input               clk,
    input               nreset,
    input  [IDW-1:0]    chipid,
    input  [15:0]       local_routing,

    output              tl_a_ready,
    input               tl_a_valid,
    input  [2:0]        tl_a_opcode,
    input  [2:0]        tl_a_param,
    input  [2:0]        tl_a_size,
    input  [4:0]        tl_a_source,
    input  [55:0]       tl_a_address,
    input  [7:0]        tl_a_mask,
    input  [63:0]       tl_a_data,
    input               tl_a_corrupt,

    input               tl_d_ready,
    output reg          tl_d_valid,
    output reg [2:0]    tl_d_opcode,
    output     [1:0]    tl_d_param,
    output reg [2:0]    tl_d_size,
    output reg [4:0]    tl_d_source,
    output              tl_d_sink,
    output              tl_d_denied,
    output reg [63:0]   tl_d_data,
    output              tl_d_corrupt,

    // Host port (per clink)
    output              uhost_req_valid,
    output [CW-1:0]     uhost_req_cmd,
    output [AW-1:0]     uhost_req_dstaddr,
    output [AW-1:0]     uhost_req_srcaddr,
    output [DW-1:0]     uhost_req_data,
    input               uhost_req_ready,

    input               uhost_resp_valid,
    input  [CW-1:0]     uhost_resp_cmd,
    input  [AW-1:0]     uhost_resp_dstaddr,
    input  [AW-1:0]     uhost_resp_srcaddr,
    input  [DW-1:0]     uhost_resp_data,
    output              uhost_resp_ready
);

    `include "umi_messages.vh"

    reg [1:0]   reset_done;

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            reset_done <= 2'b00;
        else
            reset_done <= {reset_done[0], 1'b1};
    end

    wire            fifoflex2dataag_resp_valid;
    wire [CW-1:0]   fifoflex2dataag_resp_cmd;
    wire [AW-1:0]   fifoflex2dataag_resp_dstaddr;
    wire [AW-1:0]   fifoflex2dataag_resp_srcaddr;
    wire [63:0]     fifoflex2dataag_resp_data;
    wire            fifoflex2dataag_resp_ready;

    umi_fifo_flex #(.TARGET         ("DEFAULT"),
                    .ASYNC          (0),
                    .DEPTH          (0),
                    .CW             (CW),
                    .AW             (AW),
                    .IDW            (DW),
                    .ODW            (64)
    ) tl2umi_resp_fifo_flex (
        .bypass         (1'b1),
        .chaosmode      (1'b0),
        .fifo_full      (),
        .fifo_empty     (),

        // Input
        .umi_in_clk     (clk),
        .umi_in_nreset  (nreset),
        .umi_in_valid   (uhost_resp_valid),
        .umi_in_cmd     (uhost_resp_cmd),
        .umi_in_dstaddr (uhost_resp_dstaddr),
        .umi_in_srcaddr (uhost_resp_srcaddr),
        .umi_in_data    (uhost_resp_data),
        .umi_in_ready   (uhost_resp_ready),

        // Output
        .umi_out_clk    (clk),
        .umi_out_nreset (nreset),
        .umi_out_valid  (fifoflex2dataag_resp_valid),
        .umi_out_cmd    (fifoflex2dataag_resp_cmd),
        .umi_out_dstaddr(fifoflex2dataag_resp_dstaddr),
        .umi_out_srcaddr(fifoflex2dataag_resp_srcaddr),
        .umi_out_data   (fifoflex2dataag_resp_data),
        .umi_out_ready  (fifoflex2dataag_resp_ready),

        // Supplies
        .vdd            (1'b1),
        .vss            (1'b0)
    );

    wire            dataag_out_resp_valid;
    wire [CW-1:0]   dataag_out_resp_cmd;
    wire [AW-1:0]   dataag_out_resp_dstaddr;
    wire [AW-1:0]   dataag_out_resp_srcaddr;
    wire [63:0]     dataag_out_resp_data;
    wire            dataag_out_resp_ready;

    umi_data_aggregator #(
        .CW                 (CW),
        .AW                 (AW),
        .DW                 (64)
    ) tl2umi_resp_data_aggregator (
        .clk                (clk),
        .nreset             (nreset),

        .umi_in_valid       (fifoflex2dataag_resp_valid),
        .umi_in_cmd         (fifoflex2dataag_resp_cmd),
        .umi_in_dstaddr     (fifoflex2dataag_resp_dstaddr),
        .umi_in_srcaddr     (fifoflex2dataag_resp_srcaddr),
        .umi_in_data        (fifoflex2dataag_resp_data),
        .umi_in_ready       (fifoflex2dataag_resp_ready),

        .umi_out_valid      (dataag_out_resp_valid),
        .umi_out_cmd        (dataag_out_resp_cmd),
        .umi_out_dstaddr    (dataag_out_resp_dstaddr),
        .umi_out_srcaddr    (dataag_out_resp_srcaddr),
        .umi_out_data       (dataag_out_resp_data),
        .umi_out_ready      (dataag_out_resp_ready)
    );

    wire [4:0]      dataag_out_resp_cmd_opcode;
    wire [2:0]      dataag_out_resp_cmd_size;
    wire [7:0]      dataag_out_resp_cmd_len;
    wire [7:0]      dataag_out_resp_cmd_atype;
    wire            dataag_out_resp_cmd_eom;
    wire            dataag_out_resp_cmd_invalid;
    wire            dataag_out_resp_cmd_read_resp;
    wire            dataag_out_resp_cmd_write_resp;

    umi_unpack #(
        .CW     (CW)
    ) tl2umi_resp_unpack (
        // Input CMD
        .packet_cmd         (dataag_out_resp_cmd),

        // Output Fields
        .cmd_opcode         (dataag_out_resp_cmd_opcode),
        .cmd_size           (dataag_out_resp_cmd_size),
        .cmd_len            (dataag_out_resp_cmd_len),
        .cmd_atype          (dataag_out_resp_cmd_atype),
        .cmd_qos            (),
        .cmd_prot           (),
        .cmd_eom            (dataag_out_resp_cmd_eom),
        .cmd_eof            (),
        .cmd_ex             (),
        .cmd_user           (),
        .cmd_user_extended  (),
        .cmd_err            (),
        .cmd_hostid         ()
    );

    umi_decode #(
        .CW                 (CW)
    ) tl2umi_resp_decode (
        // Packet Command
        .command            (dataag_out_resp_cmd),
        .cmd_invalid        (dataag_out_resp_cmd_invalid),
        // request/response/link
        .cmd_request        (),
        .cmd_response       (),
        // requests
        .cmd_read           (),
        .cmd_write          (),
        .cmd_write_posted   (),
        .cmd_rdma           (),
        .cmd_atomic         (),
        .cmd_user0          (),
        .cmd_future0        (),
        .cmd_error          (),
        .cmd_link           (),
        // Response (device -> host)
        .cmd_read_resp      (dataag_out_resp_cmd_read_resp),
        .cmd_write_resp     (dataag_out_resp_cmd_write_resp),
        .cmd_user0_resp     (),
        .cmd_user1_resp     (),
        .cmd_future0_resp   (),
        .cmd_future1_resp   (),
        .cmd_link_resp      (),
        // Atomic operations
        .cmd_atomic_add     (),
        .cmd_atomic_and     (),
        .cmd_atomic_or      (),
        .cmd_atomic_xor     (),
        .cmd_atomic_max     (),
        .cmd_atomic_min     (),
        .cmd_atomic_maxu    (),
        .cmd_atomic_minu    (),
        .cmd_atomic_swap    ()
    );

    assign tl_d_param   = 2'b0;
    assign tl_d_sink    = 1'b0;
    assign tl_d_denied  = 1'b0;
    assign tl_d_corrupt = 1'b0;

    reg [2:0]   resp_state;

    reg         get_ack_req;
    reg         get_ack_resp;

    reg         put_ack_req;
    reg         put_ack_resp;
    reg [7:0]   put_bytes_req;
    reg [7:0]   put_bytes_resp;
    reg         dataag_out_resp_ready_assert;
    wire [7:0]  dataag_out_resp_bytes;

    localparam RESP_IDLE    = 3'd0;
    localparam RESP_RD_BRST = 3'd1;
    localparam RESP_RD_LAST = 3'd2;
    localparam RESP_WR_BRST = 3'd3;
    localparam RESP_WR_LAST = 3'd4;

    assign dataag_out_resp_ready = reset_done[1] & tl_d_ready & dataag_out_resp_ready_assert;
    assign dataag_out_resp_bytes = (1 << dataag_out_resp_cmd_size)*(dataag_out_resp_cmd_len + 1);

    wire [2:0] dataag_out_resp_size = dataag_out_resp_dstaddr[18:16];
    wire [4:0] dataag_out_resp_source = dataag_out_resp_dstaddr[12:8];
    wire [3:0] dataag_out_ml_tx_first_one = dataag_out_resp_dstaddr[23:20];

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            resp_state <= RESP_IDLE;
            dataag_out_resp_ready_assert <= 1'b1;
            tl_d_valid <= 1'b0;
            tl_d_opcode <= 3'b0;
            tl_d_size <= 3'b0;
            tl_d_source <= 5'b0;
            tl_d_data <= 64'b0;
            put_ack_resp <= 1'b0;
            put_bytes_resp <= 8'b0;
            get_ack_resp <= 1'b0;
        end
        else begin
            case (resp_state)

            RESP_IDLE: begin
                dataag_out_resp_ready_assert <= 1'b1;
                tl_d_valid <= 1'b0;
                tl_d_opcode <= 3'b0;
                tl_d_size <= 3'b0;
                tl_d_source <= 5'b0;
                tl_d_data <= 64'b0;
                put_ack_resp <= 1'b0;
                put_bytes_resp <= 8'b0;
                get_ack_resp <= 1'b0;
                if (dataag_out_resp_ready & dataag_out_resp_valid) begin
                    if (dataag_out_resp_cmd_read_resp) begin
                        if (dataag_out_resp_cmd_eom == 1'b1) begin
                            resp_state <= RESP_RD_LAST;
                            dataag_out_resp_ready_assert <= 1'b0;
                        end
                        else begin
                            resp_state <= RESP_RD_BRST;
                            dataag_out_resp_ready_assert <= 1'b1;
                        end
                        tl_d_valid <= 1'b1;
                        tl_d_opcode <= `TL_OP_AccessAckData;
                        tl_d_size <= dataag_out_resp_size;
                        tl_d_source <= dataag_out_resp_source;
                        tl_d_data <= dataag_out_resp_data << (dataag_out_ml_tx_first_one*8);
                    end
                    else if (dataag_out_resp_cmd_write_resp) begin
                        if (dataag_out_resp_bytes == put_bytes_req) begin
                            resp_state <= RESP_WR_LAST;
                            dataag_out_resp_ready_assert <= 1'b0;
                            tl_d_valid <= 1'b1;
                        end
                        else begin
                            // Discard all UMI Write Responses except the last one
                            resp_state <= RESP_WR_BRST;
                            dataag_out_resp_ready_assert <= 1'b1;
                            tl_d_valid <= 1'b0;
                        end
                        tl_d_opcode <= `TL_OP_AccessAck;
                        tl_d_size <= dataag_out_resp_size;
                        tl_d_source <= dataag_out_resp_source;
                        put_bytes_resp <= dataag_out_resp_bytes;
                    end
                    else begin
                        // Not supported response type. Ignore and stay in idle.
                        resp_state <= RESP_IDLE;
                        dataag_out_resp_ready_assert <= 1'b1;
                        tl_d_valid <= 1'b0;
                        tl_d_opcode <= 3'b0;
                        tl_d_size <= 3'b0;
                        tl_d_source <= 5'b0;
                        tl_d_data <= 64'b0;
                        put_ack_resp <= 1'b0;
                        put_bytes_resp <= 8'b0;
                        get_ack_resp <= 1'b0;
                    `ifndef SYNTHESIS
                        $display("Unsupported response on UMI side %d", dataag_out_resp_cmd_opcode);
                    `endif
                    end
                end
            end
            RESP_RD_BRST: begin
                dataag_out_resp_ready_assert <= 1'b1;
                if (tl_d_ready & tl_d_valid) begin
                    if (dataag_out_resp_cmd_eom == 1'b1) begin
                        resp_state <= RESP_RD_LAST;
                        dataag_out_resp_ready_assert <= 1'b0;
                    end
                end
                if (dataag_out_resp_ready & dataag_out_resp_valid) begin
                    tl_d_data <= dataag_out_resp_data << (dataag_out_ml_tx_first_one*8);
                end
                if (dataag_out_resp_ready & dataag_out_resp_valid) begin
                    tl_d_valid <= 1'b1;
                end
                else if (tl_d_ready) begin
                    tl_d_valid <= 1'b0;
                end
                tl_d_opcode <= `TL_OP_AccessAckData;
                tl_d_size <= dataag_out_resp_size;
                tl_d_source <= dataag_out_resp_source;
            end
            RESP_RD_LAST: begin
                if (tl_d_ready) begin
                    resp_state <= RESP_IDLE;
                    dataag_out_resp_ready_assert <= 1'b1;
                    tl_d_valid <= 1'b0;
                    get_ack_resp <= 1'b1;
                end
            end
            RESP_WR_BRST: begin
                if (put_bytes_resp == put_bytes_req) begin
                    resp_state <= RESP_WR_LAST;
                    dataag_out_resp_ready_assert <= 1'b0;
                    tl_d_valid <= 1'b1;
                end
                else begin
                    // Discard all UMI Write Responses except the last one
                    resp_state <= RESP_WR_BRST;
                    dataag_out_resp_ready_assert <= 1'b1;
                    tl_d_valid <= 1'b0;
                end
                tl_d_opcode <= `TL_OP_AccessAck;
                tl_d_size <= dataag_out_resp_size;
                tl_d_source <= dataag_out_resp_source;
                if (dataag_out_resp_ready & dataag_out_resp_valid) begin
                    put_bytes_resp <= put_bytes_resp + dataag_out_resp_bytes;
                end
            end
            RESP_WR_LAST: begin
                if (tl_d_ready) begin
                    resp_state <= RESP_IDLE;
                    dataag_out_resp_ready_assert <= 1'b1;
                    tl_d_valid <= 1'b0;
                    put_bytes_resp <= 8'b0;
                    put_ack_resp <= 1'b1;
                end
            end
            default: begin
                // Entered wrong state. Return to idle.
                resp_state <= RESP_IDLE;
                dataag_out_resp_ready_assert <= 1'b1;
                tl_d_valid <= 1'b0;
                tl_d_opcode <= 3'b0;
                tl_d_size <= 3'b0;
                tl_d_source <= 5'b0;
                tl_d_data <= 64'b0;
                put_ack_resp <= 1'b0;
                put_bytes_resp <= 8'b0;
                get_ack_resp <= 1'b0;
            `ifndef SYNTHESIS
                $display("Entered Invalid State in Response State Machine");
            `endif
            end

            endcase
        end
    end

    // TL-A to UMI Request
    reg  [4:0]      uhost_req_packet_cmd_opcode;
    reg  [2:0]      uhost_req_packet_cmd_size;
    reg  [7:0]      uhost_req_packet_cmd_len;
    reg  [7:0]      uhost_req_packet_cmd_atype;
    reg             uhost_req_packet_cmd_eom;

    reg  [AW-1:0]   uhost_req_packet_dstaddr;
    reg  [AW-1:0]   uhost_req_packet_srcaddr;
    reg  [DW-1:0]   uhost_req_packet_data;

    wire [CW-1:0]   uhost_req_packet_cmd;
    wire [AW-1:0]   uhost_req_packet_dstaddr_m;
    wire            uhost_req_packet_valid;
    wire            uhost_req_packet_ready;

    assign uhost_req_packet_dstaddr_m = uhost_req_packet_dstaddr + 'd8;

    umi_pack #(
        .CW                 (CW)
    ) tl2umi_reqs_pack (
        .cmd_opcode         (uhost_req_packet_cmd_opcode),
        .cmd_size           (uhost_req_packet_cmd_size),
        .cmd_len            (uhost_req_packet_cmd_len),
        .cmd_atype          (uhost_req_packet_cmd_atype),
        .cmd_prot           (2'b0),
        .cmd_qos            (4'b0),
        .cmd_eom            (uhost_req_packet_cmd_eom),
        .cmd_eof            (1'b0),
        .cmd_user           (2'b0),
        .cmd_err            (2'b00),
        .cmd_ex             (1'b0),
        .cmd_hostid         (5'b0),
        .cmd_user_extended  (24'b0),

        .packet_cmd         (uhost_req_packet_cmd)
    );

    wire tl2umi_req_fifo_wr_full;
    wire tl2umi_req_fifo_rd_empty;

    la_syncfifo #(
        .DW     (CW + AW + AW + DW),
        .DEPTH  (2),
        .PROP   ("DEFAULT")
    ) tl2umi_req_fifo (
        .clk        (clk),
        .nreset     (nreset),
        .clear      (1'b0),

        .vss        (1'b0),
        .vdd        (1'b1),

        .chaosmode  (1'b0),
        .ctrl       (1'b0),
        .test       (1'b0),

        .wr_en      (uhost_req_packet_valid),
        .wr_din     ({uhost_req_packet_cmd, uhost_req_packet_dstaddr, uhost_req_packet_srcaddr, uhost_req_packet_data}),
        .wr_full    (tl2umi_req_fifo_wr_full),

        .rd_en      (uhost_req_ready),
        .rd_dout    ({uhost_req_cmd, uhost_req_dstaddr, uhost_req_srcaddr, uhost_req_data}),
        .rd_empty   (tl2umi_req_fifo_rd_empty)
    );

    assign uhost_req_packet_ready = ~tl2umi_req_fifo_wr_full;
    assign uhost_req_valid = ~tl2umi_req_fifo_rd_empty;

    // Add mask to the source address, user defined bits. This will allow us
    // to shift the response for GET/READ and ATOMIC operations


    // Aligned access + wmask to mask-less conversion
    // ml: maskless
    wire [63:0] ml_tx_addr;
    wire [63:0] ml_tx_data;
    wire [7:0]  ml_tx_len;

    wire        ml_tx_non_zero_mask;
    reg         ml_tx_non_zero_mask_r;
    reg         uhost_req_packet_valid_r;
    reg  [3:0]  ml_tx_first_one;

    assign ml_tx_non_zero_mask = |tl_a_mask;
    assign uhost_req_packet_valid = uhost_req_packet_valid_r & ml_tx_non_zero_mask_r;


    assign ml_tx_addr = {8'b0, tl_a_address[55:3], ml_tx_first_one[2:0]};
    assign ml_tx_data = tl_a_data >> (ml_tx_first_one*8);
    /* verilator lint_off WIDTH */
    assign ml_tx_len = tl_a_mask[0] + tl_a_mask[1] +
                       tl_a_mask[2] + tl_a_mask[3] +
                       tl_a_mask[4] + tl_a_mask[5] +
                       tl_a_mask[6] + tl_a_mask[7] - 1;
    /* verilator lint_on WIDTH */

    always @(*) begin
        if (tl_a_mask[0])
            ml_tx_first_one = 4'd0;
        else if (tl_a_mask[1])
            ml_tx_first_one = 4'd1;
        else if (tl_a_mask[2])
            ml_tx_first_one = 4'd2;
        else if (tl_a_mask[3])
            ml_tx_first_one = 4'd3;
        else if (tl_a_mask[4])
            ml_tx_first_one = 4'd4;
        else if (tl_a_mask[5])
            ml_tx_first_one = 4'd5;
        else if (tl_a_mask[6])
            ml_tx_first_one = 4'd6;
        else if (tl_a_mask[7])
            ml_tx_first_one = 4'd7;
        else
            ml_tx_first_one = 4'd8;
    end

    wire [15:0] umi_src_addr_user_defined = {{ml_tx_first_one, 1'b0, tl_a_size},
                                             {3'b0, tl_a_source}};
    wire [23:0] chip_address = {{(24-IDW){1'b0}}, chipid};
    wire [63:0] local_address = {chip_address, local_routing, umi_src_addr_user_defined, 8'b0};

    reg [2:0]   req_state;
    reg [7:0]   req_put_byte_counter;
    reg         tl_a_ready_assert;

    localparam REQ_IDLE     = 3'd0;
    localparam REQ_GET_LAST = 3'd1;
    localparam REQ_GET_ACK  = 3'd2;
    localparam REQ_PUT_BRST = 3'd3;
    localparam REQ_PUT_LAST = 3'd4;
    localparam REQ_PUT_ACK  = 3'd5;

    assign tl_a_ready = reset_done[1] & uhost_req_packet_ready & tl_a_ready_assert;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            req_state <= REQ_IDLE;
            tl_a_ready_assert <= 1'b1;
            uhost_req_packet_cmd_opcode <= 'b0;
            uhost_req_packet_cmd_len <= 'b0;
            uhost_req_packet_cmd_size <= 'b0;
            uhost_req_packet_cmd_atype <= 'b0;
            uhost_req_packet_cmd_eom <= 'b0;
            uhost_req_packet_dstaddr <= 'b0;
            uhost_req_packet_srcaddr <= 'b0;
            uhost_req_packet_data <= 'b0;
            uhost_req_packet_valid_r <= 1'b0;
            ml_tx_non_zero_mask_r <= 1'b0;
            put_ack_req <= 1'b0;
            put_bytes_req <= 8'b0;
        end
        else begin
            case (req_state)

            REQ_IDLE: begin
                tl_a_ready_assert <= 1'b1;
                uhost_req_packet_cmd_opcode <= 'b0;
                uhost_req_packet_cmd_len <= 'b0;
                uhost_req_packet_cmd_size <= 'b0;
                uhost_req_packet_cmd_atype <= 'b0;
                uhost_req_packet_cmd_eom <= 'b0;
                uhost_req_packet_dstaddr <= 'b0;
                uhost_req_packet_srcaddr <= 'b0;
                uhost_req_packet_data <= 'b0;
                uhost_req_packet_valid_r <= 1'b0;
                ml_tx_non_zero_mask_r <= 1'b0;
                put_bytes_req <= 8'b0;
                if (tl_a_valid & tl_a_ready) begin
                    case (tl_a_opcode)
                    `TL_OP_Get: begin
                        req_state <= REQ_GET_LAST;
                        tl_a_ready_assert <= 1'b0;
                        uhost_req_packet_cmd_opcode <= UMI_REQ_READ;
                        uhost_req_packet_cmd_size <= 'b0;
                        uhost_req_packet_cmd_len <= (1 << tl_a_size) - 1;
                        uhost_req_packet_cmd_eom <= 1'b1;
                        uhost_req_packet_dstaddr <= ml_tx_addr;
                        uhost_req_packet_srcaddr <= local_address;
                        uhost_req_packet_valid_r <= 1'b1;
                        ml_tx_non_zero_mask_r <= ml_tx_non_zero_mask;
                        get_ack_req <= 1'b1;
                    end
                    `TL_OP_PutFullData, `TL_OP_PutPartialData: begin
                        if (tl_a_size > 3'd3) begin
                            req_state <= REQ_PUT_BRST;
                            tl_a_ready_assert <= 1'b1;
                            uhost_req_packet_cmd_eom <= 1'b0;
                            req_put_byte_counter <= (1 << tl_a_size) - 8'd8;
                        end
                        else begin
                            req_state <= REQ_PUT_LAST;
                            tl_a_ready_assert <= 1'b0;
                            uhost_req_packet_cmd_eom <= 1'b1;
                        end
                        uhost_req_packet_cmd_opcode <= UMI_REQ_WRITE;
                        uhost_req_packet_cmd_size <= 'b0;
                        uhost_req_packet_cmd_len <= ml_tx_len;
                        uhost_req_packet_dstaddr <= ml_tx_addr;
                        uhost_req_packet_srcaddr <= local_address;
                        uhost_req_packet_valid_r <= 1'b1;
                        ml_tx_non_zero_mask_r <= ml_tx_non_zero_mask;
                        uhost_req_packet_data[63:0] <= ml_tx_data;
                        put_bytes_req <= ml_tx_len + 1;
                    end
                    `TL_OP_ArithmeticData, `TL_OP_LogicalData: begin
                        req_state <= REQ_PUT_LAST;
                        tl_a_ready_assert <= 1'b0;
                        uhost_req_packet_cmd_opcode <= UMI_REQ_ATOMIC;
                        uhost_req_packet_cmd_size <= tl_a_size;
                        uhost_req_packet_cmd_len <= 8'b0;
                        uhost_req_packet_cmd_eom <= 1'b1;
                        uhost_req_packet_dstaddr <= ml_tx_addr;
                        uhost_req_packet_srcaddr <= local_address;
                        uhost_req_packet_valid_r <= 1'b1;
                        ml_tx_non_zero_mask_r <= ml_tx_non_zero_mask;
                        uhost_req_packet_data[63:0] <= ml_tx_data;
                        case ({tl_a_opcode, tl_a_param})
                        {`TL_OP_ArithmeticData, `TL_PA_MIN}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICMIN;
                        {`TL_OP_ArithmeticData, `TL_PA_MAX}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICMAX;
                        {`TL_OP_ArithmeticData, `TL_PA_MINU}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICMINU;
                        {`TL_OP_ArithmeticData, `TL_PA_MAXU}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICMAXU;
                        {`TL_OP_ArithmeticData, `TL_PA_ADD}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICADD;
                        {`TL_OP_LogicalData, `TL_PL_XOR}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICXOR;
                        {`TL_OP_LogicalData, `TL_PL_OR}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICOR;
                        {`TL_OP_LogicalData, `TL_PL_AND}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICAND;
                        {`TL_OP_LogicalData, `TL_PL_SWAP}:
                                uhost_req_packet_cmd_atype <= UMI_REQ_ATOMICSWAP;
                        default: uhost_req_packet_cmd_opcode <= UMI_REQ_ERROR[4:0];
                        endcase
                    end
                    default: begin
                        // Not supported request type. Ignore and stay in idle.
                        req_state <= REQ_IDLE;
                        tl_a_ready_assert <= 1'b1;
                        uhost_req_packet_cmd_opcode <= 'b0;
                        uhost_req_packet_cmd_len <= 'b0;
                        uhost_req_packet_cmd_size <= 'b0;
                        uhost_req_packet_cmd_atype <= 'b0;
                        uhost_req_packet_cmd_eom <= 'b0;
                        uhost_req_packet_dstaddr <= 'b0;
                        uhost_req_packet_srcaddr <= 'b0;
                        uhost_req_packet_data <= 'b0;
                        uhost_req_packet_valid_r <= 1'b0;
                        ml_tx_non_zero_mask_r <= 1'b0;
                        put_bytes_req <= 8'b0;
                    `ifndef SYNTHESIS
                        $display("Unsupported request on TL side %d", tl_a_opcode);
                    `endif
                    end
                    endcase
                end
            end
            REQ_GET_LAST: begin
                if (uhost_req_packet_ready) begin
                    req_state <= REQ_GET_ACK;
                    uhost_req_packet_cmd_eom <= 1'b0;
                    uhost_req_packet_valid_r <= 1'b0;
                    ml_tx_non_zero_mask_r <= 1'b0;
                end
            end
            REQ_GET_ACK: begin
                if (get_ack_resp) begin
                    req_state <= REQ_IDLE;
                    tl_a_ready_assert <= 1'b1;
                    get_ack_req <= 1'b0;
                end
            end
            REQ_PUT_BRST: begin
                tl_a_ready_assert <= 1'b1;
                uhost_req_packet_cmd_opcode <= UMI_REQ_WRITE;
                uhost_req_packet_cmd_eom <= 1'b0;

                if (tl_a_ready & tl_a_valid) begin
                    uhost_req_packet_dstaddr <= {uhost_req_packet_dstaddr_m[AW-1:3], ml_tx_first_one[2:0]};
                    uhost_req_packet_data[63:0] <= ml_tx_data;
                    uhost_req_packet_cmd_len <= ml_tx_len;
                    ml_tx_non_zero_mask_r <= ml_tx_non_zero_mask;
                    req_put_byte_counter <= req_put_byte_counter - 8'd8;
                    put_bytes_req <= put_bytes_req + ml_tx_len + 1;
                    if (req_put_byte_counter == 8'd8) begin
                        req_state <= REQ_PUT_LAST;
                        tl_a_ready_assert <= 1'b0;
                        uhost_req_packet_cmd_eom <= 1'b1;
                    end
                end

                if (tl_a_ready & tl_a_valid) begin
                    uhost_req_packet_valid_r <= 1'b1;
                end
                else if (uhost_req_packet_ready) begin
                    uhost_req_packet_valid_r <= 1'b0;
                end
            end
            REQ_PUT_LAST: begin
                if (uhost_req_packet_ready) begin
                    req_state <= REQ_PUT_ACK;
                    uhost_req_packet_cmd_eom <= 1'b0;
                    uhost_req_packet_valid_r <= 1'b0;
                    ml_tx_non_zero_mask_r <= 1'b0;
                    put_ack_req <= 1'b1;
                end
            end
            REQ_PUT_ACK: begin
                if (put_ack_resp) begin
                    req_state <= REQ_IDLE;
                    tl_a_ready_assert <= 1'b1;
                    put_ack_req <= 1'b0;
                    put_bytes_req <= 8'b0;
                end
            end
            default: begin
                // Entered wrong state. Return to idle.
                req_state <= REQ_IDLE;
                tl_a_ready_assert <= 1'b1;
                uhost_req_packet_cmd_opcode <= 'b0;
                uhost_req_packet_cmd_len <= 'b0;
                uhost_req_packet_cmd_size <= 'b0;
                uhost_req_packet_cmd_atype <= 'b0;
                uhost_req_packet_cmd_eom <= 'b0;
                uhost_req_packet_dstaddr <= 'b0;
                uhost_req_packet_srcaddr <= 'b0;
                uhost_req_packet_data <= 'b0;
                uhost_req_packet_valid_r <= 1'b0;
                ml_tx_non_zero_mask_r <= 1'b0;
                put_ack_req <= 1'b0;
                put_bytes_req <= 8'b0;
            `ifndef SYNTHESIS
                $display("Entered Invalid State in Request State Machine");
            `endif
            end

            endcase
        end
    end

endmodule
