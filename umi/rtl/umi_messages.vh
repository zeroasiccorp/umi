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

localparam UMI_WRITE_POSTED    = 8'h01;
localparam UMI_WRITE_RESPONSE  = 8'h03;
localparam UMI_WRITE_SIGNAL    = 8'h05;
localparam UMI_WRITE_STREAM    = 8'h07;
localparam UMI_WRITE_ACK       = 8'h09;
localparam UMI_WRITE_MULTICAST = 8'h0B;
localparam UMI_WRITE_RESERVED0 = 8'h0D;
localparam UMI_WRITE_RESERVED1 = 8'h0F;

localparam UMI_READ_REQUEST    = 8'h02;
localparam UMI_ATOMIC          = 8'h00;//alias for group
localparam UMI_ATOMIC_ADD      = 8'h04;
localparam UMI_ATOMIC_AND      = 8'h14;
localparam UMI_ATOMIC_OR       = 8'h24;
localparam UMI_ATOMIC_XOR      = 8'h34;
localparam UMI_ATOMIC_MAX      = 8'h44;
localparam UMI_ATOMIC_MIN      = 8'h54;
localparam UMI_ATOMIC_MAXU     = 8'h64;
localparam UMI_ATOMIC_MINU     = 8'h74;
localparam UMI_ATOMIC_SWAP     = 8'h84;
localparam UMI_READ_RESERVED0  = 8'h06;
localparam UMI_READ_RESERVED1  = 8'h08;
localparam UMI_READ_RESERVED2  = 8'h0A;
localparam UMI_READ_RESERVED3  = 8'h0C;
localparam UMI_READ_RESERVED4  = 8'h0E;
