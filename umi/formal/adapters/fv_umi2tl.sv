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
 * - Proves umi2tl issues legal TileLink-UL requests on the A channel,
 *   and shows the one shape it does not.
 *
 * THE OTHER HALF OF STEP 40'S LAW SET. fv_tl2umi asserts the TL-UL
 * rules on D, where that block is the source. umi2tl is the manager, so
 * it owns A, and the obligations that fall on it are the request-side
 * ones a TL-UL protocol checker enforces:
 *
 *   asserted (this block is the source of A)
 *     TL_a_hold / TL_a_stable   the irrevocable rule on A
 *     TL_a_opcode_legal         Get, PutFullData or PutPartialData
 *     TL_a_align                a_address aligned to a_size
 *     TL_a_mask_size            countones(a_mask) == 2^a_size --
 *                               behind `FV_TLM_ASSERT_MASK, because the
 *                               block does not satisfy it; see below
 *
 *   assumed (the subordinate is the source of D)
 *     m_tl_d_hold / m_tl_d_stable   the same irrevocable rule on D
 *     m_tl_d_owed                   it answers only what it was asked
 *
 * TL_a_mask_size is the one that matters. SIZE and MASK are not
 * independent in TileLink: a_size names a power-of-two byte count and
 * a_mask must have exactly that many lanes enabled. A request whose
 * size says one thing and whose mask says another is not a legal
 * TL-UL request, and a subordinate is entitled to do anything with it.
 *
 * WHAT IS PROVEN ON THE UMI SIDE:
 *   RULE2_valid_hold / RULE3_*_stable   the UMI response channel this
 *                     block drives, with the request channel
 *                     constrained legal by the same checker
 *
 * NOT PROVEN HERE. The data shift and the address composition are
 * single assigns off registered request fields. The multi-beat path
 * through umi_fifoflex is byte accounting and is not attempted; the
 * harness holds requests to one bus word.
 *
 * SCOPE. Bounded. One clock. IDW=128 and ODW=64, the configuration the
 * block header records as the tested one.
 *
 * ROWS (tests/test_formal_sc.py):
 *   tlm:bmc             the TileLink and UMI laws, bounded
 *   tlm:cover           witnesses: expect all reached
 *   tlm:fault_a         must FAIL, TL_a_hold
 *   tlm:fault_stable    must FAIL, TL_a_stable
 *   tlm:fault_mask      must FAIL, TL_a_mask_size. Nothing injected --
 *                       the req_bytes == 1 arm of the size/mask table
 *                       (umi2tl.v:196-200) sets size 1 beside a
 *                       one-lane mask
 *
 ******************************************************************************/

`default_nettype none

