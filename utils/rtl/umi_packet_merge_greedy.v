`timescale 1ns / 1ps
`default_nettype wire

module umi_packet_merge_greedy #(
    parameter CW    = 32,   // command width
    parameter AW    = 64,   // address width
    parameter IDW   = 64,   // input data width
    parameter ODW   = 2*IDW // output data width (requirement: >= 2x input data width)
)
(
    input               clk,
    input               nreset,

    input               umi_in_valid,
    input  [CW-1:0]     umi_in_cmd,
    input  [AW-1:0]     umi_in_dstaddr,
    input  [AW-1:0]     umi_in_srcaddr,
    input  [IDW-1:0]    umi_in_data,
    output              umi_in_ready,

    output              umi_out_valid,
    output [CW-1:0]     umi_out_cmd,
    output [AW-1:0]     umi_out_dstaddr,
    output [AW-1:0]     umi_out_srcaddr,
    output [ODW-1:0]    umi_out_data,
    input               umi_out_ready
);

    wire                    umi_in_cmd_commit;
    wire                    umi_out_cmd_commit;

    assign umi_in_cmd_commit = umi_in_ready & umi_in_valid;
    assign umi_out_cmd_commit = umi_out_ready & umi_out_valid;

    wire [4:0]  umi_in_cmd_opcode;
    wire [2:0]  umi_in_cmd_size;
    wire [7:0]  umi_in_cmd_len;
    wire [7:0]  umi_in_cmd_atype;
    wire [3:0]  umi_in_cmd_qos;
    wire [1:0]  umi_in_cmd_prot;
    wire        umi_in_cmd_eom;
    wire        umi_in_cmd_eof;
    wire        umi_in_cmd_ex;
    wire [1:0]  umi_in_cmd_user;
    wire [23:0] umi_in_cmd_user_extended;
    wire [1:0]  umi_in_cmd_err;
    wire [4:0]  umi_in_cmd_hostid;

    umi_unpack #(
        .CW                 (CW)
    ) umi_unpack_i (
        // Inputs
        .packet_cmd         (umi_in_cmd),

        // Outputs
        .cmd_opcode         (umi_in_cmd_opcode),
        .cmd_size           (umi_in_cmd_size),
        .cmd_len            (umi_in_cmd_len),
        .cmd_atype          (umi_in_cmd_atype),
        .cmd_qos            (umi_in_cmd_qos),
        .cmd_prot           (umi_in_cmd_prot),
        .cmd_eom            (umi_in_cmd_eom),
        .cmd_eof            (umi_in_cmd_eof),
        .cmd_ex             (umi_in_cmd_ex),
        .cmd_user           (umi_in_cmd_user),
        .cmd_user_extended  (umi_in_cmd_user_extended),
        .cmd_err            (umi_in_cmd_err),
        .cmd_hostid         (umi_in_cmd_hostid)
    );

    wire umi_in_cmd_read;
    wire umi_in_cmd_write;
    wire umi_in_cmd_write_posted;
    wire umi_in_cmd_rdma;
    wire umi_in_cmd_read_resp;
    wire umi_in_cmd_write_resp;

    umi_decode #(
        .CW                 (32)
    ) umi_decode_i (
        // Packet Command
        .command            (umi_in_cmd),
        .cmd_invalid        (),
        // request/response/link
        .cmd_request        (),
        .cmd_response       (),
        // requests
        .cmd_read           (umi_in_cmd_read),
        .cmd_write          (umi_in_cmd_write),
        .cmd_write_posted   (umi_in_cmd_write_posted),
        .cmd_rdma           (umi_in_cmd_rdma),
        .cmd_atomic         (),
        .cmd_user0          (),
        .cmd_future0        (),
        .cmd_error          (),
        .cmd_link           (),
        // Response (device -> host)
        .cmd_read_resp      (umi_in_cmd_read_resp),
        .cmd_write_resp     (umi_in_cmd_write_resp),
        .cmd_user0_resp     (),
        .cmd_user1_resp     (),
        .cmd_future0_resp   (),
        .cmd_future1_resp   (),
        .cmd_link_resp      (),
        // Atomic operations
        .cmd_atomic_add     (),
        .cmd_atomic_and     (),
        .cmd_atomic_or      (),
        .cmd_atomic_xor     (),
        .cmd_atomic_max     (),
        .cmd_atomic_min     (),
        .cmd_atomic_maxu    (),
        .cmd_atomic_minu    (),
        .cmd_atomic_swap    ()
    );

    reg                     umi_in_valid_r;
    wire                    umi_in_ready_r;
    wire                    umi_in_cmd_commit_r;

    assign umi_in_cmd_commit_r = umi_in_ready_r & umi_in_valid_r;
    assign umi_in_ready = !umi_in_valid_r | umi_in_ready_r;
    assign umi_in_ready_r = umi_out_cmd_commit |
                            (umi_in_mergeable_r & ((byte_counter + umi_in_bytes_r) <= (ODW/8))) |
                            (byte_counter == 0);

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            umi_in_valid_r <= 1'b0;
        end
        else begin
            if (umi_in_cmd_commit)
                umi_in_valid_r <= 1'b1;
            else if (umi_in_cmd_commit_r)
                umi_in_valid_r <= 1'b0;
        end
    end

    reg  [4:0]              umi_in_cmd_opcode_r;
    reg  [2:0]              umi_in_cmd_size_r;
    reg  [7:0]              umi_in_cmd_len_r;
    reg  [7:0]              umi_in_cmd_atype_r;
    reg  [3:0]              umi_in_cmd_qos_r;
    reg  [1:0]              umi_in_cmd_prot_r;
    reg                     umi_in_cmd_eom_r;
    reg                     umi_in_cmd_eof_r;
    reg                     umi_in_cmd_ex_r;
    reg  [1:0]              umi_in_cmd_user_r;
    reg  [23:0]             umi_in_cmd_user_extended_r;
    reg  [1:0]              umi_in_cmd_err_r;
    reg  [4:0]              umi_in_cmd_hostid_r;

    reg [AW-1:0]            umi_in_dstaddr_r;
    reg [AW-1:0]            umi_in_srcaddr_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            umi_in_cmd_opcode_r         <= 'b0;
            umi_in_cmd_size_r           <= 'b0;
            umi_in_cmd_len_r            <= 'b0;
            umi_in_cmd_atype_r          <= 'b0;
            umi_in_cmd_qos_r            <= 'b0;
            umi_in_cmd_prot_r           <= 'b0;
            umi_in_cmd_eom_r            <= 'b0;
            umi_in_cmd_eof_r            <= 'b0;
            umi_in_cmd_ex_r             <= 'b0;
            umi_in_cmd_user_r           <= 'b0;
            umi_in_cmd_user_extended_r  <= 'b0;
            umi_in_cmd_err_r            <= 'b0;
            umi_in_cmd_hostid_r         <= 'b0;
            umi_in_dstaddr_r            <= 'b0;
            umi_in_srcaddr_r            <= 'b0;
        end
        else if (umi_in_cmd_commit) begin
            umi_in_cmd_opcode_r         <= umi_in_cmd_opcode;
            umi_in_cmd_size_r           <= umi_in_cmd_size;
            umi_in_cmd_len_r            <= umi_in_cmd_len;
            umi_in_cmd_atype_r          <= umi_in_cmd_atype;
            umi_in_cmd_qos_r            <= umi_in_cmd_qos;
            umi_in_cmd_prot_r           <= umi_in_cmd_prot;
            umi_in_cmd_eom_r            <= umi_in_cmd_eom;
            umi_in_cmd_eof_r            <= umi_in_cmd_eof;
            umi_in_cmd_ex_r             <= umi_in_cmd_ex;
            umi_in_cmd_user_r           <= umi_in_cmd_user;
            umi_in_cmd_user_extended_r  <= umi_in_cmd_user_extended;
            umi_in_cmd_err_r            <= umi_in_cmd_err;
            umi_in_cmd_hostid_r         <= umi_in_cmd_hostid;
            umi_in_dstaddr_r            <= umi_in_dstaddr;
            umi_in_srcaddr_r            <= umi_in_srcaddr;
        end
    end

    reg [IDW-1:0]           umi_in_data_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            umi_in_data_r <= 'b0;
        else if (umi_in_cmd_commit)
            umi_in_data_r <= umi_in_data;
    end

    wire                    umi_in_opcode_check;
    wire                    umi_in_field_match;
    wire                    umi_in_mergeable;
    wire [$clog2(IDW/8):0]  umi_in_bytes;
    reg                     umi_in_mergeable_r;
    reg  [$clog2(IDW/8):0]  umi_in_bytes_r;

    reg [AW-1:0]            umi_in_dstaddr_nx;
    reg [AW-1:0]            umi_in_srcaddr_nx;

    assign umi_in_opcode_check = umi_in_cmd_read |
                                 umi_in_cmd_write |
                                 umi_in_cmd_write_posted |
                                 umi_in_cmd_rdma |
                                 umi_in_cmd_read_resp |
                                 umi_in_cmd_write_resp;

    assign umi_in_field_match = (umi_in_cmd_opcode == umi_in_cmd_opcode_r) &
                                (umi_in_cmd_size   == umi_in_cmd_size_r  ) &
                                (umi_in_cmd_qos    == umi_in_cmd_qos_r   ) &
                                (umi_in_cmd_prot   == umi_in_cmd_prot_r  ) &
                                (umi_in_cmd_eof    == umi_in_cmd_eof_r   ) &
                                (umi_in_cmd_user   == umi_in_cmd_user_r  ) &
                                (umi_in_cmd_err    == umi_in_cmd_err_r   ) &
                                (umi_in_cmd_hostid == umi_in_cmd_hostid_r) &
                                (umi_in_dstaddr    == umi_in_dstaddr_nx  ) &
                                (umi_in_srcaddr    == umi_in_srcaddr_nx  ) &
                                !umi_in_cmd_ex;

    assign umi_in_mergeable = umi_in_cmd_commit &
                              umi_in_opcode_check &
                              umi_in_field_match;

    assign umi_in_bytes = (1 << umi_in_cmd_size)*(umi_in_cmd_len + 1);

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            umi_in_mergeable_r <= 1'b0;
        else if (umi_in_cmd_commit)
            umi_in_mergeable_r <= umi_in_mergeable;
        else if (umi_in_cmd_commit_r)
            umi_in_mergeable_r <= 1'b0;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            umi_in_bytes_r <= 1'b0;
        else if (umi_in_cmd_commit)
            umi_in_bytes_r <= umi_in_bytes;
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            umi_in_dstaddr_nx <= 'b0;
            umi_in_srcaddr_nx <= 'b0;
        end
        else if (umi_in_cmd_commit) begin
            umi_in_dstaddr_nx <= umi_in_dstaddr + umi_in_bytes;
            umi_in_srcaddr_nx <= umi_in_srcaddr + umi_in_bytes;
        end
    end

    reg  [4:0]              umi_out_cmd_opcode_r;
    reg  [2:0]              umi_out_cmd_size_r;
    reg  [7:0]              umi_out_cmd_atype_r;
    reg  [3:0]              umi_out_cmd_qos_r;
    reg  [1:0]              umi_out_cmd_prot_r;
    reg                     umi_out_cmd_eom_r;
    reg                     umi_out_cmd_eof_r;
    reg                     umi_out_cmd_ex_r;
    reg  [1:0]              umi_out_cmd_user_r;
    reg  [23:0]             umi_out_cmd_user_extended_r;
    reg  [1:0]              umi_out_cmd_err_r;
    reg  [4:0]              umi_out_cmd_hostid_r;
    reg  [AW-1:0]           umi_out_dstaddr_r;
    reg  [AW-1:0]           umi_out_srcaddr_r;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            umi_out_cmd_opcode_r        <= 'b0;
            umi_out_cmd_size_r          <= 'b0;
            umi_out_cmd_atype_r         <= 'b0;
            umi_out_cmd_qos_r           <= 'b0;
            umi_out_cmd_prot_r          <= 'b0;
            umi_out_cmd_eom_r           <= 'b0;
            umi_out_cmd_eof_r           <= 'b0;
            umi_out_cmd_ex_r            <= 'b0;
            umi_out_cmd_user_r          <= 'b0;
            umi_out_cmd_user_extended_r <= 'b0;
            umi_out_cmd_err_r           <= 'b0;
            umi_out_cmd_hostid_r        <= 'b0;
            umi_out_dstaddr_r           <= 'b0;
            umi_out_srcaddr_r           <= 'b0;
        end
        else if (umi_in_cmd_commit_r) begin
            umi_out_cmd_opcode_r        <= umi_in_cmd_opcode_r;
            umi_out_cmd_size_r          <= umi_in_cmd_size_r;
            umi_out_cmd_atype_r         <= umi_in_cmd_atype_r;
            umi_out_cmd_qos_r           <= umi_in_cmd_qos_r;
            umi_out_cmd_prot_r          <= umi_in_cmd_prot_r;
            umi_out_cmd_eom_r           <= umi_in_cmd_eom_r;
            umi_out_cmd_eof_r           <= umi_in_cmd_eof_r;
            umi_out_cmd_ex_r            <= umi_in_cmd_ex_r;
            umi_out_cmd_user_r          <= umi_in_cmd_user_r;
            umi_out_cmd_user_extended_r <= umi_in_cmd_user_extended_r;
            umi_out_cmd_err_r           <= umi_in_cmd_err_r;
            umi_out_cmd_hostid_r        <= umi_in_cmd_hostid_r;

            if ((byte_counter == 0) | umi_out_cmd_commit) begin
                umi_out_dstaddr_r       <= umi_in_dstaddr_r;
                umi_out_srcaddr_r       <= umi_in_srcaddr_r;
            end
        end
    end

    assign umi_out_dstaddr  = umi_out_dstaddr_r;
    assign umi_out_srcaddr  = umi_out_srcaddr_r;
    assign umi_out_valid = ((!umi_in_mergeable_r | umi_out_cmd_eom_r) & |byte_counter) |
                           ((byte_counter + umi_in_bytes_r) > (ODW/8));

    reg [$clog2(ODW/8):0]   byte_counter;

    always @(posedge clk) begin
        if (~nreset) begin
            byte_counter <= 'b0;
        end
        else begin
            if (umi_in_cmd_commit_r & umi_out_cmd_commit)
                byte_counter <= umi_in_bytes_r;
            else if (umi_in_cmd_commit_r)
                byte_counter <= byte_counter + umi_in_bytes_r;
            else if (umi_out_cmd_commit)
                byte_counter <= 'b0;
        end
    end

    wire [ODW-1:0]  umi_in_data_masked;
    reg  [ODW-1:0]  umi_out_data_r;

    assign umi_in_data_masked = umi_in_data_r & ((1 << (umi_in_bytes_r*8))-1);

    always @(posedge clk) begin
        if (~nreset) begin
            umi_out_data_r <= 'b0;
        end
        else begin
            if (umi_out_cmd_commit & umi_in_cmd_commit_r)
                umi_out_data_r <= umi_in_data_masked;
            else if (umi_in_cmd_commit_r)
                umi_out_data_r <= umi_out_data_r | (umi_in_data_masked << (byte_counter*8));
            else if (umi_out_cmd_commit)
                umi_out_data_r <= 'b0;
        end
    end

    wire [7:0]              umi_out_cmd_len_m;

    assign umi_out_cmd_len_m = (byte_counter >> umi_out_cmd_size_r) - 1;

    umi_pack #(
        .CW                 (CW)
    ) umi_pack_i (
        // Command inputs
        .cmd_opcode         (umi_out_cmd_opcode_r),
        .cmd_size           (umi_out_cmd_size_r),
        .cmd_len            (umi_out_cmd_len_m),
        .cmd_atype          (umi_out_cmd_atype_r),
        .cmd_qos            (umi_out_cmd_qos_r),
        .cmd_prot           (umi_out_cmd_prot_r),
        .cmd_eom            (umi_out_cmd_eom_r),
        .cmd_eof            (umi_out_cmd_eof_r),
        .cmd_ex             (umi_out_cmd_ex_r),
        .cmd_user           (umi_out_cmd_user_r),
        .cmd_user_extended  (umi_out_cmd_user_extended_r),
        .cmd_err            (umi_out_cmd_err_r),
        .cmd_hostid         (umi_out_cmd_hostid_r),

        // Output packet
        .packet_cmd         (umi_out_cmd)
    );

    assign umi_out_data = umi_out_data_r;

endmodule
