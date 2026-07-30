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
 * Formal harness: umi_txn_checker (response-side L2 / framing rules)
 * driven by a small requester + responder model.
 *
 *   (anyseq legal requests) --> fv_umi_responder --clean resp--> [corrupt]
 *                                     |                              |
 *                                     +--(hierarchical glue lemmas)--+
 *                                     |                              v
 *                                     +----------------------> umi_txn_checker
 *                                                              (ASSERT face)
 *
 * The requester builds LEGAL single-beat requests from anyseq fields
 * (opcode in {READ,WRITE,ATOMIC}, legal ATYPE, EOM=1). The responder is
 * a perfect in-order device model: it enqueues each request that
 * expects a response, and emits the matching response -- splitting reads
 * word-per-beat, choosing ERR/data freely (anyseq) -- HS-clean by
 * construction. The checker observes both channels and must never fire.
 *
 * OPERATING CONDITION -- NO INTERLEAVE. This harness drives a SINGLE
 * point-to-point link: one responder, responses in request order. That
 * is exactly the condition umi_txn_checker assumes (see its header and
 * umi/formal/README.md). Because there is no interleave, the checker's
 * shadow FIFO equals the responder's queue ENTRY-FOR-ENTRY -- the glue
 * lemmas below are a DIRECT equality, not a per-key subsequence.
 *
 * Why the glue lemmas. The checker is stateful; a bare k-induction step
 * may place the checker's tracker out of sync with the responder and
 * then "discover" a field-copy violation that no reachable trace
 * exhibits. The glue lemmas (a_glue_*) are the inductive strengthening:
 * (1) the checker's queue equals the responder's queue, and (2) the
 * live response beat equals the responder's head. Together they discharge
 * every checker assertion. They are ASSERTED (proven), never assumed.
 *
 * Fault tasks (see fv_umi_txn.sby). Each FV_FAULT_* corrupts ONLY the
 * response view the CHECKER sees (the [corrupt] block), leaving the
 * responder -- and therefore every glue lemma -- clean, so each fault
 * trips its intended checker assertion. Some corruptions violate several
 * related rules on the same beat, and which label BMC reports is
 * solver-dependent (fv_umi_txn.sby tabulates the intended and alternate
 * labels per fault). The
 * two exceptions carry no corruption at all: fault_msgbytes shrinks the
 * message-byte ceiling (chparam MAX_MSG_BYTES) under a legal over-long message,
 * and fault_occ shrinks the tracker capacity (chparam CAP) under two
 * legal outstanding requests -- the checker convicts its own bound.
 *
 * Decode note: the checker keeps its own module-local field decoders
 * (portable subset, no package). This formal-only harness shares its
 * decoders through the txf package, referenced by explicit scope
 * (txf::op5 ...), which yosys read_verilog accepts (an in-module
 * `import pkg::*` does not parse). Both slice identical umi_messages.vh
 * positions.
 ******************************************************************************/

