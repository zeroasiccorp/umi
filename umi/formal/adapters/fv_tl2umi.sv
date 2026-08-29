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
 * - Proves tl2umi drives a legal TileLink-UL subordinate D channel and
 *   a legal SUMI request channel.
 *
 * TILELINK IS NOT A HANDSHAKE PROBLEM EITHER. Like AXI4, TL-UL puts
 * obligations on a response that no channel handshake enforces: the
 * answer must carry the SOURCE of the request it answers, the same
 * SIZE, and the opcode that request's opcode demands. tl2umi is the
 * subordinate, so it owns D and the manager owns A.
 *
 *   asserted (this block is the source of D)
 *     TL_d_hold / TL_d_stable    the irrevocable rule on D
 *     TL_d_opcode_legal          AccessAck or AccessAckData, nothing else
 *
 *   assumed (the manager is the source of A)
 *     m_tl_a_hold / m_tl_a_stable   the same irrevocable rule on A
 *     m_tl_a_opcode                 Get, PutFullData or PutPartialData
 *     m_tl_a_align                  a_address aligned to a_size
 *     m_tl_a_mask                   countones(a_mask) == 2^a_size
 *     m_tl_one_outstanding          one request in flight at a time
 *
 * The rule set is the one an implemented TL-UL protocol checker
 * enforces, not a reading of the prose: legal A opcodes are the three
 * above, a D opcode must match the request kind, d_source must
 * reference a request that was actually issued, response size must
 * match request size, a_address must be aligned to a_size, and
 * 2^a_size must equal countones(a_mask).
 *
 * THE CORRESPONDENCE LAWS ARE NOT PROVEN HERE, AND THAT IS THE MAIN
 * LIMITATION OF THIS FILE. Three of the rules above relate the D
 * channel back to the A request that caused it -- d_source, d_size and
 * the Get/Put to AccessAckData/AccessAck pairing. They are written,
 * behind `FV_TL_CORRESPOND, and they do not hold as written.
 *
 * The reason is a property of the harness rather than a defect that has
 * been demonstrated in the block. tl2umi does not keep the TileLink
 * source and size in registers; it tunnels them through the UMI
 * address. The request encodes them into its SRCADDR user field
 * (tl2umi.v:533) and the response reads them back out:
 *
 *     d_source = resp_dstaddr[4:0]      (tl2umi.v:263)
 *     d_size   = resp_dstaddr[10:8]     (tl2umi.v:264)
 *
 * Between the A handshake and the UMI request there is a FIFO, and
 * between the UMI response and the D beat there is umi_data_aggregator.
 * A model that latches the request at the A handshake and compares it
 * against the next D beat -- which is what this harness does -- is
 * correlating two boundaries that those two blocks are free to
 * decouple. Three attempts to close it were made and none held, so the
 * laws are recorded as an open question rather than shipped as either
 * a proof or a finding. Getting them would want a transaction model
 * that follows an item through the FIFO and the aggregator, which is
 * the same tracking the byte-accounting work wants.
 *
 * To reproduce: add FV_TL_CORRESPOND to a bmc row.
 *
 * WHAT IS PROVEN ON THE UMI SIDE:
 *   RULE2_valid_hold / RULE3_*_stable   the UMI request channel this
 *                     block drives
 *
 * ALSO NOT PROVEN. The burst path through umi_data_aggregator -- the
 * multi-beat Get that returns several D beats -- is byte accounting
 * across a width change, the same work umi_fifoflex wants, and is not
 * attempted. m_tl_a_size holds requests to a single bus word so the
 * aggregator's burst arm is not exercised, and the harness says so
 * rather than proving something narrower than it looks.
 *
 * The d_param, d_sink, d_denied and d_corrupt outputs are tied
 * (tl2umi.v:237-240); asserting a constant against itself is the code
 * read back, so they are not asserted.
 *
 * SCOPE. Bounded. One clock. Single-beat requests only, per above.
 *
 * ROWS (tests/test_formal_sc.py):
 *   tl:bmc               the TileLink and UMI laws, bounded
 *   tl:cover             witnesses: expect all reached
 *   tl:fault_d           must FAIL, TL_d_stable
 *   tl:fault_hold        must FAIL, TL_d_hold
 *   tl:fault_opcode      must FAIL, TL_d_opcode_legal
 *
 ******************************************************************************/

`default_nettype none

module fv_tl2umi #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64
) (
    input wire clk
);

