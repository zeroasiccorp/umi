/*******************************************************************************
 * Copyright 2026 Zero ASIC Corporation
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
 *
 * - Proves umi2axil drives a legal AXI4-Lite manager interface, and
 *   that the SUMI response it builds matches the request it served.
 *
 * TWO PROTOCOLS. The UMI face is held to README.md section 4.2 by
 * umi_handshake_checker -- the request side in its ASSUME face, the
 * response side in its assert face, one rule list for both. The AXI
 * face is held to the AMBA AXI specification, section A3.2.1, written
 * out here rather than pulled from a vendor library.
 *
 * THE AXI RULE, ONCE, PER CHANNEL. AXI gives every channel the same
 * source obligation: once VALID is asserted it stays asserted until the
 * handshake completes, and the payload it carries does not move while
 * it waits. umi2axil is the manager, so it owns AW, W and AR; the
 * completer owns B and R.
 *
 *   asserted (the DUT is the source)
 *     AXIL_aw_hold / AXIL_aw_stable   write address channel
 *     AXIL_w_hold  / AXIL_w_stable    write data channel
 *     AXIL_ar_hold / AXIL_ar_stable   read address channel
 *
 *   assumed (the completer is the source)
 *     m_axil_b_hold / m_axil_b_stable
 *     m_axil_r_hold / m_axil_r_stable
 *
 * The six asserted laws are written out one per channel rather than
 * factored into a shared property module on purpose: a fault row pins
 * the LABEL sby reports, and a shared module would give all three
 * channels the same leaf label, so a fault in AW and a fault in W would
 * be indistinguishable in the lane. axil2umi will mirror this same law
 * set from the subordinate side, where the ownership is reversed.
 *
 * WHAT IS PROVEN ON THE UMI SIDE:
 *   RULE2_valid_hold / RULE3_*_stable  the response channel keeps the
 *                     README 4.2 handshake
 *   a_axil_kind       a REQ_WR is answered RESP_WR, a REQ_RD RESP_RD
 *                     (README 3.4.11, 3.4.12)
 *   a_axil_one_inflight  one request is served at a time
 *
 * THE RESPONSE DATA FIELD DOES NOT KEEP RULE 3. udev_resp_data is
 * axi_rdata shifted (umi2axil.v:350) with no term selecting which
 * response channel is live, while udev_resp_valid follows axi_bvalid
 * for a write and axi_rvalid for a read (umi2axil.v:351). So on a WRITE
 * response -- BVALID high, RVALID low -- the UMI payload is driven by
 * RDATA, which AXI leaves free whenever RVALID is low. The field moves
 * under a standing offer, which is a README 4.2 rule 3 violation on the
 * UMI face.
 *
 * The solver produced this rather than a source reading: the witness is
 * a REQ_WR (cmd[4:0] = 5'b00011) with RVALID low throughout and RDATA
 * taking two distinct values while udev_resp_valid stands and
 * udev_resp_ready is low.
 *
 * It is handled the way umi_ram's equivalent is: the green row masks
 * RULE3_data_stable (RESP_RULE_EN bit 4) so the other five rules are
 * still proven, and axil:fault_data leaves the rule in and REQUIRES the
 * failure. Nothing is injected on that row.
 *
 * THE OPCODE SET IS AN ASSUMPTION, AND IT IS FALSIFIABLE. m_axil_op
 * holds the request channel to READ, WRITE and POSTED, the three this
 * block maps. axil:hazard withdraws it and reaches both
 * c_axil_atomic_bus and c_axil_rdma_bus, so an atomic request starts a
 * real AXI write and an RDMA request a real AXI read -- the same
 * absence of an opcode filter apb:hazard finds in umi2apb. Read those
 * covers under the cover-mode caveat in the folder README: reachable,
 * not legal.
 *
 * NOT PROVEN HERE. The response address swap, the PROT mapping and the
 * AXI-to-UMI error code pass-through are single assigns off registered
 * request fields; asserting each against its own expression would be
 * the code read back. The read-data barrel shift
 * (umi2axil.v:350) is a width-and-offset claim that belongs with the
 * byte-accounting work umi_fifoflex also wants, and is not attempted.
 *
 * SCOPE. Bounded. One clock -- umi2axil is single-domain, and its
 * la_drsync reset synchroniser is driven from the same clock, so this
 * is the whole design rather than a simplification. The block splits
 * incoming requests through umi_fifoflex at SPLIT=1, the arm the SUMI
 * work pinned as not conserving bytes (fifoflex:fault_split); this
 * harness assumes a single-beat request that needs no splitting, so
 * that arm is not exercised here and the pinned finding stands
 * untouched.
 *
 * ROWS (tests/test_formal_sc.py):
 *   axil:bmc              the AXI and UMI laws, bounded, with
 *                         RESP_RULE_EN masking RULE3_data_stable
 *   axil:cover            witnesses: expect all reached
 *   axil:hazard           the opcode assumption withdrawn: an atomic
 *                         and an RDMA request each reach the AXI bus
 *   axil:fault_aw         must FAIL, AXIL_aw_hold
 *   axil:fault_w          must FAIL, AXIL_w_stable
 *   axil:fault_ar         must FAIL, AXIL_ar_hold
 *   axil:fault_kind       must FAIL, a_axil_kind
 *   axil:fault_lane       must FAIL, a_axil_wdata_lane. Nothing
 *                         injected -- the byte-lane shift amount is
 *                         evaluated at 3 bits and is always zero
 *   axil:fault_data       must FAIL, RULE3_data_stable. Nothing
 *                         injected -- the response data field moves
 *                         under a standing offer on a write response
 *
 ******************************************************************************/

