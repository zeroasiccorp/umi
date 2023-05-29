![UMI](docs/_images/hokusai.jpg)

# Universal Memory Interface (UMI)

## Overview

The Universal Memory Interface (UMI) is a stack of standardized abstractions for reading and writing memory, with the core principle being "everything is an address". UMI includes four distinct layers:

* **Protocol**: Overlay of standard communication protocols (Ethernet, PCIE, CXL).   
* **Transaction**: Address based read/write transactions.
* **Link**: Communication integrity (flow control, reliability).
* **Physical**: Electrical signaling (pins, wires, etc.).

Key supported features of UMI are:
  * separation of concerns though unified abstraction stack
  * 64b/32b addressing support
  * bursting of up to 256 transfers
  * data sizes up to 1024 bits
  * atomic transactions
  * error detection and correction
  * user reserved commands
  * transaction extendability

## Glossary/Abbreviations

| Word   | Meaning                                  |
|--------|------------------------------------------|
| Host   | Initiates a request                      |
| Device | Responds to a request                    |
| SA     | Source address                           |
| DA     | Destination address                      |
| DATA   | Data packet                              |
| CMD    | Transaction command                      |
| SIZE   | Data size per individual transfer        |
| LEN    | Number of individual transfers           |
| EDAC   | Error detect/correction control          |
| PRIV   | Privilege mode                           |
| EOT    | End of transfer indicator                |
| EXT    | Extended header indicator                |
| USER   | User command bits                        |
| ERR    | Error code                               |

## Transaction Layer

The UMI transaction layer defines a set of operations for interacting with a broad set of address based memory systems.

TBD:
- ordering
- others...

| COMMAND       |DATA|SA |DA  |31  |30:20|19:18|17:16|15:8 |7   |6:4 |3:0 |
|---------------|--- |---|----|----|-----|-----|-----|-----|----|----|----|
| INVALID		    |    |   |    |--  | --  |--   |--   |--   |0   |000 |0x0 |
| REQ_RD        |	   |Y	 |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0x1 |
| REQ_WR        |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0x3 |
| REQ_WRPOSTED  |Y   |   |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0x5 |
| REQ_RDMA	    |	   |Y	 |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0x7 |
| REQ_ATOMICADD |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x00 |1	  |SIZE|0x9 |
| REQ_ATOMICAND |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x01 |1	  |SIZE|0x9 |
| REQ_ATOMICOR  |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x02 |1	  |SIZE|0x9 |
| REQ_ATOMICXOR |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x03 |1	  |SIZE|0x9 |
| REQ_ATOMICMAX |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x04 |1	  |SIZE|0x9 |
| REQ_ATOMICMIN |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x05 |1	  |SIZE|0x9 |
| REQ_ATOMICMAXU|Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x06 |1	  |SIZE|0x9 |
| REQ_ATOMICMINU|Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x07 |1	  |SIZE|0x9 |
| REQ_ATOMICSWAP|Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |0x08 |1	  |SIZE|0x9 |
| REQ_MULTICAST |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0xB |
| REQ_ERROR     |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |ERR  |USER|0x0 |0xD |
| REQ_LINK      |	   |	 |	  |EXT |--   |--   |--   |--   |-   |0x1 |0xD |
| REQ_RESERVED  |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |LEN  |USER|SIZE|0xF |

| COMMAND       |DATA|SA |DA  |31  |30:20|19:18|17:16|15:8 |7   |6:4 |3:0 |
|---------------|--- |---|----|----|-----|-----|-----|-----|----|----|----|
| RESP_READ	    |Y	 |Y	 |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0x2 |
| RESP_READANON |Y   |   |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0x4 |
| RESP_WRITE    |	   |Y	 |Y	  |EXT |USER |EDAC |PRIV |LEN  |EOT	|SIZE|0x6 |
| RESP_WRITEANON|Y	 |   |Y   |EXT |USER |EDAC |PRIV |LEN  |EOT |SIZE|0x8 |
| RESP_ERROR    |Y 	 |Y  |Y   |EXT |USER |EDAC |PRIV |ERR  |USER|0x0 |0xA |
| RESP_LINK     |	   |	 |	  |--  |--   |--   |--   |--   |-   |0x1 |0xA |
| RESP_RESERVED |Y   |Y  |Y   |EXT |USER |EDAC |PRIV |--   |-   |--  |0xC |
| RESP_RESERVED |Y   |   |Y   |EXT |USER |EDAC |PRIV |--   |-   |--  |0xE |

## Protocol Layer

UMI standardizes the overlay of higher level communication protocols layers on top of a common memory transaction layer. Standardization of protocol selection is 
needed in cases where multiple types of traffic is transmitted over a single 
channel. Bit 31 of the UMI transaction command field is used to enable protocol extensions, with byte 0 of the data field acting as a protocol selector. The protocol layer is identical to the transaction layer when cmd[31]=0.

