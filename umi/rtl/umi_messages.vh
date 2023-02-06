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

localparam UMI_WRITE_POSTED   = 8'h01; // write without ack
localparam UMI_WRITE_RESPONSE = 8'h03; // response from read request
localparam UMI_WRITE_SIGNAL   = 8'h05; // signal write without ack
localparam UMI_WRITE_STREAM   = 8'h07; // stream (no address decode)
localparam UMI_WRITE_ACK      = 8'h09; // acknowledge to write request
localparam UMI_WRITE_RES0     = 8'h0B;
localparam UMI_WRITE_RES1     = 8'h0D;
localparam UMI_WRITE_RES2     = 8'h0F;
localparam UMI_REQUEST_READ   = 8'h02; // read request (read/load)
localparam UMI_REQUEST_WRITE  = 8'h04; // write request (with ack)
localparam UMI_ATOMIC         = 8'h06; // alias for all atomics
localparam UMI_ATOMIC_ADD     = 8'h06;
localparam UMI_ATOMIC_AND     = 8'h16;
localparam UMI_ATOMIC_OR      = 8'h26;
localparam UMI_ATOMIC_XOR     = 8'h36;
localparam UMI_ATOMIC_MAX     = 8'h46;
localparam UMI_ATOMIC_MIN     = 8'h56;
localparam UMI_ATOMIC_MAXU    = 8'h66;
localparam UMI_ATOMIC_MINU    = 8'h76;
localparam UMI_ATOMIC_SWAP    = 8'h86;
localparam UMI_REQUEST_RES0   = 8'h08;
localparam UMI_REQUEST_RES1   = 8'h0A;
localparam UMI_REQUEST_RES2   = 8'h0C;
localparam UMI_REQUEST_RES3   = 8'h0E;
