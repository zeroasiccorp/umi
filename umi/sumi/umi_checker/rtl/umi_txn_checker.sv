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
 * Passive transaction / framing checker for the SUMI RESPONSE stream
 * (README section 3, "Transaction Layer", and section 4.1 "Signal UMI
 * / packet splitting"). The checker observes BOTH channels of one
 * point-to-point link -- the request channel to learn what responses
 * are owed, the response channel to convict every response beat that
 * breaks a transaction- or framing-level rule. It drives nothing and
 * never interferes with the design; attach it exactly like the
 * handshake and command checkers in this directory.
 *
 * This is the L2 (response-side) partner of umi_cmd_checker (L1,
 * per-beat CMD legality). Where umi_cmd_checker judges a single beat in
 * isolation, umi_txn_checker judges a beat AGAINST THE REQUEST IT
 * ANSWERS and against the framing history of the message it belongs to.
 *
 * OPERATING CONDITION -- NO INTERLEAVE (read this first). This checker
 * assumes a SINGLE, UN-INTERLEAVED response stream: the point-to-point
 * link BEFORE any mux/merge, where responses return in the same order
 * as the requests that elicited them. It tracks outstanding requests in
 * a small in-order shadow FIFO and matches each response beat against
 * the queue HEAD. It does NOT fold responses by HOSTID (or by any other
 * routing key), so it must NOT be bound downstream of a mux that
 * interleaves responses from several devices -- there it would convict
 * legal merged traffic (the correct fold key is bridge-dependent -- TL
 * carries source in SA[7:0], not HOSTID -- so per-key folding is
 * deferred). Bind it on the un-merged link segment.
 *
 * SCOPE -- RESPONSE-SIDE FRAMING ONLY. Every asserted rule is a property
 * of a RESPONSE beat. Request beats are observed (to populate the
 * tracker) but their intra-message framing is NOT asserted here:
 * request-side framing assertion is future work -- a host emitting
 * broken multi-beat requests is not caught by this module.
 *
 * The rules, with their README (UMI spec) anchors:
 *
 *   TXN_p5_outstanding   every response beat has a matching outstanding
 *                        request: the tracker is non-empty (README 3:
 *                        a response answers a request).
 *   TXN_kind             the response OPCODE is the kind the request
 *                        maps to: REQ_RD/REQ_ATOMIC -> RESP_RD,
 *                        REQ_WR -> RESP_WR (README 3.2.3).
 *   TXN_size / TXN_qos / TXN_prot / TXN_hostid
 *                        the response copies the request's SIZE, QOS,
 *                        PROT and HOSTID fields (README 3.2.3 field
 *                        columns). HOSTID is checked here (not used as a
 *                        fold key -- see NO INTERLEAVE).
 *   TXN_exok             an EXOK (ERR==0b01) response is returned only
 *                        for a request that carried EX (README 3.3.8
 *                        exclusive-access sequence, 3.3.9 EXOK).
 *   TXN_da_first         the FIRST response beat's DA equals the
 *                        request's SA ("For responses, the DA field
 *                        returned is a copy of the requester SA field",
 *                        README 3.3.1).
 *   TXN_da_cont          a CONTINUATION beat's DA equals the running
 *                        address: prev DA + (2^SIZE)*(LEN+1) of the
 *                        previous beat (README 3.3.3 ADDR_i law, 4.1
 *                        split example "only DA increments"). Computed
 *                        modulo 2^AW -- the wrap boundary is an open
 *                        question (README 4.1 gives a safe-bit rule
 *                        A[n-1:0]+(2^SIZE)(LEN+1) < 2^n but does not
 *                        define behaviour past the wrap; this checker
 *                        follows modular wrap).
 *   TXN_frm2_err         ERR and EOF are stable across the beats of one
 *   TXN_frm2_eof         message: a split response does not change its
 *                        error status or frame membership mid-message
 *                        (README 3.3.7 EOF, 3.3.9 ERR).
 *   TXN_err_len          an error response (DEVERR/NETERR) copies the
 *   TXN_err_first        request LEN, is the FIRST beat, is single-beat
 *   TXN_err_eom          (EOM), and carries zero data in the relevant
 *   TXN_err_zero         lanes (README 3.3.9 error semantics; an error
 *                        reply is one terminating beat that echoes the
 *                        request length and returns no data).
 *   TXN_bytes_le         a non-error response never returns more bytes
 *                        than the request asked for: the running total
 *                        got + this-beat-bytes <= expected message bytes
 *                        (README 3.3.2/3.3.3).
 *   TXN_eom_iff_closed   EOM is set on a non-error beat IFF that beat
 *                        closes the message exactly (running total ==
 *                        expected) -- EOM neither early nor missing
 *                        (README 3.3.6 EOM, 4.1 "EOM indicates the last
 *                        packet").
 *   TXN_msgbytes         the accumulated data bytes of the in-flight
 *                        response message never exceed MAX_MSG_BYTES
 *                        (default 32768 = the spec bound 128 B/word *
 *                        256 words, README 3.3.2 SIZE, 3.3.3 LEN).
 *                        This is a per-message byte accumulator: a
 *                        single beat's 16-bit (2^SIZE)*(LEN+1) cannot
 *                        exceed 32768, so a per-beat check would be
 *                        vacuous (no counterexample exists). The
 *                        accumulator instead sums the ACTUAL response
 *                        stream across beats and IS falsifiable: a
 *                        responder that returns more bytes than the
 *                        bound trips it.
 *   TXN_occ_bound        the outstanding-request tracker never exceeds
 *                        its capacity CAP: tracker overflow is REPORTED,
 *                        never silent (a bound checker must announce
 *                        when it can no longer track).
 *   TXN_reconcile        an idle link (nothing outstanding) reconciles
 *                        to a fresh framing state (no half-received
 *                        message left dangling) -- an inductive
 *                        invariant that also documents the idle
 *                        contract.
 *
 * DEFERRED: a bounded-response LIVENESS rule ("the head is answered
 * within LIV_MAX cycles") is NOT included. It needs a fairness
 * assumption on resp_ready and an age counter whose progress tie is not
 * inductive in the portable subset without harness support. Liveness is
 * left to a dedicated watchdog. The occupancy bound above is the safety
 * half that this checker does make precise.
 *
 * ASSUME parameter: identical contract to the other checkers in this
 * directory.
 *   ASSUME=0 (default): assert the rules -- attach to the response
 *            channel a design under test drives (simulation or formal).
 *   ASSUME=1: assume the rules (formal-only) -- constrain the free
 *            response channel of a harness to legal response traffic.
 *            The same file is both requirement and environment, so the
 *            two can never drift apart.
 *
 * RULE_EN parameter: one enable bit per rule, so a link that breaks a
 * single rule -- or an integrator who reads one rule differently --
 * can drop that one rule instead of unbinding the whole checker. A
 * cleared bit removes the rule from BOTH the assert and the assume
 * face, so a masked instance stays the same property in either
 * direction. The default 20'hFFFFF enables every rule and is
 * behaviour-identical to leaving the parameter unset.
 *
 *   bit  rule                bit  rule
 *   ---  ------------------  ---  ------------------
 *    0   TXN_p5_outstanding   10  TXN_frm2_eof
 *    1   TXN_kind             11  TXN_err_len
 *    2   TXN_size             12  TXN_err_first
 *    3   TXN_qos              13  TXN_err_eom
 *    4   TXN_prot             14  TXN_err_zero
 *    5   TXN_hostid           15  TXN_bytes_le
 *    6   TXN_exok             16  TXN_eom_iff_closed
 *    7   TXN_da_first         17  TXN_msgbytes
 *    8   TXN_da_cont          18  TXN_occ_bound
 *    9   TXN_frm2_err         19  TXN_reconcile
 *
 * Parameters:
 *   CW / AW / DW    command / address / data bus widths.
 *   CAP             outstanding-request tracker capacity (the overflow
 *                   report threshold for a_txn_occ_bound). The shadow
 *                   storage is two deep (head e0 + next e1) -- the small
 *                   window a point-to-point link needs; CAP in {1,2} is
 *                   meaningful (CAP=1 models a single-outstanding link;
 *                   a deeper store is future work). Default 2.
 *   MAX_MSG_BYTES   per-message byte ceiling (default 32768, the
 *                   spec maximum). Lower it (e.g. 256) to make the
 *                   accumulator boundary observable at shallow depth.
 *   ASSUME          assert (0) vs assume (1) the rules.
 *   RULE_EN         per-rule enables (see the table above).
 *
 * Bind guidance: instantiate one per point-to-point UMI link, wiring
 * the request channel to the host->device path and the response channel
 * to the device->host path. Bind it BEFORE any response mux (see NO
 * INTERLEAVE). Response SRCADDR is undefined by README 3.3.1 and is
 * observed-but-never-checked; request DATA is not judged by an L2
 * pairing checker and is likewise waived.
 *
 * Implementation notes (same portable subset as the other checkers):
 *  - Field positions and opcode values come from umi_messages.vh, the
 *    repo's single source of truth. Decode is done through module-local
 *    `function automatic`s in the name-assignment form (no 'return', no
 *    'inside', no packages) so the same file parses under slang, yosys
 *    (read_verilog -formal), Verilator and Icarus. The only locally
 *    declared constants are the ERR codes, which umi_messages.vh does
 *    not define (README 3.3.9).
 *  - Named immediate assertions inside always blocks; each assert is
 *    paired with an `ifndef FORMAL $error twin whose !== comparison also
 *    catches X in 4-state simulation. Cover statements are formal-only
 *    (`ifdef FORMAL).
 *  - No $past: the framing history is kept in explicit shadow registers
 *    grounded in an initial block, so the file runs under simulators
 *    without $past support and is Verilator -Wall clean.
 ******************************************************************************/

`default_nettype none

module umi_txn_checker #(
    parameter CW = 32,                       // command width
    parameter AW = 64,                       // address width
    parameter DW = 256,                      // data width
    parameter CAP = 2,                       // outstanding-tracker report threshold
    parameter [31:0] MAX_MSG_BYTES = 32768,  // per-message byte ceiling
    parameter ASSUME = 0,                    // 0: assert the rules, 1: assume them
    parameter [19:0] RULE_EN = 20'hFFFFF     // per-rule enables (see header table)
) (
    input wire          clk,
    input wire          nreset,
    // request channel (observed to learn what responses are owed)
    input wire          req_valid,
    input wire          req_ready,
    input wire [CW-1:0] req_cmd,
    input wire [AW-1:0] req_dstaddr,
    input wire [AW-1:0] req_srcaddr,
    input wire [DW-1:0] req_data,
    // response channel (checked)
    input wire          resp_valid,
    input wire          resp_ready,
    input wire [CW-1:0] resp_cmd,
    input wire [AW-1:0] resp_dstaddr,
    input wire [AW-1:0] resp_srcaddr,
    input wire [DW-1:0] resp_data,
    // ---- formal observation outputs (tracker / framing shadow state) ----
    // These expose the internal shadow registers so a formal HARNESS can
    // write glue lemmas that tie this checker's tracker to a reference
    // model (see umi/formal/sumi/fv_umi_txn.sv). They carry NO functional
    // obligation: leave them UNCONNECTED in every simulation or formal
    // bind, where they are optimized away. Entry packing (LSB first):
    // {bytes[15:0], da[AW-1:0], hostid[4:0], ex, prot[1:0], qos[3:0],
    //  len[7:0], size[2:0], ropc[4:0]} = AW+44 bits.
    output wire [1:0]     f_occ,
    output wire [15:0]    f_got,
    output wire           f_first,
    output wire [AW-1:0]  f_next_da,
    output wire [CW-1:0]  f_last_cmd,
    output wire [AW+43:0] f_e0,
    output wire [AW+43:0] f_e1
);

    // the shared header declares every UMI constant; a checker uses only
    // a subset, so the unused ones are waived
    // verilator lint_off UNUSEDPARAM
`include "umi_messages.vh"
    // verilator lint_on UNUSEDPARAM

    // ERR codes on the response USER/ERR field (README 3.3.9). These are
    // the one set of constants not present in umi_messages.vh; the
    // sibling umi_cmd_checker declares them the same way.
    localparam [1:0] UMI_ERR_EXOK   = 2'd1;
    localparam [1:0] UMI_ERR_DEVERR = 2'd2;
    localparam [1:0] UMI_ERR_NETERR = 2'd3;

    // request DATA and request DSTADDR (the target of the request, not
    // needed to judge a response) are not L2 obligations; response
    // SRCADDR is undefined (README 3.3.1) -- observe, but never convict
    wire unused_ok = &{1'b1, req_data, req_dstaddr, resp_srcaddr};

    // #################################################################
    // # Field decode (umi_messages.vh bit positions) -- portable
    // # name-assignment functions, callable on req_cmd or resp_cmd. Each
    // # function slices its wide CMD argument, so its unused bits are
    // # waived (a generic decoder over the whole command word).
    // #################################################################

    // verilator lint_off UNUSEDSIGNAL
    function automatic [4:0] f_op5(input [CW-1:0] c);
        f_op5 = c[UMI_OPCODE_MSB:UMI_OPCODE_LSB]; endfunction
    function automatic [7:0] f_opbyte(input [CW-1:0] c);
        f_opbyte = c[7:0]; endfunction
    function automatic [2:0] f_size(input [CW-1:0] c);
        f_size = c[UMI_SIZE_MSB:UMI_SIZE_LSB]; endfunction
    function automatic [7:0] f_len(input [CW-1:0] c);
        f_len = c[UMI_LEN_MSB:UMI_LEN_LSB]; endfunction
    function automatic [3:0] f_qos(input [CW-1:0] c);
        f_qos = c[UMI_QOS_MSB:UMI_QOS_LSB]; endfunction
    function automatic [1:0] f_prot(input [CW-1:0] c);
        f_prot = c[UMI_PROT_MSB:UMI_PROT_LSB]; endfunction
    function automatic f_eom(input [CW-1:0] c);
        f_eom = c[UMI_EOM_BIT]; endfunction
    function automatic f_eof(input [CW-1:0] c);
        f_eof = c[UMI_EOF_BIT]; endfunction
    function automatic f_ex(input [CW-1:0] c);
        f_ex = c[UMI_EX_BIT]; endfunction
    function automatic [1:0] f_user(input [CW-1:0] c);
        f_user = c[UMI_USER_MSB:UMI_USER_LSB]; endfunction
    function automatic [4:0] f_hostid(input [CW-1:0] c);
        f_hostid = c[UMI_HOSTID_MSB:UMI_HOSTID_LSB]; endfunction

    function automatic f_is_req(input [CW-1:0] c);
        f_is_req = c[0] & (f_opbyte(c) != UMI_INVALID); endfunction
    function automatic f_is_resp(input [CW-1:0] c);
        f_is_resp = ~c[0] & (f_opbyte(c) != UMI_INVALID); endfunction
    function automatic f_is_link(input [CW-1:0] c);
        f_is_link = (f_opbyte(c) == UMI_REQ_LINK)
                  | (f_opbyte(c) == UMI_RESP_LINK); endfunction
    function automatic f_is_fullbyte(input [CW-1:0] c);
        f_is_fullbyte = (f_opbyte(c) == UMI_REQ_ERROR)
                      | (f_opbyte(c) == UMI_REQ_LINK)
                      | (f_opbyte(c) == UMI_RESP_LINK); endfunction

    // which requests elicit a response, and of which kind (README 3.2.3;
    // POSTED/RDMA/ERROR/LINK elicit nothing, USER/FUTURE excluded)
    function automatic f_expects_resp(input [CW-1:0] c);
        f_expects_resp = f_is_req(c) & ~f_is_fullbyte(c)
                       & ((f_op5(c) == UMI_REQ_READ)
                          | (f_op5(c) == UMI_REQ_WRITE)
                          | (f_op5(c) == UMI_REQ_ATOMIC)); endfunction
    function automatic [4:0] f_resp_op5(input [CW-1:0] c);
        f_resp_op5 = (f_op5(c) == UMI_REQ_WRITE)
                   ? UMI_RESP_WRITE[4:0] : UMI_RESP_READ[4:0]; endfunction

    // raw byte count (2^SIZE)*(LEN+1) -- NOT relevance-aware
    function automatic [15:0] f_bytes(input [CW-1:0] c);
        f_bytes = (16'd1 << f_size(c)) * ({8'd0, f_len(c)} + 16'd1);
        endfunction
    // does this opcode carry DATA (README 3.2.3 DATA column)
    function automatic f_has_data(input [CW-1:0] c);
        f_has_data = (f_op5(c) == UMI_REQ_WRITE)
                   | (f_op5(c) == UMI_REQ_POSTED)
                   | (f_op5(c) == UMI_REQ_ATOMIC)
                   | (f_op5(c) == UMI_REQ_USER0)
                   | (f_op5(c) == UMI_REQ_FUTURE0)
                   | (f_op5(c) == UMI_RESP_READ)
                   | (f_op5(c) == UMI_RESP_USER1)
                   | (f_op5(c) == UMI_RESP_FUTURE1); endfunction
    // relevance-aware byte count: none if no data; 2^SIZE for atomics
    // (LEN aliases ATYPE); else (2^SIZE)*(LEN+1)
    function automatic [15:0] f_bytes_rel(input [CW-1:0] c);
        f_bytes_rel = ~f_has_data(c) ? 16'd0
                    : (f_op5(c) == UMI_REQ_ATOMIC) ? (16'd1 << f_size(c))
                    : f_bytes(c); endfunction
    // verilator lint_on UNUSEDSIGNAL

    // #################################################################
    // # Beat / pairing events
    // #################################################################

    wire req_beat  = req_valid & req_ready;
    // enqueue a response obligation at the request's EOM beat (the whole
    // request message maps to one response message)
    wire req_qual  = req_beat & f_expects_resp(req_cmd);
    wire push      = req_qual & f_eom(req_cmd);

    // NO INTERLEAVE: every response beat matches the queue head -- no
    // HOSTID (or other key) filtering
    wire resp_beat = resp_valid & resp_ready;
    wire resp_hit  = resp_beat & f_is_resp(resp_cmd) & ~f_is_link(resp_cmd);
    wire resp_err  = (f_user(resp_cmd) == UMI_ERR_DEVERR)
                   | (f_user(resp_cmd) == UMI_ERR_NETERR);
    wire pop       = resp_hit & f_eom(resp_cmd);
    wire [15:0] rbytes = f_bytes_rel(resp_cmd);

    // expected response bytes for the request being enqueued: WR acks
    // carry none; atomics return 2^SIZE (LEN is ATYPE); reads return the
    // full (2^SIZE)*(LEN+1)
    wire [15:0] push_bytes =
          (f_op5(req_cmd) == UMI_REQ_WRITE)  ? 16'd0
        : (f_op5(req_cmd) == UMI_REQ_ATOMIC) ? (16'd1 << f_size(req_cmd))
        : f_bytes(req_cmd);

    // #################################################################
    // # Outstanding-request tracker: in-order shadow FIFO (head e0,
    // # next e1). occ is the count; CAP is the report threshold.
    // #################################################################

    reg [1:0]    occ;
    reg [4:0]    e0_ropc,  e1_ropc;
    reg [2:0]    e0_size,  e1_size;
    reg [7:0]    e0_len,   e1_len;
    reg [3:0]    e0_qos,   e1_qos;
    reg [1:0]    e0_prot,  e1_prot;
    reg          e0_ex,    e1_ex;
    reg [4:0]    e0_hostid, e1_hostid;
    reg [AW-1:0] e0_da,    e1_da;
    reg [15:0]   e0_bytes, e1_bytes;

    reg [15:0]   got;        // data bytes received for the head message so far
    reg          first;      // next response beat is the head's first beat
    reg [AW-1:0] next_da;    // running continuation address (DA law)
    reg [CW-1:0] last_cmd;   // previous response beat's cmd (no $past)

    initial begin
        occ     = 2'd0;
        got     = 16'd0;
        first   = 1'b1;
        next_da = {AW{1'b0}};
        last_cmd = {CW{1'b0}};
    end

    always @(posedge clk) begin
        if (!nreset) begin
            occ   <= 2'd0;
            got   <= 16'd0;
            first <= 1'b1;
        end else begin
            // ---- queue update (head-shift register, depth 2) ----
            case ({push, pop})
                2'b10: begin                              // push only
                    if (occ == 2'd0) begin
                        e0_ropc <= f_resp_op5(req_cmd);
                        e0_size <= f_size(req_cmd);
                        e0_len  <= f_len(req_cmd);
                        e0_qos  <= f_qos(req_cmd);
                        e0_prot <= f_prot(req_cmd);
                        e0_ex   <= f_ex(req_cmd);
                        e0_hostid <= f_hostid(req_cmd);
                        e0_da   <= req_srcaddr;
                        e0_bytes <= push_bytes;
                    end else begin
                        e1_ropc <= f_resp_op5(req_cmd);
                        e1_size <= f_size(req_cmd);
                        e1_len  <= f_len(req_cmd);
                        e1_qos  <= f_qos(req_cmd);
                        e1_prot <= f_prot(req_cmd);
                        e1_ex   <= f_ex(req_cmd);
                        e1_hostid <= f_hostid(req_cmd);
                        e1_da   <= req_srcaddr;
                        e1_bytes <= push_bytes;
                    end
                    occ <= occ + 2'd1;
                end
                2'b01: begin                              // pop only
                    e0_ropc <= e1_ropc;
                    e0_size <= e1_size;
                    e0_len  <= e1_len;
                    e0_qos  <= e1_qos;
                    e0_prot <= e1_prot;
                    e0_ex   <= e1_ex;
                    e0_hostid <= e1_hostid;
                    e0_da   <= e1_da;
                    e0_bytes <= e1_bytes;
                    occ <= occ - 2'd1;
                end
                2'b11: begin                              // push + pop
                    if (occ == 2'd1) begin
                        e0_ropc <= f_resp_op5(req_cmd);
                        e0_size <= f_size(req_cmd);
                        e0_len  <= f_len(req_cmd);
                        e0_qos  <= f_qos(req_cmd);
                        e0_prot <= f_prot(req_cmd);
                        e0_ex   <= f_ex(req_cmd);
                        e0_hostid <= f_hostid(req_cmd);
                        e0_da   <= req_srcaddr;
                        e0_bytes <= push_bytes;
                    end else begin
                        e0_ropc <= e1_ropc;
                        e0_size <= e1_size;
                        e0_len  <= e1_len;
                        e0_qos  <= e1_qos;
                        e0_prot <= e1_prot;
                        e0_ex   <= e1_ex;
                        e0_hostid <= e1_hostid;
                        e0_da   <= e1_da;
                        e0_bytes <= e1_bytes;
                        e1_ropc <= f_resp_op5(req_cmd);
                        e1_size <= f_size(req_cmd);
                        e1_len  <= f_len(req_cmd);
                        e1_qos  <= f_qos(req_cmd);
                        e1_prot <= f_prot(req_cmd);
                        e1_ex   <= f_ex(req_cmd);
                        e1_hostid <= f_hostid(req_cmd);
                        e1_da   <= req_srcaddr;
                        e1_bytes <= push_bytes;
                    end
                end
                default: ;                                // idle
            endcase

            // ---- framing progress on the response head ----
            if (resp_hit) begin
                last_cmd <= resp_cmd;
                if (f_eom(resp_cmd)) begin
                    got   <= 16'd0;                       // message closed
                    first <= 1'b1;
                end else begin
                    got     <= got + rbytes;              // per-message accumulate
                    first   <= 1'b0;
                    // continuation address: prev DA + prev-beat bytes,
                    // modulo 2^AW (wrap boundary undefined by the spec)
                    next_da <= resp_dstaddr
                               + {{(AW-16){1'b0}}, f_bytes(resp_cmd)};
                end
            end
        end
    end

    // #################################################################
    // # Error-branch DATA==0 lane check (rel-masked over the beat)
    // #################################################################

    integer li;
    reg lanes_zero;
    always @(*) begin
        lanes_zero = 1'b1;
        for (li = 0; li < DW/8; li = li + 1)
            if ({16'd0, li[15:0]} < {16'd0, rbytes}
                && resp_data[8*li +: 8] != 8'd0)
                lanes_zero = 1'b0;
    end

    // running / next byte totals for the head message
    wire [31:0] tot_bytes = {16'd0, got} + {16'd0, rbytes};

    // formal observation taps (see port comment)
    assign f_occ     = occ;
    assign f_got     = got;
    assign f_first   = first;
    assign f_next_da = next_da;
    assign f_last_cmd = last_cmd;
    assign f_e0 = {e0_bytes, e0_da, e0_hostid, e0_ex, e0_prot, e0_qos,
                   e0_len, e0_size, e0_ropc};
    assign f_e1 = {e1_bytes, e1_da, e1_hostid, e1_ex, e1_prot, e1_qos,
                   e1_len, e1_size, e1_ropc};

    // #################################################################
    // # The rules (one generate arm per direction)
    // #################################################################

    generate
        if (ASSUME == 0) begin : g_assert

            always @(posedge clk) begin
                if (nreset) begin
                    if (resp_hit) begin
                        if (RULE_EN[0]) begin
                            TXN_p5_outstanding : assert (occ != 2'd0);
`ifndef FORMAL
                            if ((occ != 2'd0) !== 1'b1)
                                $error("UMI-TXN p5 %m: response beat with nothing outstanding (README 3: a response answers a request)");
`endif
                        end
                        if (RULE_EN[1]) begin
                            TXN_kind : assert (f_op5(resp_cmd) == e0_ropc);
`ifndef FORMAL
                            if ((f_op5(resp_cmd) == e0_ropc) !== 1'b1)
                                $error("UMI-TXN kind %m: response OPCODE does not match the request's response kind (README 3.2.3)");
`endif
                        end
                        if (RULE_EN[2]) begin
                            TXN_size : assert (f_size(resp_cmd) == e0_size);
`ifndef FORMAL
                            if ((f_size(resp_cmd) == e0_size) !== 1'b1)
                                $error("UMI-TXN size %m: response SIZE != request SIZE (README 3.2.3)");
`endif
                        end
                        if (RULE_EN[3]) begin
                            TXN_qos : assert (f_qos(resp_cmd) == e0_qos);
`ifndef FORMAL
                            if ((f_qos(resp_cmd) == e0_qos) !== 1'b1)
                                $error("UMI-TXN qos %m: response QOS != request QOS (README 3.2.3)");
`endif
                        end
                        if (RULE_EN[4]) begin
                            TXN_prot : assert (f_prot(resp_cmd) == e0_prot);
`ifndef FORMAL
                            if ((f_prot(resp_cmd) == e0_prot) !== 1'b1)
                                $error("UMI-TXN prot %m: response PROT != request PROT (README 3.2.3)");
`endif
                        end
                        if (RULE_EN[5]) begin
                            TXN_hostid : assert (f_hostid(resp_cmd) == e0_hostid);
`ifndef FORMAL
                            if ((f_hostid(resp_cmd) == e0_hostid) !== 1'b1)
                                $error("UMI-TXN hostid %m: response HOSTID != request HOSTID (README 3.2.3)");
`endif
                        end
                        if (RULE_EN[6]) begin
                            TXN_exok : assert ((f_user(resp_cmd) != UMI_ERR_EXOK) || e0_ex);
`ifndef FORMAL
                            if (((f_user(resp_cmd) != UMI_ERR_EXOK) || e0_ex) !== 1'b1)
                                $error("UMI-TXN exok %m: EXOK response to a non-exclusive request (README 3.3.8/3.3.9)");
`endif
                        end
                        if (first) begin
                            if (RULE_EN[7]) begin
                                TXN_da_first : assert (resp_dstaddr == e0_da);
`ifndef FORMAL
                                if ((resp_dstaddr == e0_da) !== 1'b1)
                                    $error("UMI-TXN da_first %m: first response DA != request SA (README 3.3.1)");
`endif
                            end
                        end else begin
                            if (RULE_EN[8]) begin
                                TXN_da_cont : assert (resp_dstaddr == next_da);
`ifndef FORMAL
                                if ((resp_dstaddr == next_da) !== 1'b1)
                                    $error("UMI-TXN da_cont %m: split-response DA breaks the continuation law (README 3.3.3/4.1)");
`endif
                            end
                            if (RULE_EN[9]) begin
                                TXN_frm2_err : assert (f_user(resp_cmd) == f_user(last_cmd));
`ifndef FORMAL
                                if ((f_user(resp_cmd) == f_user(last_cmd)) !== 1'b1)
                                    $error("UMI-TXN frm2 %m: ERR changed mid-message (README 3.3.9)");
`endif
                            end
                            if (RULE_EN[10]) begin
                                TXN_frm2_eof : assert (f_eof(resp_cmd) == f_eof(last_cmd));
`ifndef FORMAL
                                if ((f_eof(resp_cmd) == f_eof(last_cmd)) !== 1'b1)
                                    $error("UMI-TXN frm2 %m: EOF changed mid-message (README 3.3.7)");
`endif
                            end
                        end
                        if (resp_err) begin
                            if (RULE_EN[11]) begin
                                TXN_err_len : assert (f_len(resp_cmd) == e0_len);
`ifndef FORMAL
                                if ((f_len(resp_cmd) == e0_len) !== 1'b1)
                                    $error("UMI-TXN err_len %m: error response LEN != request LEN (README 3.3.9)");
`endif
                            end
                            if (RULE_EN[12]) begin
                                TXN_err_first : assert (first);
`ifndef FORMAL
                                if ((first) !== 1'b1)
                                    $error("UMI-TXN err_first %m: error response beat mid-message (README 3.3.9)");
`endif
                            end
                            if (RULE_EN[13]) begin
                                TXN_err_eom : assert (f_eom(resp_cmd));
`ifndef FORMAL
                                if ((f_eom(resp_cmd)) !== 1'b1)
                                    $error("UMI-TXN err_eom %m: error response not single-beat (README 3.3.9)");
`endif
                            end
                            if (RULE_EN[14]) begin
                                TXN_err_zero : assert (lanes_zero);
`ifndef FORMAL
                                if ((lanes_zero) !== 1'b1)
                                    $error("UMI-TXN err_zero %m: DEVERR/NETERR response carries nonzero data (README 3.3.9)");
`endif
                            end
                        end else begin
                            if (RULE_EN[15]) begin
                                TXN_bytes_le : assert (tot_bytes[15:0] <= e0_bytes
                                                       && tot_bytes[31:16] == 16'd0);
`ifndef FORMAL
                                if ((tot_bytes <= {16'd0, e0_bytes}) !== 1'b1)
                                    $error("UMI-TXN bytes_le %m: response over-returns bytes (README 3.3.2/3.3.3)");
`endif
                            end
                            if (RULE_EN[16]) begin
                                TXN_eom_iff_closed : assert (f_eom(resp_cmd)
                                                             == (tot_bytes == {16'd0, e0_bytes}));
`ifndef FORMAL
                                if ((f_eom(resp_cmd) == (tot_bytes == {16'd0, e0_bytes})) !== 1'b1)
                                    $error("UMI-TXN eom_iff_closed %m: EOM not exactly on the closing beat (README 3.3.6/4.1)");
`endif
                            end
                            // real per-message byte accumulator
                            // (a per-beat check would be vacuous)
                            if (RULE_EN[17]) begin
                                TXN_msgbytes : assert (tot_bytes <= MAX_MSG_BYTES);
`ifndef FORMAL
                                if ((tot_bytes <= MAX_MSG_BYTES) !== 1'b1)
                                    $error("UMI-TXN msgbytes %m: message byte total exceeds MAX_MSG_BYTES (README 3.3.2/3.3.3)");
`endif
                            end
                        end
                    end
                    if (RULE_EN[18]) begin
                        TXN_occ_bound : assert (occ <= CAP);
`ifndef FORMAL
                        if ((occ <= CAP) !== 1'b1)
                            $error("UMI-TXN occ_bound %m: outstanding-request tracker overflow (> CAP)");
`endif
                    end
                    if (RULE_EN[19]) begin
                        TXN_reconcile : assert ((occ != 2'd0) || (got == 16'd0 && first));
`ifndef FORMAL
                        if (((occ != 2'd0) || (got == 16'd0 && first)) !== 1'b1)
                            $error("UMI-TXN reconcile %m: idle link left a dangling half-message");
`endif
                    end
                end
            end

        end else begin : g_assume
`ifdef FORMAL
            always @(posedge clk) begin
                if (nreset) begin
                    if (resp_hit) begin
                        if (RULE_EN[0])
                            TXN_p5_outstanding : assume (occ != 2'd0);
                        if (RULE_EN[1])
                            TXN_kind : assume (f_op5(resp_cmd) == e0_ropc);
                        if (RULE_EN[2])
                            TXN_size : assume (f_size(resp_cmd) == e0_size);
                        if (RULE_EN[3])
                            TXN_qos : assume (f_qos(resp_cmd) == e0_qos);
                        if (RULE_EN[4])
                            TXN_prot : assume (f_prot(resp_cmd) == e0_prot);
                        if (RULE_EN[5])
                            TXN_hostid : assume (f_hostid(resp_cmd) == e0_hostid);
                        if (RULE_EN[6])
                            TXN_exok : assume ((f_user(resp_cmd) != UMI_ERR_EXOK) || e0_ex);
                        if (first) begin
                            if (RULE_EN[7])
                                TXN_da_first : assume (resp_dstaddr == e0_da);
                        end else begin
                            if (RULE_EN[8])
                                TXN_da_cont : assume (resp_dstaddr == next_da);
                            if (RULE_EN[9])
                                TXN_frm2_err : assume (f_user(resp_cmd) == f_user(last_cmd));
                            if (RULE_EN[10])
                                TXN_frm2_eof : assume (f_eof(resp_cmd) == f_eof(last_cmd));
                        end
                        if (resp_err) begin
                            if (RULE_EN[11])
                                TXN_err_len : assume (f_len(resp_cmd) == e0_len);
                            if (RULE_EN[12])
                                TXN_err_first : assume (first);
                            if (RULE_EN[13])
                                TXN_err_eom : assume (f_eom(resp_cmd));
                            if (RULE_EN[14])
                                TXN_err_zero : assume (lanes_zero);
                        end else begin
                            if (RULE_EN[15])
                                TXN_bytes_le : assume (tot_bytes <= {16'd0, e0_bytes});
                            if (RULE_EN[16])
                                TXN_eom_iff_closed : assume (f_eom(resp_cmd)
                                                             == (tot_bytes == {16'd0, e0_bytes}));
                            if (RULE_EN[17])
                                TXN_msgbytes : assume (tot_bytes <= MAX_MSG_BYTES);
                        end
                    end
                    if (RULE_EN[18])
                        TXN_occ_bound : assume (occ <= CAP);
                    if (RULE_EN[19])
                        TXN_reconcile : assume ((occ != 2'd0) || (got == 16'd0 && first));
                end
            end
`endif
        end
    endgenerate

    // #################################################################
    // # Vacuity witnesses (formal-only)
    // #################################################################
    // A transaction proof over an environment that never completes a
    // message, never splits one, never returns an error, or never fills
    // the tracker proves little. These covers fail loudly (unreached) if
    // a harness or a bind over-constrains the channels.

`ifdef FORMAL
    always @(posedge clk) begin
        if (nreset) begin
            SAW_complete : cover (pop);
            SAW_split    : cover (resp_hit & ~f_eom(resp_cmd));
            SAW_journey  : cover (pop & ~first);            // multi-beat msg closes
            SAW_err      : cover (resp_hit & resp_err);
            SAW_full     : cover (occ == CAP);
`ifdef FORMAL_MSGBYTES_BOUNDARY
            // the accumulator reaches EXACTLY the ceiling (run with a
            // small chparam MAX_MSG_BYTES so the boundary is shallow)
            SAW_msgbytes_boundary :
                cover (resp_hit & ~resp_err & (tot_bytes == MAX_MSG_BYTES));
`endif
        end
    end
`endif

endmodule

`default_nettype wire
