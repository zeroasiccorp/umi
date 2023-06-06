![UMI](docs/_images/hokusai.jpg)

# Universal Memory Interface (UMI)

## 1. Introduction

### 1.1 Architecture

The Universal Memory Interface (UMI) is a transaction based standard for interacting with memory through request-response message exchange patterns. UMI includes five distinct abstraction layers:

* **Protocol**: Protocol/application specific payload (Ethernet, PCIe, ...)
* **Transaction**: Address based request-response messaging
* **Signal**: Latency insensitive signaling layer (packet, ready, valid)
* **Link**: Communication integrity (flow control, reliability)
* **Physical**: Electrical signaling (electrons, wires, etc.)

![UMI](docs/_images/umi_stack.svg)

### 1.2 Key Features

  * independent request and response channels
  * word sizes up to 1024 bits
  * up to 256 word transfers per transaction
  * atomic transaction support
  * quality of service support
  * reserved opcodes for users and future expansion

### 1.3 Key Terms

* **Transaction**: A complete request-response message based memory operation.
* **Message**: Request or response message, consisting of a command header, address fields, and an optional data payload.
* **Host**: Initiator of memory requests.
* **Device**: Responder to memory requests.

----
## 2. Protocol UMI (PUMI) Layer

UMI transaction payloads are treated as a series of opaque bytes and can carry arbitrary data, including higher level protocols. The maximum data size available for communication protocol data and headers is 32,768 bytes. The following table illustrates recommended bit packing for a number of common communication standards.

| Protocol  | Payload(UMI DATA) | Header(UMI Data)|UMI Addresses + Command |
|:---------:|:-----------------:|:---------------:|:----------------------:|
| Ethernet  | 64B - 1,518B      |14B              | 20B                    |
| CXL-68    | 64B               |2B               | 20B                    |
| CXL-256   | 254B              |2B               | 20B                    |
----
## 3. Transaction UMI (TUMI) Layer

### 3.1 Theory of Operation

UMI transactions are request-response message exchanges between Hosts and addressable Devices. Hosts send memory access requests to devices and get responses back. The figure below illustrates the relationship between hosts, devices, and the interconnect network.

![UMI](docs/_images/tumi_connections.png)

Hosts:

* Send read, write memory access request messages
* Validate and execute incoming response
* Identify egress interface through which to send requests (in case of multiple)

Devices:

* Validate and execute incoming memory request messages
* Initiate response messages when required
* Identify egress interface through which to send responses (in case of multiple)

Constraints:
* Device and source addresses must be aligned to 2^SIZE bytes.
* The maximum data field size is 32,768 bytes.
* Transactions must not cross 4KB address boundaries
* All data bytes must be arrive at final destination.
* Message content arrive at a device in the same order that they left the host.
* Message content arrive at the host in the same order that they left the device.

### 3.2 Message Format

#### 3.2.1 Message Fields

| Term        | Meaning    |
|-------------|------------|
| CMD         | Command (type + options)
| DA          | Device address (target of a request)
| SA          | Source address (where to send the response)
| DATA        | Data payload
| OPCODE      | Command opcode
| SIZE        | Word size
| LEN         | Word transfers per message
| QOS         | Quality of service required
| PROT        | Protection mode
| EX          | Exclusive access indicator
| EOF         | End of frame indicator
| EOM         | End of message indicator
| U           | User defined message bit
| R           | Reserved message bit
| ERR         | Error code
| HOSTID      | Host ID
| DEVID       | Device ID
| MSB         | Most significant bit

#### 3.2.2 Message Byte Order

Request and response messages consist of CMD, DA, SA, and DATA fields.
The byte ordering of a message is shown in the table below.

|                  |MSB-1:160|159:96|95:32|31:0|
|------------------|:-------:|:----:|:---:|:--:|
| 64b architecture |DATA     |SA    |DA   | CMD|
| 32b architecture |DATA     |DATA  |SA,DA| CMD|

#### 3.2.3 Message Types