`default_nettype none

// Shared field kernels for the responder and the harness (formal-only).
package txf;
`include "umi_messages.vh"
    function automatic logic [4:0] op5(input logic [31:0] c);
        op5 = c[UMI_OPCODE_MSB:UMI_OPCODE_LSB]; endfunction
    function automatic logic [7:0] opbyte(input logic [31:0] c);
        opbyte = c[7:0]; endfunction
    function automatic logic [2:0] size(input logic [31:0] c);
        size = c[UMI_SIZE_MSB:UMI_SIZE_LSB]; endfunction
    function automatic logic [7:0] len(input logic [31:0] c);
        len = c[UMI_LEN_MSB:UMI_LEN_LSB]; endfunction
    function automatic logic [3:0] qos(input logic [31:0] c);
        qos = c[UMI_QOS_MSB:UMI_QOS_LSB]; endfunction
    function automatic logic [1:0] prot(input logic [31:0] c);
        prot = c[UMI_PROT_MSB:UMI_PROT_LSB]; endfunction
    function automatic logic eom(input logic [31:0] c);
        eom = c[UMI_EOM_BIT]; endfunction
    function automatic logic eof(input logic [31:0] c);
        eof = c[UMI_EOF_BIT]; endfunction
    function automatic logic ex(input logic [31:0] c);
        ex = c[UMI_EX_BIT]; endfunction
    function automatic logic [1:0] user(input logic [31:0] c);
        user = c[UMI_USER_MSB:UMI_USER_LSB]; endfunction
    function automatic logic [4:0] hostid(input logic [31:0] c);
        hostid = c[UMI_HOSTID_MSB:UMI_HOSTID_LSB]; endfunction
    function automatic logic is_req(input logic [31:0] c);
        is_req = c[0] && (opbyte(c) != UMI_INVALID); endfunction
    function automatic logic is_resp(input logic [31:0] c);
        is_resp = !c[0] && (opbyte(c) != UMI_INVALID); endfunction
    function automatic logic is_link(input logic [31:0] c);
        is_link = (opbyte(c) == UMI_REQ_LINK) || (opbyte(c) == UMI_RESP_LINK);
        endfunction
    function automatic logic is_fullbyte(input logic [31:0] c);
        is_fullbyte = (opbyte(c) == UMI_REQ_ERROR) || (opbyte(c) == UMI_REQ_LINK)
                   || (opbyte(c) == UMI_RESP_LINK); endfunction
    function automatic logic expects_resp(input logic [31:0] c);
        expects_resp = is_req(c) && !is_fullbyte(c)
                    && ((op5(c) == UMI_REQ_READ) || (op5(c) == UMI_REQ_WRITE)
                        || (op5(c) == UMI_REQ_ATOMIC)); endfunction
    function automatic logic [4:0] resp_op5(input logic [31:0] c);
        resp_op5 = (op5(c) == UMI_REQ_WRITE) ? UMI_RESP_WRITE[4:0]
                                             : UMI_RESP_READ[4:0]; endfunction
    function automatic logic [15:0] bytes(input logic [31:0] c);
        bytes = (16'd1 << size(c)) * ({8'd0, len(c)} + 16'd1); endfunction
    function automatic logic has_data(input logic [31:0] c);
        has_data = (op5(c) == UMI_REQ_WRITE) || (op5(c) == UMI_REQ_POSTED)
                || (op5(c) == UMI_REQ_ATOMIC) || (op5(c) == UMI_REQ_USER0)
                || (op5(c) == UMI_REQ_FUTURE0) || (op5(c) == UMI_RESP_READ)
                || (op5(c) == UMI_RESP_USER1) || (op5(c) == UMI_RESP_FUTURE1);
        endfunction
    function automatic logic [15:0] bytes_rel(input logic [31:0] c);
        bytes_rel = !has_data(c) ? 16'd0
                  : (op5(c) == UMI_REQ_ATOMIC) ? (16'd1 << size(c))
                  : bytes(c); endfunction
endpackage

// ---------------------------------------------------------------------------
// Perfect in-order responder model. One HOSTID stream, responses in
// request order, reads split word-per-beat. Free choices are anyseq.
// Internal state (occ, q0/q1, got_m, first_m, err_lat, err_pick) is read
// hierarchically by the harness glue.
// ---------------------------------------------------------------------------
module fv_umi_responder #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64
) (
    input  wire          clk,
    input  wire          nreset,
    input  wire          req_valid,
    output wire          req_ready,
    input  wire [CW-1:0] req_cmd,
    input  wire [AW-1:0] req_srcaddr,
    input  wire          resp_ready,
    output wire          resp_valid,
    output wire [CW-1:0] resp_cmd,
    output wire [AW-1:0] resp_dstaddr,
    output wire [DW-1:0] resp_data,
    // observation outputs for the harness glue (same packing as the checker)
    output wire [1:0]     f_occ,
    output wire [15:0]    f_got,
    output wire           f_first,
    output wire [1:0]     f_errlat,
    output wire           f_errpick,
    output wire [AW+43:0] f_q0,
    output wire [AW+43:0] f_q1
);
    // verilator lint_off UNUSEDPARAM
