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
 * - AXI4 read channel (AR, R) to UMI converter
 *
 ******************************************************************************/

`default_nettype wire

module axiread2umi #(
    parameter CW        = 32,   // command width
    parameter AW        = 64,   // address width
    parameter DW        = 64,   // umi packet width
    parameter IDW       = 16,   // brick ID width
    parameter AXI_IDW   = 8     // AXI ID width
)
(
    input                   clk,
    input                   nreset,
    input  [IDW-1:0]        chipid,
    input  [15:0]           local_routing,

    // AXI4 Interface
    input  [AXI_IDW-1:0]    axi_arid,
    input  [AW-1:0]         axi_araddr,
    input  [7:0]            axi_arlen,
    input  [2:0]            axi_arsize,
    input  [1:0]            axi_arburst,
    input                   axi_arlock,
    input  [3:0]            axi_arcache,
    input  [2:0]            axi_arprot,
    input  [3:0]            axi_arqos,
    input  [3:0]            axi_arregion,
    input                   axi_arvalid,
    output                  axi_arready,

    output [AXI_IDW-1:0]    axi_rid,
    output [DW-1:0]         axi_rdata,
    output [1:0]            axi_rresp,
    output                  axi_rlast,
    output                  axi_rvalid,
    input                   axi_rready,

    // Host port (per clink)
    output                  uhost_req_valid,
    output [CW-1:0]         uhost_req_cmd,
    output [AW-1:0]         uhost_req_dstaddr,
    output [AW-1:0]         uhost_req_srcaddr,
    output [DW-1:0]         uhost_req_data,
    input                   uhost_req_ready,

    input                   uhost_resp_valid,
    input  [CW-1:0]         uhost_resp_cmd,
    input  [AW-1:0]         uhost_resp_dstaddr,
    input  [AW-1:0]         uhost_resp_srcaddr,
    input  [DW-1:0]         uhost_resp_data,
    output                  uhost_resp_ready
);

    `include "umi_messages.vh"

    localparam DWLOG = $clog2(DW/8);

    wire    reset_done;

    la_drsync la_drsync_i (
        .clk     (clk),
        .nreset  (nreset),
        .in      (1'b1),
        .out     (reset_done)
    );

    //reg             wlast_protcol_violation;
    //reg             wid_protocol_violation;
    wire            any_protocol_violation;

    assign any_protocol_violation = 1'b0;
    //assign any_protocol_violation = wid_protocol_violation |
    //                                wlast_protcol_violation;

    reg                 read_in_flight;

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            read_in_flight <= 1'b0;
        else if (axi_arvalid & axi_arready)
            read_in_flight <= 1'b1;
        else if (axi_rvalid & axi_rready & axi_rlast)
            read_in_flight <= 1'b0;
    end

    // Read address
    reg  [AXI_IDW-1:0]  axi_arid_r;
    reg  [AW-DWLOG-1:0] axi_araddr_line_r;
    reg  [DWLOG-1:0]    axi_araddr_byte_r;
    reg  [8:0]          axi_arbeats_rem;
    reg  [2:0]          axi_arsize_r;
    reg  [1:0]          axi_arburst_r;
    reg                 axi_arlock_r;
    reg  [3:0]          axi_arcache_r;
    reg  [2:0]          axi_arprot_r;
    reg  [3:0]          axi_arqos_r;
    reg  [3:0]          axi_arregion_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_arid_r      <= 'b0;
            axi_arsize_r    <= 'b0;
            axi_arburst_r   <= 'b0;
            axi_arlock_r    <= 'b0;
            axi_arcache_r   <= 'b0;
            axi_arprot_r    <= 'b0;
            axi_arqos_r     <= 'b0;
            axi_arregion_r  <= 'b0;
        end
        else if (axi_arvalid & axi_arready) begin
            axi_arid_r      <= axi_arid;
            axi_arsize_r    <= axi_arsize;
            axi_arburst_r   <= axi_arburst;
            axi_arlock_r    <= axi_arlock;
            axi_arcache_r   <= axi_arcache;
            axi_arprot_r    <= axi_arprot;
            axi_arqos_r     <= axi_arqos;
            axi_arregion_r  <= axi_arregion;
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_araddr_line_r <= 'b0;
            axi_araddr_byte_r <= 'b0;
        end
        else if (axi_arvalid & axi_arready) begin
            axi_araddr_line_r <= axi_araddr[AW-1:DWLOG];
            axi_araddr_byte_r <= axi_araddr[DWLOG-1:0];
        end
        else if (uhost_req_valid & uhost_req_ready) begin
            axi_araddr_line_r <= axi_araddr_line_r + 1;
            axi_araddr_byte_r <= 'b0;
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_arbeats_rem <= 'b0;
        else if (axi_arvalid & axi_arready)
            axi_arbeats_rem <= axi_arlen + 1;
        else if (uhost_req_valid & uhost_req_ready)
            axi_arbeats_rem <= axi_arbeats_rem - 1;
    end

    assign axi_arready = !read_in_flight & !any_protocol_violation & reset_done;

    // UMI request
    wire [4:0]      umi_req_cmd_opcode;
    wire [7:0]      umi_req_cmd_len;
    wire [8:0]      umi_req_cmd_len_plus_one;
    wire [1:0]      umi_req_cmd_prot;
    wire [3:0]      umi_req_cmd_qos;
    wire            umi_req_cmd_eom;
    wire            umi_req_cmd_ex;

    assign umi_req_cmd_opcode = UMI_REQ_READ;
    // This is trick that returns the number of bytes to request in a UMI Tx
    // Say the byte offset is 2 on an 8 byte bus which means we are requesting
    // 6 bytes (addr[2:0] = 3'b010) in the first AXI beat. The appropriate UMI
    // length is 5. This formula extends 3'b010 with 5 1s i.e. 8'b1111_1_010.
    // Then the number is inverted giving us 8'b0000_0_101 - the correct len.
    assign umi_req_cmd_len    = ~{{(8-DWLOG){1'b1}}, axi_araddr_byte_r};
    assign umi_req_cmd_prot   = axi_arprot_r[1:0];
    assign umi_req_cmd_qos    = axi_arqos_r[3:0];
    // Every request contains an EOM which is used to aggregate the data
    // before sending an AXI read response beat
    assign umi_req_cmd_eom    = 1'b1;
    assign umi_req_cmd_ex     = axi_arlock_r;

    umi_pack #(
        .CW                 (CW)
    ) umi_req_pack (
        .cmd_opcode         (umi_req_cmd_opcode),
        .cmd_size           (3'b0),
        .cmd_len            (umi_req_cmd_len),
        .cmd_atype          (8'b0),
        .cmd_prot           (umi_req_cmd_prot),
        .cmd_qos            (umi_req_cmd_qos),
        .cmd_eom            (umi_req_cmd_eom),
        .cmd_eof            (1'b0),
        .cmd_user           (2'b0),
        .cmd_err            (2'b00),
        .cmd_ex             (umi_req_cmd_ex),
        .cmd_hostid         (5'b0),
        .cmd_user_extended  (24'b0),

        .packet_cmd         (uhost_req_cmd)
    );

    assign umi_req_cmd_len_plus_one = umi_req_cmd_len + 1;

    wire [23:0] chip_address = {{(24-IDW){1'b0}}, chipid};

    assign uhost_req_dstaddr = {axi_araddr_line_r, axi_araddr_byte_r};
    assign uhost_req_srcaddr = {chip_address, local_routing, 24'b0};
    assign uhost_req_data    = 'b0;
    assign uhost_req_valid   = (axi_arbeats_rem > 0) & reset_done;

    // UMI response
    wire [4:0]  umi_resp_cmd_opcode;
    wire [7:0]  umi_resp_cmd_len;
    wire [8:0]  umi_resp_cmd_len_plus_one;
    wire        umi_resp_cmd_eom;
    wire [1:0]  umi_resp_cmd_err;

    reg  [1:0]  umi_resp_cmd_err_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            umi_resp_cmd_err_r <= 'b0;
        else if (axi_arvalid & axi_arready)
            umi_resp_cmd_err_r <= 'b0;
        else if (uhost_resp_valid & uhost_resp_ready & (|umi_resp_cmd_err))
            umi_resp_cmd_err_r <= umi_resp_cmd_err;
    end

    umi_unpack #(
        .CW     (CW)
    ) axi2umi_resp_unpack (
        // Input CMD
        .packet_cmd         (uhost_resp_cmd),

        // Output Fields
        .cmd_opcode         (umi_resp_cmd_opcode),
        .cmd_size           (),
        .cmd_len            (umi_resp_cmd_len),
        .cmd_atype          (),
        .cmd_qos            (),
        .cmd_prot           (),
        .cmd_eom            (umi_resp_cmd_eom),
        .cmd_eof            (),
        .cmd_ex             (),
        .cmd_user           (),
        .cmd_user_extended  (),
        .cmd_err            (umi_resp_cmd_err),
        .cmd_hostid         ()
    );

    assign umi_resp_cmd_len_plus_one = umi_resp_cmd_len + 1;
    assign uhost_resp_ready = (axi_rready | !uhost_resp_valid_r) & reset_done;

    // Read response
    reg  [(DWLOG+8):0]  tx_bytes_ctr;
    wire [(DWLOG+8):0]  tx_bytes_req;
    wire [(DWLOG+8):0]  tx_bytes_resp;

    assign tx_bytes_req  = {{DWLOG{1'b0}}, umi_req_cmd_len_plus_one};
    assign tx_bytes_resp = {{DWLOG{1'b0}}, umi_resp_cmd_len_plus_one};

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            tx_bytes_ctr <= 'b0;
        else if (uhost_req_valid & uhost_req_ready &
                 uhost_resp_valid & uhost_resp_ready)
            tx_bytes_ctr <= tx_bytes_ctr + tx_bytes_req  - tx_bytes_resp;
        else if (uhost_req_valid & uhost_req_ready)
            tx_bytes_ctr <= tx_bytes_ctr + tx_bytes_req;
        else if (uhost_resp_valid & uhost_resp_ready)
            tx_bytes_ctr <= tx_bytes_ctr - tx_bytes_resp;
    end

    genvar              i;
    wire [DW-1:0]       uhost_resp_data_masked;
    wire [DWLOG+3:0]    uhost_resp_data_shift;
    reg  [DW-1:0]       uhost_resp_data_r;
    reg                 uhost_resp_valid_r;
    reg  [DWLOG+2:0]    axi_rdata_shift;

    assign uhost_resp_data_shift = {umi_resp_cmd_len_plus_one[DWLOG:0], 3'b000};

    for (i = 0; i < (DW/8); i = i + 1) begin
        assign uhost_resp_data_masked[i*8+:8] = (i < umi_resp_cmd_len_plus_one) ?
                                                {8{1'b1}} :
                                                {8{1'b0}};
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            uhost_resp_data_r <= 'b0;
        else if (uhost_resp_valid & uhost_resp_ready)
            uhost_resp_data_r <= (axi_rdata << uhost_resp_data_shift) |
                                 (uhost_resp_data & uhost_resp_data_masked);
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            uhost_resp_valid_r <= 1'b0;
        else if (uhost_resp_valid & uhost_resp_ready & umi_resp_cmd_eom)
            uhost_resp_valid_r <= 1'b1;
        else if (axi_rvalid & axi_rready)
            uhost_resp_valid_r <= 1'b0;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_rdata_shift <= 'b0;
        else if (axi_arvalid & axi_arready)
            axi_rdata_shift <= {axi_araddr[DWLOG-1:0], 3'b000};
        else if (axi_rvalid & axi_rready)
            axi_rdata_shift <= 'b0;
    end

    assign axi_rid    = axi_arid_r;
    assign axi_rdata  = uhost_resp_data_r << axi_rdata_shift;
    assign axi_rresp  = umi_resp_cmd_err_r;
    assign axi_rlast  = (tx_bytes_ctr == 0) & (axi_arbeats_rem == 0) &
                        read_in_flight & reset_done;
    assign axi_rvalid = uhost_resp_valid_r & reset_done;

endmodule