| Mode    | Data (Bytes) | Data (Bytes) | Command (bit 31) |
|---------|--------------|--------------|:----------------:|
| NATIVE  | Data(N:1)    | Data(0)      | 0                |
| EXTENDED| Data(N-1:0)  | Opcode       | 1                |

The following list of protocols are supported. More protocols will be added as
needed.

| Opcode[7:0] | Mode                              | 
|:-----------:|-----------------------------------|
|8'h00        | Invalid                           |
|8'h01        | Ethernet                          |
|8'h02        | USB                               |
|8'h03        | PCIe                              |
|8'h04        | CXL.IO                            |
|8'h05        | CXL.cache                         |
|8'h06        | CXL.memory                        |
|8'h07        | Interlaken                        |
|8'h08        | JESD204                           |


## Physical Layer

UMI channel signal bundle consists of a packet, a valid signal,
and a ready signal with the following naming convention:

```
u<host|dev>_<req|resp>_<packet|ready|valid>
```

Connections shall only be made between hosts and devices,
per the diagram below.

![UMI](docs/_images/umi_connections.png)


Modules can have a UMI host port, device port, or both.

```verilog

// HOST VERILOG
output        uhost_req_valid;
output[255:0] uhost_req_packet;
input         uhost_req_ready;
input         uhost_resp_valid;
input[255:0]  uhost_resp_packet;
output        uhost_resp_ready;

// DEVICE VERILOG
input         udev_req_valid;
input[255:0]  udev_req_packet;
output        udev_req_ready;
output        udev_resp_valid;
output[255:0] udev_resp_packet;
input         udev_resp_ready;
```

## Handshake Protocol

![UMI](docs/_images/ready_valid.svg)

UMI adheres to the following ready/valid handshake protocol:
1. A transaction occurs on every rising clock edge in which READY and VALID are both asserted.
2. Once VALID is asserted, it must not be de-asserted until a transaction completes.
3. READY, on the other hand, may be de-asserted before a transaction completes.
3. The assertion of VALID must not depend on the assertion of READY.  In other words, it is not legal for the VALID assertion to wait for the READY assertion.
4. However, it is legal for the READY assertion to be dependent on the VALID assertion (as long as this dependence is not combinational).

#### Legal: VALID asserted before READY

![UMIX1](docs/_images/ok_valid_ready.svg)

#### Legal: READY asserted before VALID

![UMIX2](docs/_images/ok_ready_valid.svg)

#### Legal: READY and VALID asserted simultaneously

![UMIX3](docs/_images/ok_sametime.svg)

#### Legal: READY toggles with no effect

![UMIX4](docs/_images/ok_ready_toggle.svg)

#### **ILLEGAL**: VALID de-asserted without waiting for READY

![UMIX5](docs/_images/bad_valid_toggle.svg)

#### Legal: VALID asserted for multiple cycles

In this case, multiple transactions occur.

![UMIX6](docs/_images/ok_double_xaction.svg)

#### Example Bidirectional Transaction

![UMIX7](docs/_images/example_rw_xaction.svg)


## Packet Structure

UMI packets are encoded with the scheme shown below.


| [UW-1:32]  | [31:12]   | [11:8] |  [7:0]       |
|------------|-----------|--------|--------------|
| MESSAGE    | OPTIONS   | SIZE   | COMMAND      |

## Transaction Types

UMI transactions are split into separate request and
response channels.

In case of channel multiplexing, responses take priority over requests.

The table below gives a summary of all UMI transaction
opcodes.

| TRANSACTION    | P7:0 |  DESCRIPTION                               |
|----------------|------|--------------------------------------------|
| INVALID        | 00   | Invalid
| REQ_READ       | 02   | Read request (returns data response)
| REQ_WRITE      | 04   | Write request (with acknowledge)
| REQ_POSTED     | 06   | Write request (**without** acknowledge)
| REQ_MULTICAST  | 08   | Multicast request (**without** acknowledge)
| REQ_STREAM     | 0A   | Stream request (**without** acknowledge)
| REQ_ZZZ        | 0C   | Reserved
| REQ_ATOMICADD  | 0E   | Atomic add operation
| REQ_ATOMICAND  | 1E   | Atomic and operation
| REQ_ATOMICOR   | 2E   | Atomic or operation
| REQ_ATOMICXOR  | 3E   | Atomic xor operation
| REQ_ATOMICMAX  | 4E   | Atomic max operation
| REQ_ATOMICMIN  | 5E   | Atomic min operation
| REQ_ATOMICMAXU | 6E   | Atomic unsigned max operation
| REQ_ATOMICMINU | 7E   | Atomic unsigned min operation
| REQ_ATOMICSWAP | 8E   | Atomic swap operation
| -------------  | ---- | -----------------------
| RESP_READ      | 01   | Response to read request
| RESP_WRITE     | 03   | Response (ack) to write request
| RESP_ATOMIC    | 05   | Response to atomic request
| RESP_XXX       | 07   | Streaming unordered write
| RESP_XXX       | 09   | Reserved
| RESP_XXX       | 0B   | Reserved
| RESP_XXX       | 0D   | Reserved
| RESP_XXX       | 0F   | Reserved

