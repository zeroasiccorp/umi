`default_nettype wire

module umi_data_aggregator #(
    parameter CW    = 32,   // command width
    parameter AW    = 64,   // address width
    parameter DW    = 64    // data width
)
(
    input               clk,
    input               nreset,

    input               umi_in_valid,
    input  [CW-1:0]     umi_in_cmd,
    input  [AW-1:0]     umi_in_dstaddr,
    input  [AW-1:0]     umi_in_srcaddr,
    input  [DW-1:0]     umi_in_data,
    output              umi_in_ready,

    output              umi_out_valid,
    output [CW-1:0]     umi_out_cmd,
    output [AW-1:0]     umi_out_dstaddr,
    output [AW-1:0]     umi_out_srcaddr,
    output [DW-1:0]     umi_out_data,
    input               umi_out_ready
);

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

    reg  [4:0]      umi_in_cmd_opcode_r;
    reg  [2:0]      umi_in_cmd_size_r;
    wire [7:0]      umi_in_cmd_len_m;
    reg  [7:0]      umi_in_cmd_atype_r;
    reg  [3:0]      umi_in_cmd_qos_r;
    reg  [1:0]      umi_in_cmd_prot_r;
    reg             umi_in_cmd_eom_r;
    reg             umi_in_cmd_eof_r;
    reg             umi_in_cmd_ex_r;
    reg  [1:0]      umi_in_cmd_user_r;
    reg  [23:0]     umi_in_cmd_user_extended_r;
    reg  [1:0]      umi_in_cmd_err_r;
    reg  [4:0]      umi_in_cmd_hostid_r;

    reg [AW-1:0]    umi_in_dstaddr_r;
    reg [AW-1:0]    umi_in_srcaddr_r;
    reg [2*DW-1:0]  umi_in_data_r;

    reg             umi_in_cmd_passthrough;

    reg             first;
    wire            umi_in_cmd_commit;
    wire            umi_in_opcode_check;
    wire            umi_in_field_match;
    wire            umi_in_mergeable;

    assign umi_in_cmd_commit = umi_in_ready && umi_in_valid;

    assign umi_in_opcode_check = umi_in_cmd_read ||
                                 umi_in_cmd_write ||
                                 umi_in_cmd_write_posted ||
                                 umi_in_cmd_rdma ||
                                 umi_in_cmd_read_resp;

    assign umi_in_field_match = first ||
                               ((umi_in_cmd_opcode == umi_in_cmd_opcode_r) &&
                                (umi_in_cmd_size   == umi_in_cmd_size_r  ) &&
                                (umi_in_cmd_qos    == umi_in_cmd_qos_r   ) &&
                                (umi_in_cmd_prot   == umi_in_cmd_prot_r  ) &&
                                (umi_in_cmd_eof    == umi_in_cmd_eof_r   ) &&
                                (umi_in_cmd_user   == umi_in_cmd_user_r  ) &&
                                (umi_in_cmd_err    == umi_in_cmd_err_r   ) &&
                                (umi_in_cmd_hostid == umi_in_cmd_hostid_r) &&
                                !umi_in_cmd_ex);

    assign umi_in_mergeable = umi_in_cmd_commit &&
                              umi_in_opcode_check &&
                              umi_in_field_match;

    // For flits except the last flit in a message, first is set to 0
    // Last flit in message sets first to 1
    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            first <= 1'b1;
        end
        else begin
            if (umi_in_cmd_commit)
                first <= (umi_in_cmd_eom || umi_in_cmd_write_resp);
        end
    end

    assign umi_out_dstaddr  = umi_in_dstaddr_r;
    assign umi_out_srcaddr  = umi_in_srcaddr_r;

    reg [$clog2(DW/8)+1:0]  byte_counter;
    /* verilator lint_off WIDTHTRUNC */
    localparam [$clog2(DW/8)+1:0]   DW_BYTES = DW/8;
    /* verilator lint_on WIDTHTRUNC */

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            umi_in_cmd_opcode_r         <= 'b0;
            umi_in_cmd_size_r           <= 'b0;
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
        else begin

            if (first && umi_in_cmd_commit) begin
                umi_in_cmd_opcode_r         <= umi_in_cmd_opcode;
                umi_in_cmd_size_r           <= umi_in_cmd_size;
                umi_in_cmd_atype_r          <= umi_in_cmd_atype;
                umi_in_cmd_qos_r            <= umi_in_cmd_qos;
                umi_in_cmd_prot_r           <= umi_in_cmd_prot;
                umi_in_cmd_eof_r            <= umi_in_cmd_eof;
                umi_in_cmd_ex_r             <= umi_in_cmd_ex;
                umi_in_cmd_user_r           <= umi_in_cmd_user;
                umi_in_cmd_user_extended_r  <= umi_in_cmd_user_extended;
                umi_in_cmd_err_r            <= umi_in_cmd_err;
                umi_in_cmd_hostid_r         <= umi_in_cmd_hostid;
                umi_in_dstaddr_r            <= umi_in_dstaddr;
                umi_in_srcaddr_r            <= umi_in_srcaddr;
            end

            if (umi_in_cmd_eom && umi_in_cmd_commit) begin
                umi_in_cmd_eom_r <= 1'b1;
            end
            else if (byte_counter == 0) begin
                umi_in_cmd_eom_r <= 1'b0;
            end

            if ((umi_in_cmd_eom || !umi_in_mergeable) && umi_in_cmd_commit) begin
                umi_in_cmd_passthrough <= 1'b1;
            end
            else if (byte_counter == 0) begin
                umi_in_cmd_passthrough <= 1'b0;
            end
        end
    end

    wire                    umi_out_cmd_commit;
    wire [$clog2(DW/8):0]   umi_in_bytes;

    assign umi_in_ready = (umi_out_ready || (byte_counter <= DW_BYTES)) && !umi_in_cmd_passthrough;
    assign umi_out_valid = (umi_in_cmd_passthrough && |byte_counter) || (byte_counter >= DW_BYTES);
    assign umi_out_cmd_commit = umi_out_ready && umi_out_valid;
    /* verilator lint_off WIDTHTRUNC */
    assign umi_in_bytes = (1 << umi_in_cmd_size)*(umi_in_cmd_len + 1);
    /* verilator lint_on WIDTHTRUNC */

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            byte_counter <= 'b0;
        end
        else begin
            if (umi_in_cmd_commit && umi_out_cmd_commit) begin
                if (byte_counter < DW_BYTES) begin
                    byte_counter <= {1'b0, umi_in_bytes};
                end
                else begin
                    byte_counter <= byte_counter + {1'b0, umi_in_bytes} - DW_BYTES;
                end
            end
            else if (umi_in_cmd_commit) begin
                byte_counter <= byte_counter + {1'b0, umi_in_bytes};
            end
            else if (umi_out_cmd_commit) begin
                if (byte_counter < DW_BYTES) begin
                    byte_counter <= 'b0;
                end
                else begin
                    byte_counter <= byte_counter - DW_BYTES;
                end
            end
        end
    end

    wire [DW-1:0]   umi_in_data_masked;

    assign umi_in_data_masked = umi_in_data & ((1 << (umi_in_bytes*8))-1);

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            umi_in_data_r <= 'b0;
        end
        else begin
            if (first && umi_in_cmd_commit) begin
                umi_in_data_r <= {{DW{1'b0}}, umi_in_data_masked};
            end
            else if (umi_in_cmd_commit && umi_out_cmd_commit) begin
                /* verilator lint_off WIDTHEXPAND */
                umi_in_data_r <= (umi_in_data_r >> DW) | (umi_in_data_masked << ((byte_counter - DW_BYTES)*8));
                /* verilator lint_on WIDTHEXPAND */
            end
            else if (umi_in_cmd_commit) begin
                /* verilator lint_off WIDTHEXPAND */
                umi_in_data_r <= umi_in_data_r | (umi_in_data_masked << (byte_counter*8));
                /* verilator lint_on WIDTHEXPAND */
            end
            else if (umi_out_cmd_commit) begin
                umi_in_data_r <= umi_in_data_r >> DW;
            end
        end
    end

    /* verilator lint_off WIDTHEXPAND */
    assign umi_in_cmd_len_m = (byte_counter > DW_BYTES) ?
                              ((DW_BYTES >> umi_in_cmd_size_r) - 1) :
                              ((byte_counter >> umi_in_cmd_size_r) - 1);
    /* verilator lint_on WIDTHEXPAND */

    umi_pack #(
        .CW                 (CW)
    ) umi_pack_i (
        // Command inputs
        .cmd_opcode         (umi_in_cmd_opcode_r),
        .cmd_size           (umi_in_cmd_size_r),
        .cmd_len            (umi_in_cmd_len_m),
        .cmd_atype          (umi_in_cmd_atype_r),
        .cmd_qos            (umi_in_cmd_qos_r),
        .cmd_prot           (umi_in_cmd_prot_r),
        .cmd_eom            (umi_in_cmd_eom_r && (byte_counter <= DW_BYTES)),
        .cmd_eof            (umi_in_cmd_eof_r),
        .cmd_ex             (umi_in_cmd_ex_r),
        .cmd_user           (umi_in_cmd_user_r),
        .cmd_user_extended  (umi_in_cmd_user_extended_r),
        .cmd_err            (umi_in_cmd_err_r),
        .cmd_hostid         (umi_in_cmd_hostid_r),

        // Output packet
        .packet_cmd         (umi_out_cmd)
    );

    assign umi_out_data = umi_in_data_r[0+:DW];

endmodule
