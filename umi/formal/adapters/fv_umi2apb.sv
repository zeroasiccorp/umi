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
 * - Proves umi2apb drives a legal AMBA APB requester interface, and
 *   that the SUMI response it builds matches the request it answers.
 *
 * TWO PROTOCOLS, TWO SOURCES OF TRUTH. The UMI side is held to
 * README.md section 4.2 by umi_handshake_checker, the same module the
 * SUMI proofs use, so the request face is constrained by exactly the
 * rules the response face is judged against. The APB side is held to
 * the AMBA APB specification, written out here rather than pulled from
 * a vendor library:
 *
 *   APB1_enable_needs_sel  PENABLE never asserts without PSEL.
 *   APB2_setup_to_access   a SETUP phase (PSEL, no PENABLE) is followed
 *                          by an ACCESS phase (PSEL and PENABLE) on the
 *                          next cycle -- APB has no other successor.
 *   APB3_hold_until_ready  ACCESS is held until the completer answers:
 *                          PSEL and PENABLE stay up while PREADY is low.
 *   APB4_payload_stable    PADDR, PWRITE, PWDATA, PSTRB and PPROT hold
 *                          the value they took in SETUP for the whole
 *                          of ACCESS.
 *   APB5_sel_drops_clean   PSEL falls only out of a completed transfer,
 *                          never mid-ACCESS.
 *
 * APB4 is the one worth stating carefully. umi2apb drives the bus from
 * two different places: in SETUP the payload comes straight off the UMI
 * request wires (umi2apb.v:142-143, the incoming_req arm), and in
 * ACCESS it comes from registers captured on that same cycle
 * (umi2apb.v:118-124). The two agree only because the capture and the
 * combinational drive read the same word on the same edge. That is a
 * property of the design, not an identity, and it is what APB4 checks.
 *
 * WHAT IS PROVEN ON THE UMI SIDE:
 *   RULE2_valid_hold / RULE3_*_stable  the response channel keeps the
 *                     README 4.2 handshake
 *   a_apb_kind        a REQ_RD is answered RESP_RD and a REQ_WR
 *                     RESP_WR (README 3.4.11, 3.4.12)
 *   a_apb_posted_quiet  a posted write raises no response at all
 *                     (README 3.4.4)
 *   a_apb_err_map     PSLVERR becomes ERR=DEVERR (2'b10) in the
 *                     response, and a clean transfer ERR=0
 *                     (README section 3.3.9 error encoding)
 *   a_apb_one_outstanding  at most one transfer is in flight
 *
 * NOT PROVEN HERE. The response address swap (DSTADDR from the
 * request's SRCADDR and back) and the PPROT mapping are single assigns
 * off registered request fields; asserting each against its own
 * expression would be the code read back rather than a check of it.
 * Read data carriage is likewise a single zero-extended assign.
 *
 * SCOPE. One clock: umi2apb is single-domain by construction, so this
 * is the whole design rather than a simplification. RW-aligned accesses
 * of at most RW bits are the supported set per the block header, and
 * the harness assumes that shape.
 *
 * ROWS (tests/test_formal_sc.py):
 *   apb:bmc               the APB and UMI laws, bounded
 *   apb:cover             witnesses: expect all reached
 *   apb:fault_enable      must FAIL, APB2_setup_to_access
 *   apb:fault_stable      must FAIL, APB4_payload_stable
 *   apb:fault_kind        must FAIL, a_apb_kind
 *   apb:fault_posted      must FAIL, a_apb_posted_quiet
 *
 ******************************************************************************/

`default_nettype none

module fv_umi2apb #(
    parameter CW  = 32,
    parameter AW  = 64,
    parameter DW  = 256,
    parameter RW  = 64,
    parameter RAW = 64
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

    // APB completer answers when it likes, with any data
    (* anyseq *) wire          pready;
    (* anyseq *) wire [RW-1:0] prdata;
    (* anyseq *) wire          pslverr;

    wire          req_ready;
    wire          resp_valid;
    wire [CW-1:0] resp_cmd;
    wire [AW-1:0] resp_dstaddr;
    wire [AW-1:0] resp_srcaddr;
    wire [DW-1:0] resp_data;

    wire            penable;
    wire            pwrite;
    wire [RAW-1:0]  paddr;
    wire [RW-1:0]   pwdata;
    wire [RW/8-1:0] pstrb;
    wire [2:0]      pprot;
    wire            psel;

    umi2apb #(
        .AW (AW), .CW (CW), .DW (DW), .RW (RW), .RAW (RAW)
    ) dut (
        .apb_nreset       (nreset),
        .apb_pclk         (clk),
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
        .apb_penable      (penable),
        .apb_pwrite       (pwrite),
        .apb_paddr        (paddr),
        .apb_pwdata       (pwdata),
        .apb_pstrb        (pstrb),
        .apb_pprot        (pprot),
        .apb_psel         (psel),
        .apb_pready       (pready),
        .apb_prdata       (prdata),
        .apb_pslverr      (pslverr)
    );

    // ----------------------------------------------------------------
    // the UMI request face is constrained legal by the same rule list
    // the response face is judged by
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
    // the request shape the block header supports: an RW-wide aligned
    // single-beat access. Wider or unaligned requests are outside the
    // block's stated contract.
    // ----------------------------------------------------------------
    wire [2:0] req_size = req_cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    wire [7:0] req_len  = req_cmd[UMI_LEN_MSB:UMI_LEN_LSB];
    wire [4:0] req_op   = req_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

    always @(*) begin
        m_apb_size  : assume ((32'd1 << req_size) <= (RW / 8));
        m_apb_len   : assume (req_len == 8'd0);
        m_apb_align : assume ((req_dstaddr
                               & (({{(AW-1){1'b0}}, 1'b1} << req_size)
                                  - {{(AW-1){1'b0}}, 1'b1})) == {AW{1'b0}});
    end

    // The supported opcode set, per the block header: read, write and
    // posted write. The hazard row withdraws this and covers what the
    // block does with the opcodes the header says it does not support.
`ifndef FV_APB_ANYOP
    always @(*)
        m_apb_op : assume ((req_op == UMI_REQ_READ)
                           || (req_op == UMI_REQ_WRITE)
                           || (req_op == UMI_REQ_POSTED));
`endif

    // ----------------------------------------------------------------
    // observed outputs. Faults corrupt what the laws see, never the
    // DUT: no RTL is copied or edited. Everything below is derived from
    // ports only -- the harness holds no copy of a DUT register.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_ENABLE
    // an ACCESS phase that never arrives
    wire obs_penable = penable & ~f_glitch;
`else
    wire obs_penable = penable;
`endif

`ifdef FV_FAULT_STABLE
    // a payload wire that moves under a standing ACCESS
    wire [RAW-1:0] obs_paddr = paddr ^ {{(RAW-1){1'b0}}, f_glitch};
`else
    wire [RAW-1:0] obs_paddr = paddr;
`endif

    // ----------------------------------------------------------------
    // APB phase tracking, from the ports alone
    // ----------------------------------------------------------------
    wire setup    = psel & ~obs_penable;
    wire access   = psel &  obs_penable;
    wire bus_fire = access & pready;

    reg            setup_d, access_d, pready_d;
    reg            psel_d, penable_d;
    reg [RAW-1:0]  paddr_s;
    reg [RW-1:0]   pwdata_s;
    reg [RW/8-1:0] pstrb_s;
    reg [2:0]      pprot_s;
    reg            pwrite_s;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            setup_d   <= 1'b0;
            access_d  <= 1'b0;
            pready_d  <= 1'b0;
            psel_d    <= 1'b0;
            penable_d <= 1'b0;
        end else begin
            setup_d   <= setup;
            access_d  <= access;
            pready_d  <= pready;
            psel_d    <= psel;
            penable_d <= obs_penable;
        end

    // the payload as it stood in SETUP, which ACCESS must repeat
    always @(posedge clk)
        if (setup) begin
            paddr_s  <= obs_paddr;
            pwdata_s <= pwdata;
            pstrb_s  <= pstrb;
            pprot_s  <= pprot;
            pwrite_s <= pwrite;
        end

    // The request a transfer serves is the one on the UMI wires in its
    // SETUP cycle: umi2apb drives the bus combinationally from those
    // wires that cycle (umi2apb.v:142-143) and latches the same word on
    // the same edge (umi2apb.v:118-124). Shadowing it here from the
    // PORTS keeps every law port-observable.
    reg [4:0] setup_op;
    always @(posedge clk)
        if (setup)
            setup_op <= req_op;

    reg [4:0] served_op;
    reg       served_err;
    reg       posted_seen;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            served_op   <= 5'd0;
            served_err  <= 1'b0;
            posted_seen <= 1'b0;
        end else if (bus_fire) begin
            served_op   <= setup_op;
            served_err  <= pslverr;
            posted_seen <= (setup_op == UMI_REQ_POSTED);
        end

`ifdef FV_FAULT_KIND
    // the response opcode swapped: RESP_RD 0x02 and RESP_WR 0x04 differ
    // by 0x06, so one constant exchanges them without disturbing any
    // other field
    wire [CW-1:0] obs_resp_cmd = resp_cmd ^ {{(CW-5){1'b0}}, 5'h06};
`else
    wire [CW-1:0] obs_resp_cmd = resp_cmd;
`endif

`ifdef FV_FAULT_POSTED
    // a response raised for a posted write, which must never be answered
    wire obs_resp_valid = resp_valid | (f_glitch & posted_seen);
`else
    wire obs_resp_valid = resp_valid;
`endif

    // ----------------------------------------------------------------
    // the response channel is judged by the same rule list the request
    // face is constrained by
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (0)
    ) chk_resp (
        .clk (clk), .nreset (nreset),
        .valid (obs_resp_valid), .ready (resp_ready),
        .cmd (obs_resp_cmd), .dstaddr (resp_dstaddr),
        .srcaddr (resp_srcaddr), .data (resp_data)
    );

    // ----------------------------------------------------------------
    // AMBA APB requester obligations
    // ----------------------------------------------------------------
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            APB1_enable_needs_sel : assert (!obs_penable || psel);
            APB2_setup_to_access  : assert (!setup_d || access);
            APB3_hold_until_ready : assert (!(access_d & ~pready_d) || access);
            APB4_payload_stable   : assert (!access
                                            || ((obs_paddr == paddr_s)
                                                && (pwdata  == pwdata_s)
                                                && (pstrb   == pstrb_s)
                                                && (pprot   == pprot_s)
                                                && (pwrite  == pwrite_s)));
            APB5_sel_drops_clean  : assert (!(psel_d & ~psel)
                                            || (penable_d & pready_d));
        end

    // ----------------------------------------------------------------
    // the response answers the request
    // ----------------------------------------------------------------
    wire [4:0] resp_op  = obs_resp_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];
    wire [1:0] resp_err = obs_resp_cmd[UMI_USER_MSB:UMI_USER_LSB];

    always @(posedge clk)
        if (nreset & f_past_exists & obs_resp_valid) begin
            a_apb_kind : assert (resp_op == ((served_op == UMI_REQ_READ)
                                             ? UMI_RESP_READ : UMI_RESP_WRITE));
            a_apb_err_map : assert (resp_err == (served_err ? 2'b10 : 2'b00));
            a_apb_posted_quiet : assert (!posted_seen);
        end

    // a new SETUP cannot begin while an answer is still standing
    always @(posedge clk)
        if (nreset & f_past_exists)
            a_apb_one_outstanding : assert (!(setup & obs_resp_valid));

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_apb_setup   : cover (setup);
            c_apb_access  : cover (access);
            c_apb_wait    : cover (access & ~pready);
            c_apb_fire    : cover (bus_fire);
            c_apb_write   : cover (bus_fire & pwrite);
            c_apb_read    : cover (bus_fire & ~pwrite);
            c_apb_resp    : cover (obs_resp_valid & resp_ready);
            c_apb_err     : cover (obs_resp_valid & (resp_err == 2'b10));
            c_apb_stalled : cover (obs_resp_valid & ~resp_ready);
        end
`ifdef FV_APB_ASSERT_DROP
    // The block header's own claim, written as a law:
    //
    //   "SUMI Atomics are not supported. Atomic requests will be
    //    dropped silently. SUMI RDMA is not supported. RDMA requests
    //    will be dropped silently."   (umi2apb.v:33-34)
    //
    // It does not hold. incoming_req (umi2apb.v:116) is
    // valid & ready & group_match with no opcode term, so an atomic or
    // an RDMA request starts an APB transfer like any other. This row
    // is pinned as a must-FAIL so the finding cannot quietly go away:
    // if the block ever does filter these opcodes, the row goes green
    // and the lane reports it.
    always @(posedge clk)
        if (nreset & f_past_exists)
            a_apb_unsupported_dropped :
                assert (!(bus_fire & ((setup_op == UMI_REQ_ATOMIC)
                                      || (setup_op == UMI_REQ_RDMA))));
`endif

`ifdef FV_APB_ANYOP
    // With the opcode assumption withdrawn: the block header says
    // atomics and RDMA are "dropped silently", but incoming_req
    // (umi2apb.v:116) has no opcode term, so nothing filters them.
    // These witnesses record what actually happens.
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_apb_atomic_bus  : cover (bus_fire & (setup_op == UMI_REQ_ATOMIC));
            c_apb_rdma_bus    : cover (bus_fire & (setup_op == UMI_REQ_RDMA));
            // and the answer they get back
            c_apb_atomic_resp : cover (obs_resp_valid
                                       & (served_op == UMI_REQ_ATOMIC));
        end
`endif
`endif

endmodule

`default_nettype wire