`include "umi_messages.vh"
    // verilator lint_on UNUSEDPARAM
    localparam [1:0] ERR_OK = 2'd0, ERR_EXOK = 2'd1,
                     ERR_DEVERR = 2'd2, ERR_NETERR = 2'd3;

    (* anyseq *) wire [1:0]    f_err_sel;
    (* anyseq *) wire [DW-1:0] f_mem_data;

    wire req_beat  = req_valid && req_ready;
    wire push_req  = req_beat && txf::expects_resp(req_cmd) && txf::eom(req_cmd);
    wire [15:0] push_bytes =
          (txf::op5(req_cmd) == UMI_REQ_WRITE)  ? 16'd0
        : (txf::op5(req_cmd) == UMI_REQ_ATOMIC) ? (16'd1 << txf::size(req_cmd))
        : txf::bytes(req_cmd);

    reg [1:0]    occ;
    reg [4:0]    q0_ropc, q1_ropc;
    reg [2:0]    q0_size, q1_size;
    reg [7:0]    q0_len,  q1_len;
    reg [3:0]    q0_qos,  q1_qos;
    reg [1:0]    q0_prot, q1_prot;
    reg          q0_ex,   q1_ex;
    reg [4:0]    q0_hostid, q1_hostid;
    reg [AW-1:0] q0_da,   q1_da;
    reg [15:0]   q0_bytes, q1_bytes;

    // registered offer (HS-clean: held stable while stalled)
    reg          off_v;
    reg [4:0]    off_ropc;
    reg [2:0]    off_size;
    reg [7:0]    off_len;
    reg [3:0]    off_qos;
    reg [1:0]    off_prot;
    reg [4:0]    off_hostid;
    reg          off_eom;
    reg [1:0]    off_err;
    reg [AW-1:0] off_da;
    reg [DW-1:0] off_data;
    reg [1:0]    err_lat;
    reg          err_pick;
    reg [15:0]   got_m;
    reg          first_m;

    wire [15:0] step_bytes = (16'd1 << q0_size);        // one word per split beat

    wire [1:0] err_choice = (f_err_sel == ERR_EXOK && !q0_ex) ? ERR_OK : f_err_sel;
    wire [1:0] err_now    = err_pick ? err_lat : err_choice;
    wire err_now_is_err   = (err_now == ERR_DEVERR) || (err_now == ERR_NETERR);

    wire accept = off_v && resp_ready;
    wire pop_q  = accept && off_eom;

    assign req_ready = (occ != 2'd2) || pop_q;          // blocks only at CAP

    initial begin
        occ = 2'd0; off_v = 1'b0; err_pick = 1'b0; got_m = 16'd0; first_m = 1'b1;
    end

    always @(posedge clk) begin
        if (!nreset) begin
            occ <= 2'd0; off_v <= 1'b0; err_pick <= 1'b0;
            got_m <= 16'd0; first_m <= 1'b1;
        end else begin
            case ({push_req, pop_q})
                2'b10: begin
                    if (occ == 2'd0) begin
                        q0_ropc <= txf::resp_op5(req_cmd); q0_size <= txf::size(req_cmd);
                        q0_len <= txf::len(req_cmd);       q0_qos <= txf::qos(req_cmd);
                        q0_prot <= txf::prot(req_cmd);     q0_ex <= txf::ex(req_cmd);
                        q0_hostid <= txf::hostid(req_cmd); q0_da <= req_srcaddr;
                        q0_bytes <= push_bytes;
                    end else begin
                        q1_ropc <= txf::resp_op5(req_cmd); q1_size <= txf::size(req_cmd);
                        q1_len <= txf::len(req_cmd);       q1_qos <= txf::qos(req_cmd);
                        q1_prot <= txf::prot(req_cmd);     q1_ex <= txf::ex(req_cmd);
                        q1_hostid <= txf::hostid(req_cmd); q1_da <= req_srcaddr;
                        q1_bytes <= push_bytes;
                    end
                    occ <= occ + 2'd1;
                end
                2'b01: begin
                    q0_ropc <= q1_ropc; q0_size <= q1_size; q0_len <= q1_len;
                    q0_qos <= q1_qos;   q0_prot <= q1_prot; q0_ex <= q1_ex;
                    q0_hostid <= q1_hostid; q0_da <= q1_da; q0_bytes <= q1_bytes;
                    occ <= occ - 2'd1;
                end
                2'b11: begin
                    if (occ == 2'd1) begin
                        q0_ropc <= txf::resp_op5(req_cmd); q0_size <= txf::size(req_cmd);
                        q0_len <= txf::len(req_cmd);       q0_qos <= txf::qos(req_cmd);
                        q0_prot <= txf::prot(req_cmd);     q0_ex <= txf::ex(req_cmd);
                        q0_hostid <= txf::hostid(req_cmd); q0_da <= req_srcaddr;
                        q0_bytes <= push_bytes;
                    end else begin
                        q0_ropc <= q1_ropc; q0_size <= q1_size; q0_len <= q1_len;
                        q0_qos <= q1_qos;   q0_prot <= q1_prot; q0_ex <= q1_ex;
                        q0_hostid <= q1_hostid; q0_da <= q1_da; q0_bytes <= q1_bytes;
                        q1_ropc <= txf::resp_op5(req_cmd); q1_size <= txf::size(req_cmd);
                        q1_len <= txf::len(req_cmd);       q1_qos <= txf::qos(req_cmd);
                        q1_prot <= txf::prot(req_cmd);     q1_ex <= txf::ex(req_cmd);
                        q1_hostid <= txf::hostid(req_cmd); q1_da <= req_srcaddr;
                        q1_bytes <= push_bytes;
                    end
                end
                default: ;
            endcase

            if (accept) begin
                off_v <= 1'b0;
                if (off_eom) begin
                    err_pick <= 1'b0; got_m <= 16'd0; first_m <= 1'b1;
                end else begin
                    got_m <= got_m + txf::bytes_rel(resp_cmd); first_m <= 1'b0;
                end
            end else if (!off_v && occ != 2'd0) begin
                off_v      <= 1'b1;
                off_ropc   <= q0_ropc;
                off_size   <= q0_size;
                off_qos    <= q0_qos;
                off_prot   <= q0_prot;
                off_hostid <= q0_hostid;
                off_err    <= err_now;
                off_data   <= f_mem_data;
                off_len    <= err_now_is_err ? q0_len
                              : ((q0_ropc == UMI_RESP_WRITE[4:0]) ? q0_len : 8'd0);
                off_eom    <= (q0_ropc == UMI_RESP_WRITE[4:0]) || err_now_is_err
                              || ((q0_bytes - got_m) <= step_bytes);
                off_da     <= q0_da + {{(AW-16){1'b0}}, got_m};
                if (!err_pick) begin
                    err_lat <= err_choice; err_pick <= 1'b1;
                end
            end
        end
    end

    assign resp_valid = off_v;
    assign resp_cmd =
          {27'd0, off_ropc}
        | ({29'd0, off_size} << UMI_SIZE_LSB)
        | ({24'd0, off_len}  << UMI_LEN_LSB)
        | ({28'd0, off_qos}  << UMI_QOS_LSB)
        | ({30'd0, off_prot} << UMI_PROT_LSB)
        | ({31'd0, off_eom}  << UMI_EOM_BIT)
        | (32'd1 << UMI_EOF_BIT)
        | ({30'd0, off_err}  << UMI_USER_LSB)
        | ({27'd0, off_hostid} << UMI_HOSTID_LSB);
    assign resp_dstaddr = off_da;
    assign resp_data = err_now_is_err ? {DW{1'b0}} : off_data;

    assign f_occ     = occ;
    assign f_got     = got_m;
    assign f_first   = first_m;
    assign f_errlat  = err_lat;
    assign f_errpick = err_pick;
    assign f_q0 = {q0_bytes, q0_da, q0_hostid, q0_ex, q0_prot, q0_qos,
                   q0_len, q0_size, q0_ropc};
    assign f_q1 = {q1_bytes, q1_da, q1_hostid, q1_ex, q1_prot, q1_qos,
                   q1_len, q1_size, q1_ropc};
endmodule

// ---------------------------------------------------------------------------
// The harness top.
// ---------------------------------------------------------------------------
module fv_umi_txn #(
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 64,
    parameter CAP = 2,
    parameter [31:0] MAX_MSG_BYTES = 32768,
    parameter [7:0]  MAXLEN = 8'd1        // request LEN ceiling (shallow proof)
) (
    input wire clk
);
    // verilator lint_off UNUSEDPARAM
`include "umi_messages.vh"
    // verilator lint_on UNUSEDPARAM
    localparam [1:0] ERR_OK = 2'd0, ERR_EXOK = 2'd1,
                     ERR_DEVERR = 2'd2, ERR_NETERR = 2'd3;

    // Effective request-LEN ceiling: this MUST match the m_len assumption
    // below so the byte-bound glue lemmas (a_glue_e0_bytes/e1_bytes) stay
    // TRUE for the legal environment. FV_BIGMSG (fault_msgbytes) relaxes the
    // ceiling to 7 words; a MAXLEN-only bound would falsely fire at the
    // enqueue and mask the intended TXN_msgbytes conviction.
