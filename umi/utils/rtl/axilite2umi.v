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
 * - AXI4-Lite to UMI converter
 *
 ******************************************************************************/

`default_nettype wire

module axilite2umi #(
    parameter CW    = 32,   // command width
    parameter AW    = 64,   // address width
    parameter DW    = 64,   // umi packet width
    parameter IDW   = 16    // chip ID width
)
(
    input               clk,
    input               nreset,
    input  [IDW-1:0]    chipid,
    input  [15:0]       local_routing,

    // AXI4Lite Interface
    input  [AW-1:0]     axi_awaddr,
    input  [2:0]        axi_awprot,
    input               axi_awvalid,
    output              axi_awready,

    input  [DW-1:0]     axi_wdata,
    input  [(DW/8)-1:0] axi_wstrb,
    input               axi_wvalid,
    output              axi_wready,

    output [1:0]        axi_bresp,
    output              axi_bvalid,
    input               axi_bready,

    input  [AW-1:0]     axi_araddr,
    input  [2:0]        axi_arprot,
    input               axi_arvalid,
    output              axi_arready,

    output [DW-1:0]     axi_rdata,
    output [1:0]        axi_rresp,
    output              axi_rvalid,
    input               axi_rready,

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

    localparam DWLOG = $clog2(DW/8);

    // Additional UMI signals
    wire [4:0]      umi_req_cmd_opcode;
    wire [7:0]      umi_req_cmd_len;
    wire [1:0]      umi_req_cmd_prot;

    wire    reset_done;

    la_drsync la_drsync_i (
        .clk     (clk),
        .nreset  (nreset),
        .in      (1'b1),
        .out     (reset_done)
    );

    reg                 write_in_flight;
    reg                 read_in_flight;

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            write_in_flight <= 1'b0;
        else if (axi_awvalid & axi_awready)
            write_in_flight <= 1'b1;
        else if (axi_bvalid & axi_bready)
            write_in_flight <= 1'b0;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            read_in_flight <= 1'b0;
        else if (axi_arvalid & axi_arready)
            read_in_flight <= 1'b1;
        else if (axi_rvalid & axi_rready)
            read_in_flight <= 1'b0;
    end

    // Write Address
    reg  [AW-1:0]       axi_awaddr_r;
    reg  [2:0]          axi_awprot_r;
    reg                 axi_awvalid_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_awaddr_r    <= 'b0;
            axi_awprot_r    <= 'b0;
        end
        else if (axi_awvalid & axi_awready) begin
            axi_awaddr_r    <= axi_awaddr;
            axi_awprot_r    <= axi_awprot;
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_awvalid_r   <= 1'b0;
        else if (axi_awvalid & axi_awready)
            axi_awvalid_r   <= 1'b1;
        else if (uhost_req_valid & uhost_req_ready & (umi_req_cmd_opcode == UMI_REQ_WRITE))
            axi_awvalid_r   <= 1'b0;
    end

    // Write data prep
    integer             i;
    reg  [DWLOG:0]      axi_wstrb_ctr;
    reg  [(DW/8)-1:0]   axi_wstrb_cml_one;
    reg  [DWLOG-1:0]    axi_wdata_byte_shift;

    always @* begin
        axi_wstrb_ctr = {(DWLOG + 1){1'b0}};
        for (i = 0; i < (DW/8); i = i + 1) begin
            axi_wstrb_ctr = axi_wstrb_ctr + {{(DWLOG){1'b0}}, axi_wstrb[i]};
        end

        axi_wstrb_cml_one[0] = axi_wstrb[0];
        for (i = 1; i < (DW/8); i = i + 1) begin
            axi_wstrb_cml_one[i] = axi_wstrb[i] | axi_wstrb_cml_one[i-1];
        end

        axi_wdata_byte_shift = {(DWLOG){1'b0}};
        for (i = 1; i < (DW/8); i = i + 1) begin
            if (axi_wstrb[i] & !axi_wstrb_cml_one[i-1])
                axi_wdata_byte_shift = axi_wdata_byte_shift | i[DWLOG-1:0];
        end
    end

    assign axi_awready = !(write_in_flight | read_in_flight) & reset_done;

    // Write data
    reg  [DW-1:0]       axi_wdata_r;
    reg  [(DW/8)-1:0]   axi_wstrb_r;
    reg  [DWLOG:0]      axi_wstrb_ctr_r;
    reg  [AW-1:0]       axi_addr_offset;
    reg                 axi_wvalid_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_wdata_r     <= 'b0;
            axi_wstrb_r     <= 'b0;
            axi_wstrb_ctr_r <= 'b0;
            axi_addr_offset <= 'b0;
        end
        else if (axi_wvalid & axi_wready) begin
            axi_wdata_r     <= axi_wdata >> ({3'b000, axi_wdata_byte_shift} << 3);
            axi_wstrb_r     <= axi_wstrb;
            axi_wstrb_ctr_r <= axi_wstrb_ctr;
            axi_addr_offset <= {{(AW-DWLOG){1'b0}}, axi_wdata_byte_shift};
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_wvalid_r    <= 1'b0;
        else if (axi_wvalid & axi_wready)
            axi_wvalid_r    <= 1'b1;
        else if (uhost_req_valid & uhost_req_ready & (umi_req_cmd_opcode == UMI_REQ_WRITE))
            axi_wvalid_r    <= 1'b0;
    end

    assign axi_wready  = axi_awvalid_r & !axi_wvalid_r & reset_done;

    // Read address
    reg  [AW-1:0]   axi_araddr_r;
    reg  [2:0]      axi_arprot_r;
    reg             axi_arvalid_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_araddr_r    <= 'b0;
            axi_arprot_r    <= 'b0;
        end
        else if (axi_arvalid & axi_arready) begin
            axi_araddr_r    <= axi_araddr;
            axi_arprot_r    <= axi_arprot;
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_arvalid_r   <= 1'b0;
        else if (axi_arvalid & axi_arready)
            axi_arvalid_r   <= 1'b1;
        else if (uhost_req_valid & uhost_req_ready & (umi_req_cmd_opcode == UMI_REQ_READ))
            axi_arvalid_r   <= 1'b0;
    end

    assign axi_arready = !(write_in_flight | read_in_flight) & reset_done;

    // UMI request

    assign umi_req_cmd_opcode = write_in_flight ?
                                UMI_REQ_WRITE :
                                UMI_REQ_READ;
    assign umi_req_cmd_len    = write_in_flight ?
                                (axi_wstrb_ctr_r-1) :
                                ((DW/8)-1);
    assign umi_req_cmd_prot   = write_in_flight ?
                                axi_awprot_r[1:0] :
                                axi_arprot_r[1:0];

    umi_pack #(
        .CW                 (CW)
    ) umi_req_pack (
        .cmd_opcode         (umi_req_cmd_opcode),
        .cmd_size           (3'b0),
        .cmd_len            (umi_req_cmd_len),
        .cmd_atype          (8'b0),
        .cmd_prot           (umi_req_cmd_prot),
        .cmd_qos            (4'b0),
        .cmd_eom            (1'b1),
        .cmd_eof            (1'b0),
        .cmd_user           (2'b0),
        .cmd_err            (2'b00),
        .cmd_ex             (1'b0),
        .cmd_hostid         (5'b0),
        .cmd_user_extended  (24'b0),

        .packet_cmd         (uhost_req_cmd)
    );

    wire [23:0] chip_address = {{(24-IDW){1'b0}}, chipid};

    assign uhost_req_dstaddr = write_in_flight ?
                               (axi_awaddr_r + axi_addr_offset) :
                               axi_araddr_r;
    assign uhost_req_srcaddr = {chip_address, local_routing, 24'b0};
    assign uhost_req_data    = axi_wdata_r;
    assign uhost_req_valid   = write_in_flight ?
                               (axi_awvalid_r & axi_wvalid_r & reset_done) :
                               (axi_arvalid_r & reset_done);

    // UMI response
    wire [4:0]  umi_resp_cmd_opcode;
    wire [2:0]  umi_resp_cmd_size;
    wire [7:0]  umi_resp_cmd_len;
    wire        umi_resp_cmd_eom;
    wire [1:0]  umi_resp_cmd_err;

    umi_unpack #(
        .CW     (CW)
    ) axilite2umi_resp_unpack (
        // Input CMD
        .packet_cmd         (uhost_resp_cmd),

        // Output Fields
        .cmd_opcode         (umi_resp_cmd_opcode),
        .cmd_size           (umi_resp_cmd_size),
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

    assign uhost_resp_ready = write_in_flight ?
                              (axi_bready & reset_done) :
                              (axi_rready & reset_done);

    // Read response
    assign axi_rdata  = uhost_resp_data;
    assign axi_rresp  = umi_resp_cmd_err;
    assign axi_rvalid = read_in_flight &
                        uhost_resp_valid &
                        (umi_resp_cmd_opcode == UMI_RESP_READ) &
                        reset_done;

    // Write response
    assign axi_bresp  = umi_resp_cmd_err;
    assign axi_bvalid = write_in_flight &
                        uhost_resp_valid &
                        (umi_resp_cmd_opcode == UMI_RESP_WRITE) &
                        reset_done;

endmodule
