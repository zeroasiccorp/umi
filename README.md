![UMI](docs/_images/hokusai.jpg)

# Universal Memory Interface (UMI)

## Overview

* Applicable to any read/write addressable memory.
* Follows Little Endian convention.
* All transactions are atomic.
* Transactions specified through 32 bit command fields.
* Read requests include full source and destination addreses.
* Valid transaction indicated by separate physical valid bit.
* TX/RX operating modes set up through separate side channels.
* Support for 32b, 64b, 128b memory architectures.
* Support for PCIe 6.0 Flit Mode
* Support for CXL 2.0 Mode
* Support for Streaming Mode

## Command Types

| Command        | 31:12      |  11:8     |  OPCODE   |
|----------------|------------|-----------|-----------|
| INVALID        | USER[19:0] | SIZE[3:0] | 0000_0000 |
| WRITE          | USER[19:0] | SIZE[3:0] | 0001_0000 |
| WRITE-SIGNAL   | USER[19:0] | SIZE[3:0] | 0010_0000 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_0010 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_0011 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_0100 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_0101 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_0110 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_0111 |
|----------------|------------|-----------|-----------|
| READ           | USER[19:0] | SIZE[3:0] | XXXX_1000 |
| ATOMIC-SWAP    | USER[19:0] | SIZE[3:0] | 0000_1001 |
| ATOMIC-ADD     | USER[19:0] | SIZE[3:0] | 0001_1001 |
| ATOMIC-AND     | USER[19:0] | SIZE[3:0] | 0010_1001 |
| ATOMIC-OR      | USER[19:0] | SIZE[3:0] | 0011_1001 |
| ATOMIC-XOR     | USER[19:0] | SIZE[3:0] | 0100_1001 |
| ATOMIC-MAX     | USER[19:0] | SIZE[3:0] | 0101_1001 |
| ATOMIC-MIN     | USER[19:0] | SIZE[3:0] | 0110_1001 |
| ATOMIC-ADD     | USER[19:0] | SIZE[3:0] | 0111_1001 |
| ATOMIC-USER    | USER[19:0] | SIZE[3:0] | 1000_1001 |
| WRITE-WITH-ACK | USER[19:0] | SIZE[3:0] | XXXX_1010 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_1011 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_1100 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_1101 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_1110 |
| USER           | USER[19:0] | SIZE[3:0] | XXXX_1111 |

## Data Sizes

* The number of bytes transferred is 2^SIZE.
* The range of sizes supported is system dependent.
* The minimum data transfer size if >=AW.

| SIZE    | TRANSER   | NOTE              |
|---------|-----------|-------------------|
| 0       | 1B        | Single byte       |
| 1       | 2B        |                   |
| 2       | 4B        |                   |
| 3       | 8B        |                   |
| 4       | 16B       | 128b single cycle |
| 5       | 32B       |                   |
| 6       | 64B       |                   |
| 7       | 128B      |                   |
| 8       | 256B      | Cache line        |
| ...     | ...       |                   |
| 14      | 16,384B   | >Jumbo frame      |
| 15      | 32,657B   |                   |

## Packet Formats

* For AW=64 and PW=256
* DA is the most important field,so always keep in the same space
* AW32 and AW64 are binary compatible
* Min wires for AW32 is 128
* Min wires for AW64 us 256 (dicated by placement and atomics)

### Single Cycle Write

|AW |255:224   |223:160   |159:128   |127:96  |95:64   | 63:32  | 31:0    |
|---|----------|----------|----------|--------|--------|--------|---------|
|32 |          |          |          |D[31:0] |        |DA[31:0]|CMD[31:0]|
|32 |          |          |          |D[31:0] |        |DA[31:0]|CMD[31:0]|
|64 |          |          |D[63:32]  |D[31:0] |        |DA[31:0]|CMD[31:0]|
|64 |DA[63:32] |D[127:64] |D[63:32]  |D[31:0] |        |DA[31:0]|CMD[31:0]|

### Single Cycle Read Request

|AW |255:224   |223:160   |159:128   |127:96  |95:64   | 63:32  | 31:0    |
|---|----------|----------|----------|--------|--------|--------|---------|
|32 |          |          |          |        |SA[31:0]|DA[31:0]|CMD[31:0]|
|64 |DA[63:32] |SA[63:32] |          |        |SA[31:0]|DA[31:0]|CMD[31:0]|

### Single Cycle Atomic

|AW |255:224   |223:160   |159:128   |127:96  |95:64   | 63:32  | 31:0    |
|---|----------|----------|----------|--------|--------|--------|---------|
|32 |          |          |D[63:32]  |D[31:0] |SA[31:0]|DA[31:0]|CMD[31:0]|
|64 |DA[63:32] |SA[63:32] |D[63:32]  |D[31:0] |SA[31:0]|DA[31:0]|CMD[31:0]|

### Multi Cycle Write

|AW |255:224   |223:160   |159:128  |127:96  |95:64     | 63:32    | 31:0     |
|---|----------|----------|---------|--------|----------|----------|----------|
|64 |DA[63:32] |D[127:64] |D[63:32] |D[31:0] |          |DA[31:0]  |CMD[31:0] |
|64 |D[159:128]|D[127:64] |D[63:32] |D[31:0] |D[255:224]|D[223:192]|D[191:160]|


### 802.3 Ethernet Packet (AW=64)

* 112 ethernet header sent on first cycle
* Transaction size set to total ethernet frame + control + 2 empty bytes on first cycle

|255:224   |223:160     |159:128  |127:96  |95:64     | 63:32    | 31:0     |
|----------|------------|---------|--------|----------|----------|----------|
|DA[63:32] |0,HD[112:64]|HD[63:32]|HD[31:0]|          |DA[31:0]  |CMD[31:0] |
|D[159:128]|D[127:64]   |D[63:32] |D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[63:32] |D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[63:32] |D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[63:32] |D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[63:32] |D[31:0] |D[255:224]|D[223:192]|D[191:160]|

### CXL.IO Latency Optimized 256B Flit (AW=64)

* 16 bit cxl header setn on first cycle
* Transaction size set to 256 bytes (plus 14 empty byts on first cycle)

|255:224   |223:160   |159:128  |127:96     |95:64         | 63:32    | 31:0     |
|----------|----------|---------|---------- |--------------|----------|----------|
|DA[63:32] |          |         |00,HD[15:0]|              |DA[31:0]  |CMD[31:0] |
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |00,D[239:224] |D[223:192]|D[191:160]|
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |CRC,D[239:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64] |D[63:32] |D[31:0]    |CRC,M,TLP]    |D[223:192]|D[191:160]|


## Signal Interface


## File format