`default_nettype none

module fv_umi2axil #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    // response-channel rule mask. Bit 4 is RULE3_data_stable, which the
    // block does not satisfy on a write response -- see the header.
    parameter [5:0] RESP_RULE_EN = 6'h3F
) (
    input wire clk
);

`include "umi_messages.vh"

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero (grounds all history)
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // free environment
    // ----------------------------------------------------------------
    (* anyseq *) wire          req_valid;
    (* anyseq *) wire [CW-1:0] req_cmd;
    (* anyseq *) wire [AW-1:0] req_dstaddr;
    (* anyseq *) wire [AW-1:0] req_srcaddr;
    (* anyseq *) wire [DW-1:0] req_data;
    (* anyseq *) wire          resp_ready;

    (* anyseq *) wire          awready, wready, arready;
    (* anyseq *) wire          bvalid, rvalid;
    (* anyseq *) wire [1:0]    bresp, rresp;
    (* anyseq *) wire [DW-1:0] rdata;

    wire            req_ready;
    wire            resp_valid;
    wire [CW-1:0]   resp_cmd;
    wire [AW-1:0]   resp_dstaddr;
    wire [AW-1:0]   resp_srcaddr;
    wire [DW-1:0]   resp_data;

    wire [AW-1:0]     awaddr, araddr;
    wire [2:0]        awprot, arprot;
    wire              awvalid, wvalid, arvalid;
    wire [DW-1:0]     wdata;
    wire [(DW/8)-1:0] wstrb;
    wire              bready, rready;

    umi2axil #(
        .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .clk              (clk),
        .nreset           (nreset),
        .udev_req_valid   (req_valid),
        .udev_req_cmd     (req_cmd),
        .udev_req_dstaddr (req_dstaddr),
        .udev_req_srcaddr (req_srcaddr),
        .udev_req_data    (req_data),
        .udev_req_ready   (req_ready),
        .udev_resp_valid  (resp_valid),
        .udev_resp_cmd    (resp_cmd),
        .udev_resp_dstaddr(resp_dstaddr),
        .udev_resp_srcaddr(resp_srcaddr),
        .udev_resp_data   (resp_data),
        .udev_resp_ready  (resp_ready),
        .axi_awaddr       (awaddr),
        .axi_awprot       (awprot),
        .axi_awvalid      (awvalid),
        .axi_awready      (awready),
        .axi_wdata        (wdata),
        .axi_wstrb        (wstrb),
        .axi_wvalid       (wvalid),
        .axi_wready       (wready),
        .axi_bresp        (bresp),
        .axi_bvalid       (bvalid),
        .axi_bready       (bready),
        .axi_araddr       (araddr),
        .axi_arprot       (arprot),
        .axi_arvalid      (arvalid),
        .axi_arready      (arready),
        .axi_rdata        (rdata),
        .axi_rresp        (rresp),
        .axi_rvalid       (rvalid),
        .axi_rready       (rready)
    );

    // ----------------------------------------------------------------
    // the UMI request face, constrained by the rule list the response
    // face is judged by
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (1)
    ) env_req (
        .clk (clk), .nreset (nreset),
        .valid (req_valid), .ready (req_ready),
        .cmd (req_cmd), .dstaddr (req_dstaddr),
        .srcaddr (req_srcaddr), .data (req_data)
    );

    // ----------------------------------------------------------------
    // the request shape: a single-beat access that fits one AXI4-Lite
    // transfer, which is what this adapter maps. Wider requests go
    // through the umi_fifoflex split arm, which the SUMI work pinned
    // separately.
    // ----------------------------------------------------------------
    wire [2:0] req_size = req_cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    wire [7:0] req_len  = req_cmd[UMI_LEN_MSB:UMI_LEN_LSB];
    wire [4:0] req_op   = req_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

    always @(*) begin
        m_axil_size : assume ((32'd1 << req_size) <= (DW / 8));
        m_axil_len  : assume (req_len == 8'd0);
    end

`ifndef FV_AXIL_ANYOP
    always @(*)
        m_axil_op : assume ((req_op == UMI_REQ_READ)
                            || (req_op == UMI_REQ_WRITE)
                            || (req_op == UMI_REQ_POSTED));
`endif

    // ----------------------------------------------------------------
    // history, and the observed outputs the laws read. Faults corrupt
    // what the laws see, never the DUT.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_AW
    wire obs_awvalid = awvalid & ~f_glitch;      // an offer withdrawn
`else
    wire obs_awvalid = awvalid;
`endif

`ifdef FV_FAULT_W
    wire [DW-1:0] obs_wdata = wdata ^ {{(DW-1){1'b0}}, f_glitch};
`else
    wire [DW-1:0] obs_wdata = wdata;
`endif

`ifdef FV_FAULT_AR
    wire obs_arvalid = arvalid & ~f_glitch;
`else
    wire obs_arvalid = arvalid;
`endif

`ifdef FV_FAULT_KIND
    // RESP_RD 0x02 and RESP_WR 0x04 differ by 0x06, so one constant
    // exchanges them without disturbing any other field
    wire [CW-1:0] obs_resp_cmd = resp_cmd ^ {{(CW-5){1'b0}}, 5'h06};
`else
    wire [CW-1:0] obs_resp_cmd = resp_cmd;
`endif

    reg awvalid_d, wvalid_d, arvalid_d;
    reg awready_d, wready_d, arready_d;
    reg [AW-1:0]     awaddr_d, araddr_d;
    reg [2:0]        awprot_d, arprot_d;
    reg [DW-1:0]     wdata_d;
    reg [(DW/8)-1:0] wstrb_d;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            awvalid_d <= 1'b0; wvalid_d <= 1'b0; arvalid_d <= 1'b0;
            awready_d <= 1'b0; wready_d <= 1'b0; arready_d <= 1'b0;
        end else begin
            awvalid_d <= obs_awvalid; wvalid_d <= wvalid; arvalid_d <= obs_arvalid;
            awready_d <= awready;     wready_d <= wready; arready_d <= arready;
        end

    always @(posedge clk) begin
        awaddr_d <= awaddr;  awprot_d <= awprot;
        araddr_d <= araddr;  arprot_d <= arprot;
        wdata_d  <= obs_wdata; wstrb_d <= wstrb;
    end

    // ----------------------------------------------------------------
    // AXI4-Lite manager obligations, AMBA AXI section A3.2.1
    // ----------------------------------------------------------------
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            AXIL_aw_hold   : assert (!(awvalid_d & ~awready_d) || obs_awvalid);
            AXIL_aw_stable : assert (!(awvalid_d & ~awready_d)
                                     || ((awaddr == awaddr_d)
                                         && (awprot == awprot_d)));
            AXIL_w_hold    : assert (!(wvalid_d & ~wready_d) || wvalid);
            AXIL_w_stable  : assert (!(wvalid_d & ~wready_d)
                                     || ((obs_wdata == wdata_d)
                                         && (wstrb == wstrb_d)));
            AXIL_ar_hold   : assert (!(arvalid_d & ~arready_d) || obs_arvalid);
            AXIL_ar_stable : assert (!(arvalid_d & ~arready_d)
                                     || ((araddr == araddr_d)
                                         && (arprot == arprot_d)));
        end

    // ----------------------------------------------------------------
    // the completer holds its side of the same rule
    // ----------------------------------------------------------------
    reg bvalid_d, rvalid_d, bready_d, rready_d;
    reg [1:0] bresp_d, rresp_d;
    reg [DW-1:0] rdata_d;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            bvalid_d <= 1'b0; rvalid_d <= 1'b0;
            bready_d <= 1'b0; rready_d <= 1'b0;
        end else begin
            bvalid_d <= bvalid; rvalid_d <= rvalid;
            bready_d <= bready; rready_d <= rready;
        end
    always @(posedge clk) begin
        bresp_d <= bresp; rresp_d <= rresp; rdata_d <= rdata;
    end

    // AXI requires a source to hold VALID low while the reset is
    // asserted. umi2axil gates its own AW/W/AR with reset_done
    // (umi2axil.v:287, 292, 297) but passes the completer's B/R VALID
    // straight through to udev_resp_valid (umi2axil.v:351), so a
    // completer that broke this rule would carry the breakage onto the
    // UMI face. Constraining the completer here is what makes the
    // response-side reset law a statement about the adapter.
    always @(*)
        m_axil_reset_quiet : assume (nreset || (!bvalid && !rvalid));

    // A completer answers only what it was asked. Without this the
    // solver is free to invent an R beat for a write, or a B beat for
    // nothing, which is not an AXI completer and would make every
    // downstream law a statement about an impossible environment.
    reg [1:0] ar_out, aw_out, w_out;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            ar_out <= 2'd0; aw_out <= 2'd0; w_out <= 2'd0;
        end else begin
            case ({obs_arvalid & arready, rvalid & rready})
                2'b10: ar_out <= ar_out + 2'd1;
                2'b01: ar_out <= ar_out - 2'd1;
                default: ar_out <= ar_out;
            endcase
            case ({obs_awvalid & awready, bvalid & bready})
                2'b10: aw_out <= aw_out + 2'd1;
                2'b01: aw_out <= aw_out - 2'd1;
                default: aw_out <= aw_out;
            endcase
            case ({wvalid & wready, bvalid & bready})
                2'b10: w_out <= w_out + 2'd1;
                2'b01: w_out <= w_out - 2'd1;
                default: w_out <= w_out;
            endcase
        end

    always @(*) begin
        m_axil_r_owed : assume (!rvalid || (ar_out != 2'd0));
        m_axil_b_owed : assume (!bvalid || ((aw_out != 2'd0)
                                            && (w_out != 2'd0)));
        // the adapter never issues more than one at a time, so the
        // counters cannot wrap; this keeps them honest
        m_axil_no_wrap : assume ((ar_out != 2'd3) && (aw_out != 2'd3)
                                 && (w_out != 2'd3));
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            m_axil_b_hold   : assume (!(bvalid_d & ~bready_d) || bvalid);
            m_axil_b_stable : assume (!(bvalid_d & ~bready_d)
                                      || (bresp == bresp_d));
            m_axil_r_hold   : assume (!(rvalid_d & ~rready_d) || rvalid);
            m_axil_r_stable : assume (!(rvalid_d & ~rready_d)
                                      || ((rresp == rresp_d)
                                          && (rdata == rdata_d)));
        end

    // ----------------------------------------------------------------
    // the UMI response face is judged by the same rule list
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (0),
        .RULE_EN (RESP_RULE_EN)
    ) chk_resp (
        .clk (clk), .nreset (nreset),
        .valid (resp_valid), .ready (resp_ready),
        .cmd (obs_resp_cmd), .dstaddr (resp_dstaddr),
        .srcaddr (resp_srcaddr), .data (resp_data)
    );

    // ----------------------------------------------------------------
    // the response answers the request. The opcode of the request being
    // served is shadowed from the PORTS at the cycle it is accepted.
    // ----------------------------------------------------------------
    wire req_fire = req_valid & req_ready;
    reg [4:0] served_op;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            served_op <= 5'd0;
        else if (req_fire)
            served_op <= req_op;

    // the accepted request, shadowed from the PORTS
    reg [AW-1:0] shadow_addr;
    reg [DW-1:0] shadow_data;
    always @(posedge clk)
        if (req_fire) begin
            shadow_addr <= req_dstaddr;
            shadow_data <= req_data;
        end

    localparam DWLOG = $clog2(DW / 8);

`ifdef FV_AXIL_ASSERT_LANE
    // AXI byte-lane placement: a write to address A must present its
    // data in the byte lanes A[DWLOG-1:0] selects. umi2axil intends
    // exactly this (umi2axil.v:200) but the shift amount it computes,
    // (req_data_shift << 3), is evaluated at the 3-bit width of
    // req_data_shift and is therefore always zero. This row asserts the
    // law and is pinned as a must-FAIL.
    wire [31:0] lane_bits =
        {{(32-DWLOG){1'b0}}, shadow_addr[DWLOG-1:0]} * 32'd8;
    always @(posedge clk)
        if (nreset & f_past_exists & wvalid)
            a_axil_wdata_lane : assert (obs_wdata == (shadow_data << lane_bits));
`endif

    wire [4:0] resp_op = obs_resp_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

    always @(posedge clk)
        if (nreset & f_past_exists & resp_valid)
            a_axil_kind : assert (resp_op == ((served_op == UMI_REQ_WRITE)
                                              ? UMI_RESP_WRITE : UMI_RESP_READ));

    // one request served at a time: a second cannot be accepted while
    // an answer for the first is still standing
    always @(posedge clk)
        if (nreset & f_past_exists)
            a_axil_one_inflight : assert (!(req_fire & resp_valid));

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_axil_aw     : cover (obs_awvalid & awready);
            c_axil_w      : cover (wvalid & wready);
            c_axil_ar     : cover (obs_arvalid & arready);
            c_axil_b      : cover (bvalid & bready);
            c_axil_r      : cover (rvalid & rready);
            c_axil_aw_wait: cover (obs_awvalid & ~awready);
            c_axil_resp   : cover (resp_valid & resp_ready);
            c_axil_rd     : cover (resp_valid & (resp_op == UMI_RESP_READ));
            c_axil_wr     : cover (resp_valid & (resp_op == UMI_RESP_WRITE));
            // an unaligned write really reaches the bus: the case the
            // byte-lane law is about
            c_axil_unaligned : cover (wvalid & (shadow_addr[DWLOG-1:0] != 0)
                                      & (shadow_data != {DW{1'b0}}));
            // an error code really reaches the response
            c_axil_err    : cover (resp_valid
                                   & (obs_resp_cmd[UMI_USER_MSB:UMI_USER_LSB]
                                      != 2'b00));
        end
`endif

`ifdef FV_AXIL_ANYOP
    // The opcode assumption withdrawn. umi2axil maps READ, WRITE and
    // POSTED; m_axil_op holds the request channel to those three on
    // every other row. These witnesses record what the block does with
    // an opcode it was never given a mapping for -- the same question
    // apb:hazard asks of umi2apb.
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_axil_atomic_bus : cover (obs_awvalid & (req_op == UMI_REQ_ATOMIC));
            c_axil_rdma_bus   : cover (obs_arvalid & (req_op == UMI_REQ_RDMA));
        end
`endif

endmodule

`default_nettype wire