`include "umi_messages.vh"
`include "tl-uh.vh"

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
    (* anyconst *) wire [AW-1:0] srcaddr;

    (* anyseq *) wire        a_valid;
    (* anyseq *) wire [2:0]  a_opcode, a_param, a_size;
    (* anyseq *) wire [4:0]  a_source;
    (* anyseq *) wire [55:0] a_address;
    (* anyseq *) wire [7:0]  a_mask;
    (* anyseq *) wire [63:0] a_data;
    (* anyseq *) wire        a_corrupt;
    (* anyseq *) wire        d_ready;

    (* anyseq *) wire          req_ready;
    (* anyseq *) wire          resp_valid;
    (* anyseq *) wire [CW-1:0] resp_cmd;
    (* anyseq *) wire [AW-1:0] resp_dstaddr;
    (* anyseq *) wire [AW-1:0] resp_srcaddr;
    (* anyseq *) wire [DW-1:0] resp_data;

    wire        a_ready;
    wire        d_valid;
    wire [2:0]  d_opcode, d_size;
    wire [1:0]  d_param;
    wire [4:0]  d_source;
    wire        d_sink, d_denied, d_corrupt;
    wire [63:0] d_data;

    wire          req_valid;
    wire [CW-1:0] req_cmd;
    wire [AW-1:0] req_dstaddr;
    wire [AW-1:0] req_srcaddr;
    wire [DW-1:0] req_data;
    wire          resp_ready;

    tl2umi #(
        .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .clk (clk), .nreset (nreset), .srcaddr (srcaddr),
        .tl_a_ready (a_ready), .tl_a_valid (a_valid),
        .tl_a_opcode (a_opcode), .tl_a_param (a_param), .tl_a_size (a_size),
        .tl_a_source (a_source), .tl_a_address (a_address),
        .tl_a_mask (a_mask), .tl_a_data (a_data), .tl_a_corrupt (a_corrupt),
        .tl_d_ready (d_ready), .tl_d_valid (d_valid),
        .tl_d_opcode (d_opcode), .tl_d_param (d_param), .tl_d_size (d_size),
        .tl_d_source (d_source), .tl_d_sink (d_sink),
        .tl_d_denied (d_denied), .tl_d_data (d_data),
        .tl_d_corrupt (d_corrupt),
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

`ifdef FV_FAULT_D
    wire [63:0] obs_d_data = d_data ^ {63'd0, f_glitch};
`else
    wire [63:0] obs_d_data = d_data;
`endif

    wire [4:0] obs_d_source = d_source;
    wire [2:0] obs_d_size = d_size;

`ifdef FV_FAULT_HOLD
    wire obs_d_valid = d_valid & ~f_glitch;      // an offer withdrawn
`else
    wire obs_d_valid = d_valid;
`endif

`ifdef FV_FAULT_OPCODE
    // 3'd4 is Get, an A-channel opcode: never legal on D
    wire [2:0] obs_d_opcode = f_glitch ? 3'd4 : d_opcode;
`else
    wire [2:0] obs_d_opcode = d_opcode;
