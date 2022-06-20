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
|----------------|-----------|-----------|
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

| SIZE    | MEANING   |
|---------|-----------|
| 0       | 1B        |
| 1       | 2B        |
| 2       | 4B        |
| ...     | ...       |
| 8       | 256B      |
| ...     | ...       |
| 15      | 32,657B   |

## Packet Formats

| Bits    | AW==32 | AW==64 | AW==128 |
|---------|--------|--------|---------|
| 31:0    | CMD/D6 | CMD/D6 | CMD/D6  |
| 63:32   | DA0/D7 | DA0/D7 | DA0/D7  |
| 95:64   | D0/SA0 | D0/SA0 | D0/SA0  |
| 127:96  | D1/0   | D1/SA1 | D1/SA1  |
| 159:128 | D5     | DA1/D5 | DA1/D5  |
| 191:160 | D2     | D2     | D2/SA2  |
| 223:192 | D3     | D3     | D3/SA3  |
| 255:224 | D4     | D4     | D4/SA3  |

## Examples

* For AW=64 and PW=256

### 802.3 Ethernet Packet 

| Cycle   | Content                  |
|---------|--------------------------|
| 0       | UMI Transaction          |
| 1       | Header (14B), data(18B)  |
| 3,4     | Data (64B)               |
| 5,6     | Data (64B)               |
| 7,8     | Data (64B)               |

### CXL.IO Latency Optimized 256B Flit 

| Cycle   | Content                  |
|---------|--------------------------|
| 0       | UMI Transaction          |
| 1,2     | CXL header + Flit Chunk0 |
| 3,4     | Flit Chunk1, DLP, CRC0   |
| 5,6     | Flit Chunk2              |
| 7,8     | Flit Chunk3, Market, CRC2|

## Signal Interface




## File format


