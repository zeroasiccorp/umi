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
 * - Proves axi2umi drives a legal AXI4 subordinate interface on the
 *   channels it owns, and that a read burst it returns is the burst the
 *   manager asked for.
 *
 * THE THIRD SIDE OF ONE LAW SET. fv_umi2axil asserts the AXI source
 * rule on AW, W and AR; fv_axil2umi asserts it on B and R. This harness
 * is the same rule again on B and R, now with AXI4's burst fields in
 * the payload -- RID and RLAST join RDATA and RRESP as things that must
 * not move under a standing RVALID.
 *
 *   asserted (this block is the source)
 *     AXI_b_hold / AXI_b_stable      BID and BRESP
 *     AXI_r_hold                     RVALID stays up until RREADY
 *     AXI_r_data / AXI_r_id /        one label per R payload field, so
 *     AXI_r_resp / AXI_r_last        a fault row names which one moved
 *     AXI_rid_match                  RID is the ARID of the burst being
 *                                    returned (axird2umi.v:185)
 *     AXI_rlast_count                RLAST lands on beat ARLEN+1 and
 *                                    nowhere else
 *
 *   assumed (the manager is the source)
 *     m_axi_aw_* / m_axi_w_* / m_axi_ar_*   the same rule, other side
 *
 * WHAT AXI4 ADDS, AND WHERE THIS BLOCK PUTS IT. A burst is not a
 * handshake property: an AXI4 subordinate owes the manager exactly
 * ARLEN+1 read beats with RLAST on the last one, and nothing about the
 * R channel handshake enforces that. axird2umi does not count them:
 *
 *     assign s_axi_rvalid = uhost_resp_valid;      // :182
 *     assign s_axi_rlast  = uhost_resp_cmd[UMI_EOM_BIT];  // :188
 *
 * RLAST is whatever EOM the UMI device set. The block header says so
 * plainly -- "The UMI endpoint is responsible for returning one
 * RESP_READ per beat" (axird2umi.v:22-23) -- so this is a stated
 * integration condition rather than a hidden one, and the harness
 * treats it as such: m_axi_resp_eom assumes the device closes the
 * message on beat ARLEN+1, and AXI_rlast_count then proves the AXI
 * obligation follows.
 *
 * WHICH SIDE THAT ASSUMPTION IS STATED ON DECIDES WHETHER THE PROOF
 * SAYS ANYTHING. m_axi_resp_eom constrains resp_cmd[UMI_EOM_BIT], the
 * device's own bit and free stimulus here. It would be one assign
 * shorter to write it on s_axi_rlast instead -- the two are separated
 * only by axird2umi.v:188 -- and that version is worthless: the
 * assertion would then repeat the assumption word for word and hold
 * whatever the block did with the bit in between. Inverting that
 * assign is caught on axi:bmc, which is the check that the law still
 * has work to do. For the same reason the burst model below closes on
 * ARLEN+1 accepted beats rather than on the block's own RLAST.
 *
 * The hazard row withdraws that assumption. What it shows is the size
 * of the condition: a device that miscounts by one beat does not
 * produce a UMI error, it produces an AXI protocol violation at this
 * block's own output, and nothing between the two notices.
 *
 * WHAT IS PROVEN ON THE UMI SIDE:
 *   RULE2_valid_hold / RULE3_*_stable  the UMI request channel this
 *                     block drives. On the read path that channel is a
 *                     direct passthrough of the AR channel
 *                     (axird2umi.v:153-154), so the proof is that AXI
 *                     source stability really does carry across into
 *                     README 4.2 rule 3.
 *
 * NOT PROVEN HERE. The write path's beat accounting (axiwr2umi.v:297
 * onward) is a state machine over WSTRB and burst length; it wants the
 * byte-accounting treatment umi_fifoflex also wants and is not
 * attempted. The address and QOS/PROT mappings are single assigns.
 *
 * SCOPE. Bounded. One clock. DW is narrowed from the block default of
 * 128 to 64 for solve time. Every law here is width-independent, but
 * that is an argument rather than a second elaboration: the
 * configuration matrix in tests/test_formal_sc.py re-answers the SUMI
 * families at other widths and carries no adapter row, so this face is
 * the only one any adapter is proven at. Bursts are held to
 * ARLEN <= MAXLEN = 2 and to INCR, which m_axi_len and m_axi_burst
 * state; FIXED and WRAP are out of scope.
 *
 * ROWS (tests/test_formal_sc.py):
 *   axi:bmc              the AXI and UMI laws, bounded
 *   axi:cover            witnesses: expect all reached
 *   axi:hazard           the EOM integration condition withdrawn
 *   axi:fault_r          must FAIL, AXI_r_data
 *   axi:fault_rid        must FAIL, AXI_rid_match
 *   axi:fault_b          must FAIL, AXI_b_hold
 *   axi:fault_burst      must FAIL, AXI_rlast_count. Nothing injected --
 *                        the device miscounts and the block passes it on
 *   axi:hazard_multi     a second AR while a burst returns: witness
 *   axi:fault_multi      must FAIL, AXI_r_id. Nothing injected --
 *                        the single ar_id register is overwritten
 *
 ******************************************************************************/