`endif

    // ----------------------------------------------------------------
    // the TileLink manager holds its side of the irrevocable rule, and
    // issues only legal TL-UL requests
    // ----------------------------------------------------------------
    wire a_fire = a_valid & a_ready;
    wire d_fire = d_valid & d_ready;

    reg        a_valid_d, a_ready_d;
    reg [2:0]  a_opcode_d, a_size_d;
    reg [4:0]  a_source_d;
    reg [55:0] a_address_d;
    reg [7:0]  a_mask_d;
    reg [63:0] a_data_d;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            a_valid_d <= 1'b0; a_ready_d <= 1'b0;
        end else begin
            a_valid_d <= a_valid; a_ready_d <= a_ready;
        end
    always @(posedge clk) begin
        a_opcode_d <= a_opcode; a_size_d <= a_size;
        a_source_d <= a_source; a_address_d <= a_address;
        a_mask_d   <= a_mask;   a_data_d <= a_data;
    end

    always @(*) begin
        m_tl_reset_quiet : assume (nreset || !a_valid);
        // the three legal TL-UL request opcodes
        m_tl_a_opcode : assume ((a_opcode == `TL_OP_Get)
                                || (a_opcode == `TL_OP_PutFullData)
                                || (a_opcode == `TL_OP_PutPartialData));
        // one bus word at most, so the aggregator's burst arm is out of
        // scope here and the byte accounting it needs is not implied
        m_tl_a_size  : assume (a_size <= 3'd3);
        // a_address aligned to a_size
        m_tl_a_align : assume ((a_address & ((56'd1 << a_size) - 56'd1))
                               == 56'd0);
        // 2^a_size == countones(a_mask)
        m_tl_a_mask  : assume ($countones(a_mask) == (32'd1 << a_size));
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            m_tl_a_hold   : assume (!(a_valid_d & ~a_ready_d) || a_valid);
            m_tl_a_stable : assume (!(a_valid_d & ~a_ready_d)
                                    || ((a_opcode  == a_opcode_d)
                                        && (a_size    == a_size_d)
                                        && (a_source  == a_source_d)
                                        && (a_address == a_address_d)
                                        && (a_mask    == a_mask_d)
                                        && (a_data    == a_data_d)));
        end

    // ----------------------------------------------------------------
    // the request in flight, tracked from the PORTS
    // ----------------------------------------------------------------
    reg [2:0] req_opcode, req_size;
    reg [4:0] req_source;
    reg       req_open;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            req_opcode <= 3'd0; req_size <= 3'd0;
            req_source <= 5'd0; req_open <= 1'b0;
        end else if (a_fire) begin
            req_opcode <= a_opcode; req_size <= a_size;
            req_source <= a_source; req_open <= 1'b1;
        end else if (d_fire)
            req_open <= 1'b0;

    // TL-UL allows several outstanding requests distinguished by source
    // ID. tl2umi answers from one set of response registers
    // (tl2umi.v:271-289), so the harness holds the manager to one at a
    // time and the laws below are about that case.
    always @(*)
        m_tl_one_outstanding : assume (!(a_fire & req_open));

    // ----------------------------------------------------------------
    // the UMI device: keeps README 4.2 and answers only what it owes
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (1)
    ) env_resp (
        .clk (clk), .nreset (nreset),
        .valid (resp_valid), .ready (resp_ready),
        .cmd (resp_cmd), .dstaddr (resp_dstaddr),
        .srcaddr (resp_srcaddr), .data (resp_data)
    );

    wire [4:0] resp_op = resp_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

    // THE ROUND TRIP THIS BLOCK RESTS ON. tl2umi does not keep the
    // TileLink source and size in registers. It tunnels them through
    // the UMI address: the request carries them in its SRCADDR user
    // field, and the response is read back as
    //     d_source = resp_dstaddr[4:0]      (tl2umi.v:263)
    //     d_size   = resp_dstaddr[10:8]     (tl2umi.v:264)
    // That works only because a UMI device answers with the request's
    // SRCADDR as the response's DSTADDR (README.md section 3.3.1).
    // Nothing in this block enforces it; the device is trusted to.
    // Assuming it here is what makes the D-channel laws below a
    // statement about tl2umi rather than about a device that scrambles
    // addresses.
    reg [AW-1:0] req_srcaddr_s;
    always @(posedge clk)
        if (req_valid & req_ready)
            req_srcaddr_s <= req_srcaddr;

    always @(*)
        if (resp_valid) begin
            m_tl_resp_owed : assume (req_open);
            m_tl_resp_addr : assume (resp_dstaddr == req_srcaddr_s);
            m_tl_resp_kind : assume ((req_opcode == `TL_OP_Get)
                                     ? (resp_op == UMI_RESP_READ)
                                     : (resp_op == UMI_RESP_WRITE));
        end

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
    // TileLink-UL subordinate obligations on D
    // ----------------------------------------------------------------
    reg        d_valid_d, d_ready_d;
    reg [2:0]  d_opcode_d, d_size_d;
    reg [4:0]  d_source_d;
    reg [63:0] d_data_d;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            d_valid_d <= 1'b0; d_ready_d <= 1'b0;
        end else begin
            d_valid_d <= obs_d_valid; d_ready_d <= d_ready;
        end
    always @(posedge clk) begin
        d_opcode_d <= obs_d_opcode; d_size_d <= obs_d_size;
        d_source_d <= obs_d_source; d_data_d <= obs_d_data;
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            TL_d_hold   : assert (!(d_valid_d & ~d_ready_d) || obs_d_valid);
            TL_d_stable : assert (!(d_valid_d & ~d_ready_d)
                                  || ((obs_d_data   == d_data_d)
                                      && (obs_d_opcode == d_opcode_d)
                                      && (obs_d_size   == d_size_d)
                                      && (obs_d_source == d_source_d)));
        end

    always @(posedge clk)
        if (nreset & f_past_exists & d_valid & req_open) begin
            // only the two TL-UL response opcodes exist
            TL_d_opcode_legal : assert ((obs_d_opcode == `TL_OP_AccessAck)
                                        || (obs_d_opcode == `TL_OP_AccessAckData));
        end

`ifdef FV_TL_CORRESPOND
    always @(posedge clk)
        if (nreset & f_past_exists & d_valid & req_open) begin
            // the answer carries the request's source and size
            TL_d_source_match : assert (obs_d_source == req_source);
            // UNRESOLVED, and deliberately not in a shipped row. d_size
            // is resp_dstaddr[10:8] (tl2umi.v:264), which the request
            // encodes as tl_a_size (tl2umi.v:533). The round trip
            // should therefore return a_size, and it does not always.
            // Three hypotheses were tested and none held, so this is
            // recorded as an open question rather than shipped as
            // either a proof or a finding. Run the row by hand with
            // FV_TL_SIZE to reproduce.
            TL_d_size_match   : assert (obs_d_size == req_size);
            // a Get is answered with data, a Put with an ack
            TL_d_kind : assert (obs_d_opcode == ((req_opcode == `TL_OP_Get)
                                                 ? `TL_OP_AccessAckData
                                                 : `TL_OP_AccessAck));
        end
`endif

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_tl_a       : cover (a_fire);
            c_tl_get     : cover (a_fire & (a_opcode == `TL_OP_Get));
            c_tl_put     : cover (a_fire & (a_opcode == `TL_OP_PutFullData));
            c_tl_d       : cover (d_fire);
            c_tl_d_wait  : cover (d_valid & ~d_ready);
            c_tl_ackdata : cover (d_fire & (obs_d_opcode == `TL_OP_AccessAckData));
            c_tl_ack     : cover (d_fire & (obs_d_opcode == `TL_OP_AccessAck));
            c_tl_req     : cover (req_valid & req_ready);
            c_tl_resp    : cover (resp_valid & resp_ready);
        end
`endif

endmodule

`default_nettype wire
