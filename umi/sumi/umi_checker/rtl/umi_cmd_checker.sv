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
 * Passive protocol checker for SUMI command-word (CMD) legality.
 * Attach one instance per SUMI channel, exactly like the handshake
 * checker in this directory; it drives nothing and never interferes
 * with the design. Every rule is a same-cycle predicate over the
 * OFFERED beat (checked whenever VALID is high out of reset): a beat
 * that is never accepted must still be a legal beat, so READY is
 * deliberately not consulted.
 *
 * The rules, with their README (UMI spec) anchors:
 *
 *   CMD1_opcode_legal    OPCODE is one of the 13 structured opcodes or
 *                        the 3 full-byte specials REQ_ERROR/REQ_LINK/
 *                        RESP_LINK (README 3.2.3 message-types table).
 *                        INVALID (CMD[7:0]==0x00) and the reserved
 *                        opcode holes are rejected on an offered beat
 *                        (INVALID is admitted by ALLOW_INVALID,
 *                        default OFF, see below).
 *   CMD2_atype_legal     REQ_ATOMIC carries ATYPE in the LEN bit
 *                        positions; only 0x00..0x08 (ADD..SWAP) are
 *                        defined (README 3.3.9 ATYPE table).
 *   CMD4_da_aligned      DA aligned to 2^SIZE whenever the message has
 *   CMD4_sa_aligned      a DA (everything but LINK); SA aligned on
 *                        requests (README 3.1 "Device and source
 *                        addresses must be aligned to the native word
 *                        size"). Response SA is undefined by README
 *                        3.3.1 and never checked.
 *   CMD6_sa_reserved     (gated by CHECK_SA_RESERVED, default OFF, see
 *                        below) request SA reserved bits are zero:
 *                        SA[63:40] for AW>=64, SA[31:24] otherwise
 *                        (README 3.3.1 SA bit map, 3.3.12 "R ... shall
 *                        be set to zero").
 *   CMD10_fullbyte_decode the full-byte opcode family is unambiguous:
 *                        a 5-bit opcode of 0x0F must extend to
 *                        REQ_ERROR (CMD[7:5]==0) or REQ_LINK
 *                        (CMD[7:5]==1); 0x0E must extend to RESP_LINK
 *                        (CMD[7:5]==0) (README 3.2.3 rows REQ_ERROR /
 *                        REQ_LINK / RESP_LINK).
 *   CMD11_ex_zero        EX==0 for REQ_WRPOSTED / REQ_RDMA /
 *                        REQ_ATOMIC (README 3.2.3: bit 24 is "0" in
 *                        those rows).
 *   CMD12_error_size     the REQ_ERROR family (5-bit opcode 0x0F, not
 *                        the REQ_LINK extension) carries SIZE==0
 *                        (README 3.2.3 REQ_ERROR row, SIZE column
 *                        0x0). NOTE: classified by the 5-bit opcode,
 *                        not CMD[7:0]==0x0F -- the full-byte
 *                        classification makes the rule a tautology
 *                        (0x0F in [7:0] already forces [7:5]==0), i.e.
 *                        unfalsifiable. The 5-bit form is falsifiable;
 *                        the set of beats accepted by the checker as a
 *                        whole is unchanged (every CMD-12 violation is
 *                        also outside the CMD-1 legal-opcode set).
 *                        Exhaustively: the per-rule extra rejects are
 *                        exactly opbyte in {0x4F,0x6F,0x8F,0xAF,0xCF,
 *                        0xEF}, each already rejected by CMD-1 (not
 *                        structured, not a legal full-byte), so the
 *                        ten-rule conjunction accepts the identical
 *                        language.
 *   CMD15_beat_capacity  the bytes implied by SIZE/LEN for one beat --
 *                        (LEN+1)*2^SIZE, or 2^SIZE for atomics, or 0
 *                        for no-data messages -- fit the data bus:
 *                        <= DW/8 (README 3.3.2 SIZE, 3.3.3 LEN; a SUMI
 *                        packet is a complete routable mini-message,
 *                        README 4.1). EXEMPTION: responses with
 *                        ERR==DEVERR or ERR==NETERR are not convicted.
 *                        An error response echoes the SIZE/LEN of a
 *                        request that may span several beats, and by
 *                        CMD16 it carries no data -- convicting a
 *                        NETERR reply to a multi-beat read would be a
 *                        spec-plausible false positive.
 *   CMD16_err_data_zero  a response with ERR==DEVERR or ERR==NETERR
 *                        carries no data: the byte lanes SIZE/LEN
 *                        declare relevant must be zero (README 3.3.9
 *                        ERR codes; data-carrying rows in 3.2.3).
 *
 * ASSUME parameter: identical contract to umi_handshake_checker.
 *   ASSUME=0 (default): assert the rules -- attach to any channel the
 *            design under test drives (simulation or formal).
 *   ASSUME=1: assume the rules. Formal-only: constrains free inputs of
 *            a harness to legal command traffic. The same file is both
 *            the requirement and the environment, so the two can never
 *            drift apart.
 *
 * CHECK_SA_RESERVED parameter (default 0 = OFF): README 3.3.1 marks
 * SA[63:40] (64b mode) reserved and 3.3.12 requires reserved bits to
 * be zero -- but README 3.3.1 equally allows SA to be "a partial
 * routing address and a set of optional UMI signal layer controls",
 * and this repository's own reference traffic and bus adapters carry
 * routing/implementation bits in the high SA bytes. Shipping the rule
 * hard-on would convict the reference RTL and push adopters to turn
 * the whole checker off, so the strict reserved-zero profile is opt-in
 * (CHECK_SA_RESERVED=1).
 *
 * ALLOW_INVALID parameter (default 0 = OFF): README 3.4.1 says of the
 * INVALID message that "a receiver can choose to ignore the message or
 * to take corrective action", so a link whose receiver is specified to
 * ignore INVALID is not broken by an INVALID beat appearing on it.
 * README 3.2.3 gives that message no field encodings at all, though,
 * so a command word that reached zero by accident is indistinguishable
 * from one sent deliberately; the strict reading -- an offered beat
 * must name a real message -- is what ships. ALLOW_INVALID=1 admits
 * CMD[7:0]==0x00 through CMD1_opcode_legal and, because README 3.2.3
 * leaves the DA column of the INVALID row blank, also drops the
 * CMD4_da_aligned obligation on that beat. No other rule is affected,
 * and at the default no rule is affected at all.
 *
 * RULE_EN parameter: one enable bit per rule, so a channel that breaks
 * a single rule -- or an integrator who reads one rule differently --
 * can drop that one rule instead of unbinding the whole checker. A
 * cleared bit removes the rule from BOTH the assert and the assume
 * face, so a masked instance stays the same property in either
 * direction. The default 10'h3FF enables every rule and is
 * behaviour-identical to leaving the parameter unset.
 *
 *   bit  rule
 *   ---  -----------------------------------------------------------
 *    0   CMD1_opcode_legal
 *    1   CMD2_atype_legal
 *    2   CMD4_da_aligned
 *    3   CMD4_sa_aligned
 *    4   CMD6_sa_reserved (also gated by CHECK_SA_RESERVED)
 *    5   CMD10_fullbyte_decode
 *    6   CMD11_ex_zero
 *    7   CMD12_error_size
 *    8   CMD15_beat_capacity
 *    9   CMD16_err_data_zero
 *
 * Implementation notes (same portable subset as umi_handshake_checker):
 *  - Field positions and opcode values come from umi_messages.vh, the
 *    repo's single source of truth. The only locally declared
 *    constants are the ERR codes, which umi_messages.vh does not
 *    define (README 3.3.9).
 *  - Named immediate assertions inside always blocks; each assert is
 *    paired with an `ifndef FORMAL $error twin whose !== comparison
 *    also catches X in 4-state simulation. Cover statements are
 *    formal-only (`ifdef FORMAL).
 *  - No $past, no sequences, no bind, no packages: the same file works
 *    under yosys/SymbiYosys (read_verilog -formal), Verilator
 *    (--assert), slang lint, and Icarus Verilog.
 ******************************************************************************/

`default_nettype none

module umi_cmd_checker #(
    parameter CW = 32,              // command width
    parameter AW = 64,              // address width
    parameter DW = 256,             // data width
    parameter ASSUME = 0,           // 0: assert the rules, 1: assume them
    parameter CHECK_SA_RESERVED = 0, // 1: also require request SA reserved bits zero
    parameter ALLOW_INVALID = 0,     // 1: admit an in-band INVALID beat
    parameter [9:0] RULE_EN = 10'h3FF // per-rule enables (see header table)
) (
    input wire          clk,
    input wire          nreset,
    input wire          valid,
    input wire          ready,
    input wire [CW-1:0] cmd,
    input wire [AW-1:0] dstaddr,
    input wire [AW-1:0] srcaddr,
    input wire [DW-1:0] data
);

    // the shared header declares every UMI constant; a checker uses
    // only the command-legality subset, so the unused ones are waived
    // verilator lint_off UNUSEDPARAM
`include "umi_messages.vh"
    // verilator lint_on UNUSEDPARAM

    // ERR codes on the response USER/ERR field (README 3.3.9). These
    // are the one set of constants not present in umi_messages.vh.
    localparam [1:0] UMI_ERR_DEVERR = 2'd2;
    localparam [1:0] UMI_ERR_NETERR = 2'd3;

    localparam [15:0] BEAT_BYTES = DW / 8;  // data-bus capacity of one beat

    // beat legality is a property of the OFFERED beat, so READY is
    // unused (kept so handshake- and cmd-checker binds look alike);
    // QOS/PROT/EOM/EOF/HOSTID carry no per-beat legality obligation
    wire unused_ok = &{1'b1, ready,
                       cmd[UMI_HOSTID_MSB:UMI_HOSTID_LSB],
                       cmd[UMI_EOF_BIT],
                       cmd[UMI_EOM_BIT],
                       cmd[UMI_PROT_MSB:UMI_PROT_LSB],
                       cmd[UMI_QOS_MSB:UMI_QOS_LSB]};

    // #################################################################
    // # Field extraction (umi_messages.vh bit positions)
    // #################################################################

    wire [4:0] dec_op5    = cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];
    wire [7:0] dec_opbyte = cmd[7:0];                        // opcode + extension
    wire [2:0] dec_size   = cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    wire [7:0] dec_len    = cmd[UMI_LEN_MSB:UMI_LEN_LSB];    // ATYPE on REQ_ATOMIC
    wire       dec_ex     = cmd[UMI_EX_BIT];
    wire [1:0] dec_userr  = cmd[UMI_USER_MSB:UMI_USER_LSB];  // USER on req / ERR on resp

    // #################################################################
    // # Decode (message classes per README 3.2.3)
    // #################################################################

    // the thirteen structured opcodes (requests odd, responses even)
    wire dec_structured =
        (dec_op5 == UMI_REQ_READ)    | (dec_op5 == UMI_REQ_WRITE)   |
        (dec_op5 == UMI_REQ_POSTED)  | (dec_op5 == UMI_REQ_RDMA)    |
        (dec_op5 == UMI_REQ_ATOMIC)  | (dec_op5 == UMI_REQ_USER0)   |
        (dec_op5 == UMI_REQ_FUTURE0) |
        (dec_op5 == UMI_RESP_READ)   | (dec_op5 == UMI_RESP_WRITE)  |
        (dec_op5 == UMI_RESP_USER0)  | (dec_op5 == UMI_RESP_USER1)  |
        (dec_op5 == UMI_RESP_FUTURE0)| (dec_op5 == UMI_RESP_FUTURE1);

    // the three full-byte specials (opcode field spans CMD[7:0])
    wire dec_fullbyte = (dec_opbyte == UMI_REQ_ERROR)
                      | (dec_opbyte == UMI_REQ_LINK)
                      | (dec_opbyte == UMI_RESP_LINK);

    wire dec_is_link  = (dec_opbyte == UMI_REQ_LINK)
                      | (dec_opbyte == UMI_RESP_LINK);

    // the in-band INVALID beat a receiver may be specified to ignore
    // (README 3.4.1); admitted only under the ALLOW_INVALID profile
    wire dec_is_invalid = (dec_opbyte == UMI_INVALID);
    wire dec_invalid_ok = (ALLOW_INVALID != 0) & dec_is_invalid;

    // requests odd / responses even; INVALID (0x00) is neither
    wire dec_is_req   =  cmd[0] & ~dec_is_invalid;
    wire dec_is_resp  = ~cmd[0] & ~dec_is_invalid;

    // field applicability (README 3.2.3 DATA/SA/DA columns):
    // DA everywhere but LINK; SA on requests only (README 3.3.1 leaves
    // response SA undefined, so it is never an obligation). An admitted
    // INVALID beat has no DA either -- README 3.2.3 leaves the whole
    // INVALID row blank
    wire dec_has_da   = ~dec_is_link & ~dec_invalid_ok;
    wire dec_has_sa   = dec_is_req & ~dec_is_link;
    wire dec_has_data = (dec_op5 == UMI_REQ_WRITE)
                      | (dec_op5 == UMI_REQ_POSTED)
                      | (dec_op5 == UMI_REQ_ATOMIC)
                      | (dec_op5 == UMI_REQ_USER0)
                      | (dec_op5 == UMI_REQ_FUTURE0)
                      | (dec_op5 == UMI_RESP_READ)
                      | (dec_op5 == UMI_RESP_USER1)
                      | (dec_op5 == UMI_RESP_FUTURE1);

    // bytes carried by ONE beat of this message (relevance-aware):
    // no-data messages carry 0; atomics carry 2^SIZE (LEN aliases
    // ATYPE, the LEN formula never applies); else (LEN+1)*2^SIZE
    // (README 3.3.2 / 3.3.3)
    wire [15:0] dec_words     = {8'd0, dec_len} + 16'd1;
    wire [15:0] dec_bytes     = (16'd1 << dec_size) * dec_words;
    wire [15:0] dec_bytes_rel = ~dec_has_data ? 16'd0
                              : (dec_op5 == UMI_REQ_ATOMIC) ? (16'd1 << dec_size)
                              : dec_bytes;

    // alignment kernel (README 3.1): low SIZE bits of an address zero
    localparam [AW-1:0] ADDR_ONE = {{(AW-1){1'b0}}, 1'b1};
    wire [AW-1:0] dec_align_mask = (ADDR_ONE << dec_size) - ADDR_ONE;
    wire dec_da_aligned = ((dstaddr & dec_align_mask) == {AW{1'b0}});
    wire dec_sa_aligned = ((srcaddr & dec_align_mask) == {AW{1'b0}});

    // request SA reserved bits (README 3.3.1 SA bit map)
    wire dec_sa_res_zero;
    generate
        if (AW >= 64) begin : g_sa_64b
            assign dec_sa_res_zero = (srcaddr[63:40] == 24'd0);
        end else begin : g_sa_32b
            assign dec_sa_res_zero = (srcaddr[AW-1:AW-8] == 8'd0);
        end
    endgenerate

    // byte-lane relevance mask for CMD16: lane i is relevant when
    // i < bytes carried by the beat
    wire [BEAT_BYTES-1:0] dec_rel_lane;
    wire [DW-1:0]         dec_rel_mask;
    genvar gi;
    generate
        for (gi = 0; gi < DW/8; gi = gi + 1) begin : g_rel
            // gi is an elaboration constant; the sized localparam keeps
            // the lane compare pure 16-bit unsigned
            localparam [15:0] GLANE = gi[15:0];
            assign dec_rel_lane[gi] = (GLANE < dec_bytes_rel);
            assign dec_rel_mask[8*gi +: 8] = {8{dec_rel_lane[gi]}};
        end
    endgenerate

    // #################################################################
    // # The rules (one wire per rule; the same wire is asserted or
    // # assumed depending on ASSUME)
    // #################################################################

    wire dec_cmd1_ok  = dec_structured | dec_fullbyte | dec_invalid_ok;

    wire dec_cmd2_ok  = (dec_op5 != UMI_REQ_ATOMIC)
                      | (dec_len <= UMI_REQ_ATOMICSWAP);

    wire dec_cmd4a_ok = ~dec_has_da | dec_da_aligned;
    wire dec_cmd4b_ok = ~dec_has_sa | dec_sa_aligned;

    wire dec_cmd6_ok  = ~dec_has_sa | dec_sa_res_zero;

    // 5-bit opcode 0x0F is REQ_ERROR/REQ_LINK territory, 0x0E is
    // RESP_LINK territory; any other extension is an aliasing error
    wire dec_cmd10_ok = ((dec_op5 != UMI_REQ_ERROR[4:0])
                         | (cmd[7:5] == 3'd0) | (cmd[7:5] == 3'd1))
                      & ((dec_op5 != UMI_RESP_LINK[4:0])
                         | (cmd[7:5] == 3'd0));

    wire dec_cmd11_ok = ~(((dec_op5 == UMI_REQ_POSTED)
                         | (dec_op5 == UMI_REQ_RDMA)
                         | (dec_op5 == UMI_REQ_ATOMIC)) & dec_ex);

    // REQ_ERROR family by 5-bit opcode, REQ_LINK extension exempt --
    // see the CMD12 header note on falsifiability
    wire dec_cmd12_ok = (dec_op5 != UMI_REQ_ERROR[4:0])
                      | (cmd[7:5] == 3'd1)
                      | (dec_size == 3'd0);

    // DEVERR/NETERR response: exempt from beat capacity (CMD15, see
    // header) and must carry all-zero relevant data lanes (CMD16)
    wire dec_err_resp = dec_is_resp & ((dec_userr == UMI_ERR_DEVERR)
                                     | (dec_userr == UMI_ERR_NETERR));

    wire dec_cmd15_ok = dec_err_resp | (dec_bytes_rel <= BEAT_BYTES);

    wire dec_cmd16_ok = ~(dec_err_resp & dec_has_data)
                      | ((data & dec_rel_mask) == {DW{1'b0}});

    // #################################################################
    // # Assert or assume (one generate arm per direction)
    // #################################################################

    generate
        if (ASSUME == 0) begin : g_assert

            always @(posedge clk) begin
                if (nreset & valid) begin
                    if (RULE_EN[0]) begin
                        CMD1_opcode_legal : assert (dec_cmd1_ok);
`ifndef FORMAL
                        if ((dec_cmd1_ok) !== 1'b1)
                            $error("UMI-CMD CMD-1 %m: illegal OPCODE on a valid beat (README 3.2.3 message-types table)");
`endif
                    end
                    if (RULE_EN[1]) begin
                        CMD2_atype_legal : assert (dec_cmd2_ok);
`ifndef FORMAL
                        if ((dec_cmd2_ok) !== 1'b1)
                            $error("UMI-CMD CMD-2 %m: REQ_ATOMIC with ATYPE above ATOMICSWAP (README 3.3.9 ATYPE table)");
`endif
                    end
                    if (RULE_EN[2]) begin
                        CMD4_da_aligned : assert (dec_cmd4a_ok);
`ifndef FORMAL
                        if ((dec_cmd4a_ok) !== 1'b1)
                            $error("UMI-CMD CMD-4 %m: DSTADDR not aligned to 2^SIZE (README 3.1)");
`endif
                    end
                    if (RULE_EN[3]) begin
                        CMD4_sa_aligned : assert (dec_cmd4b_ok);
`ifndef FORMAL
                        if ((dec_cmd4b_ok) !== 1'b1)
                            $error("UMI-CMD CMD-4 %m: request SRCADDR not aligned to 2^SIZE (README 3.1)");
`endif
                    end
                    if ((CHECK_SA_RESERVED != 0) && RULE_EN[4]) begin
                        CMD6_sa_reserved : assert (dec_cmd6_ok);
`ifndef FORMAL
                        if ((dec_cmd6_ok) !== 1'b1)
                            $error("UMI-CMD CMD-6 %m: request SRCADDR reserved bits nonzero (README 3.3.1/3.3.12)");
`endif
                    end
                    if (RULE_EN[5]) begin
                        CMD10_fullbyte_decode : assert (dec_cmd10_ok);
`ifndef FORMAL
                        if ((dec_cmd10_ok) !== 1'b1)
                            $error("UMI-CMD CMD-10 %m: full-byte opcode family aliased outside REQ_ERROR/REQ_LINK/RESP_LINK (README 3.2.3)");
`endif
                    end
                    if (RULE_EN[6]) begin
                        CMD11_ex_zero : assert (dec_cmd11_ok);
`ifndef FORMAL
                        if ((dec_cmd11_ok) !== 1'b1)
                            $error("UMI-CMD CMD-11 %m: EX set on REQ_WRPOSTED/REQ_RDMA/REQ_ATOMIC (README 3.2.3)");
`endif
                    end
                    if (RULE_EN[7]) begin
                        CMD12_error_size : assert (dec_cmd12_ok);
`ifndef FORMAL
                        if ((dec_cmd12_ok) !== 1'b1)
                            $error("UMI-CMD CMD-12 %m: REQ_ERROR with SIZE != 0 (README 3.2.3 REQ_ERROR row)");
`endif
                    end
                    if (RULE_EN[8]) begin
                        CMD15_beat_capacity : assert (dec_cmd15_ok);
`ifndef FORMAL
                        if ((dec_cmd15_ok) !== 1'b1)
                            $error("UMI-CMD CMD-15 %m: SIZE/LEN imply more bytes than one DW-bit beat carries (README 3.3.2/3.3.3)");
`endif
                    end
                    if (RULE_EN[9]) begin
                        CMD16_err_data_zero : assert (dec_cmd16_ok);
`ifndef FORMAL
                        if ((dec_cmd16_ok) !== 1'b1)
                            $error("UMI-CMD CMD-16 %m: DEVERR/NETERR response carrying nonzero data in relevant byte lanes (README 3.3.9)");
`endif
                    end
                end
            end

        end else begin : g_assume
`ifdef FORMAL
            always @(posedge clk) begin
                if (nreset & valid) begin
                    if (RULE_EN[0])
                        CMD1_opcode_legal : assume (dec_cmd1_ok);
                    if (RULE_EN[1])
                        CMD2_atype_legal : assume (dec_cmd2_ok);
                    if (RULE_EN[2])
                        CMD4_da_aligned : assume (dec_cmd4a_ok);
                    if (RULE_EN[3])
                        CMD4_sa_aligned : assume (dec_cmd4b_ok);
                    if ((CHECK_SA_RESERVED != 0) && RULE_EN[4])
                        CMD6_sa_reserved : assume (dec_cmd6_ok);
                    if (RULE_EN[5])
                        CMD10_fullbyte_decode : assume (dec_cmd10_ok);
                    if (RULE_EN[6])
                        CMD11_ex_zero : assume (dec_cmd11_ok);
                    if (RULE_EN[7])
                        CMD12_error_size : assume (dec_cmd12_ok);
                    if (RULE_EN[8])
                        CMD15_beat_capacity : assume (dec_cmd15_ok);
                    if (RULE_EN[9])
                        CMD16_err_data_zero : assume (dec_cmd16_ok);
                end
            end
`endif
        end
    endgenerate

    // #################################################################
    // # Vacuity witnesses (formal-only)
    // #################################################################
    // A command-legality proof over an environment that can not reach
    // every legal opcode -- or a full-capacity beat -- proves nothing.
    // These covers fail loudly (unreached) if a harness or a bind
    // over-constrains the channel.

`ifdef FORMAL
    always @(posedge clk) begin
        if (nreset & valid) begin
            SAW_req_read : cover (dec_op5 == UMI_REQ_READ);
            SAW_req_write : cover (dec_op5 == UMI_REQ_WRITE);
            SAW_req_posted : cover (dec_op5 == UMI_REQ_POSTED);
            SAW_req_rdma : cover (dec_op5 == UMI_REQ_RDMA);
            SAW_req_atomic : cover (dec_op5 == UMI_REQ_ATOMIC);
            SAW_req_user0 : cover (dec_op5 == UMI_REQ_USER0);
            SAW_req_future0 : cover (dec_op5 == UMI_REQ_FUTURE0);
            SAW_resp_read : cover (dec_op5 == UMI_RESP_READ);
            SAW_resp_write : cover (dec_op5 == UMI_RESP_WRITE);
            SAW_resp_user0 : cover (dec_op5 == UMI_RESP_USER0);
            SAW_resp_user1 : cover (dec_op5 == UMI_RESP_USER1);
            SAW_resp_future0 : cover (dec_op5 == UMI_RESP_FUTURE0);
            SAW_resp_future1 : cover (dec_op5 == UMI_RESP_FUTURE1);
            SAW_full_capacity : cover (dec_bytes_rel == BEAT_BYTES);
            if (CHECK_SA_RESERVED != 0)
                SAW_sa_checked : cover (dec_has_sa & dec_cmd6_ok);
            if (ALLOW_INVALID != 0)
                SAW_invalid : cover (dec_is_invalid & dec_cmd1_ok);
        end
    end
`endif

endmodule

`default_nettype wire