module fv_umi2tl #(
    parameter CW  = 32,
    parameter AW  = 64,
    parameter IDW = 128,
    parameter ODW = 64
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
    (* anyseq *) wire           a_ready;
    (* anyseq *) wire           d_valid;
    (* anyseq *) wire [2:0]     d_opcode, d_size;
    (* anyseq *) wire [1:0]     d_param;
    (* anyseq *) wire [3:0]     d_source;
    (* anyseq *) wire           d_sink, d_denied, d_corrupt;
    (* anyseq *) wire [ODW-1:0] d_data;

    (* anyseq *) wire           req_valid;
    (* anyseq *) wire [CW-1:0]  req_cmd;
    (* anyseq *) wire [AW-1:0]  req_dstaddr;
    (* anyseq *) wire [AW-1:0]  req_srcaddr;
    (* anyseq *) wire [IDW-1:0] req_data;
    (* anyseq *) wire           resp_ready;

    wire           a_valid;
    wire [2:0]     a_opcode, a_param, a_size;
    wire [3:0]     a_source;
    wire [55:0]    a_address;
    wire [7:0]     a_mask;
    wire [ODW-1:0] a_data;
    wire           a_corrupt, d_ready;

    wire           req_ready;
    wire           resp_valid;
    wire [CW-1:0]  resp_cmd;
    wire [AW-1:0]  resp_dstaddr;
    wire [AW-1:0]  resp_srcaddr;
    wire [IDW-1:0] resp_data;

    umi2tl #(
        .CW (CW), .AW (AW), .IDW (IDW), .ODW (ODW)
    ) dut (
        .clk (clk), .nreset (nreset),
        .tl_a_ready (a_ready), .tl_a_valid (a_valid),
        .tl_a_opcode (a_opcode), .tl_a_param (a_param), .tl_a_size (a_size),
        .tl_a_source (a_source), .tl_a_address (a_address),
        .tl_a_mask (a_mask), .tl_a_data (a_data), .tl_a_corrupt (a_corrupt),
        .tl_d_ready (d_ready), .tl_d_valid (d_valid),
        .tl_d_opcode (d_opcode), .tl_d_param (d_param), .tl_d_size (d_size),
        .tl_d_source (d_source), .tl_d_sink (d_sink), .tl_d_denied (d_denied),
        .tl_d_data (d_data), .tl_d_corrupt (d_corrupt),
        .udev_req_valid (req_valid), .udev_req_cmd (req_cmd),
        .udev_req_dstaddr (req_dstaddr), .udev_req_srcaddr (req_srcaddr),
        .udev_req_data (req_data), .udev_req_ready (req_ready),
        .udev_resp_valid (resp_valid), .udev_resp_cmd (resp_cmd),
        .udev_resp_dstaddr (resp_dstaddr), .udev_resp_srcaddr (resp_srcaddr),
        .udev_resp_data (resp_data), .udev_resp_ready (resp_ready)
    );

    // ----------------------------------------------------------------
    // the UMI request face, constrained legal by the same rule list the
    // response face is judged by
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (IDW), .ASSUME (1)
    ) env_req (
        .clk (clk), .nreset (nreset),
        .valid (req_valid), .ready (req_ready),
        .cmd (req_cmd), .dstaddr (req_dstaddr),
        .srcaddr (req_srcaddr), .data (req_data)
    );

    wire [2:0] req_size = req_cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    wire [7:0] req_len  = req_cmd[UMI_LEN_MSB:UMI_LEN_LSB];
    wire [4:0] req_op   = req_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

    always @(*) begin
        // one bus word at most, so the fifoflex split arm is out of
        // scope and its byte accounting is not implied here
        m_tlm_size : assume ((32'd1 << req_size) <= (ODW / 8));
        m_tlm_len  : assume (req_len == 8'd0);
        m_tlm_op   : assume ((req_op == UMI_REQ_READ)
                             || (req_op == UMI_REQ_WRITE)
                             || (req_op == UMI_REQ_POSTED));
    end

    // ----------------------------------------------------------------
    // faults corrupt what the laws see, never the DUT
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_A
    wire obs_a_valid = a_valid & ~f_glitch;       // an offer withdrawn
`else
    wire obs_a_valid = a_valid;
`endif

    wire [55:0] obs_a_address = a_address;

`ifdef FV_FAULT_STABLE
    // a_data, not the address: corrupting the address breaks TL_a_align
    // before it can reach the stability law
    wire [ODW-1:0] obs_a_data = a_data ^ {{(ODW-1){1'b0}}, f_glitch};
`else
    wire [ODW-1:0] obs_a_data = a_data;
`endif

    // ----------------------------------------------------------------
    // the subordinate holds its side, and answers only what it owes
    // ----------------------------------------------------------------
    wire a_fire = obs_a_valid & a_ready;
    wire d_fire = d_valid & d_ready;

    reg [1:0] a_out;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            a_out <= 2'd0;
        else
            case ({a_fire, d_fire})
                2'b10:   a_out <= a_out + 2'd1;
                2'b01:   a_out <= a_out - 2'd1;
                default: a_out <= a_out;
            endcase

    reg d_valid_d, d_ready_d;
    reg [2:0] d_opcode_d, d_size_d;
    reg [3:0] d_source_d;
    reg [ODW-1:0] d_data_d;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            d_valid_d <= 1'b0; d_ready_d <= 1'b0;
        end else begin
            d_valid_d <= d_valid; d_ready_d <= d_ready;
        end
    always @(posedge clk) begin
        d_opcode_d <= d_opcode; d_size_d <= d_size;
        d_source_d <= d_source; d_data_d <= d_data;
    end

    always @(*) begin
        m_tl_reset_quiet : assume (nreset || !d_valid);
        m_tl_d_owed  : assume (!d_valid || (a_out != 2'd0));
        m_tl_d_kind  : assume (!d_valid || (d_opcode == `TL_OP_AccessAck)
                               || (d_opcode == `TL_OP_AccessAckData));
        m_tl_no_wrap : assume (a_out != 2'd3);
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            m_tl_d_hold   : assume (!(d_valid_d & ~d_ready_d) || d_valid);
            m_tl_d_stable : assume (!(d_valid_d & ~d_ready_d)
                                    || ((d_opcode == d_opcode_d)
                                        && (d_size   == d_size_d)
                                        && (d_source == d_source_d)
                                        && (d_data   == d_data_d)));
        end

    // ----------------------------------------------------------------
    // the UMI response channel this block drives is judged
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (IDW), .ASSUME (0)
    ) chk_resp (
        .clk (clk), .nreset (nreset),
        .valid (resp_valid), .ready (resp_ready),
        .cmd (resp_cmd), .dstaddr (resp_dstaddr),
        .srcaddr (resp_srcaddr), .data (resp_data)
    );

    // ----------------------------------------------------------------
    // TileLink-UL manager obligations on A
    // ----------------------------------------------------------------
    reg        a_valid_d, a_ready_d;
    reg [2:0]  a_opcode_d, a_size_d;
    reg [3:0]  a_source_d;
    reg [55:0] a_address_d;
    reg [7:0]  a_mask_d;
    reg [ODW-1:0] a_data_d;

    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            a_valid_d <= 1'b0; a_ready_d <= 1'b0;
        end else begin
            a_valid_d <= obs_a_valid; a_ready_d <= a_ready;
        end
    always @(posedge clk) begin
        a_opcode_d <= a_opcode; a_size_d <= a_size;
        a_source_d <= a_source; a_address_d <= obs_a_address;
        a_mask_d   <= a_mask;   a_data_d <= obs_a_data;
    end

    always @(posedge clk)
        if (nreset & f_past_exists) begin
            TL_a_hold   : assert (!(a_valid_d & ~a_ready_d) || obs_a_valid);
            TL_a_stable : assert (!(a_valid_d & ~a_ready_d)
                                  || ((a_opcode == a_opcode_d)
                                      && (a_size   == a_size_d)
                                      && (a_source == a_source_d)
                                      && (obs_a_address == a_address_d)
                                      && (a_mask   == a_mask_d)
                                      && (obs_a_data == a_data_d)));
        end

    always @(posedge clk)
        if (nreset & f_past_exists & obs_a_valid) begin
            TL_a_opcode_legal : assert ((a_opcode == `TL_OP_Get)
                                        || (a_opcode == `TL_OP_PutFullData)
                                        || (a_opcode == `TL_OP_PutPartialData));
            TL_a_align : assert ((obs_a_address
                                  & ((56'd1 << a_size) - 56'd1)) == 56'd0);
        end

`ifdef FV_TLM_ASSERT_MASK
    // SIZE and MASK are not independent in TileLink: a_size names a
    // power-of-two byte count and a_mask must enable exactly that many
    // lanes. umi2tl does not satisfy this for a one-byte access -- the
    // req_bytes == 1 arm sets size 1, meaning two bytes, beside a mask
    // with a single lane enabled (umi2tl.v:196-200). Nothing is
    // injected on this row: the shipped table is the subject.
    always @(posedge clk)
        if (nreset & f_past_exists & obs_a_valid)
            TL_a_mask_size : assert ($countones(a_mask) == (32'd1 << a_size));
`endif

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (nreset & f_past_exists) begin
            c_tlm_a       : cover (a_fire);
            c_tlm_a_wait  : cover (obs_a_valid & ~a_ready);
            c_tlm_get     : cover (a_fire & (a_opcode == `TL_OP_Get));
            c_tlm_put     : cover (a_fire & (a_opcode == `TL_OP_PutFullData));
            c_tlm_d       : cover (d_fire);
            c_tlm_req     : cover (req_valid & req_ready);
            c_tlm_resp    : cover (resp_valid & resp_ready);
            // the byte sizes the size/mask table distinguishes
            c_tlm_byte    : cover (a_fire & (a_mask == 8'd1));
            c_tlm_word    : cover (a_fire & (a_mask == 8'd255));
            // the one-byte request the size/mask table mishandles
            c_tlm_byte1   : cover (a_fire & (req_size == 3'd0)
                                   & ($countones(a_mask) == 32'd1)
                                   & (a_size == 3'd1));
        end
`endif

endmodule

`default_nettype wire
