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
 * - Proves the CMD codec round-trips over the 13 structured opcodes.
 *   FWD_*: unpack(pack(fields)) returns the fields, with the format's
 *   two aliases handled exactly: REQ_ATOMIC carries ATYPE in the LEN
 *   bit positions (LEN reads back 0), and CMD[26:25] is USER on
 *   requests / ERR on responses.
 *   REV_cmd: pack(unpack(word)) == word for structured words.
 * - Full-byte opcodes (REQ_ERROR 0x0F, REQ_LINK 0x2F, RESP_LINK 0x0E)
 *   redefine the field layout and are excluded here. The whitelist
 *   also avoids opcode 5'h19, which the codec's 4-bit atomic compare
 *   (packet_cmd[3:0] == 4'h9) reads as an atomic.
 * - Purely combinational, so induction closes immediately; the value
 *   of prove mode is the quantifier over all inputs.
 * - fault_eom (see .sby) flips the EOM bit in transit; FWD_eom must
 *   fail. A proof that cannot fail proves nothing.
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_codec #(
    parameter CW = 32
) (
    input wire clk
);

`include "umi_messages.vh"

    // ----------------------------------------------------------------
    // free field tuple
    // ----------------------------------------------------------------
    (* anyseq *) wire [4:0]  f_opcode;
    (* anyseq *) wire [2:0]  f_size;
    (* anyseq *) wire [7:0]  f_len;
    (* anyseq *) wire [7:0]  f_atype;
    (* anyseq *) wire [3:0]  f_qos;
    (* anyseq *) wire [1:0]  f_prot;
    (* anyseq *) wire        f_eom;
    (* anyseq *) wire        f_eof;
    (* anyseq *) wire [1:0]  f_user;
    (* anyseq *) wire [1:0]  f_err;
    (* anyseq *) wire        f_ex;
    (* anyseq *) wire [4:0]  f_hostid;

    // the thirteen structured opcodes (requests odd, responses even)
    wire f_structured =
        (f_opcode == UMI_REQ_READ)    | (f_opcode == UMI_REQ_WRITE)   |
        (f_opcode == UMI_REQ_POSTED)  | (f_opcode == UMI_REQ_RDMA)    |
        (f_opcode == UMI_REQ_ATOMIC)  | (f_opcode == UMI_REQ_USER0)   |
        (f_opcode == UMI_REQ_FUTURE0) |
        (f_opcode == UMI_RESP_READ)   | (f_opcode == UMI_RESP_WRITE)  |
        (f_opcode == UMI_RESP_USER0)  | (f_opcode == UMI_RESP_USER1)  |
        (f_opcode == UMI_RESP_FUTURE0)| (f_opcode == UMI_RESP_FUTURE1);

    wire f_is_atomic   = (f_opcode == UMI_REQ_ATOMIC);
    wire f_is_response = ~f_opcode[0];

    always @(*) begin
        legal_opcode : assume (f_structured);
        // ATYPE is an 8-bit field but only ADD..SWAP are defined
        legal_atype : assume (!f_is_atomic
                              || (f_atype <= UMI_REQ_ATOMICSWAP));
    end

    // ----------------------------------------------------------------
    // forward: fields -> pack -> unpack -> fields
    // ----------------------------------------------------------------
    wire [CW-1:0] packed_cmd;

    umi_pack #(.CW(CW)) u_pack (
        .cmd_opcode        (f_opcode),
        .cmd_size          (f_size),
        .cmd_len           (f_len),
        .cmd_atype         (f_atype),
        .cmd_prot          (f_prot),
        .cmd_qos           (f_qos),
        .cmd_eom           (f_eom),
        .cmd_eof           (f_eof),
        .cmd_user          (f_user),
        .cmd_err           (f_err),
        .cmd_ex            (f_ex),
        .cmd_hostid        (f_hostid),
        .cmd_user_extended (24'd0),          // structured opcodes only
        .packet_cmd        (packed_cmd)
    );

`ifdef FV_FAULT_EOM
    // the known-answer fault: EOM flipped in transit; FWD_eom must fail
    wire [CW-1:0] wire_cmd = packed_cmd ^ (32'h1 << 22);
`else
    wire [CW-1:0] wire_cmd = packed_cmd;
`endif

    wire [4:0]  u_opcode;
    wire [2:0]  u_size;
    wire [7:0]  u_len;
    wire [7:0]  u_atype;
    wire [3:0]  u_qos;
    wire [1:0]  u_prot;
    wire        u_eom;
    wire        u_eof;
    wire        u_ex;
    wire [1:0]  u_user;
    wire [23:0] u_user_extended;
    wire [1:0]  u_err;
    wire [4:0]  u_hostid;

    umi_unpack #(.CW(CW)) u_unpack (
        .packet_cmd        (wire_cmd),
        .cmd_opcode        (u_opcode),
        .cmd_size          (u_size),
        .cmd_len           (u_len),
        .cmd_atype         (u_atype),
        .cmd_qos           (u_qos),
        .cmd_prot          (u_prot),
        .cmd_eom           (u_eom),
        .cmd_eof           (u_eof),
        .cmd_ex            (u_ex),
        .cmd_user          (u_user),
        .cmd_user_extended (u_user_extended),
        .cmd_err           (u_err),
        .cmd_hostid        (u_hostid)
    );

    always @(*) begin
        FWD_opcode : assert (u_opcode == f_opcode);
        FWD_size : assert (u_size == f_size);
        FWD_qos : assert (u_qos == f_qos);
        FWD_prot : assert (u_prot == f_prot);
        FWD_eom : assert (u_eom == f_eom);
        FWD_eof : assert (u_eof == f_eof);
        FWD_ex : assert (u_ex == f_ex);
        FWD_hostid : assert (u_hostid == f_hostid);
        // the LEN/ATYPE alias, exactly as the format defines it
        FWD_len : assert (f_is_atomic ? (u_len == 8'd0)
                                      : (u_len == f_len));
        FWD_atype : assert (!f_is_atomic || (u_atype == f_atype));
        // the USER/ERR alias: requests carry USER, responses carry ERR
        FWD_user : assert (f_is_response || (u_user == f_user));
        FWD_err : assert (f_is_response ? (u_err == f_err)
                                        : (u_err == 2'd0));
    end

    // ----------------------------------------------------------------
    // reverse: word -> unpack -> pack -> the same word
    // ----------------------------------------------------------------
    (* anyseq *) wire [CW-1:0] r_cmd;

    wire r_structured =
        (r_cmd[4:0] == UMI_REQ_READ)    | (r_cmd[4:0] == UMI_REQ_WRITE)   |
        (r_cmd[4:0] == UMI_REQ_POSTED)  | (r_cmd[4:0] == UMI_REQ_RDMA)    |
        (r_cmd[4:0] == UMI_REQ_ATOMIC)  | (r_cmd[4:0] == UMI_REQ_USER0)   |
        (r_cmd[4:0] == UMI_REQ_FUTURE0) |
        (r_cmd[4:0] == UMI_RESP_READ)   | (r_cmd[4:0] == UMI_RESP_WRITE)  |
        (r_cmd[4:0] == UMI_RESP_USER0)  | (r_cmd[4:0] == UMI_RESP_USER1)  |
        (r_cmd[4:0] == UMI_RESP_FUTURE0)| (r_cmd[4:0] == UMI_RESP_FUTURE1);

    always @(*) begin
        legal_r_opcode : assume (r_structured);
    end

    wire [4:0]  r_opcode;
    wire [2:0]  r_size;
    wire [7:0]  r_len;
    wire [7:0]  r_atype;
    wire [3:0]  r_qos;
    wire [1:0]  r_prot;
    wire        r_eom;
    wire        r_eof;
    wire        r_ex;
    wire [1:0]  r_user;
    wire [23:0] r_user_extended;
    wire [1:0]  r_err;
    wire [4:0]  r_hostid;

    umi_unpack #(.CW(CW)) r_unpack (
        .packet_cmd        (r_cmd),
        .cmd_opcode        (r_opcode),
        .cmd_size          (r_size),
        .cmd_len           (r_len),
        .cmd_atype         (r_atype),
        .cmd_qos           (r_qos),
        .cmd_prot          (r_prot),
        .cmd_eom           (r_eom),
        .cmd_eof           (r_eof),
        .cmd_ex            (r_ex),
        .cmd_user          (r_user),
        .cmd_user_extended (r_user_extended),
        .cmd_err           (r_err),
        .cmd_hostid        (r_hostid)
    );

    wire [CW-1:0] r_repacked;

    umi_pack #(.CW(CW)) r_pack (
        .cmd_opcode        (r_opcode),
        .cmd_size          (r_size),
        .cmd_len           (r_len),
        .cmd_atype         (r_atype),
        .cmd_prot          (r_prot),
        .cmd_qos           (r_qos),
        .cmd_eom           (r_eom),
        .cmd_eof           (r_eof),
        .cmd_user          (r_user),
        .cmd_err           (r_err),
        .cmd_ex            (r_ex),
        .cmd_hostid        (r_hostid),
        .cmd_user_extended (24'd0),
        .packet_cmd        (r_repacked)
    );

    always @(*) begin
        REV_cmd : assert (r_repacked == r_cmd);
    end

    // ----------------------------------------------------------------
    // vacuity witnesses: each interesting class is actually explored
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(*) begin
        SAW_read_req : cover (f_opcode == UMI_REQ_READ);
        SAW_write_resp : cover (f_opcode == UMI_RESP_WRITE && f_err != 2'd0);
        SAW_atomic : cover (f_is_atomic && f_atype == UMI_REQ_ATOMICSWAP);
    end
`endif

endmodule

`default_nettype wire