The following table documents the UMI messages. CMD[4:0] is the opcode defining the type of message being sent. CMD[31:5] are used for message specific options. Complete functional descriptions of each message can be found in the [Message Description Section](#34-transaction-descriptions).

|Message     |DATA|SA|DA|31:25|24|23:22  |21:18|17:16|15:8 |7:5 |4|3:0|
|------------|:--:|--|--|:---:|--|:-----:|:---:|-----|-----|----|-|---|
|INVALID     |    |Y |Y |--   |- |--     |--   |--   |--   |0x0 |0|0x0|
|REQ_RD      |    |Y |Y |U    |EX|EOF,EOM|QOS  |PROT |LEN  |SIZE|R|0x1|
|REQ_WR      |Y   |Y |Y |U    |EX|EOF,EOM|QOS  |PROT |LEN  |SIZE|R|0x3|
|REQ_WRPOSTED|Y   |Y |Y |U    |0 |EOF,EOM|QOS  |PROT |LEN  |SIZE|R|0x5|
|REQ_RDMA    |    |Y |Y |U    |0 |EOF,EOM|QOS  |PROT |LEN  |SIZE|R|0x7|
|REQ_ATOMIC  |Y   |Y |Y |U    |0 |EOF,EOM|QOS  |PROT |ATYPE|SIZE|R|0x9|
|REQ_USER0   |Y   |Y |Y |U    |EX|EOF,EOM|QOS  |PROT |LEN  |SIZE|R|0xB|
|REQ_FUTURE0 |Y   |Y |Y |U    |EX|EOF,EOM|QOS  |PROT |LEN  |SIZE|R|0xD|
|REQ_ERROR   |    |Y |Y |U    |0 |ERR    |QOS  |PROT |U    |0x0 |R|0xF|
|REQ_LINK    |    |  |  |U    |0 |U      |U    |U    |U    |0x1 |R|0xF|
|RESP_READ   |Y   |Y |Y |U    |EX|ERR    |QOS  |PROT |LEN  |SIZE|R|0x2|
|RESP_WR     |    |Y |Y |U    |EX|ERR    |QOS  |PROT |LEN  |SIZE|R|0x4|
|RESP_USER0  |    |Y |Y |U    |EX|ERR    |QOS  |PROT |LEN  |SIZE|R|0x6|
|RESP_USER1  |    |Y |Y |U    |EX|ERR    |QOS  |PROT |LEN  |SIZE|R|0x8|
|RESP_FUTURE0|    |Y |Y |U    |EX|ERR    |QOS  |PROT |LEN  |SIZE|R|0xA|
|RESP_FUTURE1|    |Y |Y |U    |EX|ERR    |QOS  |PROT |LEN  |SIZE|R|0xC|
|RESP_LINK   |    |  |  |U    |0 |U      |U    |U    |U    |0x0 |R|0xE|

### 3.3 Message Fields

### 3.3.1 Source Address (SA[63:0])

The source address (SA) field is used for routing information and [UMI signal layer](#UMI-Signal-layer) controls. The following table specifies the prescribed use of all SA bits.

| SA       |63:40|39:32|31:24|23:8|7:0   |
|----------|:---:|:---:|:---:|:--:|:-----|
| 64b mode | R   | U   | U   |U   |HOSTID|
| 32b mode | --  | --  | R   |U   |HOSTID|

* HOSTID bits are used for routing.
* R bits are dedicated to future enhancements.
* U bits are available for signal layer controls.

### 3.3.2 Transaction Word Size (SIZE[2:0])

The SIZE field defines the number of bytes in a transaction word. Devices are not required to support all SIZE options. Hosts must only send messages with a SIZE supported by the target device.

|SIZE[2:0] |Bytes per word|
|:--------:|:------------:|
| 0b000    | 1
| 0b001    | 2
| 0b010    | 4
| 0b011    | 8
| 0b100    | 16
| 0b101    | 32
| 0b110    | 64
| 0b111    | 128

### 3.3.3 Transaction Length (LEN[7:0])

The LEN field defines the number of words of size 2^SIZE bytes transferred by a transaction. The number of transfers is equal to LEN + 1, equating to a range of 1-256 transfers per transaction. The current address of transfer number 'i' in a transaction is defined by:

ADDR_i = START_ADDR + (i-1) * 2^SIZE.

### 3.3.4 Protection Mode (PROT[1:0])

The PROT field indicates the protected access level of the transaction, enabling controlled access to memory.

|PROT[Bit] | Value | Function            |
|:--------:|:-----:|---------------------|
| [0]      | 0     | Unprivileged access |
|          | 1     | Privileged access   |
| [1]      | 0     | Secure access       |
|          | 1     | Non-secure access   |

### 3.3.5 Quality of Service (QOS[3:0])

The QOS field controls the quality of service required from the interconnect network. The interpretation of the QOS bits is interconnect network specific.

### 3.3.6 End of Message (EOM)

The EOM bit is reserved for signal layer user to indicate transfer of the last word in a message.

### 3.3.7 End of Frame (EOF)

The EOF bit indicates that this transaction is the last one in a sequence of related UMI transactions. Use of the EOF bit at an endpoint is optional and implementation specific.

### 3.3.8 Error Code (ERR[1:0])

The ERR field indicates the error status of a response (RESP_WR, RESP_RD) transaction.

|ERR[1:0]| Meaning                            |
|:------:|------------------------------------|
| 0b00   | OK (no error)                      |
| 0b01   | EXOK (successful exclusive access) |
| 0b10   | DEVERR (device error)              |
| 0b11   | NETERR (network error)             |

DEVERR trigger examples:

* Insufficient privilege level for access
* Write attempted to read-only location
* Unsupported word size
* Access attempt to disabled function

NETERR trigger examples:
* Device address unreachable

### 3.3.9 Atomic Transaction Type (ATYPE[7:0])

The ATYPE field indicates the type of the atomic transaction.

|ATYPE[7:0]| Meaning     |
|:--------:|-------------|
| 0x00     | Atomic add  |
| 0x01     | Atomic and  |
| 0x02     | Atomic or   |
| 0x03     | Atomic xor  |
| 0x04     | Atomic max  |
| 0x05     | Atomic min  |
| 0x06     | Atomic maxu |
| 0x07     | Atomic minu |
| 0x08     | Atomic swap |

### 3.3.10 User Field (U)

Message bit designated with a U are available for use by application and signal layer implementations. Any undefined user bits shall be set to zero.  

### 3.3.11 Reserved Field (R)

Message bit designated with an R are  reserved for future UMI enhancements and shall be set to zero.

## 3.4 Message Descriptions

### 3.4.1 INVALID

INVALID indicates an invalid message. A receiver can choose to ignore the message or to take corrective action.

### 3.4.2 REQ_RD

REQ_RD reads (2^SIZE)*(LEN+1) bytes from device address(DA). The device initiates a RESP_RD message to return data to the host source address (SA).

### 3.4.3 REQ_WR

REQ_WR writes (2^SIZE)*(LEN+1) bytes to destination address(DA). The device then initiates a RESP_WR acknowledgment message to the host source address (SA).

### 3.4.4 REQ_WRPOSTED

REQ_WRPOSTED performs a unidirectional posted-write of (2^SIZE)*(LEN+1) bytes to destination address(DA). There is no response message sent by the device back to the host.

### 3.4.5 REQ_RDMA

REQ_RDMA reads (2^SIZE)\*(LEN+1) bytes of data from a primary device destination address (DA) along with a source address (SA). The primary device then initiates a REQ_WRPOSTED message to write (2^SIZE)*(LEN+1) data bytes to the address (SA) in a secondary device. REQ_RDMA requires the complete SA field for addressing and does not support pass through information for the UMI signal layer.

### 3.4.6 REQ_ATOMIC{ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP}

REQ_ATOMIC initiates an atomic read-modify-write memory operation of size (2^SIZE) at destination address (DA). The REQ_ATOMIC sequence involves:

1. Host sending data (DATA), destination address (DA), and source address (SA) to the device,
2. Device reading data address DA
3. Applying a binary operator {ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP} between D and the original device data
4. Writing the result back to device address DA
5. Returning the original device data to host address SA

### 3.4.7 REQ_ERROR

REQ_ERROR sends a unidirectional message to a device (ERR) to indicate that an error has occurred. The device can choose to ignore the message or to take action. There is no response message sent back to the host from the device.

### 3.4.8 REQ_LINK

RESP_LINK is a reserved CMD only message for link layer non-memory mapped actions such as credit updates, time stamps, and framing. CMD[31-8] are all available as user specified control bits. The message is local to the signal (physical) layer and does not include routing information and does not elicit a response from the receiver.

### 3.4.9 REQ_USER

REQ_USER message types are reserved for non-standardized custom UMI messages.

### 3.4.10 REQ_FUTURE

REQ_FUTURE message types are reserved for future UMI feature enhancements.

### 3.4.11 RESP_RD

RESP_RD returns (2^SIZE)*(LEN+1) bytes of data to the host source address (SA) specified by the REQ_RD message.

### 3.4.12 RESP_WR

RESP_WR returns an acknowledgment to the original source address (SA) specified by the the REQ_WR transaction. The message does not include any DATA.

### 3.4.13 RESP_LINK

RESP_LINK is a reserved CMD only transaction for link layer non-memory mapped actions such as credit updates, time stamps, and framing. CMD[31-8] are all available as user specified control bits. The transaction is local to the signal (physical) layer and does not include routing information.

### 3.4.14 RESP_USER

RESP_USER message types are reserved for non-standardized custom UMI messages.

### 3.4.15 RESP_FUTURE

RESP_FUTURE message types are reserved for future UMI feature enhancements.

----
## 4. Signal UMI Layer (SUMI)

### 4.1 Theory of Operation

The UMI signal layer (SUMI) defines the mapping of UMI transactions to a
point-to-point, latency insensitive, parallel, synchronous interface with a [valid ready handshake protocol](#32-handshake-protocol).

![UMI](docs/_images/sumi_connections.png)

The SUMI signaling layer defines a subset of TUMI information the be transmitted as a bundled packet over a single clock cycle. The follow table documents the legal set of SUMI packet parameters .

| Field    | Width (bits)       |
|:--------:|--------------------|
| CMD      | 32                 |
| DA       | 32, 64             |
| SA       | 32, 64             |
| DATA     | 64,128,256,512,1024|

The following example illustrates a complete request-response transaction between a host and a device.

![UMIX7](docs/_images/example_rw_xaction.svg)

UMI messages with DATA exceeding the SUMI DATA width can be split into separate atomic shorter packets as long as message ordering and byte ordering is preserved. A SUMI packet is a complete routable mini-message comprised of a CMD, DA, SA, and DATA field. The end of message (EOM) bit indicates the arrival of the last packet in a message.

The following example illustrates a TUMI 128B write request split into two separate SUMI request packets in a SUMI implementation with a 64B data width.

TUMI REQ_WR transaction:

* LEN =  0h01
* SIZE = 0b110
* EOM   = 0

SUMI REQ_WR #1:

* LEN =  0h00
* SIZE = 0b110
* DA = 0x0
* EOM  = 0
  
SUMI REQ_WR #2:

* LEN  =  0h00
* SIZE = 0b110
* DA = 0x40
* EOM  = 1

### 4.2 Handshake Protocol

SUMI adheres to the following ready/valid handshake protocol:

![UMI](docs/_images/ready_valid.svg)

1. A transaction occurs on every rising clock edge in which READY and VALID are both asserted.
2. Once VALID is asserted, it must not be de-asserted until a transaction completes.
3. READY, on the other hand, may be de-asserted before a transaction completes.
4. The assertion of VALID must not depend on the assertion of READY.  In other words, it is not legal for the VALID assertion to wait for the READY assertion.
5. However, it is legal for the READY assertion to be dependent on the VALID assertion (as long as this dependence is not combinational).

#### LEGAL: VALID asserted before READY

![UMIX1](docs/_images/ok_valid_ready.svg)

#### LEGAL: READY asserted before VALID

![UMIX2](docs/_images/ok_ready_valid.svg)

#### LEGAL: READY and VALID asserted simultaneously

![UMIX3](docs/_images/ok_sametime.svg)

#### LEGAL: READY toggles with no effect

![UMIX4](docs/_images/ok_ready_toggle.svg)

#### LEGAL: VALID asserted for multiple cycles (multiple transactions)

![UMIX6](docs/_images/ok_double_xaction.svg)

#### **ILLEGAL**: VALID de-asserted without waiting for READY

![UMIX5](docs/_images/bad_valid_toggle.svg)

### 4.3 Verilog Standard Interfaces

#### 4.3.1 Host Interface

```verilog
output          uhost_req_valid;
input           uhost_req_ready;
output [CW-1:0] uhost_req_cmd;
output [AW-1:0] uhost_req_dstaddr;
output [AW-1:0] uhost_req_srcaddr;
output [DW-1:0] uhost_req_data;

input           uhost_resp_valid;
output          uhost_resp_ready;
input [CW-1:0]  uhost_resp_cmd;
input [AW-1:0]  uhost_resp_dstaddr;
input [AW-1:0]  uhost_resp_srcaddr;
input [DW-1:0]  uhost_resp_data;
```
#### 4.3.1 Device Interface

```verilog
input           udev_req_valid;
output          udev_req_ready;
input [CW-1:0]  udev_req_cmd;
input [AW-1:0]  udev_req_dstaddr;
input [AW-1:0]  udev_req_srcaddr;
input [DW-1:0]  udev_req_data;

output          udev_resp_valid;
input           udev_resp_ready;
output [CW-1:0] udev_resp_cmd;
output [AW-1:0] udev_resp_dstaddr;
output [AW-1:0] udev_resp_srcaddr;
output [DW-1:0] udev_resp_data;
```
----
## 5. UMI Link Layer (LUMI)

(Place Holder)

* Serialization
* Flow control
----
## Appendix A: UMI Transaction Translation

### A.1 RISC-V

The following table illustrates the mapping between UMI transactions and RISC-V load store instructions. Extra information fields not provided by the RISC-V ISA (such as as QOS and PRIV) would need to be hard-coded or driven from CSRs.

| RISC-V Instruction   | DATA | SA       | DA | CMD         |
|:--------------------:|------|----------|----|-------------|
| LD RD, offset(RS1)   | --   | addr(RD) | RS1| REQ_RD      |
| SD RD, offset(RS1)   | RD   | addr(RD) | RS1| REQ_WR      |
| AMOADD.D rd,rs2,(rs1)| RD   | addr(RD) | RS1| REQ_ATOMADD |

The address(RD)refers to the ID or source address associated with the RD register in a RISC-V CPU. In a bus based architecture, this would generally be the host-id of the CPU.

### A.2 TileLink

### A.2.1 TileLink Overview

TileLink is a chip-scale interconnect standard providing multiple masters (host) with coherent memory-mapped access to memory and other slave (device) devices.

**TileLink:**

* provides a physically addressed, shared-memory system
* provides coherent access for an arbitrary mix of caching or non-caching masters
* has three conformance levels:
  * TL-UL: Uncached simple read/write operations of a single word (TL-UL)
  * TL-UH: Bursting read/write without support for coherent caches
  * TL-C: Complete cache coherency protocol
* has five separate channels
  * Channel A: Request messages sent to an address
  * Channel B: Request messages sent to a cached block (TL-C only)
  * Channel C: Response messages from a cached block (TL-C only)
  * Channel D: Response messages from an address
  * Channel E: Final handshake for cache block transfer (TL-C only)

### A.1.1 TileLink <-> UMI Mapping

This section outlines the recommended mapping between UMI transaction and the TileLink messages. Here, we only explore mapping TL/UH TileLink modes with UMI 64bit addressing and UMI bit mask support up to 128 bits.

| Symbol | Meaning                   | TileLink Name       |
|:------:|---------------------------|---------------------|
| C      | Data is corrupt           | {a,b,c,d,e}_corrupt |
| BMASK  | Mask (2^SIZE)/8 (strobea) | {a,b,c,d,e}_mask    |
| HOSTID | Source ID                 | {a,b,c,d,e}_source  |

The following table shows the mapping between TileLink and UMI transactions.

| TileLink Message| UMI Transaction |CMD[21:28]|CMD[27:24]|
|-----------------|-----------------|----------|----------|
| Get             | REQ_RD          | 0b0000   |0b0000    |
| AccessAckData   | RESP_WR         | 0b0000   |0b0000    |
| PutFullData     | REQ_WR          | 0b0000   |0b000C    |
| PutPartialData  | REQ_WR          | 0b0000   |0b000C    |
| AccessAck       | RESP_WR         | 0b0000   |0b0000    |
| ArithmaticData  | REQ_ATOMIC      | 0b0000   |0b0000    |
| LogicalData     | REQ_ATOMIC      | 0b0000   |0b000C    |
| Intent          | REQ_RD          | 0b0100   |0b0000    |
| HintAck         | RESP_RD         | 0b0101   |0b0000    |

The TileLink has a single long n bit wide '_size' field, enabling 2^n to transfers per message. This is in contrast to UMI which has two fields a SIZE field to indicate word size and a LEN field to indicate the number of words to be transferred. The number of bytes transferred by a UMI transaction is (2^SIZE)*(LEN+1).

The pseudo code below demonstrates one way of translating from the TileLink size and the UMI SIZE/LEN fields.

```c
if (tilelink_size<8){
   SIZE = tilelink_size;
   LEN = 0;
} else {
   SIZE = 7;
   LEN  = 2^(tilelink_size-8+1)-1
}
```
The TileLink master id and masking signals are mapped to the UMI SA field as shown in the table below.

| Field    |63:40   |39:32 | 31:24  |23:16 | 15:8 | 7:0  |
|----------|:------:|:----:|:------:|:-----|------|------|
| SA       |RESERVED|--    |--      | BMASK|BMASK |HOSTID|

The TileLink atomic operations encoded in the param field map to the UMI ATYPE field as follows.

| TileLink param |UMI ATYPE   |
|----------------|:----------:|
| MIN (0)        | ATOMICMIN  |
| MAX (1)        | ATOMICMAX  |
| MINU (2)       | ATOMICMINU |
| MAXU (3)       | ATOMICMAXU |
| XOR(0)         | ATOMICXOR  |
| OR  (1)        | ATOMICOR   |
| AND  (2)       | ATOMICAND  |
| SWAP  (3)      | ATOMICSWAP |

### A.2 AXI4

### A.2.1 AXI4 Overview

AXI is a transaction based memory access protocol with five independent channels:

* Write requests
* Write data
* Write response
* Read request
* Read data

Terminology:

* Hosts are called 'Managers' in AXI
* Devices are called 'Subordinates' in AXI

Constraints:

* Data width is 8, 16, 32, 64, 128, 256, 512, or 1024 bits wide


### A.2.2 AXI4 <-> UMI Mapping

Table showing mapping between the five AXI channels to UMI messages.

| AXI Channel     | UMI Message |
|-----------------|-------------|
| Write request   | REQ_WR      | 
| Write data      | REQ_WR      | 
| Write response  | RESP_WR     |
| Read request    | REQ_RD      |
| Read data       | RESP_RD     |

The AXI LEN, SIZE, ADDR, DATA, QOS, PROT fields map directly to equivalent UMI CMD fields.

The AXI ID,REGION,and STRB signals map the source address, all other control signals map to the CMD field per the table below.

NOTES: 
* PROT[2] is always set to 0.

| Field    |31:27     |26:25     |
|----------|:--------:|:--------:|
| CMD      |CACHE[3:0]|BURST[1:0]|


| Field    |63:40|39:32|31:24|23:16 |15:12  | 11:8 | 7:0  |
|----------|:---:|:---:|:---:|:-----|-------|------|------|
| SA-64    |R    |R    |STRB |STRB  |AXIUSER|REGION|HOSTID|
| SA-32    |--   |--   |R    |STRB  |AXIUSER|REGION|HOSTID|

### A.3 AXI Stream

### A.3.1 AXI Stream Overview

### A.3.2 AXI Stream <-> UMI Mapping

----
## References

[1] [AMBA AXI Protocol Specification (2023/Mar/01 J)](https://www.arm.com/architecture/system-architectures/amba/amba-specifications)

[2] [TileLink Specification (version 1.7)](https://static.dev.sifive.com/docs/tilelink/tilelink-spec-1.7-draft.pdf)