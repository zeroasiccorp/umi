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
 * - AXI4 write channels (AW, W, B) to UMI converter
 *
 ******************************************************************************/

`default_nettype wire

module axiwrite2umi #(
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

    // AXI4 Write Interface
    input  [AXI_IDW-1:0]    axi_awid,
    input  [AW-1:0]         axi_awaddr,
    input  [7:0]            axi_awlen,
    input  [2:0]            axi_awsize,
    input  [1:0]            axi_awburst,
    input                   axi_awlock,
    input  [3:0]            axi_awcache,
    input  [2:0]            axi_awprot,
    input  [3:0]            axi_awqos,
    input  [3:0]            axi_awregion,
    input                   axi_awvalid,
    output                  axi_awready,

    input  [AXI_IDW-1:0]    axi_wid,
    input  [DW-1:0]         axi_wdata,
    input  [(DW/8)-1:0]     axi_wstrb,
    input                   axi_wlast,
    input                   axi_wvalid,
    output                  axi_wready,

    output [AXI_IDW-1:0]    axi_bid,
    output [1:0]            axi_bresp,
    output                  axi_bvalid,
    input                   axi_bready,

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

    reg             wlast_protcol_violation;
    reg             wid_protocol_violation;
    wire            any_protocol_violation;

    assign any_protocol_violation = wid_protocol_violation |
                                    wlast_protcol_violation;

    reg                 write_in_flight;

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            write_in_flight <= 1'b0;
        else if (axi_awvalid & axi_awready)
            write_in_flight <= 1'b1;
        else if (axi_bvalid & axi_bready)
            write_in_flight <= 1'b0;
    end

    // Write Address
    reg  [AXI_IDW-1:0]  axi_awid_r;
    reg  [AW-1:0]       axi_awaddr_r;
    reg  [8:0]          axi_wbeats_rem;
    reg  [2:0]          axi_awsize_r;
    reg  [1:0]          axi_awburst_r;
    reg                 axi_awlock_r;
    reg  [3:0]          axi_awcache_r;
    reg  [2:0]          axi_awprot_r;
    reg  [3:0]          axi_awqos_r;
    reg  [3:0]          axi_awregion_r;
    reg                 axi_awvalid_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_awid_r      <= 'b0;
            axi_awsize_r    <= 'b0;
            axi_awburst_r   <= 'b0;
            axi_awlock_r    <= 'b0;
            axi_awcache_r   <= 'b0;
            axi_awprot_r    <= 'b0;
            axi_awqos_r     <= 'b0;
            axi_awregion_r  <= 'b0;
        end
        else if (axi_awvalid & axi_awready) begin
            axi_awid_r      <= axi_awid;
            axi_awsize_r    <= axi_awsize;
            axi_awburst_r   <= axi_awburst;
            axi_awlock_r    <= axi_awlock;
            axi_awcache_r   <= axi_awcache;
            axi_awprot_r    <= axi_awprot;
            axi_awqos_r     <= axi_awqos;
            axi_awregion_r  <= axi_awregion;
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_awaddr_r <= 'b0;
        else if (axi_awvalid & axi_awready)
            axi_awaddr_r <= axi_awaddr & ({AW{1'b1}} << DWLOG);
        else if (uhost_req_valid & uhost_req_ready)
            axi_awaddr_r <= axi_awaddr_r + (DW/8);
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_wbeats_rem <= 'b0;
        else if (axi_awvalid & axi_awready)
            axi_wbeats_rem <= axi_awlen + 1;
        else if (axi_wvalid & axi_wready)
            axi_wbeats_rem <= axi_wbeats_rem - 1;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_awvalid_r <= 1'b0;
        else if (axi_awvalid & axi_awready)
            axi_awvalid_r <= 1'b1;
        else if (axi_wvalid & axi_wready & (axi_wbeats_rem == 1))
            axi_awvalid_r <= 1'b0;
    end

    assign axi_awready = !write_in_flight & !any_protocol_violation & reset_done;

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

    // Write data
    reg  [AXI_IDW-1:0]  axi_wid_r;
    reg  [DW-1:0]       axi_wdata_r;
    reg  [(DW/8)-1:0]   axi_wstrb_r;
    reg  [7:0]          axi_wstrb_ctr_r;
    reg  [AW-1:0]       axi_addr_offset;
    reg                 axi_wlast_r;
    reg                 axi_wvalid_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_wid_r       <= 'b0;
            axi_wdata_r     <= 'b0;
            axi_wstrb_r     <= 'b0;
            axi_wstrb_ctr_r <= 'b0;
            axi_addr_offset <= 'b0;
        end
        else if (axi_wvalid & axi_wready) begin
            axi_wid_r       <= axi_wid;
            axi_wdata_r     <= axi_wdata >> {axi_wdata_byte_shift, 3'b000};
            axi_wstrb_r     <= axi_wstrb;
            axi_wstrb_ctr_r <= {{(7-DWLOG){1'b0}}, axi_wstrb_ctr};
            axi_addr_offset <= {{(AW-DWLOG){1'b0}}, axi_wdata_byte_shift};
        end
    end

    // Assert wid protocol violation if needed
    // No further beats will be accepted if asserted
    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            wid_protocol_violation <= 1'b0;
        else if (axi_wvalid & axi_wready & (axi_wid != axi_awid_r))
            wid_protocol_violation <= 1'b1;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_wlast_r <= 1'b0;
        else if (axi_wvalid & axi_wready)
            axi_wlast_r <= axi_wlast;
        else if (axi_bvalid & axi_bready)
            axi_wlast_r <= 1'b0;
    end

    // Assert wlast protocol violation if needed
    // No further beats will be accepted if asserted
    // Protocol is not violated if and only if last_r=1 and beats_remaining=0
    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            wlast_protcol_violation <= 1'b0;
        else if (axi_bvalid & axi_bready & !(axi_wlast_r & (axi_wbeats_rem == 0)))
            wlast_protcol_violation <= 1'b1;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            axi_wvalid_r <= 1'b0;
        else if (axi_wvalid & axi_wready)
            axi_wvalid_r <= 1'b1;
        else if (uhost_req_valid & uhost_req_ready)
            axi_wvalid_r <= 1'b0;
    end

    assign axi_wready  = (axi_wbeats_rem > 0) & uhost_req_ready &
                         !any_protocol_violation & reset_done;

    // UMI request
    wire [4:0]      umi_req_cmd_opcode;
    wire [7:0]      umi_req_cmd_len;
    wire [1:0]      umi_req_cmd_prot;
    wire [3:0]      umi_req_cmd_qos;
    wire            umi_req_cmd_eom;
    wire            umi_req_cmd_ex;

    assign umi_req_cmd_opcode = UMI_REQ_WRITE;
    assign umi_req_cmd_len    = axi_wstrb_ctr_r-1;
    assign umi_req_cmd_prot   = axi_awprot_r[1:0];
    assign umi_req_cmd_qos    = axi_awqos_r[3:0];
    assign umi_req_cmd_eom    = axi_wlast_r;
    assign umi_req_cmd_ex     = axi_awlock_r;

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

    wire [23:0] chip_address = {{(24-IDW){1'b0}}, chipid};

    assign uhost_req_dstaddr = axi_awaddr_r + axi_addr_offset;
    assign uhost_req_srcaddr = {chip_address, local_routing, 24'b0};
    assign uhost_req_data    = axi_wdata_r;
    assign uhost_req_valid   = axi_wvalid_r & reset_done;

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
        else if (axi_awvalid & axi_awready)
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
    assign uhost_resp_ready          = reset_done;

    // Write response
    reg  [(DWLOG+8):0]  tx_bytes_ctr;
    wire [(DWLOG+8):0]  tx_bytes_req;
    wire [(DWLOG+8):0]  tx_bytes_resp;

    assign tx_bytes_req  = {{(DWLOG+1){1'b0}}, axi_wstrb_ctr_r};
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

    assign axi_bid    = axi_awid_r;
    assign axi_bresp  = umi_resp_cmd_err_r;
    assign axi_bvalid = (tx_bytes_ctr == 0) & (axi_wbeats_rem == 0) &
                        write_in_flight & reset_done;

endmodule
