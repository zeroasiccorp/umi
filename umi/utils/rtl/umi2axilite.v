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
 * - UMI to AXI4-Lite converter
 *
 ******************************************************************************/

`default_nettype wire

module umi2axilite #(
    parameter CW    = 32,   // command width
    parameter AW    = 64,   // address width
    parameter DW    = 64    // umi packet width
)
(
    input               clk,
    input               nreset,

    // UMI Device port
    input               udev_req_valid,
    input  [CW-1:0]     udev_req_cmd,
    input  [AW-1:0]     udev_req_dstaddr,
    input  [AW-1:0]     udev_req_srcaddr,
    input  [DW-1:0]     udev_req_data,
    output              udev_req_ready,

    output              udev_resp_valid,
    output [CW-1:0]     udev_resp_cmd,
    output [AW-1:0]     udev_resp_dstaddr,
    output [AW-1:0]     udev_resp_srcaddr,
    output [DW-1:0]     udev_resp_data,
    input               udev_resp_ready,

    // AXI4Lite Interface
    output [AW-1:0]     axi_awaddr,
    output [2:0]        axi_awprot,
    output              axi_awvalid,
    input               axi_awready,

    output [DW-1:0]     axi_wdata,
    output [(DW/8)-1:0] axi_wstrb,
    output              axi_wvalid,
    input               axi_wready,

    input  [1:0]        axi_bresp,
    input               axi_bvalid,
    output              axi_bready,

    output [AW-1:0]     axi_araddr,
    output [2:0]        axi_arprot,
    output              axi_arvalid,
    input               axi_arready,

    input  [DW-1:0]     axi_rdata,
    input  [1:0]        axi_rresp,
    input               axi_rvalid,
    output              axi_rready
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

    // Split incoming requests
    wire                ff_out_req_valid;
    wire [CW-1:0]       ff_out_req_cmd;
    wire [AW-1:0]       ff_out_req_dstaddr;
    wire [AW-1:0]       ff_out_req_srcaddr;
    wire [DW-1:0]       ff_out_req_data;
    wire                ff_out_req_ready;

    umi_fifo_flex #(
        .TARGET         ("DEFAULT"),
        .ASYNC          (0),
        .SPLIT          (1),
        .DEPTH          (0),
        .CW             (CW),
        .AW             (AW),
        .IDW            (DW),
        .ODW            (DW)
    ) umi2axilite_req_fifo_flex (
        .bypass         (1'b1),
        .chaosmode      (1'b0),
        .fifo_full      (),
        .fifo_empty     (),

        // Input
        .umi_in_clk     (clk),
        .umi_in_nreset  (nreset),
        .umi_in_valid   (udev_req_valid),
        .umi_in_cmd     (udev_req_cmd),
        .umi_in_dstaddr (udev_req_dstaddr),
        .umi_in_srcaddr (udev_req_srcaddr),
        .umi_in_data    (udev_req_data),
        .umi_in_ready   (udev_req_ready),

        // Output
        .umi_out_clk    (clk),
        .umi_out_nreset (nreset),
        .umi_out_valid  (ff_out_req_valid),
        .umi_out_cmd    (ff_out_req_cmd),
        .umi_out_dstaddr(ff_out_req_dstaddr),
        .umi_out_srcaddr(ff_out_req_srcaddr),
        .umi_out_data   (ff_out_req_data),
        .umi_out_ready  (ff_out_req_ready),

        // Supplies
        .vdd            (1'b1),
        .vss            (1'b0)
    );

    // UMI request unpack
    wire [4:0]  ff_out_req_cmd_opcode;
    wire [2:0]  ff_out_req_cmd_size;
    wire [7:0]  ff_out_req_cmd_len;

    umi_unpack #(
        .CW     (CW)
    ) umi2axilite_ff_req_unpack (
        // Input CMD
        .packet_cmd         (ff_out_req_cmd),

        // Output Fields
        .cmd_opcode         (ff_out_req_cmd_opcode),
        .cmd_size           (ff_out_req_cmd_size),
        .cmd_len            (ff_out_req_cmd_len),
        .cmd_atype          (),
        .cmd_qos            (),
        .cmd_prot           (),
        .cmd_eom            (),
        .cmd_eof            (),
        .cmd_ex             (),
        .cmd_user           (),
        .cmd_user_extended  (),
        .cmd_err            (),
        .cmd_hostid         ()
    );

    // UMI request (post split) buffering
    reg  [CW-1:0]       ff_out_req_cmd_r;
    reg  [AW-1:0]       ff_out_req_dstaddr_r;
    reg  [AW-1:0]       ff_out_req_srcaddr_r;
    reg  [DW-1:0]       ff_out_req_data_shifted_r;
    reg  [(DW/8)-1:0]   ff_out_req_data_strb_r;
    reg  [DWLOG-1:0]    req_data_shift_r;

    wire [DWLOG-1:0]    req_data_shift;
    wire [8:0]          ff_out_req_cmd_len_plus_one;
    wire [15:0]         req_data_bytes;
    wire [(DW/8)-1:0]   ff_out_req_data_strb_unshifted;

    genvar i;

    assign req_data_shift = ff_out_req_dstaddr[DWLOG-1:0];

    assign ff_out_req_cmd_len_plus_one = (ff_out_req_cmd_len + 1);
    assign req_data_bytes = {7'b0, ff_out_req_cmd_len_plus_one} << ff_out_req_cmd_size;

    for (i = 0; i < (DW/8); i = i + 1) begin
        assign ff_out_req_data_strb_unshifted[i] = (i < req_data_bytes) ? 1'b1 : 1'b0;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            ff_out_req_cmd_r            <= 'b0;
            ff_out_req_dstaddr_r        <= 'b0;
            ff_out_req_srcaddr_r        <= 'b0;
            ff_out_req_data_shifted_r   <= 'b0;
            ff_out_req_data_strb_r      <= 'b0;
            req_data_shift_r            <= 'b0;
        end
        else if (ff_out_req_valid & ff_out_req_ready) begin
            ff_out_req_cmd_r            <= ff_out_req_cmd;
            ff_out_req_dstaddr_r        <= ff_out_req_dstaddr;
            ff_out_req_srcaddr_r        <= ff_out_req_srcaddr;
            ff_out_req_data_shifted_r   <= ff_out_req_data << (req_data_shift << 3);
            ff_out_req_data_strb_r      <= ff_out_req_data_strb_unshifted << req_data_shift;
            req_data_shift_r            <= req_data_shift;
        end
    end

    wire                axi_write_en;
    wire                axi_read_en;
    reg                 axi_awvalid_r;
    reg                 axi_wvalid_r;
    reg                 axi_arvalid_r;

    assign axi_write_en = ff_out_req_valid &
                          ff_out_req_ready &
                          ((ff_out_req_cmd_opcode == UMI_REQ_WRITE) |
                          (ff_out_req_cmd_opcode == UMI_REQ_POSTED));

    assign axi_read_en  = ff_out_req_valid &
                          ff_out_req_ready &
                          (ff_out_req_cmd_opcode == UMI_REQ_READ);

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_awvalid_r <= 1'b0;
        else if (axi_write_en)
            axi_awvalid_r <= 1'b1;
        else if (axi_awvalid & axi_awready)
            axi_awvalid_r <= 1'b0;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_wvalid_r <= 1'b0;
        else if (axi_write_en)
            axi_wvalid_r <= 1'b1;
        else if (axi_wvalid & axi_wready)
            axi_wvalid_r <= 1'b0;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_arvalid_r <= 1'b0;
        else if (axi_read_en)
            axi_arvalid_r <= 1'b1;
        else if (axi_arvalid & axi_arready)
            axi_arvalid_r <= 1'b0;
    end

    wire [4:0]  ff_out_req_cmd_opcode_r;
    wire [2:0]  ff_out_req_cmd_size_r;
    wire [7:0]  ff_out_req_cmd_len_r;
    wire [7:0]  ff_out_req_cmd_atype_r;
    wire [3:0]  ff_out_req_cmd_qos_r;
    wire [1:0]  ff_out_req_cmd_prot_r;
    wire        ff_out_req_cmd_eom_r;
    wire        ff_out_req_cmd_eof_r;
    wire        ff_out_req_cmd_ex_r;
    wire [1:0]  ff_out_req_cmd_user_r;
    wire [23:0] ff_out_req_cmd_user_extended_r;
    wire [1:0]  ff_out_req_cmd_err_r;
    wire [4:0]  ff_out_req_cmd_hostid_r;

    umi_unpack #(
        .CW     (CW)
    ) umi2axilite_ff_req_r_unpack (
        // Input CMD
        .packet_cmd         (ff_out_req_cmd_r),

        // Output Fields
        .cmd_opcode         (ff_out_req_cmd_opcode_r),
        .cmd_size           (ff_out_req_cmd_size_r),
        .cmd_len            (ff_out_req_cmd_len_r),
        .cmd_atype          (ff_out_req_cmd_atype_r),
        .cmd_qos            (ff_out_req_cmd_qos_r),
        .cmd_prot           (ff_out_req_cmd_prot_r),
        .cmd_eom            (ff_out_req_cmd_eom_r),
        .cmd_eof            (ff_out_req_cmd_eof_r),
        .cmd_ex             (ff_out_req_cmd_ex_r),
        .cmd_user           (ff_out_req_cmd_user_r),
        .cmd_user_extended  (ff_out_req_cmd_user_extended_r),
        .cmd_err            (ff_out_req_cmd_err_r),
        .cmd_hostid         (ff_out_req_cmd_hostid_r)
    );

    // AXI write address bus
    assign axi_awaddr   = ff_out_req_dstaddr_r;
    assign axi_awprot   = {1'b0, ff_out_req_cmd_prot_r};
    assign axi_awvalid  = axi_awvalid_r & reset_done;

    // AXI write data bus
    assign axi_wdata    = ff_out_req_data_shifted_r;
    assign axi_wstrb    = ff_out_req_data_strb_r;
    assign axi_wvalid   = axi_wvalid_r & reset_done;

    // AXI read address bus
    assign axi_araddr   = ff_out_req_dstaddr_r;
    assign axi_arprot   = {1'b0, ff_out_req_cmd_prot_r};
    assign axi_arvalid  = axi_arvalid_r & reset_done;

    // One request at a time
    reg                 umi_req_in_flight;
    wire                umi_req_done;

    assign umi_req_done = (ff_out_req_cmd_opcode_r == UMI_REQ_POSTED) ?
                          (axi_bvalid & axi_bready) :
                          (udev_resp_valid & udev_resp_ready);

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            umi_req_in_flight <= 1'b0;
        else if (ff_out_req_valid & ff_out_req_ready)
            umi_req_in_flight <= 1'b1;
        else if (umi_req_done)
            umi_req_in_flight <= 1'b0;
    end

    assign ff_out_req_ready = !umi_req_in_flight & reset_done;

    // AXI response
    wire [4:0]  udev_resp_cmd_opcode;
    wire [1:0]  udev_resp_cmd_err;

    assign udev_resp_cmd_opcode = (ff_out_req_cmd_opcode_r == UMI_REQ_WRITE) ?
                                  UMI_RESP_WRITE : UMI_RESP_READ;

    assign udev_resp_cmd_err = (ff_out_req_cmd_opcode_r == UMI_REQ_WRITE) ?
                               axi_bresp : axi_rresp;

    umi_pack #(
        .CW                 (CW)
    ) umi_req_pack (
        .cmd_opcode         (udev_resp_cmd_opcode),
        .cmd_size           (ff_out_req_cmd_size_r),
        .cmd_len            (ff_out_req_cmd_len_r),
        .cmd_atype          (ff_out_req_cmd_atype_r),
        .cmd_prot           (ff_out_req_cmd_prot_r),
        .cmd_qos            (ff_out_req_cmd_qos_r),
        .cmd_eom            (ff_out_req_cmd_eom_r),
        .cmd_eof            (ff_out_req_cmd_eof_r),
        .cmd_user           (ff_out_req_cmd_user_r),
        .cmd_err            (udev_resp_cmd_err),
        .cmd_ex             (ff_out_req_cmd_ex_r),
        .cmd_hostid         (ff_out_req_cmd_hostid_r),
        .cmd_user_extended  (ff_out_req_cmd_user_extended_r),

        .packet_cmd         (udev_resp_cmd)
    );

    assign udev_resp_dstaddr = ff_out_req_srcaddr_r;
    assign udev_resp_srcaddr = ff_out_req_dstaddr_r;
    assign udev_resp_data = axi_rdata >> (req_data_shift_r << 3);
    assign udev_resp_valid = (ff_out_req_cmd_opcode_r == UMI_REQ_WRITE) ?
                             axi_bvalid : axi_rvalid;

    // AXI write response ready
    // Discard response in case of posted writes
    assign axi_bready = udev_resp_ready &
                        ((ff_out_req_cmd_opcode_r == UMI_REQ_WRITE) |
                        (ff_out_req_cmd_opcode_r == UMI_REQ_POSTED));

    // AXI read response ready
    assign axi_rready = udev_resp_ready &
                        (ff_out_req_cmd_opcode_r == UMI_REQ_READ);

endmodule