## Data Sizes Supported

* The number of bytes in the request/reseponse is 2^SIZE.
* The range of sizes supported is system dependent.
* The minimum data transfer size if >=AW.

| SIZE | TRANSER  | NOTE           |
|------|----------|----------------|
| 0    | 1B       | Single byte    |
| 1    | 2B       |                |
| 2    | 4B       |                |
| 3    | 8B       |                |
| 4    | 16B      | 128b per cycle |
| 5    | 32B      |                |
| 6    | 64B      | Cache line     |
| 7    | 128B     |                |
| 8    | 256B     |                |
| 9    | 512B     |                |
| 10   | 1,024B   |                |
| 11   | 2,048B   |                |
| 12   | 4,096B   |                |
| 13   | 8,192B   |                |
| 14   | 16,384B  | >Jumbo frame   |
| 15   | 32,657B  |                |

## Message Encoding

### Single Cycle Write

|AW |255:224 |223:192  |191:160 |159:128 |127:96 |95:64  | 63:32 | 31:0  |
|---|--------|---------|--------|--------|-------|-------|-------|-------|
|64 |A[63:32]|D[127:96]|D[95:64]|D[63:32]|D[31:0]|       |A[31:0]|C[31:0]|
|32 |        |D[127:96]|D[95:64]|D[63:32]|D[31:0]|       |A[31:0]|C[31:0]|

### Single Cycle Read Request

|AW |255:224 |223:192  |191:160 |159:128 |127:96 |95:64  | 63:32 | 31:0  |
|---|--------|---------|--------|--------|-------|-------|-------|-------|
|64 |A[63:32]|S[63:32] |        |        |       |S[31:0]|A[31:0]|C[31:0]|
|32 |        |         |        |        |       |S[31:0]|A[31:0]|C[31:0]|

### Single Cycle Atomic

|AW |255:224 |223:192  |191:160 |159:128 |127:96 |95:64  | 63:32 | 31:0  |
|---|--------|---------|--------|--------|-------|-------|-------|-------|
|64 |A[63:32]|S[63:32] |D[95:64]|D[63:32]|D[31:0]|S[31:0]|A[31:0]|C[31:0]|
|32 |        |         |        |        |D[31:0]|S[31:0]|A[31:0]|C[31:0]|


### Multi Cycle Write

|255:224   |223:192  |191:160 |159:128 |127:96 |95:64     |63:32     | 31:0    |
|----------|---------|--------|--------|-------|----------|----------|----------|
|A[63:32]  |D[127:96]|D[95:64]|D[63:32]|D[31:0]|          |A[31:0]   |C[31:0]   |
|D[159:128]|D[127:96]|D[95:64]|D[63:32]|D[31:0]|D[255:224]|D[223:192]|D[191:160]|

### 802.3 Ethernet Packet (AW=64)

* 112b ethernet header sent on first cycle
* Transaction size set to total ethernet frame + control + 2 empty bytes on first cycle

|255:224   |223:192     |191:160 |159:128 |127:96  |95:64     | 63:32    | 31:0     |
|----------|------------|--------|--------|--------|----------|----------|----------|
|A[63:32]  |00,H[111:96]|H[95:64]|H[63:32]|H[31:0] |          |A[31:0]   |C[31:0]   |
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|

### 802.3 Ethernet Packet (AW=64)

* 112b ethernet header sent on first cycle
* Transaction size set to total ethernet frame + control + 2 empty bytes on first cycle

|255:224   |223:192     |191:160 |159:128 |127:96  |95:64     | 63:32    | 31:0     |
|----------|------------|--------|--------|--------|----------|----------|----------|
|A[63:32]  |00,H[111:96]|H[95:64]|H[63:32]|H[31:0] |          |A[31:0]   |C[31:0]   |
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]   |D[95:64]|D[63:32]|D[31:0] |D[255:224]|D[223:192]|D[191:160]|

### CXL.IO Latency Optimized 256B Flit (AW=64)

* 16b cxl header set on first cycle
* Transaction size set to 256 bytes (plus 14 empty byts on first cycle)

|255:224   |223:192  |191:160 |159:128 |127:96   |95:64         | 63:32    | 31:0     |
|----------|---------|--------|--------|---------|--------------|----------|----------|
|A[63:32]  |         |        |        |0,H[15:0]|              |A[31:0]   |C[31:0]   |
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |0,D[239:224]  |D[223:192]|D[191:160]|
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |CRC,D[239:224]|D[223:192]|D[191:160]|
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |D[255:224]    |D[223:192]|D[191:160]|
|D[159:128]|D[127:64]|D[95:64]|D[63:32]|D[31:0]  |CRC,M,TLP     |D[223:192]|D[191:160]|
