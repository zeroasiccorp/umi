/*******************************************************************************
 * Copyright 2020 Zero ASIC Corporation
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
 * ##Documentation##
 *
 * - This file defines all UMI commands.
 *
 *
 ******************************************************************************/

// Command decode [31:0]

localparam UMI_OPCODE_LSB = 0;
localparam UMI_OPCODE_MSB = 4;

localparam UMI_SIZE_LSB   = 5;
localparam UMI_SIZE_MSB   = 7;

localparam UMI_LEN_LSB    = 8;
localparam UMI_LEN_MSB    = 15;

localparam UMI_QOS_LSB    = 16;
localparam UMI_QOS_MSB    = 19;

localparam UMI_PROT_LSB   = 20;
localparam UMI_PROT_MSB   = 21;

localparam UMI_EOM_BIT    = 22;
localparam UMI_EOF_BIT    = 23;

localparam UMI_EX_BIT     = 24;

localparam UMI_USER_LSB   = 25;
localparam UMI_USER_MSB   = 26;

localparam UMI_HOSTID_LSB = 27;
localparam UMI_HOSTID_MSB = 31;

// Requests (host -> device)
localparam UMI_MAXSIZE         = 1024;  // max word size per transaction
localparam UMI_MAXLEN          = 256;   // max word transfers per transaction

// Invalid transaction indicator (cmd[7:0])
localparam UMI_INVALID         = 8'h00;

// Requests (host -> device) (cmd[7:0])
localparam UMI_REQ_READ        = 5'h01; // read/load
localparam UMI_REQ_WRITE       = 5'h03; // write/store with ack
localparam UMI_REQ_POSTED      = 5'h05; // posted write
localparam UMI_REQ_RDMA        = 5'h07; // remote DMA command
localparam UMI_REQ_ATOMIC      = 5'h09; // alias for all atomics
localparam UMI_REQ_USER0       = 5'h0B; // reserved for user
localparam UMI_REQ_FUTURE0     = 5'h0D; // reserved fur future use
localparam UMI_REQ_ERROR       = 8'h0F; // reserved for error message
localparam UMI_REQ_LINK        = 8'h2F; // reserved for link ctrl

// Response (device -> host) (cmd[7:0])
localparam UMI_RESP_READ       = 5'h02; // response to read request
localparam UMI_RESP_WRITE      = 5'h04; // response (ack) from write request
localparam UMI_RESP_USER0      = 5'h06; // signal write without ack
localparam UMI_RESP_USER1      = 5'h08; // reserved for user
localparam UMI_RESP_FUTURE0    = 5'h0A; // reserved for future use
localparam UMI_RESP_FUTURE1    = 5'h0C; // reserved for future use
localparam UMI_RESP_LINK       = 8'h0E; // reserved for link ctrl

// Atomic command decode (cmd[15:8])
localparam UMI_REQ_ATOMICADD   = 8'h00;
localparam UMI_REQ_ATOMICAND   = 8'h01;
localparam UMI_REQ_ATOMICOR    = 8'h02;
localparam UMI_REQ_ATOMICXOR   = 8'h03;
localparam UMI_REQ_ATOMICMAX   = 8'h04;
localparam UMI_REQ_ATOMICMIN   = 8'h05;
localparam UMI_REQ_ATOMICMAXU  = 8'h06;
localparam UMI_REQ_ATOMICMINU  = 8'h07;
localparam UMI_REQ_ATOMICSWAP  = 8'h08;
