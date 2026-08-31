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
 * - Proves axil2umi drives a legal AXI4-Lite SUBORDINATE interface and
 *   a legal SUMI request channel.
 *
 * THE SAME LAW SET AS fv_umi2axil, FROM THE OTHER SIDE. AXI gives
 * every channel one source obligation: once VALID is asserted it stays
 * asserted until the handshake completes, and the payload does not move
 * while it waits. umi2axil is the manager and owns AW, W and AR;
 * axil2umi is the subordinate and owns B and R. So the two harnesses
 * assert and assume exactly opposite halves of one rule set, and
 * between them every AXI4-Lite channel in the repo is judged from the
 * side that drives it.
 *
 *   asserted (this block is the source)
 *     AXIL_b_hold / AXIL_b_stable    write response channel
 *     AXIL_r_hold / AXIL_r_stable    read response channel
 *
 *   assumed (the manager is the source)
 *     m_axil_aw_hold / m_axil_aw_stable
 *     m_axil_w_hold  / m_axil_w_stable
 *     m_axil_ar_hold / m_axil_ar_stable
 *
 * The UMI side is the mirror too. umi2axil is a device and answers a
 * request; axil2umi is a HOST and issues one, so here the UMI REQUEST
 * channel is the thing being judged and the response channel is the
 * environment.
 *
 * WHAT IS PROVEN:
 *   RULE2_valid_hold / RULE3_*_stable  the UMI request channel keeps
 *                     the README 4.2 handshake
 *   AXIL_b_* / AXIL_r_*   the two AXI channels this block drives
 *   a_axil2_kind      an AXI write becomes a UMI REQ_WR and an AXI read
 *                     a REQ_RD (README 3.4.2, 3.4.3)
 *   a_axil2_one_inflight  the block serves one AXI transaction at a
 *                     time -- awready and arready are both
 *                     !(write_in_flight | read_in_flight)
 *                     (axil2umi.v:167, 227)
 *
 * WHY THE RESPONSE PASSTHROUGH HOLDS. axi_rdata is uhost_resp_data
 * directly (axil2umi.v:306) and axi_rvalid follows uhost_resp_valid
 * (axil2umi.v:308-311), so AXI stability on R rests entirely on the UMI
 * device keeping README 4.2 rule 3. The block earns that by driving
 * uhost_resp_ready from axi_rready (axil2umi.v:301-303): while the AXI
 * manager is not ready the UMI response is not consumed, so it cannot
 * be replaced underneath. That chain is what AXIL_r_stable checks, and
 * it is the reason the UMI response channel here is constrained by the
 * checker rather than left free.
 *
 * NOT PROVEN HERE. The address composition (chipid, local_routing and
 * the offset arithmetic) and the AXI-to-UMI error mapping are single
 * assigns off registered inputs. The write-strobe accumulator
 * (axil2umi.v:145-147) is byte-accounting and belongs with the work
 * umi_fifoflex also wants.
 *
 * SCOPE. Bounded. One clock. Single-beat AXI4-Lite transfers, which is
 * all AXI4-Lite has.
 *
 * ROWS (tests/test_formal_sc.py):
 *   axil2:bmc             the AXI and UMI laws, bounded
 *   axil2:cover           witnesses: expect all reached
 *   axil2:fault_b         must FAIL, AXIL_b_hold
 *   axil2:fault_r         must FAIL, AXIL_r_stable
 *   axil2:fault_kind      must FAIL, a_axil2_kind
 *   axil2:fault_inflight  must FAIL, a_axil2_one_inflight
 *   axil2:hazard          AWVALID and ARVALID together: expect the
 *                         witness reached
 *   axil2:fault_concurrent  must FAIL, AXIL_r_hold. Nothing injected --
 *                         see the note on m_axil2_no_concurrent
 *
 ******************************************************************************/

