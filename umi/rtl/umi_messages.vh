/*******************************************************************************
 * Function:  UMI Opcodes
 * Author:    Andreas Olofsson
 *
 * Copyright (c) 2023 Zero ASIC Corporation
 * This code is licensed under Apache License 2.0 (see LICENSE for details)
 *
 * Documentation:
 *
 * This file defines all UMI commands.
 * command[7:4] is used for non-functional
 *
 * This file describes the standard opcodes for umi transactions.
 *
 * opcode[3:0] dictates transaction types
 * opcode[7:4] is used for hints and transaction options.
 *
 ******************************************************************************/

localparam UMI_INVALID         = 8'h00;

// Requests (host -> device)
localparam UMI_REQ_READ        = 5'h01; // read/load
localparam UMI_REQ_WRITE       = 5'h03; // write/store with ack
localparam UMI_REQ_POSTED      = 5'h05;
localparam UMI_REQ_RDMA        = 5'h07;
localparam UMI_REQ_ATOMIC      = 5'h09; // alias for all atomics
localparam UMI_REQ_USER0       = 5'h0B;
localparam UMI_REQ_FUTURE0     = 5'h0D;
localparam UMI_REQ_ERROR       = 8'h0F;
localparam UMI_REQ_LINK        = 8'h2F;
// Response (device -> host)
localparam UMI_RESP_READ       = 5'h02; // response to read request
localparam UMI_RESP_WRITE      = 5'h04; // response (ack) from write request
localparam UMI_RESP_USER0      = 5'h06; // signal write without ack
localparam UMI_RESP_USER1      = 5'h08;
localparam UMI_RESP_FUTURE0    = 5'h0A;
localparam UMI_RESP_FUTURE1    = 5'h0C;
localparam UMI_RESP_LINK       = 8'h0E;

localparam UMI_REQ_ATOMICADD   = 8'h00;
localparam UMI_REQ_ATOMICAND   = 8'h01;
localparam UMI_REQ_ATOMICOR    = 8'h02;
localparam UMI_REQ_ATOMICXOR   = 8'h03;
localparam UMI_REQ_ATOMICMAX   = 8'h04;
localparam UMI_REQ_ATOMICMIN   = 8'h05;
localparam UMI_REQ_ATOMICMAXU  = 8'h06;
localparam UMI_REQ_ATOMICMINU  = 8'h07;
localparam UMI_REQ_ATOMICSWAP  = 8'h08;
