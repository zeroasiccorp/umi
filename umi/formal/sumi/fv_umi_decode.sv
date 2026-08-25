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
 * - Proves umi_decode classifies a command word the way README.md
 *   section 3.2.3 and umi_messages.vh define it, and that the sixteen
 *   class outputs it drives are mutually exclusive and complete.
 *
 * FIVE-BIT LAWS OVER FOUR-BIT COMPARES. umi_decode compares four bits
 * for every structured class (umi_decode.v:75-91, e.g. command[3:0] ==
 * UMI_REQ_READ[3:0]) while the opcodes it compares against are five-bit
 * localparams. This harness asserts the five-bit equality instead:
 *
 *     DEC_read : cmd_read == (command[4:0] == UMI_REQ_READ)
 *
 * The two agree only because every legal structured opcode is below
 * 5'h10, so bit 4 is zero across the legal set and the shorter compare
 * decides it. The assumption that makes them agree is stated here and
 * withdrawn in the hazard row, where the covers show what the shorter
 * compare admits without it.
 *
 * STRUCTURAL LAWS, held for EVERY command word, legal or not:
 *   DEC_class_onehot0   at most one of the sixteen class outputs is
 *                       high. The thirteen structured classes take
 *                       distinct nibbles, and the three full-byte
 *                       classes (REQ_ERROR 0x0F, REQ_LINK 0x2F,
 *                       RESP_LINK 0x0E) land on nibbles 0xF and 0xE
 *                       that no structured class claims.
 *   DEC_req_implies     every request class implies cmd_request
 *   DEC_resp_implies    every response class implies cmd_response
 *   DEC_reqresp_excl    cmd_request and cmd_response never agree
 *   DEC_invalid_quiet   INVALID drives no class at all
 *   DEC_atomic_onehot0  at most one atomic sub-operation
 *   DEC_atomic_implies  every sub-operation implies cmd_atomic
 *
 * LEGAL-SET LAWS (the assumption above): the thirteen five-bit
 * equalities, plus DEC_legal_complete -- on a legal non-INVALID word
 * exactly one class fires, so the decoder has no holes.
 *
 * ATYPE OUTSIDE ADD..SWAP. Only 0x00-0x08 name an operation
 * (umi_messages.vh:84-92), so a REQ_ATOMIC carrying ATYPE >= 9 sets
 * cmd_atomic with no sub-operation selected. DEC_atomic_hole asserts
 * that, c_dec_atomic_hole witnesses it is reachable. What a consumer
 * does with an atomic naming no operation is the consumer's contract;
 * no property here speaks to it.
 *
 * THE HAZARD ROW (decode:hazard, FV_DEC_ANYOPCODE). The legal-opcode
 * assumption is dropped and the five-bit laws go with it. The
 * structural laws still hold, and three covers pin the aliasing:
 *   c_dec_alias_read    an opcode that is not REQ_READ decoding as a
 *                       read (5'h11 is the smallest)
 *   c_dec_alias_atomic  an opcode that is not REQ_ATOMIC decoding as an
 *                       atomic (5'h19)
 *   c_dec_alias_quiet   an illegal opcode decoding as no class at all
 * The aliasing is behaviour of the shipped RTL, not a fault this
 * harness injects.
 *
 * Purely combinational, so induction closes immediately; the value of
 * prove mode is the quantifier over all 2^CW command words.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   decode:prove          all laws over the legal set, unbounded
 *   decode:cover          witnesses: expect all reached
 *   decode:hazard         legal assumption dropped, aliasing witnessed
 *   decode:fault_read     must FAIL, DEC_read
 *   decode:fault_onehot   must FAIL, DEC_class_onehot0
 *   decode:fault_req      must FAIL, DEC_req_implies
 *   decode:fault_atomic   must FAIL, DEC_atomic_onehot0
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_decode #(
    parameter CW = 32
) (
    input wire clk
);

`include "umi_messages.vh"

    // ----------------------------------------------------------------
    // one free command word
    // ----------------------------------------------------------------
    (* anyseq *) wire [CW-1:0] command;

    wire [4:0] opcode5 = command[4:0];
    wire [7:0] opcode8 = command[7:0];
    wire [7:0] atype   = command[15:8];

    // the thirteen structured opcodes (requests odd, responses even)
    wire f_structured =
        (opcode5 == UMI_REQ_READ)     | (opcode5 == UMI_REQ_WRITE)    |
        (opcode5 == UMI_REQ_POSTED)   | (opcode5 == UMI_REQ_RDMA)     |
        (opcode5 == UMI_REQ_ATOMIC)   | (opcode5 == UMI_REQ_USER0)    |
        (opcode5 == UMI_REQ_FUTURE0)  |
        (opcode5 == UMI_RESP_READ)    | (opcode5 == UMI_RESP_WRITE)   |
        (opcode5 == UMI_RESP_USER0)   | (opcode5 == UMI_RESP_USER1)   |
        (opcode5 == UMI_RESP_FUTURE0) | (opcode5 == UMI_RESP_FUTURE1);

    // the three that redefine the whole byte
    wire f_fullbyte =
        (opcode8 == UMI_REQ_ERROR) | (opcode8 == UMI_REQ_LINK) |
        (opcode8 == UMI_RESP_LINK);

    wire f_invalid = (opcode8 == UMI_INVALID);

    // structured opcodes carry SIZE in command[7:5], so only the low
    // five bits are pinned here; the full-byte three pin all eight
    wire f_legal = f_structured | f_fullbyte | f_invalid;

`ifndef FV_DEC_ANYOPCODE
    always @(*) begin
        legal_opcode : assume (f_legal);
    end
`endif

    // ----------------------------------------------------------------
    // the decoder
    // ----------------------------------------------------------------
    wire cmd_invalid;
    wire cmd_request, cmd_response;
    wire cmd_read, cmd_write, cmd_write_posted, cmd_rdma, cmd_atomic;
    wire cmd_user0, cmd_future0, cmd_error, cmd_link;
    wire cmd_read_resp, cmd_write_resp, cmd_user0_resp, cmd_user1_resp;
    wire cmd_future0_resp, cmd_future1_resp, cmd_link_resp;
    wire cmd_atomic_add, cmd_atomic_and, cmd_atomic_or, cmd_atomic_xor;
    wire cmd_atomic_max, cmd_atomic_min, cmd_atomic_maxu, cmd_atomic_minu;
    wire cmd_atomic_swap;

    umi_decode #(.CW (CW)) dut (
        .command          (command),
        .cmd_invalid      (cmd_invalid),
        .cmd_request      (cmd_request),
        .cmd_response     (cmd_response),
        .cmd_read         (cmd_read),
        .cmd_write        (cmd_write),
        .cmd_write_posted (cmd_write_posted),
        .cmd_rdma         (cmd_rdma),
        .cmd_atomic       (cmd_atomic),
        .cmd_user0        (cmd_user0),
        .cmd_future0      (cmd_future0),
        .cmd_error        (cmd_error),
        .cmd_link         (cmd_link),
        .cmd_read_resp    (cmd_read_resp),
        .cmd_write_resp   (cmd_write_resp),
        .cmd_user0_resp   (cmd_user0_resp),
        .cmd_user1_resp   (cmd_user1_resp),
        .cmd_future0_resp (cmd_future0_resp),
        .cmd_future1_resp (cmd_future1_resp),
        .cmd_link_resp    (cmd_link_resp),
        .cmd_atomic_add   (cmd_atomic_add),
        .cmd_atomic_and   (cmd_atomic_and),
        .cmd_atomic_or    (cmd_atomic_or),
        .cmd_atomic_xor   (cmd_atomic_xor),
        .cmd_atomic_max   (cmd_atomic_max),
        .cmd_atomic_min   (cmd_atomic_min),
        .cmd_atomic_maxu  (cmd_atomic_maxu),
        .cmd_atomic_minu  (cmd_atomic_minu),
        .cmd_atomic_swap  (cmd_atomic_swap)
    );

    // ----------------------------------------------------------------
    // observed outputs: the faults corrupt what the laws see, never the
    // DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_READ
    wire obs_read = cmd_read ^ f_glitch;
`else
    wire obs_read = cmd_read;
`endif

`ifdef FV_FAULT_ONEHOT
    // a second class asserted alongside the first
    wire obs_write = cmd_write | (cmd_read & f_glitch);
`else
    wire obs_write = cmd_write;
`endif

`ifdef FV_FAULT_REQ
    // the request flag withdrawn under a request class
    wire obs_request = cmd_request & ~f_glitch;
`else
    wire obs_request = cmd_request;
`endif

`ifdef FV_FAULT_ATOMIC
    // two sub-operations selected at once
    wire obs_atomic_or = cmd_atomic_or | (cmd_atomic_add & f_glitch);
`else
    wire obs_atomic_or = cmd_atomic_or;
`endif

    // ----------------------------------------------------------------
    // class vectors
    // ----------------------------------------------------------------
    wire [15:0] class_vec = {
        obs_read, obs_write, cmd_write_posted, cmd_rdma,
        cmd_atomic, cmd_user0, cmd_future0, cmd_error,
        cmd_link, cmd_read_resp, cmd_write_resp, cmd_user0_resp,
        cmd_user1_resp, cmd_future0_resp, cmd_future1_resp, cmd_link_resp
    };

    wire [8:0] atomic_vec = {
        cmd_atomic_add, cmd_atomic_and, obs_atomic_or, cmd_atomic_xor,
        cmd_atomic_max, cmd_atomic_min, cmd_atomic_maxu, cmd_atomic_minu,
        cmd_atomic_swap
    };

    wire any_request = obs_read | obs_write | cmd_write_posted | cmd_rdma
                     | cmd_atomic | cmd_user0 | cmd_future0 | cmd_error
                     | cmd_link;

    wire any_response = cmd_read_resp | cmd_write_resp | cmd_user0_resp
                      | cmd_user1_resp | cmd_future0_resp | cmd_future1_resp
                      | cmd_link_resp;

    // ----------------------------------------------------------------
    // structural laws: every command word, legal or not
    // ----------------------------------------------------------------
    always @(*) begin
        // at most one class: x & (x-1) clears the lowest set bit, so a
        // zero result means at most one bit was set
        DEC_class_onehot0 : assert ((class_vec & (class_vec - 16'd1))
                                    == 16'd0);
        DEC_atomic_onehot0 : assert ((atomic_vec & (atomic_vec - 9'd1))
                                     == 9'd0);
        DEC_req_implies : assert (!any_request  || obs_request);
        DEC_resp_implies : assert (!any_response || cmd_response);
        DEC_reqresp_excl : assert (!(obs_request & cmd_response));
        DEC_invalid_quiet : assert (!cmd_invalid || (class_vec == 16'd0));
        DEC_atomic_implies : assert ((atomic_vec == 9'd0) || cmd_atomic);
        // an atomic naming an operation outside ADD..SWAP selects none
        DEC_atomic_hole : assert (!cmd_atomic || (atype <= 8'h08)
                                  || (atomic_vec == 9'd0));
    end

    // ----------------------------------------------------------------
    // legal-set laws: the full five-bit opcode equality the four-bit
    // compares are standing in for
    // ----------------------------------------------------------------
`ifndef FV_DEC_ANYOPCODE
    always @(*) begin
        DEC_read : assert (obs_read == (opcode5 == UMI_REQ_READ));
        DEC_write : assert (obs_write == (opcode5 == UMI_REQ_WRITE));
        DEC_posted : assert (cmd_write_posted == (opcode5 == UMI_REQ_POSTED));
        DEC_rdma : assert (cmd_rdma == (opcode5 == UMI_REQ_RDMA));
        DEC_atomic : assert (cmd_atomic == (opcode5 == UMI_REQ_ATOMIC));
        DEC_user0 : assert (cmd_user0 == (opcode5 == UMI_REQ_USER0));
        DEC_future0 : assert (cmd_future0 == (opcode5 == UMI_REQ_FUTURE0));
        DEC_read_resp : assert (cmd_read_resp == (opcode5 == UMI_RESP_READ));
        DEC_write_resp : assert (cmd_write_resp == (opcode5 == UMI_RESP_WRITE));
        DEC_user0_resp : assert (cmd_user0_resp == (opcode5 == UMI_RESP_USER0));
        DEC_user1_resp : assert (cmd_user1_resp == (opcode5 == UMI_RESP_USER1));
        DEC_future0_resp : assert (cmd_future0_resp
                                   == (opcode5 == UMI_RESP_FUTURE0));
        DEC_future1_resp : assert (cmd_future1_resp
                                   == (opcode5 == UMI_RESP_FUTURE1));
        // no holes: a legal word that is not INVALID lands on exactly
        // one class
        DEC_legal_complete : assert (cmd_invalid || (class_vec != 16'd0));
    end
`endif

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(*) begin
        c_dec_read : cover (cmd_read);
        c_dec_write_resp : cover (cmd_write_resp);
        c_dec_link : cover (cmd_link);
        c_dec_error : cover (cmd_error);
        c_dec_invalid : cover (cmd_invalid);
        c_dec_atomic_swap : cover (cmd_atomic_swap);
        // a REQ_ATOMIC naming no operation: reachable, and nothing
        // downstream of the decoder is told which way to resolve it
        c_dec_atomic_hole : cover (cmd_atomic & (atomic_vec == 9'd0));
    end

 `ifdef FV_DEC_ANYOPCODE
    // the aliasing the four-bit compares admit once the legal-opcode
    // assumption is withdrawn
    always @(*) begin
        c_dec_alias_read : cover (cmd_read & (opcode5 != UMI_REQ_READ));
        c_dec_alias_atomic : cover (cmd_atomic & (opcode5 != UMI_REQ_ATOMIC));
        c_dec_alias_quiet : cover (!f_legal & (class_vec == 16'd0)
                                   & !cmd_invalid);
    end
 `endif
`endif

endmodule

`default_nettype wire