`default_nettype none

module fv_axil2umi #(
    parameter CW  = 32,
    parameter AW  = 64,
    parameter DW  = 64,
    parameter IDW = 16
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
    // free environment. chipid and local_routing are configuration
    // pins: an integrator ties them, so they do not move mid-trace.
    // ----------------------------------------------------------------
    (* anyconst *) wire [IDW-1:0] chipid;
    (* anyconst *) wire [15:0]    local_routing;

    (* anyseq *) wire [AW-1:0]     awaddr, araddr;
    (* anyseq *) wire [2:0]        awprot, arprot;
    (* anyseq *) wire              awvalid, wvalid, arvalid;
    (* anyseq *) wire [DW-1:0]     wdata;
    (* anyseq *) wire [(DW/8)-1:0] wstrb;
    (* anyseq *) wire              bready, rready;

    (* anyseq *) wire          req_ready;
    (* anyseq *) wire          resp_valid;
    (* anyseq *) wire [CW-1:0] resp_cmd;
    (* anyseq *) wire [AW-1:0] resp_dstaddr;
    (* anyseq *) wire [AW-1:0] resp_srcaddr;
    (* anyseq *) wire [DW-1:0] resp_data;

    wire awready, wready, arready;
    wire [1:0] bresp, rresp;
    wire bvalid, rvalid;
    wire [DW-1:0] rdata;

    wire          req_valid;
    wire [CW-1:0] req_cmd;
    wire [AW-1:0] req_dstaddr;
    wire [AW-1:0] req_srcaddr;
    wire [DW-1:0] req_data;
    wire          resp_ready;

    axil2umi #(
        .CW (CW), .AW (AW), .DW (DW), .IDW (IDW)
    ) dut (
        .clk               (clk),
        .nreset            (nreset),
        .chipid            (chipid),
        .local_routing     (local_routing),
        .axi_awaddr        (awaddr),
        .axi_awprot        (awprot),
        .axi_awvalid       (awvalid),
        .axi_awready       (awready),
        .axi_wdata         (wdata),
        .axi_wstrb         (wstrb),
        .axi_wvalid        (wvalid),
        .axi_wready        (wready),
        .axi_bresp         (bresp),
        .axi_bvalid        (bvalid),
        .axi_bready        (bready),
        .axi_araddr        (araddr),
        .axi_arprot        (arprot),
        .axi_arvalid       (arvalid),
        .axi_arready       (arready),
        .axi_rdata         (rdata),
        .axi_rresp         (rresp),
        .axi_rvalid        (rvalid),
        .axi_rready        (rready),
        .uhost_req_valid   (req_valid),
        .uhost_req_cmd     (req_cmd),
        .uhost_req_dstaddr (req_dstaddr),
        .uhost_req_srcaddr (req_srcaddr),
        .uhost_req_data    (req_data),
        .uhost_req_ready   (req_ready),
        .uhost_resp_valid  (resp_valid),
        .uhost_resp_cmd    (resp_cmd),
        .uhost_resp_dstaddr(resp_dstaddr),
        .uhost_resp_srcaddr(resp_srcaddr),
        .uhost_resp_data   (resp_data),
        .uhost_resp_ready  (resp_ready)
    );

    // ----------------------------------------------------------------
    // faults corrupt what the laws see, never the DUT
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_B
    wire obs_bvalid = bvalid & ~f_glitch;            // an offer withdrawn
`else
    wire obs_bvalid = bvalid;
