/******************************************************************************
 * Function:  UMI to TL-UH converter
 * Author:    Aliasger Zaidy
 * Copyright: 2023 Zero ASIC Corporation. All rights reserved.
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * Documentation:
 *****************************************************************************/
`default_nettype none
`include "tl-uh.vh"

module umi2tl_np #(
    parameter CW    = 32,   // UMI command width
    parameter AW    = 64,   // UMI address width
    parameter IDW   = 128,  // UMI data width
    parameter ODW   = 64    // TileLink data width
)
(
    input  wire             clk,
    input  wire             nreset,

    // TileLink
    input  wire             tl_a_ready,
    output wire             tl_a_valid,
    output wire [2:0]       tl_a_opcode,
    output wire [2:0]       tl_a_param,
    output wire [2:0]       tl_a_size,
    output wire [3:0]       tl_a_source,
    output wire [55:0]      tl_a_address,
    output wire [7:0]       tl_a_mask,
    output wire [ODW-1:0]   tl_a_data,
    output wire             tl_a_corrupt,

    output wire             tl_d_ready,
    input  wire             tl_d_valid,
    input  wire [2:0]       tl_d_opcode,
    input  wire [1:0]       tl_d_param,
    input  wire [2:0]       tl_d_size,
    input  wire [3:0]       tl_d_source,
    input  wire             tl_d_sink,
    input  wire             tl_d_denied,
    input  wire [ODW-1:0]   tl_d_data,
    input  wire             tl_d_corrupt,

    // Device port (per clink)
    input  wire             udev_req_valid,
    input  wire [CW-1:0]    udev_req_cmd,
    input  wire [AW-1:0]    udev_req_dstaddr,
    input  wire [AW-1:0]    udev_req_srcaddr,
    input  wire [IDW-1:0]   udev_req_data,
    output wire             udev_req_ready,

    output wire             udev_resp_valid,
    output wire [CW-1:0]    udev_resp_cmd,
    output wire [AW-1:0]    udev_resp_dstaddr,
    output wire [AW-1:0]    udev_resp_srcaddr,
    output wire [IDW-1:0]   udev_resp_data,
    input  wire             udev_resp_ready
);

    `include "umi_messages.vh"

    reg [1:0]   reset_done;

    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            reset_done <= 2'b00;
        else
            reset_done <= {reset_done[0], 1'b1};
    end

    // Split incoming command into ODW sizes
    // FIXME: It is assumed that incoming transactions are powers of 2
    // Hence, if a transaction is unaligned, it means transaction is smaller
    // than ODW bits. This needs to be fixed.
    wire            fifoflex_out_req_valid;
    wire [CW-1:0]   fifoflex_out_req_cmd;
    wire [AW-1:0]   fifoflex_out_req_dstaddr;
    wire [AW-1:0]   fifoflex_out_req_srcaddr;
    wire [ODW-1:0]  fifoflex_out_req_data;
    wire            fifoflex_out_req_ready;

    umi_fifo_flex #(.TARGET         ("DEFAULT"),
                    .ASYNC          (0),
                    .DEPTH          (0),
                    .CW             (CW),
                    .AW             (AW),
                    .IDW            (IDW),
                    .ODW            (ODW)
    ) umi2tl_req_fifo_flex (
        .bypass         (1'b1),
        .chaosmode      (1'b0),
        .fifo_full      (),
        .fifo_empty     (),

        // Input
        .umi_in_clk     (clk),
        .umi_in_nreset  (nreset),
        .umi_in_valid   (udev_req_valid),
        .umi_in_cmd     (udev_req_cmd),
        .umi_in_dstaddr (udev_req_dstaddr),
        .umi_in_srcaddr (udev_req_srcaddr),
        .umi_in_data    (udev_req_data),
        .umi_in_ready   (udev_req_ready),

        // Output
        .umi_out_clk    (clk),
        .umi_out_nreset (nreset),
        .umi_out_valid  (fifoflex_out_req_valid),
        .umi_out_cmd    (fifoflex_out_req_cmd),
        .umi_out_dstaddr(fifoflex_out_req_dstaddr),
        .umi_out_srcaddr(fifoflex_out_req_srcaddr),
        .umi_out_data   (fifoflex_out_req_data),
        .umi_out_ready  (fifoflex_out_req_ready),

        // Supplies
        .vdd            (1'b1),
        .vss            (1'b0)
    );

    // Unpack command from fifoflex
    wire [4:0]  fifoflex_out_req_cmd_opcode;
    wire [2:0]  fifoflex_out_req_cmd_size;
    wire [7:0]  fifoflex_out_req_cmd_len;
    wire [7:0]  fifoflex_out_req_cmd_atype;
    wire [3:0]  fifoflex_out_req_cmd_qos;
    wire [1:0]  fifoflex_out_req_cmd_prot;
    wire        fifoflex_out_req_cmd_eom;
    wire        fifoflex_out_req_cmd_eof;
    wire        fifoflex_out_req_cmd_ex;
    wire [1:0]  fifoflex_out_req_cmd_user;
    wire [23:0] fifoflex_out_req_cmd_user_extended;
    wire [1:0]  fifoflex_out_req_cmd_err;
    wire [4:0]  fifoflex_out_req_cmd_hostid;

    umi_unpack #(
        .CW     (CW)
    ) umi2tl_req_unpack (
        // Input CMD
        .packet_cmd         (fifoflex_out_req_cmd),

        // Output Fields
        .cmd_opcode         (fifoflex_out_req_cmd_opcode),
        .cmd_size           (fifoflex_out_req_cmd_size),
        .cmd_len            (fifoflex_out_req_cmd_len),
        .cmd_atype          (fifoflex_out_req_cmd_atype),
        .cmd_qos            (fifoflex_out_req_cmd_qos),
        .cmd_prot           (fifoflex_out_req_cmd_prot),
        .cmd_eom            (fifoflex_out_req_cmd_eom),
        .cmd_eof            (fifoflex_out_req_cmd_eof),
        .cmd_ex             (fifoflex_out_req_cmd_ex),
        .cmd_user           (fifoflex_out_req_cmd_user),
        .cmd_user_extended  (fifoflex_out_req_cmd_user_extended),
        .cmd_err            (fifoflex_out_req_cmd_err),
        .cmd_hostid         (fifoflex_out_req_cmd_hostid)
    );

    // Calculate byte shift needed
    wire [$clog2(ODW/8):0] req_bytes = (1 << fifoflex_out_req_cmd_size)*(fifoflex_out_req_cmd_len + 1);

    reg [2:0]   masked_shift;
    reg [2:0]   masked_tl_a_size;
    reg [7:0]   masked_tl_a_mask;

    always @(*) begin
        if (req_bytes == 8)  begin
            masked_shift = 3'b0;
            masked_tl_a_size = 3'd3;
            masked_tl_a_mask = 8'd255;
        end
        else if (req_bytes == 4)  begin
            masked_shift = {fifoflex_out_req_dstaddr[2], 2'b0};
            masked_tl_a_size = 3'd2;
            masked_tl_a_mask = 8'd15;
        end
        else if (req_bytes == 2)  begin
            masked_shift = {fifoflex_out_req_dstaddr[2:1], 1'b0};
            masked_tl_a_size = 3'd1;
            masked_tl_a_mask = 8'd3;
        end
        else if (req_bytes == 1)  begin
            masked_shift = fifoflex_out_req_dstaddr[2:0];
            masked_tl_a_size = 3'd1;
            masked_tl_a_mask = 8'd1;
        end
        else begin
            masked_shift = 3'b0;
            masked_tl_a_size = 3'd0;
            masked_tl_a_mask = 8'd0;
        end
    end

    reg             tl_a_valid_r;
    reg  [2:0]      tl_a_opcode_r;
    reg  [2:0]      tl_a_param_r;
    reg  [2:0]      tl_a_size_r;
    reg  [3:0]      tl_a_source_r;
    reg  [55:0]     tl_a_address_r;
    reg  [7:0]      tl_a_mask_r;
    reg  [ODW-1:0]  tl_a_data_r;

    assign tl_a_valid = tl_a_valid_r;
    assign tl_a_opcode = tl_a_opcode_r;
    assign tl_a_param = tl_a_param_r;
    assign tl_a_size = tl_a_size_r;
    assign tl_a_source = tl_a_source_r;
    assign tl_a_address = tl_a_address_r;
    assign tl_a_mask = tl_a_mask_r;
    assign tl_a_data = tl_a_data_r;
    assign tl_a_corrupt = 1'b0;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            tl_a_valid_r <= 1'b0;
        end
        else begin
            if (fifoflex_out_req_ready & fifoflex_out_req_valid) begin
                tl_a_valid_r <= 1'b1;
            end
            else if (tl_a_ready & tl_a_valid) begin
                tl_a_valid_r <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            tl_a_size_r    <= 'b0;
            tl_a_source_r  <= 'b0;
            tl_a_address_r <= 'b0;
            tl_a_mask_r    <= 'b0;
            tl_a_data_r    <= 'b0;
        end
        else begin
            if (fifoflex_out_req_ready & fifoflex_out_req_valid) begin
                tl_a_size_r    <= masked_tl_a_size;
                tl_a_source_r  <= 'b0;
                tl_a_address_r <= {fifoflex_out_req_dstaddr[55:3], 3'd0};
                tl_a_mask_r    <= masked_tl_a_mask << masked_shift;
                tl_a_data_r    <= fifoflex_out_req_data << (masked_shift*8);
            end
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            tl_a_opcode_r <= 'b0;
        end
        else begin
            if (fifoflex_out_req_ready & fifoflex_out_req_valid) begin
                case (fifoflex_out_req_cmd_opcode)
                    UMI_REQ_READ:   tl_a_opcode_r <= `TL_OP_Get;
                    UMI_REQ_WRITE:  tl_a_opcode_r <= `TL_OP_PutFullData;
                    // UMI_REQ_POSTED: tl_a_opcode_r <= `TL_OP_PutFullData;
                    UMI_REQ_ATOMIC: begin
                        if ((fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICADD)  |
                            (fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICMAX)  |
                            (fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICMIN)  |
                            (fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICMAXU) |
                            (fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICMINU)) begin
                            tl_a_opcode_r <= `TL_OP_ArithmeticData;
                        end
                        else if ((fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICAND) |
                                 (fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICOR)  |
                                 (fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICXOR) |
                                 (fifoflex_out_req_cmd_atype == UMI_REQ_ATOMICSWAP)) begin
                            tl_a_opcode_r <= `TL_OP_LogicalData;
                        end
                    end
                    default: begin
                    `ifndef SYNTHESIS
                        $display("[UMI2TL]: Unsupported UMI Request");
                    `endif
                    end
                endcase
            end
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            tl_a_param_r <= 'b0;
        end
        else begin
            if (fifoflex_out_req_ready & fifoflex_out_req_valid) begin
                if (fifoflex_out_req_cmd_opcode == UMI_REQ_ATOMIC) begin
                    case (fifoflex_out_req_cmd_atype)
                        UMI_REQ_ATOMICADD:  tl_a_param_r <= `TL_PA_ADD;
                        UMI_REQ_ATOMICAND:  tl_a_param_r <= `TL_PL_AND;
                        UMI_REQ_ATOMICOR:   tl_a_param_r <= `TL_PL_OR;
                        UMI_REQ_ATOMICXOR:  tl_a_param_r <= `TL_PL_XOR;
                        UMI_REQ_ATOMICMAX:  tl_a_param_r <= `TL_PA_MAX;
                        UMI_REQ_ATOMICMIN:  tl_a_param_r <= `TL_PA_MIN;
                        UMI_REQ_ATOMICMAXU: tl_a_param_r <= `TL_PA_MAXU;
                        UMI_REQ_ATOMICMINU: tl_a_param_r <= `TL_PA_MINU;
                        UMI_REQ_ATOMICSWAP: tl_a_param_r <= `TL_PL_SWAP;
                        default: begin
                        `ifndef SYNTHESIS
                            $display("[UMI2TL]: Unsupported UMI Atomic");
                        `endif
                        end
                    endcase
                end
                else begin
                    tl_a_param_r    <= 'b0;
                end
            end
        end
    end

    // Save metadata to use with response
    reg  [CW-1:0]           fifoflex_out_req_cmd_r;
    reg  [AW-1:0]           fifoflex_out_req_dstaddr_r;
    reg  [AW-1:0]           fifoflex_out_req_srcaddr_r;
    reg  [2:0]              masked_shift_r;

    reg                     tl_transaction_in_flight;
    reg                     tl_transaction_done;

    assign fifoflex_out_req_ready = reset_done[1] & ~tl_transaction_in_flight;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            fifoflex_out_req_cmd_r     <= 'b0;
            fifoflex_out_req_dstaddr_r <= 'b0;
            fifoflex_out_req_srcaddr_r <= 'b0;
            masked_shift_r             <= 'b0;
        end
        else begin
            if (fifoflex_out_req_ready & fifoflex_out_req_valid) begin
                fifoflex_out_req_cmd_r     <= fifoflex_out_req_cmd;
                fifoflex_out_req_dstaddr_r <= fifoflex_out_req_dstaddr;
                fifoflex_out_req_srcaddr_r <= fifoflex_out_req_srcaddr;
                masked_shift_r             <= masked_shift;
            end
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            tl_transaction_in_flight <= 1'b0;
        end
        else begin
            if (fifoflex_out_req_ready & fifoflex_out_req_valid) begin
                tl_transaction_in_flight <= 1'b1;
            end
            else if (tl_transaction_done) begin
                tl_transaction_in_flight <= 1'b0;
            end
        end
    end

    // Unpack request command to forward to response`
    wire [4:0]      req2resp_cmd_opcode;
    wire [2:0]      req2resp_cmd_size;
    wire [7:0]      req2resp_cmd_len;
    wire [7:0]      req2resp_cmd_atype;
    wire [3:0]      req2resp_cmd_qos;
    wire [1:0]      req2resp_cmd_prot;
    wire            req2resp_cmd_eom;
    wire            req2resp_cmd_eof;
    wire            req2resp_cmd_ex;
    wire [1:0]      req2resp_cmd_user;
    wire [23:0]     req2resp_cmd_user_extended;
    wire [1:0]      req2resp_cmd_err;
    wire [4:0]      req2resp_cmd_hostid;

    reg             udev_resp_valid_r;
    reg  [4:0]      udev_resp_cmd_opcode_r;
    reg  [AW-1:0]   udev_resp_dstaddr_r;
    reg  [AW-1:0]   udev_resp_srcaddr_r;
    reg  [IDW-1:0]  udev_resp_data_r;

    assign udev_resp_valid = udev_resp_valid_r;
    assign udev_resp_dstaddr = udev_resp_dstaddr_r;
    assign udev_resp_srcaddr = udev_resp_srcaddr_r;
    assign udev_resp_data = udev_resp_data_r;

    umi_unpack #(
        .CW     (CW)
    ) umi2tl_req2resp_unpack (
        // Input CMD
        .packet_cmd         (fifoflex_out_req_cmd_r),

        // Output Fields
        .cmd_opcode         (req2resp_cmd_opcode),
        .cmd_size           (req2resp_cmd_size),
        .cmd_len            (req2resp_cmd_len),
        .cmd_atype          (req2resp_cmd_atype),
        .cmd_qos            (req2resp_cmd_qos),
        .cmd_prot           (req2resp_cmd_prot),
        .cmd_eom            (req2resp_cmd_eom),
        .cmd_eof            (req2resp_cmd_eof),
        .cmd_ex             (req2resp_cmd_ex),
        .cmd_user           (req2resp_cmd_user),
        .cmd_user_extended  (req2resp_cmd_user_extended),
        .cmd_err            (req2resp_cmd_err),
        .cmd_hostid         (req2resp_cmd_hostid)
    );

    umi_pack #(
        .CW                 (CW)
    ) umi2tl_req2resp_pack (
        .cmd_opcode         (udev_resp_cmd_opcode_r),
        .cmd_size           (req2resp_cmd_size),
        .cmd_len            (req2resp_cmd_len),
        .cmd_atype          (req2resp_cmd_atype),
        .cmd_qos            (req2resp_cmd_qos),
        .cmd_prot           (req2resp_cmd_prot),
        .cmd_eom            (req2resp_cmd_eom),
        .cmd_eof            (req2resp_cmd_eof),
        .cmd_ex             (req2resp_cmd_ex),
        .cmd_user           (req2resp_cmd_user),
        .cmd_user_extended  (req2resp_cmd_user_extended),
        .cmd_err            (req2resp_cmd_err),
        .cmd_hostid         (req2resp_cmd_hostid),

        .packet_cmd         (udev_resp_cmd)
    );

    assign tl_d_ready = reset_done[1] &
                        (~udev_resp_valid | udev_resp_ready);

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            udev_resp_valid_r <= 1'b0;
        end
        else begin
            if (tl_d_ready & tl_d_valid & (req2resp_cmd_opcode != UMI_REQ_POSTED)) begin
                udev_resp_valid_r <= 1'b1;
            end
            else if (udev_resp_ready & udev_resp_valid) begin
                udev_resp_valid_r <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            udev_resp_dstaddr_r <= 'b0;
            udev_resp_srcaddr_r <= 'b0;
        end
        else if (tl_d_ready & tl_d_valid) begin
                udev_resp_dstaddr_r <= fifoflex_out_req_srcaddr_r;
                udev_resp_srcaddr_r <= fifoflex_out_req_dstaddr_r;
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            udev_resp_data_r <= 'b0;
        end
        else if (tl_d_ready & tl_d_valid) begin
            udev_resp_data_r <= tl_d_data >> (masked_shift_r*8);
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            udev_resp_cmd_opcode_r <= 'b0;
        end
        else if (tl_d_ready & tl_d_valid) begin
            case (tl_d_opcode)
                `TL_OP_AccessAck:       udev_resp_cmd_opcode_r <= UMI_RESP_WRITE;
                `TL_OP_AccessAckData:   udev_resp_cmd_opcode_r <= UMI_RESP_READ;
                default: begin
                `ifndef SYNTHESIS
                    $display("[UMI2TL]: Unsupported TileLink Response");
                `endif
                end
            endcase
        end
    end

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            tl_transaction_done <= 1'b0;
        end
        else begin
            tl_transaction_done <= udev_resp_ready & udev_resp_valid;
        end
    end

endmodule

`default_nettype wire
