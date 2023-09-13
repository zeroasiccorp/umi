/******************************************************************************
 * Function:  UMI address remap
 * Author:    Aliasger Zaidy
 * Copyright: 2023 Zero ASIC Corporation. All rights reserved.
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * Documentation:
 * This module remaps UMI transactions across different memory regions.
 *****************************************************************************/

`timescale 1ns / 1ps
`default_nettype wire

module umi_address_remap #(
    parameter CW    = 32,   // command width
    parameter AW    = 64,   // address width
    parameter DW    = 128,  // data width
    parameter IDW   = 16,   // id width
    parameter NMAPS = 8     // number of remaps
)
(
    input  [IDW-1:0]        chipid,

    input  [IDW*NMAPS-1:0]  old_row_col_address,
    input  [IDW*NMAPS-1:0]  new_row_col_address,

    input  [39:0]           set_dstaddress_offset,
    input  [39:0]           set_dstaddress_high,
    input  [39:0]           set_dstaddress_low,

    input                   umi_in_valid,
    input  [CW-1:0]         umi_in_cmd,
    input  [AW-1:0]         umi_in_dstaddr,
    input  [AW-1:0]         umi_in_srcaddr,
    input  [DW-1:0]         umi_in_data,
    output                  umi_in_ready,

    output                  umi_out_valid,
    output [CW-1:0]         umi_out_cmd,
    output [AW-1:0]         umi_out_dstaddr,
    output [AW-1:0]         umi_out_srcaddr,
    output [DW-1:0]         umi_out_data,
    input                   umi_out_ready
);

    wire [IDW-1:0]  old_row_col_address_unpack [0:NMAPS-1];
    wire [IDW-1:0]  new_row_col_address_unpack [0:NMAPS-1];

    genvar i;
    generate
        for (i = 0; i < NMAPS; i = i + 1) begin
            assign old_row_col_address_unpack[i] = old_row_col_address[(IDW*(i+1))-1 : (IDW*i)];
            assign new_row_col_address_unpack[i] = new_row_col_address[(IDW*(i+1))-1 : (IDW*i)];
        end
    endgenerate

    reg [IDW-1:0] dstaddr_upper;

    always @(*) begin
        if (umi_in_dstaddr[55:40] == chipid) begin
            dstaddr_upper = chipid;
        end
        else begin
            case (umi_in_dstaddr[55:40])
                old_row_col_address_unpack[0] : dstaddr_upper = new_row_col_address_unpack[0];
                old_row_col_address_unpack[1] : dstaddr_upper = new_row_col_address_unpack[1];
                old_row_col_address_unpack[2] : dstaddr_upper = new_row_col_address_unpack[2];
                old_row_col_address_unpack[3] : dstaddr_upper = new_row_col_address_unpack[3];
                old_row_col_address_unpack[4] : dstaddr_upper = new_row_col_address_unpack[4];
                old_row_col_address_unpack[5] : dstaddr_upper = new_row_col_address_unpack[5];
                old_row_col_address_unpack[6] : dstaddr_upper = new_row_col_address_unpack[6];
                old_row_col_address_unpack[7] : dstaddr_upper = new_row_col_address_unpack[7];
                default                       : dstaddr_upper = umi_in_dstaddr[55:40];
            endcase
        end
    end

    reg [39:0] dstaddr_lower;

    always @(*) begin
        if ((umi_in_dstaddr[39:0] >= set_dstaddress_low) &
            (umi_in_dstaddr[39:0] <= set_dstaddress_high))
            dstaddr_lower = umi_in_dstaddr[39:0] - set_dstaddress_offset;
        else
            dstaddr_lower = umi_in_dstaddr[39:0];
    end

    assign umi_out_valid    = umi_in_valid;
    assign umi_out_cmd      = umi_in_cmd;
    assign umi_out_dstaddr  = {umi_in_dstaddr[63:56], dstaddr_upper, dstaddr_lower};
    assign umi_out_srcaddr  = umi_in_srcaddr;
    assign umi_out_data     = umi_in_data;
    assign umi_in_ready     = umi_out_ready;

endmodule