`ifdef FV_BIGMSG
    localparam [7:0] LEN_CEIL = 8'd7;
`else
    localparam [7:0] LEN_CEIL = MAXLEN;
`endif

    // ---- reset: free, but asserted at time zero (grounds induction) ----
    (* anyseq *) wire nreset;
    reg f_past = 1'b0;
    always @(posedge clk) f_past <= 1'b1;
    always @(*) if (!f_past) assume (!nreset);

    // ---- requester: LEGAL single-beat requests from anyseq fields ----
    (* anyseq *) wire [1:0]    a_opsel;
    (* anyseq *) wire [2:0]    a_size;
    (* anyseq *) wire [7:0]    a_len;
    (* anyseq *) wire [3:0]    a_qos;
    (* anyseq *) wire [1:0]    a_prot;
    (* anyseq *) wire          a_ex;
    (* anyseq *) wire [4:0]    a_hostid;
    (* anyseq *) wire [AW-1:0] a_srcaddr;
    (* anyseq *) wire          req_valid;
    (* anyseq *) wire          resp_ready;

    wire [4:0] req_op5 = (a_opsel == 2'd1) ? UMI_REQ_WRITE[4:0]
                       : (a_opsel == 2'd2) ? UMI_REQ_ATOMIC[4:0]
                       :                     UMI_REQ_READ[4:0];
    wire is_atomic = (req_op5 == UMI_REQ_ATOMIC[4:0]);
    // ATYPE (rides LEN) legal 0..8; other requests take the free LEN
    wire [7:0] len_use = is_atomic ? {5'd0, a_len[2:0]} : a_len;
    wire ex_use = is_atomic ? 1'b0 : a_ex;

    wire [CW-1:0] req_cmd =
          {27'd0, req_op5}
        | ({29'd0, a_size}   << UMI_SIZE_LSB)
        | ({24'd0, len_use}  << UMI_LEN_LSB)
        | ({28'd0, a_qos}    << UMI_QOS_LSB)
        | ({30'd0, a_prot}   << UMI_PROT_LSB)
        | (32'd1 << UMI_EOM_BIT)
        | (32'd1 << UMI_EOF_BIT)
        | ({31'd0, ex_use}   << UMI_EX_BIT)
        | ({27'd0, a_hostid} << UMI_HOSTID_LSB);

    // ---- responder ----
    wire          req_ready;
    wire          rsp_valid;
    wire [CW-1:0] rsp_cmd;
    wire [AW-1:0] rsp_dstaddr;
    wire [DW-1:0] rsp_data;
    // responder shadow state (glue)
    wire [1:0]     rsp_occ;
    wire [15:0]    rsp_got;
    wire           rsp_first;
    wire [1:0]     rsp_errlat;
    wire           rsp_errpick;
    wire [AW+43:0] rq0, rq1;

    fv_umi_responder #(.CW(CW), .AW(AW), .DW(DW)) u_rsp (
        .clk(clk), .nreset(nreset),
        .req_valid(req_valid), .req_ready(req_ready),
        .req_cmd(req_cmd), .req_srcaddr(a_srcaddr),
        .resp_ready(resp_ready),
        .resp_valid(rsp_valid), .resp_cmd(rsp_cmd),
        .resp_dstaddr(rsp_dstaddr), .resp_data(rsp_data),
        .f_occ(rsp_occ), .f_got(rsp_got), .f_first(rsp_first),
        .f_errlat(rsp_errlat), .f_errpick(rsp_errpick),
        .f_q0(rq0), .f_q1(rq1));

    // head field accessors on the responder's packed queue entries
    wire [4:0]    rq0_ropc = rq0[4:0];
    wire [2:0]    rq0_size = rq0[7:5];
    wire [7:0]    rq0_len  = rq0[15:8];
    wire          rq0_ex   = rq0[22];
    wire [AW-1:0] rq0_da   = rq0[AW+27:28];
    wire [15:0]   rq0_bytes = rq0[AW+43:AW+28];

    // ---- fault injection: corrupt ONLY the checker's response view ----
    // The responder outputs (rsp_*) stay clean, so every glue lemma holds
    // and each fault trips its intended checker assertion. A given fault
    // may also falsify several related rules on the same beat, and which
    // label the solver reports can vary; fv_umi_txn.sby tabulates the
    // intended label and the extra/alternate labels for each fault.
    localparam [CW-1:0] SPUR_RESP = {27'd0, UMI_RESP_READ[4:0]}
                                  | (32'd1 << UMI_EOM_BIT)
                                  | (32'd1 << UMI_EOF_BIT);   // idle-orphan beat
    (* anyseq *) wire fault_go;

    wire          c_valid;
    wire [CW-1:0] c_cmd;
    wire [AW-1:0] c_dstaddr;
    wire [DW-1:0] c_data;

`ifdef FV_FAULT_WRONGDA
    // first-beat DA off by 8 (every beat, but the first-beat law fires first)
    assign c_valid   = rsp_valid;
    assign c_cmd     = rsp_cmd;
    assign c_dstaddr = rsp_dstaddr + 64'd8;
    assign c_data    = rsp_data;
