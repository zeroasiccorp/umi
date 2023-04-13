/*******************************************************************************
 * Function:  UMI Opcodes
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * This file defines all UMI commands.
 * command[7:4] is used for non-functional
 *
 * This file describes the standard opcodes for umi transactions.
 *
 * opcode[3:0] dicates transaction types
 * opcode[7:4] is used for hints and transaction options.
 *
 ******************************************************************************/

localparam UMI_INVALID         = 8'h00;

// Requests (demands a respnse)
localparam UMI_REQ_READ        = 8'h02; // read/load
localparam UMI_REQ_WRITE       = 8'h04; // write/store with ack
localparam UMI_REQ_POSTED      = 8'h06;
localparam UMI_REQ_MULTICAST   = 8'h08;
localparam UMI_REQ_STREAM      = 8'h0A;
localparam UMI_REQ_RES3        = 8'h0C;
localparam UMI_REQ_ATOMIC      = 8'h0E; // alias for all atomics
localparam UMI_REQ_ATOMICADD   = 8'h0E;
localparam UMI_REQ_ATOMICAND   = 8'h1E;
localparam UMI_REQ_ATOMICOR    = 8'h2E;
localparam UMI_REQ_ATOMICXOR   = 8'h3E;
localparam UMI_REQ_ATOMICMAX   = 8'h4E;
localparam UMI_REQ_ATOMICMIN   = 8'h5E;
localparam UMI_REQ_ATOMICMAXU  = 8'h6E;
localparam UMI_REQ_ATOMICMINU  = 8'h7E;
localparam UMI_REQ_ATOMICSWAP  = 8'h8E;
// Response (unilateral)
localparam UMI_RESP_READ       = 8'h01; // response to read request
localparam UMI_RESP_WRITE      = 8'h03; // response (ack) from write request
localparam UMI_RESP_ATOMIC     = 8'h05; // signal write without ack
localparam UMI_RESP_RES0       = 8'h07;
localparam UMI_RESP_RES1       = 8'h09;
localparam UMI_RESP_RES2       = 8'h0B;
localparam UMI_RESP_RES3       = 8'h0D;
localparam UMI_RESP_RES4       = 8'h0F;