`endif

`ifdef FV_FAULT_R
    wire [DW-1:0] obs_rdata = rdata ^ {{(DW-1){1'b0}}, f_glitch};
`else
    wire [DW-1:0] obs_rdata = rdata;
`endif

`ifdef FV_FAULT_KIND
    // REQ_RD 0x01 and REQ_WR 0x03 differ by 0x02
    wire [CW-1:0] obs_req_cmd = req_cmd ^ {{(CW-5){1'b0}}, 5'h02};
`else
    wire [CW-1:0] obs_req_cmd = req_cmd;
`endif

`ifdef FV_FAULT_INFLIGHT
    wire obs_awready = awready | f_glitch;           // accept while busy
`else
    wire obs_awready = awready;
`endif

    // ----------------------------------------------------------------
    // the AXI manager holds its side of the source rule
    // ----------------------------------------------------------------
    reg awvalid_d, wvalid_d, arvalid_d;
    reg awready_d, wready_d, arready_d;
    reg [AW-1:0] awaddr_d, araddr_d;
    reg [2:0] awprot_d, arprot_d;
    reg [DW-1:0] wdata_d;
    reg [(DW/8)-1:0] wstrb_d;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            awvalid_d <= 1'b0; wvalid_d <= 1'b0; arvalid_d <= 1'b0;
            awready_d <= 1'b0; wready_d <= 1'b0; arready_d <= 1'b0;
        end else begin
            awvalid_d <= awvalid; wvalid_d <= wvalid; arvalid_d <= arvalid;
            awready_d <= awready; wready_d <= wready; arready_d <= arready;
        end
    always @(posedge clk) begin
        awaddr_d <= awaddr; awprot_d <= awprot;
        araddr_d <= araddr; arprot_d <= arprot;
        wdata_d  <= wdata;  wstrb_d  <= wstrb;
    end

    always @(*)
        m_axil_reset_quiet : assume (nreset || (!awvalid && !wvalid && !arvalid));

`ifndef FV_AXIL2_CONCURRENT
    // axi_awready and axi_arready are the SAME expression,
    // !(write_in_flight | read_in_flight) & reset_done
    // (axil2umi.v:167 and :227). AXI4-Lite lets a manager raise AWVALID
    // and ARVALID on the same cycle -- the address channels are
    // independent -- and when it does, both are accepted on one edge
    // and the block holds a write and a read in flight at once. Its
    // response steering (axil2umi.v:301-303) picks the B channel
    // whenever write_in_flight is set, so the UMI response is drained
    // on BREADY while RVALID is still standing, and RVALID drops
    // without RREADY.
    //
    // The green rows assume the manager does not do this. The hazard
    // row withdraws the assumption and pins the consequence.
    always @(*)
        m_axil2_no_concurrent : assume (!(awvalid & awready
                                          & arvalid & arready));
`endif

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            m_axil_aw_hold   : assume (!(awvalid_d & ~awready_d) || awvalid);
            m_axil_aw_stable : assume (!(awvalid_d & ~awready_d)
                                       || ((awaddr == awaddr_d)
                                           && (awprot == awprot_d)));
            m_axil_w_hold    : assume (!(wvalid_d & ~wready_d) || wvalid);
            m_axil_w_stable  : assume (!(wvalid_d & ~wready_d)
                                       || ((wdata == wdata_d)
                                           && (wstrb == wstrb_d)));
            m_axil_ar_hold   : assume (!(arvalid_d & ~arready_d) || arvalid);
            m_axil_ar_stable : assume (!(arvalid_d & ~arready_d)
                                       || ((araddr == araddr_d)
                                           && (arprot == arprot_d)));
        end

    // ----------------------------------------------------------------
    // the UMI device answers only what it was asked, and keeps the
    // README 4.2 handshake while doing it
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (1)
    ) env_resp (
        .clk (clk), .nreset (nreset),
        .valid (resp_valid), .ready (resp_ready),
        .cmd (resp_cmd), .dstaddr (resp_dstaddr),
        .srcaddr (resp_srcaddr), .data (resp_data)
    );

    reg [1:0] req_out;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            req_out <= 2'd0;
        else
            case ({req_valid & req_ready, resp_valid & resp_ready})
                2'b10:   req_out <= req_out + 2'd1;
                2'b01:   req_out <= req_out - 2'd1;
                default: req_out <= req_out;
            endcase

    always @(*) begin
        m_umi_resp_owed : assume (!resp_valid || (req_out != 2'd0));
        m_umi_no_wrap   : assume (req_out != 2'd3);
    end

    // ----------------------------------------------------------------
    // the UMI request channel this block drives is judged
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (0)
    ) chk_req (
        .clk (clk), .nreset (nreset),
        .valid (req_valid), .ready (req_ready),
        .cmd (obs_req_cmd), .dstaddr (req_dstaddr),
        .srcaddr (req_srcaddr), .data (req_data)
    );

    // ----------------------------------------------------------------
    // AXI4-Lite subordinate obligations, AMBA AXI section A3.2.1
    // ----------------------------------------------------------------
    reg bvalid_d, rvalid_d, bready_d, rready_d;
    reg [1:0] bresp_d, rresp_d;
    reg [DW-1:0] rdata_d;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            bvalid_d <= 1'b0; rvalid_d <= 1'b0;
            bready_d <= 1'b0; rready_d <= 1'b0;
        end else begin
            bvalid_d <= obs_bvalid; rvalid_d <= rvalid;
            bready_d <= bready;     rready_d <= rready;
        end
    always @(posedge clk) begin
        bresp_d <= bresp; rresp_d <= rresp; rdata_d <= obs_rdata;
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            AXIL_b_hold   : assert (!(bvalid_d & ~bready_d) || obs_bvalid);
            AXIL_b_stable : assert (!(bvalid_d & ~bready_d)
                                    || (bresp == bresp_d));
            AXIL_r_hold   : assert (!(rvalid_d & ~rready_d) || rvalid);
            AXIL_r_stable : assert (!(rvalid_d & ~rready_d)
                                    || ((obs_rdata == rdata_d)
                                        && (rresp == rresp_d)));
        end

    // ----------------------------------------------------------------
    // an AXI write becomes a UMI write, an AXI read a UMI read
    // ----------------------------------------------------------------
    wire [4:0] req_op = obs_req_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

    reg saw_write, saw_read;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            saw_write <= 1'b0; saw_read <= 1'b0;
        end else if (awvalid & awready) begin
            saw_write <= 1'b1; saw_read <= 1'b0;
        end else if (arvalid & arready) begin
            saw_write <= 1'b0; saw_read <= 1'b1;
        end

    // Both address channels accepted on one edge. The kind law below
    // asks which AXI transaction a UMI request belongs to, and once two
    // have been taken together this harness can no longer answer that
    // from the ports -- so the flag is sticky and the law stops for the
    // rest of the trace. The concurrent case is judged by the AXI
    // channel laws instead, which is where its damage shows.
    reg both_seen;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            both_seen <= 1'b0;
        else if ((awvalid & awready) & (arvalid & arready))
            both_seen <= 1'b1;

    always @(posedge clk)
        if (nreset & f_past_exists & req_valid & ~both_seen
            & (saw_write ^ saw_read))
            a_axil2_kind : assert (saw_write ? (req_op == UMI_REQ_WRITE)
                                             : (req_op == UMI_REQ_READ));

    // One AXI transaction at a time. Once an address has been accepted
    // the block must report not-ready on BOTH address channels until
    // that transaction's response has been taken -- which is what
    // awready and arready being !(write_in_flight | read_in_flight)
    // is for.
    reg busy;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            busy <= 1'b0;
        else if ((awvalid & awready) | (arvalid & arready))
            busy <= 1'b1;
        else if ((bvalid & bready) | (rvalid & rready))
            busy <= 1'b0;

    always @(posedge clk)
        if (nreset & f_past_exists & busy)
            a_axil2_one_inflight : assert (!obs_awready && !arready);

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_axil2_aw    : cover (awvalid & awready);
            c_axil2_w     : cover (wvalid & wready);
            c_axil2_ar    : cover (arvalid & arready);
            c_axil2_b     : cover (obs_bvalid & bready);
            c_axil2_r     : cover (rvalid & rready);
            c_axil2_b_wait: cover (obs_bvalid & ~bready);
            c_axil2_r_wait: cover (rvalid & ~rready);
            c_axil2_req   : cover (req_valid & req_ready);
            c_axil2_wr    : cover (req_valid & (req_op == UMI_REQ_WRITE));
            c_axil2_rd    : cover (req_valid & (req_op == UMI_REQ_READ));
        end
`ifdef FV_AXIL2_CONCURRENT
    always @(posedge clk)
        if (nreset & f_past_exists)
            // both address channels accepted on one edge
            c_axil2_concurrent : cover (awvalid & awready
                                        & arvalid & arready);
`endif
`endif

endmodule

`default_nettype wire
