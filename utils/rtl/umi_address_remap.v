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
 * The module introduces a new parameter called IDSB which denotes the bit at
 * which the chip ID starts in a umi address. This parameter can also be
 * considered as the per ebrick/clink address space. For example, in a 64 bit
 * address space, IDSB is 40 - along with IDW = 16, this mean the chip ID
 * resides between IDSB + IDW - 1 to IDSB i.e. bits 55:40. Additionally, one
 * can also infer that the addresses within a clink/umi connected device is
 * 40 bits wide i.e. a memory space of 1 TiB.

 * Limitation:
 * NMAPS parameterization is incomplete
 * Currently NMAPS < 8 will fail and NMAPS > 8 will not have the desired effect
 * beyond 8 remappings.
 *****************************************************************************/

`timescale 1ns / 1ps
`default_nettype wire

module umi_address_remap #(
    parameter CW    = 32,   // command width
    parameter AW    = 64,   // address width
    parameter DW    = 128,  // data width
    parameter IDW   = 16,   // id width
    parameter IDSB  = 40,   // id start bit - bit 40 in 64 bit address space
    parameter NMAPS = 8     // number of remaps
)
(
    input  [IDW-1:0]        chipid,

    input  [IDW*NMAPS-1:0]  old_row_col_address,
    input  [IDW*NMAPS-1:0]  new_row_col_address,

    input  [IDSB-1:0]       set_dstaddress_offset,
    input  [IDSB-1:0]       set_dstaddress_high,
    input  [IDSB-1:0]       set_dstaddress_low,

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
        if (umi_in_dstaddr[(IDSB+IDW-1):IDSB] == chipid) begin
            dstaddr_upper = chipid;
        end
        else begin
            // FIXME: Parameterize this
            case (umi_in_dstaddr[(IDSB+IDW-1):IDSB])
                old_row_col_address_unpack[0] : dstaddr_upper = new_row_col_address_unpack[0];
                old_row_col_address_unpack[1] : dstaddr_upper = new_row_col_address_unpack[1];
                old_row_col_address_unpack[2] : dstaddr_upper = new_row_col_address_unpack[2];
                old_row_col_address_unpack[3] : dstaddr_upper = new_row_col_address_unpack[3];
                old_row_col_address_unpack[4] : dstaddr_upper = new_row_col_address_unpack[4];
                old_row_col_address_unpack[5] : dstaddr_upper = new_row_col_address_unpack[5];
                old_row_col_address_unpack[6] : dstaddr_upper = new_row_col_address_unpack[6];
                old_row_col_address_unpack[7] : dstaddr_upper = new_row_col_address_unpack[7];
                default                       : dstaddr_upper = umi_in_dstaddr[(IDSB+IDW-1):IDSB];
            endcase
        end
    end

    reg [IDSB-1:0]  dstaddr_lower;

    always @(*) begin
        if ((umi_in_dstaddr[IDSB-1:0] >= set_dstaddress_low) &
            (umi_in_dstaddr[IDSB-1:0] <= set_dstaddress_high))
            dstaddr_lower = umi_in_dstaddr[IDSB-1:0] - set_dstaddress_offset;
        else
            dstaddr_lower = umi_in_dstaddr[IDSB-1:0];
    end

    assign umi_out_valid    = umi_in_valid;
    assign umi_out_cmd      = umi_in_cmd;
    assign umi_out_dstaddr  = ((IDSB+IDW) < AW) ?
                              {umi_in_dstaddr[AW-1:IDSB+IDW], dstaddr_upper, dstaddr_lower} :
                              {dstaddr_upper, dstaddr_lower};
    assign umi_out_srcaddr  = umi_in_srcaddr;
    assign umi_out_data     = umi_in_data;
    assign umi_in_ready     = umi_out_ready;

endmodule