`default_nettype none

module fv_axi2umi #(
    parameter CW  = 32,
    parameter AW  = 64,
    parameter DW  = 64,
    parameter IDW = 8,
    parameter [7:0] MAXLEN = 8'd2   // burst ceiling, keeps the trace short
) (
    input wire clk
);

`include "umi_messages.vh"

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero
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
    (* anyconst *) wire [AW-1:0] hostaddr;
    (* anyconst *) wire [1:0]    arbmode;

    (* anyseq *) wire [IDW-1:0]  awid, wid, arid;
    (* anyseq *) wire [AW-1:0]   awaddr, araddr;
    (* anyseq *) wire [7:0]      awlen, arlen;
    (* anyseq *) wire [2:0]      awsize, arsize, awprot, arprot;
    (* anyseq *) wire [1:0]      awburst, arburst;
    (* anyseq *) wire            awlock, arlock;
    (* anyseq *) wire [3:0]      awcache, arcache, awqos, arqos;
    (* anyseq *) wire            awvalid, arvalid;
    (* anyseq *) wire [DW-1:0]   wdata;
    (* anyseq *) wire [DW/8-1:0] wstrb;
    (* anyseq *) wire            wlast, wvalid;
    (* anyseq *) wire            bready, rready;

    (* anyseq *) wire          req_ready;
    (* anyseq *) wire          resp_valid;
    (* anyseq *) wire [CW-1:0] resp_cmd;
    (* anyseq *) wire [AW-1:0] resp_dstaddr;
    (* anyseq *) wire [AW-1:0] resp_srcaddr;
    (* anyseq *) wire [DW-1:0] resp_data;

    wire awready, wready, arready;
    wire [IDW-1:0] bid, rid;
    wire [1:0] bresp, rresp;
    wire bvalid, rvalid, rlast;
    wire [DW-1:0] rdata;

    wire          req_valid;
    wire [CW-1:0] req_cmd;
    wire [AW-1:0] req_dstaddr;
    wire [AW-1:0] req_srcaddr;
    wire [DW-1:0] req_data;
    wire          resp_ready;

    axi2umi #(
        .CW (CW), .DW (DW), .AW (AW), .IDW (IDW)
    ) dut (
        .clk (clk), .nreset (nreset),
        .hostaddr (hostaddr), .arbmode (arbmode),
        .s_axi_awid (awid), .s_axi_awaddr (awaddr), .s_axi_awlen (awlen),
        .s_axi_awsize (awsize), .s_axi_awburst (awburst),
        .s_axi_awlock (awlock), .s_axi_awcache (awcache),
        .s_axi_awprot (awprot), .s_axi_awqos (awqos),
        .s_axi_awvalid (awvalid), .s_axi_awready (awready),
        .s_axi_wid (wid), .s_axi_wdata (wdata), .s_axi_wstrb (wstrb),
        .s_axi_wlast (wlast), .s_axi_wvalid (wvalid), .s_axi_wready (wready),
        .s_axi_bid (bid), .s_axi_bresp (bresp),
        .s_axi_bvalid (bvalid), .s_axi_bready (bready),
        .s_axi_arid (arid), .s_axi_araddr (araddr), .s_axi_arlen (arlen),
        .s_axi_arsize (arsize), .s_axi_arburst (arburst),
        .s_axi_arlock (arlock), .s_axi_arcache (arcache),
        .s_axi_arprot (arprot), .s_axi_arqos (arqos),
        .s_axi_arvalid (arvalid), .s_axi_arready (arready),
        .s_axi_rid (rid), .s_axi_rdata (rdata), .s_axi_rresp (rresp),
        .s_axi_rlast (rlast), .s_axi_rvalid (rvalid), .s_axi_rready (rready),
        .uhost_req_valid (req_valid), .uhost_req_cmd (req_cmd),
        .uhost_req_dstaddr (req_dstaddr), .uhost_req_srcaddr (req_srcaddr),
        .uhost_req_data (req_data), .uhost_req_ready (req_ready),
        .uhost_resp_valid (resp_valid), .uhost_resp_cmd (resp_cmd),
        .uhost_resp_dstaddr (resp_dstaddr), .uhost_resp_srcaddr (resp_srcaddr),
        .uhost_resp_data (resp_data), .uhost_resp_ready (resp_ready)
    );

    // ----------------------------------------------------------------
    // faults corrupt what the laws see, never the DUT. Bookkeeping below
    // reads the REAL signals so a fault reaches only its own law.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_R
    wire [DW-1:0] obs_rdata = rdata ^ {{(DW-1){1'b0}}, f_glitch};
`else
    wire [DW-1:0] obs_rdata = rdata;
`endif

`ifdef FV_FAULT_RID
    wire [IDW-1:0] obs_rid = rid ^ {{(IDW-1){1'b0}}, f_glitch};
`else
    wire [IDW-1:0] obs_rid = rid;
`endif

`ifdef FV_FAULT_B
    wire obs_bvalid = bvalid & ~f_glitch;
`else
    wire obs_bvalid = bvalid;
`endif

    // ----------------------------------------------------------------
    // the AXI manager holds its side of the source rule
    // ----------------------------------------------------------------
    reg awvalid_d, wvalid_d, arvalid_d, awready_d, wready_d, arready_d;
    // the WHOLE payload of each channel, not just the fields a law
    // happens to mention: AXI requires every one of them stable while
    // VALID waits, and axird2umi builds its command word from arsize,
    // arprot and arqos as well as araddr and arlen
    reg [AW-1:0]   awaddr_d, araddr_d;
    reg [7:0]      awlen_d, arlen_d;
    reg [2:0]      awsize_d, arsize_d, awprot_d, arprot_d;
    reg [1:0]      awburst_d, arburst_d;
    reg [3:0]      awcache_d, arcache_d, awqos_d, arqos_d;
    reg            awlock_d, arlock_d;
    reg [IDW-1:0]  awid_d, arid_d, wid_d;
    reg [DW-1:0]   wdata_d;
    reg [DW/8-1:0] wstrb_d;
    reg            wlast_d;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            awvalid_d <= 1'b0; wvalid_d <= 1'b0; arvalid_d <= 1'b0;
            awready_d <= 1'b0; wready_d <= 1'b0; arready_d <= 1'b0;
        end else begin
            awvalid_d <= awvalid; wvalid_d <= wvalid; arvalid_d <= arvalid;
            awready_d <= awready; wready_d <= wready; arready_d <= arready;
        end
    always @(posedge clk) begin
        awaddr_d  <= awaddr;  araddr_d  <= araddr;
        awlen_d   <= awlen;   arlen_d   <= arlen;
        awsize_d  <= awsize;  arsize_d  <= arsize;
        awprot_d  <= awprot;  arprot_d  <= arprot;
        awburst_d <= awburst; arburst_d <= arburst;
        awcache_d <= awcache; arcache_d <= arcache;
        awqos_d   <= awqos;   arqos_d   <= arqos;
        awlock_d  <= awlock;  arlock_d  <= arlock;
        awid_d    <= awid;    arid_d    <= arid;    wid_d <= wid;
        wdata_d   <= wdata;   wstrb_d   <= wstrb;   wlast_d <= wlast;
    end

    always @(*) begin
        m_axi_reset_quiet : assume (nreset || (!awvalid && !wvalid && !arvalid));
        // keep bursts short so a whole one fits the bound, and legal:
        // INCR only, and a beat no wider than the bus
        m_axi_len   : assume ((arlen <= MAXLEN) && (awlen <= MAXLEN));
        m_axi_burst : assume ((arburst == 2'b01) && (awburst == 2'b01));
        m_axi_size  : assume (((32'd1 << arsize) <= (DW / 8))
                              && ((32'd1 << awsize) <= (DW / 8)));
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            m_axi_aw_hold   : assume (!(awvalid_d & ~awready_d) || awvalid);
            m_axi_aw_stable : assume (!(awvalid_d & ~awready_d)
                                      || ((awaddr  == awaddr_d)
                                          && (awlen   == awlen_d)
                                          && (awsize  == awsize_d)
                                          && (awburst == awburst_d)
                                          && (awprot  == awprot_d)
                                          && (awqos   == awqos_d)
                                          && (awcache == awcache_d)
                                          && (awlock  == awlock_d)
                                          && (awid    == awid_d)));
            m_axi_w_hold    : assume (!(wvalid_d & ~wready_d) || wvalid);
            m_axi_w_stable  : assume (!(wvalid_d & ~wready_d)
                                      || ((wdata == wdata_d)
                                          && (wstrb == wstrb_d)
                                          && (wid   == wid_d)
                                          && (wlast == wlast_d)));
            m_axi_ar_hold   : assume (!(arvalid_d & ~arready_d) || arvalid);
            m_axi_ar_stable : assume (!(arvalid_d & ~arready_d)
                                      || ((araddr  == araddr_d)
                                          && (arlen   == arlen_d)
                                          && (arsize  == arsize_d)
                                          && (arburst == arburst_d)
                                          && (arprot  == arprot_d)
                                          && (arqos   == arqos_d)
                                          && (arcache == arcache_d)
                                          && (arlock  == arlock_d)
                                          && (arid    == arid_d)));
        end

    // ----------------------------------------------------------------
    // the UMI device: keeps README 4.2, and answers only what it owes
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (1)
    ) env_resp (
        .clk (clk), .nreset (nreset),
        .valid (resp_valid), .ready (resp_ready),
        .cmd (resp_cmd), .dstaddr (resp_dstaddr),
        .srcaddr (resp_srcaddr), .data (resp_data)
    );

    // ----------------------------------------------------------------
    // the read burst being served, tracked from the PORTS
    // ----------------------------------------------------------------
    wire ar_fire = arvalid & arready;
    wire r_fire  = rvalid  & rready;

    reg [7:0]     burst_len;    // ARLEN of the burst in flight
    reg [7:0]     beats;        // R beats returned so far
    reg [IDW-1:0] burst_id;
    reg           burst_open;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            burst_len <= 8'd0; beats <= 8'd0;
            burst_id  <= {IDW{1'b0}}; burst_open <= 1'b0;
        end else if (ar_fire) begin
            burst_len <= arlen; beats <= 8'd0;
            burst_id  <= arid;  burst_open <= 1'b1;
        end else if (r_fire) begin
            // the burst closes on the beat AXI says is the last one --
            // ARLEN+1 accepted beats -- not on the DUT's own RLAST.
            // Counting on rlast would make this model agree with
            // whatever the block drives, and AXI_rlast_count below
            // would have nothing left to compare against
            if (beats == burst_len) begin
                beats <= 8'd0; burst_open <= 1'b0;
            end else
                beats <= beats + 8'd1;
        end

    // The device answers only what it owes. Without this the solver
    // starts with a response already standing for a burst that was
    // never asked for, and every downstream law becomes a statement
    // about an environment no UMI device could be.
    wire [4:0] resp_op = resp_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];
    wire aw_fire = awvalid & awready;
    wire b_fire  = obs_bvalid & bready;

    reg wr_owed;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            wr_owed <= 1'b0;
        else if (aw_fire)
            wr_owed <= 1'b1;
        else if (b_fire)
            wr_owed <= 1'b0;

    // and it answers with the KIND that was asked for. axi2umi demuxes
    // the response to its read or write half on the opcode, so a device
    // that answered a write with RESP_READ would raise RVALID with no
    // read outstanding -- which no device does, and which would make
    // every R-channel law a statement about an impossible environment.
    always @(*)
        if (resp_valid)
            m_axi_resp_owed : assume ((resp_op == UMI_RESP_READ)
                                      ? burst_open : wr_owed);

    // A UMI device answers with a response opcode. axi2umi demuxes the
    // response to its read or write half on that opcode, so leaving it
    // free lets the solver route a beat to neither half and the R
    // channel sees a payload change that no device could produce.
    always @(*)
        if (resp_valid)
            m_axi_resp_kind : assume ((resp_op == UMI_RESP_READ)
                                      || (resp_op == UMI_RESP_WRITE));

    // ONE READ BURST AT A TIME. axird2umi keeps a single ar_id register
    // (axird2umi.v:147) and drives s_axi_rid from it (:185), while
    // s_axi_arready is just uhost_req_ready (:154) with no term for
    // whether a burst is still returning. So a manager that issues a
    // second AR before the first burst completes -- which AXI4 permits,
    // that is what the ID field is for -- overwrites ar_id and RID
    // changes under a standing RVALID.
    //
    // The block header claims "RID held constant for all beats"
    // (axird2umi.v:58). That holds for one burst at a time and not
    // otherwise. The green rows assume the condition; the hazard row
    // withdraws it and the pinned row requires the failure.
`ifndef FV_AXI_MULTI
    always @(*)
        m_axi_one_read : assume (!(ar_fire & burst_open));
`endif

    // The integration condition axird2umi.v:22-23 states: the UMI device
    // closes the message on the beat that completes the burst. The
    // hazard row withdraws this.
    //
    // It is stated over the DEVICE's EOM bit, which is free stimulus
    // here, and never over s_axi_rlast. The two are one assign apart
    // (axird2umi.v:188), so constraining the output would make
    // AXI_rlast_count below a restatement of this line rather than a
    // check of the path between them: an inverted :188 would then still
    // satisfy both, because the solver would simply pick the EOM that
    // makes the equality hold.
`ifndef FV_AXI_ANYEOM
    always @(*)
        if (burst_open & resp_valid & (resp_op == UMI_RESP_READ))
            m_axi_resp_eom : assume (resp_cmd[UMI_EOM_BIT]
                                     == (beats == burst_len));
`endif

    // ----------------------------------------------------------------
    // the UMI request channel this block drives is judged
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (0)
    ) chk_req (
        .clk (clk), .nreset (nreset),
        .valid (req_valid), .ready (req_ready),
        .cmd (req_cmd), .dstaddr (req_dstaddr),
        .srcaddr (req_srcaddr), .data (req_data)
    );

    // ----------------------------------------------------------------
    // AXI4 subordinate obligations
    // ----------------------------------------------------------------
    reg bvalid_d, rvalid_d, bready_d, rready_d, rlast_d;
    reg [IDW-1:0] bid_d, rid_d;
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
        bid_d <= bid; bresp_d <= bresp;
        rid_d <= obs_rid; rresp_d <= rresp;
        rdata_d <= obs_rdata; rlast_d <= rlast;
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            AXI_b_hold   : assert (!(bvalid_d & ~bready_d) || obs_bvalid);
            AXI_b_stable : assert (!(bvalid_d & ~bready_d)
                                   || ((bid == bid_d) && (bresp == bresp_d)));
            AXI_r_hold   : assert (!(rvalid_d & ~rready_d) || rvalid);
            // one label per field: a fault row pins the label sby
            // reports, and a single combined label cannot say which
            // part of the R payload moved
            AXI_r_data  : assert (!(rvalid_d & ~rready_d)
                                  || (obs_rdata == rdata_d));
            AXI_r_resp  : assert (!(rvalid_d & ~rready_d)
                                  || (rresp == rresp_d));
            AXI_r_id    : assert (!(rvalid_d & ~rready_d)
                                  || (obs_rid == rid_d));
            AXI_r_last  : assert (!(rvalid_d & ~rready_d)
                                  || (rlast == rlast_d));
        end

    // RID is the ARID of the burst being returned
    always @(posedge clk)
        if (nreset & f_past_exists & rvalid & burst_open)
            AXI_rid_match : assert (obs_rid == burst_id);

    // RLAST lands on beat ARLEN+1 and nowhere else
    always @(posedge clk)
        if (nreset & f_past_exists & rvalid & burst_open)
            AXI_rlast_count : assert (rlast == (beats == burst_len));

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_axi_ar     : cover (ar_fire);
            c_axi_r      : cover (r_fire);
            c_axi_rlast  : cover (r_fire & rlast);
            c_axi_r_wait : cover (rvalid & ~rready);
            c_axi_burst  : cover (r_fire & rlast & (burst_len != 8'd0));
            c_axi_aw     : cover (awvalid & awready);
            c_axi_w      : cover (wvalid & wready);
            c_axi_wlast  : cover (wvalid & wready & wlast);
            c_axi_b      : cover (obs_bvalid & bready);
            c_axi_req    : cover (req_valid & req_ready);
        end
`ifdef FV_AXI_ANYEOM
    always @(posedge clk)
        if (nreset & f_past_exists)
            // RLAST on a beat that does not complete the burst: the
            // device miscounted and the block passed it straight on
            c_axi_short : cover (r_fire & rlast & burst_open
                                 & (beats != burst_len));
`endif
`ifdef FV_AXI_MULTI
    always @(posedge clk)
        if (nreset & f_past_exists)
            // a second read burst accepted while the first is returning
            c_axi_multi : cover (ar_fire & burst_open);
`endif
`endif

endmodule

`default_nettype wire