`elsif FV_FAULT_SIZE
    // mid-message SIZE mutation: flip SIZE only on a continuation beat
    assign c_valid   = rsp_valid;
    assign c_cmd     = rsp_cmd
                       ^ ((rsp_valid && !rsp_first) ? (32'd1 << UMI_SIZE_LSB) : 32'd0);
    assign c_dstaddr = rsp_dstaddr;
    assign c_data    = rsp_data;
`elsif FV_FAULT_EOM_EARLY
    // EOM asserted on a split first beat that has more to come
    assign c_valid   = rsp_valid;
    assign c_cmd     = rsp_cmd
                       | ((rsp_valid && rsp_first && !rsp_cmd[UMI_EOM_BIT])
                          ? (32'd1 << UMI_EOM_BIT) : 32'd0);
    assign c_dstaddr = rsp_dstaddr;
    assign c_data    = rsp_data;
`elsif FV_FAULT_EOM_MISSING
    // EOM never reaches the checker: the closing beat looks unterminated
    assign c_valid   = rsp_valid;
    assign c_cmd     = rsp_cmd & ~(32'd1 << UMI_EOM_BIT);
    assign c_dstaddr = rsp_dstaddr;
    assign c_data    = rsp_data;
`elsif FV_FAULT_ERR_LEN
    // error response with a mangled LEN (!= the request LEN it must copy)
    assign c_valid   = rsp_valid;
    assign c_cmd     = rsp_cmd
                       ^ (((txf::user(rsp_cmd) == ERR_DEVERR)
                           || (txf::user(rsp_cmd) == ERR_NETERR))
                          ? (32'd1 << UMI_LEN_LSB) : 32'd0);
    assign c_dstaddr = rsp_dstaddr;
    assign c_data    = rsp_data;
`elsif FV_FAULT_ORPHAN
    // a spurious response beat while the tracker is empty
    wire spur = fault_go && (rsp_occ == 2'd0) && !rsp_valid;
    assign c_valid   = rsp_valid | spur;
    assign c_cmd     = spur ? SPUR_RESP : rsp_cmd;
    assign c_dstaddr = rsp_dstaddr;
    assign c_data    = spur ? {DW{1'b0}} : rsp_data;
`else
    // clean: the checker sees exactly what the responder emits
    assign c_valid   = rsp_valid;
    assign c_cmd     = rsp_cmd;
    assign c_dstaddr = rsp_dstaddr;
    assign c_data    = rsp_data;
`endif

    // ---- the checker under test (ASSERT face) ----
    wire [1:0]     chk_occ;
    wire [15:0]    chk_got;
    wire           chk_first;
    wire [AW-1:0]  chk_next_da;
    wire [CW-1:0]  chk_last;
    wire [AW+43:0] chk_e0, chk_e1;

    umi_txn_checker #(
        .CW(CW), .AW(AW), .DW(DW),
        .CAP(CAP), .MAX_MSG_BYTES(MAX_MSG_BYTES), .ASSUME(0)
    ) u_chk (
        .clk(clk), .nreset(nreset),
        .req_valid(req_valid), .req_ready(req_ready), .req_cmd(req_cmd),
        .req_dstaddr({AW{1'b0}}), .req_srcaddr(a_srcaddr), .req_data({DW{1'b0}}),
        .resp_valid(c_valid), .resp_ready(resp_ready), .resp_cmd(c_cmd),
        .resp_dstaddr(c_dstaddr), .resp_srcaddr({AW{1'b0}}), .resp_data(c_data),
        .f_occ(chk_occ), .f_got(chk_got), .f_first(chk_first),
        .f_next_da(chk_next_da), .f_last_cmd(chk_last),
        .f_e0(chk_e0), .f_e1(chk_e1));

    // ---- environment discipline + witnesses ----
    reg seen_reset = 1'b0;
    always @(posedge clk) if (!nreset) seen_reset <= 1'b1;
    reg guard = 1'b0;
    always @(posedge clk) if (!nreset) guard <= 1'b0; else guard <= seen_reset;

    always @(posedge clk) begin
        // shallow proof: bound request length (relaxed by FV_BIGMSG)
`ifdef FV_BIGMSG
        m_len : assume (!req_valid || len_use <= 8'd7);
`else
        m_len : assume (!req_valid || len_use <= MAXLEN);
`endif
    end

    // ---- glue lemmas: the checker's tracker equals the responder's queue
    // ---- (direct equality: NO INTERLEAVE), and the live beat equals the
    // ---- responder head. Asserted, not assumed -- the induction scaffold.
    wire [15:0] rsp_beat_bytes = txf::bytes_rel(rsp_cmd);
    // Gate the glue lemmas on nreset -- the SAME condition under which the
    // checker fires its own TXN_* assertions -- not on the 2-cycle `guard`.
    // The checker rules constrain an INPUT response stream, so they can never
    // be self-inductive: the strengthening glue must be part of the induction
    // hypothesis in every cycle the checker asserts. Gating glue on `guard`
    // let k-induction pick an unreachable start state (seen_reset=0, guard=0,
    // nreset=1 forever) in which the glue was disabled while the checker rules
    // still fired -- an unclosable step. All glue lemmas provably hold from
    // the first post-reset cycle (occ/got/first are reset-synced and the
    // shadow-entry lemmas are vacuous while occ==0), so nreset gating is
    // sound; the basecase confirms it.
    always @(posedge clk) begin
        if (nreset) begin
            a_glue_occ   : assert (chk_occ == rsp_occ);
            a_glue_first : assert (chk_first == rsp_first);
            a_glue_got   : assert (chk_got == rsp_got);
            if (rsp_occ != 2'd0)
                a_glue_e0 : assert (chk_e0 == rq0);
            if (rsp_occ == 2'd2)
                a_glue_e1 : assert (chk_e1 == rq1);
            // Every occupied responder queue entry carries a RESPONSE opcode
            // (RESP_READ/RESP_WRITE): the queue is only ever loaded from
            // txf::resp_op5. Without this, an induction start state can seat
            // an odd (request-shaped) opcode in the head, so the beat the
            // checker sees fails f_is_resp -- the checker does not pop while
            // the responder does, desyncing chk_occ/chk_e0 from the model.
            if (rsp_occ != 2'd0)
                a_glue_rq0_ropc : assert (rq0_ropc == UMI_RESP_READ[4:0]
                                          || rq0_ropc == UMI_RESP_WRITE[4:0]);
            if (rsp_occ == 2'd2)
                a_glue_rq1_ropc : assert (rq1[4:0] == UMI_RESP_READ[4:0]
                                          || rq1[4:0] == UMI_RESP_WRITE[4:0]);
            // A write-ack head carries zero data bytes (push_bytes==0 for a
            // WRITE request). Without this an induction start state can seat a
            // nonzero byte count on a RESP_WRITE head; the responder then
            // offers it as a non-EOM (split) beat that advances the message
            // (first->0) while adding bytes_rel==0 -- an impossible open
            // message with got==0, which breaks a_glue_mid_got/a_glue_next_da.
            if (rsp_occ != 2'd0 && rq0_ropc == UMI_RESP_WRITE[4:0])
                a_glue_rq0_wr0 : assert (rq0_bytes == 16'd0);
            if (rsp_occ == 2'd2 && rq1[4:0] == UMI_RESP_WRITE[4:0])
                a_glue_rq1_wr0 : assert (rq1[AW+43:AW+28] == 16'd0);
            // A read/atomic head expects a whole, positive number of words:
            // rq0_bytes = (2^size)*(len+1) (read) or 2^size (atomic), both
            // positive multiples of the word step 2^size. The accumulator
            // advances exactly one word (2^size) per split beat, so it too
            // stays a multiple of the step. Together they keep the responder's
            // word-per-beat split landing EXACTLY on rq0_bytes: an unaligned
            // byte count would over/undershoot the closing beat and break
            // a_glue_off_ok (got + step <= rq0_bytes, EOM iff exactly equal).
            if (rsp_occ != 2'd0 && rq0_ropc == UMI_RESP_READ[4:0])
                a_glue_rq0_words : assert (rq0_bytes >= (16'd1 << rq0_size)
                    && ((rq0_bytes >> rq0_size) << rq0_size) == rq0_bytes);
            if (rsp_occ == 2'd2 && rq1[4:0] == UMI_RESP_READ[4:0])
                a_glue_rq1_words : assert (rq1[AW+43:AW+28] >= (16'd1 << rq1[7:5])
                    && ((rq1[AW+43:AW+28] >> rq1[7:5]) << rq1[7:5])
                       == rq1[AW+43:AW+28]);
            if (rsp_occ != 2'd0)
                a_glue_got_align : assert (((rsp_got >> rq0_size) << rq0_size)
                                           == rsp_got);

            // responder-internal invariants (make the head well-formed)
            a_glue_rsp_occ  : assert (rsp_occ <= 2'd2);
            a_glue_rsp_base : assert (!rsp_first || rsp_got == 16'd0);
            a_glue_rsp_idle : assert ((rsp_occ != 2'd0) || rsp_first);
            if (!rsp_first) begin
                a_glue_mid_occ  : assert (rsp_occ != 2'd0);
                a_glue_mid_pick : assert (rsp_errpick);
                a_glue_mid_got  : assert (rsp_got != 16'd0 && rsp_got < rq0_bytes);
            end
            if (rsp_errpick) begin
                a_glue_lat_occ  : assert (rsp_occ != 2'd0);
                a_glue_lat_exok : assert ((rsp_errlat != ERR_EXOK) || rq0_ex);
                if ((rsp_errlat == ERR_DEVERR) || (rsp_errlat == ERR_NETERR))
                    a_glue_lat_first : assert (rsp_first);
            end
            // the head byte total never exceeds LEN_CEIL+1 words at push time
            // (env LEN_CEIL keeps split messages short -- LEN<=1 -> <=2 words;
            // LEN<=7 -> <=8 words under FV_BIGMSG). LEN_CEIL tracks m_len so
            // this bound is TRUE for the legal environment in every task.
            if (rsp_occ != 2'd0)
                a_glue_e0_bytes : assert (rq0_bytes
                    <= (16'd1 << rq0_size) * ({8'd0, LEN_CEIL} + 16'd1));
            if (rsp_occ == 2'd2)
                a_glue_e1_bytes : assert (rq1[AW+43:AW+28]
                    <= (16'd1 << rq1[7:5]) * ({8'd0, LEN_CEIL} + 16'd1));

            // continuation-address / framing carry (checker next_da,last_cmd)
            if (!chk_first) begin
                a_glue_next_da : assert (chk_next_da
                                         == rq0_da + {{(AW-16){1'b0}}, rsp_got});
                a_glue_last_err : assert (txf::user(chk_last) == rsp_errlat);
                a_glue_last_eof : assert (txf::eof(chk_last));
            end

            // offer coherence: the live response beat IS the responder head
            if (rsp_valid) begin
                a_glue_off_occ  : assert (rsp_occ != 2'd0);
                a_glue_off_kind : assert (txf::op5(rsp_cmd) == rq0_ropc);
                a_glue_off_size : assert (txf::size(rsp_cmd) == rq0_size);
                a_glue_off_qos  : assert (txf::qos(rsp_cmd) == rq0[19:16]);
                a_glue_off_prot : assert (txf::prot(rsp_cmd) == rq0[21:20]);
                a_glue_off_hid  : assert (txf::hostid(rsp_cmd) == rq0[27:23]);
                a_glue_off_eof  : assert (txf::eof(rsp_cmd));
                a_glue_off_lat  : assert (rsp_errpick && txf::user(rsp_cmd) == rsp_errlat);
                a_glue_off_exok : assert ((txf::user(rsp_cmd) != ERR_EXOK) || rq0_ex);
                if (rsp_first)
                    a_glue_off_da  : assert (rsp_dstaddr == rq0_da);
                else
                    a_glue_off_da2 : assert (rsp_dstaddr
                                             == rq0_da + {{(AW-16){1'b0}}, rsp_got});
                if ((txf::user(rsp_cmd) == ERR_DEVERR) || (txf::user(rsp_cmd) == ERR_NETERR))
                    a_glue_off_err : assert (txf::len(rsp_cmd) == rq0_len
                                             && rsp_first && txf::eom(rsp_cmd));
                else
                    a_glue_off_ok : assert (({16'd0, rsp_got} + {16'd0, rsp_beat_bytes})
                                            <= {16'd0, rq0_bytes}
                                            && txf::eom(rsp_cmd) == (({16'd0, rsp_got}
                                               + {16'd0, rsp_beat_bytes})
                                               == {16'd0, rq0_bytes}));
            end
        end
    end

    // ---- witnesses (formal-only): the assumed language is alive ----
`ifdef FORMAL
    always @(posedge clk) begin
        if (guard) begin
            c_journey  : cover (c_valid && resp_ready && txf::eom(c_cmd)
                                && txf::op5(c_cmd) == UMI_RESP_READ[4:0]);
            c_multibeat: cover (c_valid && resp_ready && !txf::eom(c_cmd));
            c_close    : cover (c_valid && resp_ready && txf::eom(c_cmd) && !chk_first);
            c_wr_ack   : cover (c_valid && resp_ready
                                && txf::op5(c_cmd) == UMI_RESP_WRITE[4:0]);
            c_err      : cover (c_valid && resp_ready && txf::user(c_cmd) == ERR_DEVERR);
            c_backtoback : cover (c_valid && resp_ready && rsp_occ == 2'd2);
        end
    end
`endif

endmodule

`default_nettype wire
