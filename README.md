![UMI](docs/_images/hokusai.jpg)

# Universal Memory Interface (UMI)

## 1. Introduction

### 1.1 Architecture:

The Universal Memory Interface (UMI) is a set of standardized abstractions for reading and writing memory mapped devices. UMI includes five distinct layers:

* **Protocol**: Protocol/application specific payload (Ethernet, PCIe, ...)
* **Transaction**: Address based request/response transactions
* **Signal**: Latency insensitive intermediate layer (packet, ready, valid)
* **Link**: Communication integrity (flow control, reliability)
* **Physical**: Electrical signaling (pins, wires, etc.)

![UMI](docs/_images/umi_stack.svg)


### 1.2 Key Features:

  * designed for high bandwidth and low latency
  * separate request and response channels
  * 64b/32b addressing support
  * word sizes up to 1024 bits
  * total data payloads up to 32,768 bytes
  * atomic transaction support
  * quality of service support
  * error detection and correction support
  * reserved opcodes for users and future expansion

### 1.3 Terminology:

| Word        | Meaning    |
|-------------|------------|
| Transaction | Memory operation
| Host        | Initiates request
| Device      | Responds to request
| Flit        | An atomic self contained transaction piece
| CMD         | Transaction command (opcodes + options)
| DA          | Transaction device address (target of a request)
| SA          | Transaction source address (where to send the response)
| DATA        | Transaction data
| OPCODE      | Transaction opcode
| SIZE        | Data size per individual word in a transaction
| LEN         | Number of individual words in a transaction
| EDAC        | Error detect/correction control
| QOS         | Quality of service
| PRIV        | Privilege mode
| EOF         | End of frame indicator
| EOT         | End of transaction indicator
| USER        | User defined transaction information
| ERR         | Error code
| HOSTID      | Host channel ID
| DEVID       | Device channel ID
| MSB         | Most significant bit

## 2. Protocol UMI (PUMI) Layer

UMI transaction header packing is little endian, with the header starting in byte 0 of the transaction data field. Protocol layer header and payload are transparent to the UMI transaction layer and are treated as a series of opaque bytes.

Protocol overlay examples:

| Protocol  | Payload(DATA) |Header(DATA)|Source Addr|Dest Addr| Command |
|:---------:|:-------------:|:----------:|:---------:|:-------:|:-------:|
| Ethernet  | 64B - 1,518B  |14B         | 4/8B      | 4/8B    | 4B      |
| CXL-68    | 64B           |2B          | 4/8B      | 4/8B    | 4B      |
| CXL-256   | 254B          |2B          | 4/8B      | 4/8B    | 4B      |

## 3. Transaction UMI (TUMI) Layer

### 3.1 Theory of Operation

The UMI transaction layer defines a request-response memory access architecture. Hosts send read and write memory requests and devices return responses. The figure below illustrates the relationship between hosts, devices, and a interconnect networks.

![UMI](docs/_images/tumi_connections.png)

Hosts:

* Initiate request transactions
* Validate and execute incoming response transactions
* Identify egress interface through which to send request (in case of multiple)

Devices:

* Validate and execute incoming request transactions
* Initiate response transactions when required
* Identify egress interface through which to send response (in case of multiple)

Transactions include the following information fields:

* **CMD**: Complete control information specifying the transaction type and options.
* **DA**: Device address
* **SA**: Host source address/id to return response to
* **DATA**: Request write data or response read data.

UMI transactions pack these four fields in the order below.

| Architecture |MSB-1:160|159:96|95:32|31:0|
|--------------|:-------:|:----:|:---:|:--:|
| 64b          |DATA     |SA    |DA   | CMD|
| 32b          |DATA     |DATA  |SA,DA| CMD|

The source address(SA) field is used to pass control and routing information from the UMI transaction layer to the [UMI signal layer](#UMI-Signal-layer). The RESERVED bits are dedicated to implementation specific response routing information. The function of each USER bits is defined in the signal layer definitions.

| SA       |63:40   |39:32 | 31:24  |19:0  |
|----------|:------:|:----:|:------:|:-----|
| 64b mode |RESERVED| USER |USER    | USER |
| 32b mode | --     | --   |RESERVED| USER |

A UMI transaction describes the transfer of a one or more words (LEN+1) of the same size (2^SIZE bytes). It is legal for a UMI signal layer to split a transaction into multiple shorter transactions as long as all bytes arrive correctly and in order, and the SIZE field is maintained.

Constraints:

* Transactions must not cross 4KB address boundaries
* Device and source addresses (DA) must be aligned to 2^SIZE bytes.
* The maximum data field size is 32,768 bytes (LEN=255, SIZE=7).
* No partial transactions, data bytes delivered must be (LEN+1)*(2^SIZE).

Ordering Model:

* Requests sent by a host destined for the same device arrive in the same order that they were sent.
* Responses sent by a device destined for the same host arrive in the same order that they were sent.
 
### 3.2 Transaction Listing

The following table shows the complete set of UMI transactions. Descriptions of each transaction can be found in the [Transaction Description Section](#34-transaction-descriptions).

|Transaction |DATA|SA|DA|31:24|23:22|21:20|19:18|17:16|15:8 |7  | 6:4 |3:0|
|------------|:--:|--|--|:---:|:---:|:---:|-----|-----|-----|---|:---:|---|
|INVALID     |    |Y |Y |--   |--   |--   |--   |--   |--   |0  |0x0  |0x0|
|REQ_RD      |    |Y |Y |USER |USER |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x1|
|REQ_WR      |Y   |Y |Y |USER |USER |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x3|
|REQ_WRPOSTED|Y   |Y |Y |USER |USER |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x5|
|REQ_RDMA    |    |Y |Y |USER |USER |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x7|
|REQ_ATOMIC  |Y   |Y |Y |USER |USER |QOS  |EDAC |PRIV |ATYPE|1  |SIZE |0x9|
|REQ_USER0   |Y   |Y |Y |USER |USER |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0xB|
|REQ_FUTURE0 |Y   |Y |Y |USER |USER |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0xD|
|REQ_ERROR   |    |Y |Y |USER |USER |QOS  |EDAC |PRIV |ERR  |1  |0x0  |0xF|
|REQ_LINK    |    |  |  |USER |USER |USER |USER |USER |USER |1  |0x1  |0xF|
|RESP_READ   |Y   |Y |Y |USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x2|
|RESP_WR     |    |Y |Y |USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x4|
|RESP_USER0  |    |Y |Y |USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x6|
|RESP_USER1  |    |Y |Y |USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0x8|
|RESP_FUTURE0|    |Y |Y |USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0xA|
|RESP_FUTURE1|    |Y |Y |USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF|SIZE |0xC|
|RESP_LINK   |    |  |  |USER |USER |USER |USER |USER |USER |1  | 0x0 |0xE|

RESP_USER* and REQ_USER* transaction types are reserved for custom implementations and should be considered non-standard.

RESP_FUTURE* and REQ_FUTURE* transaction types are reserved for future UMI feature enhancements.

### 3.3 Command Options

### 3.3.1 Transaction Length (LEN[7:0])

The LEN field defines the number of words of size 2^SIZE bytes transferred by a transaction. The number of transfers is equal to LEN + 1, equating to a range of 1-256 transfers per transaction. The current address of transfer number 'i' in a transaction is defined by:

ADDR_i = START_ADDR + (i-1) * 2^SIZE.

### 3.3.2 Transfer Size (SIZE[2:0])

The SIZE field defines the number of bytes in a transaction word.
Devices are not required to support all SIZE options. Hosts must not send  transactions with a SIZE field unsupported the target device.

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

### 3.3.3 End of Frame (EOF)

The EOF bit indicates that this transaction is the last transaction in a sequence of related UMI transactions.

### 3.3.4 Privilege Mode (PRIV[1:0])

The PRIV field indicates the privilege level of the transaction, following the
RISC-V architecture convention. The information enables control access to memory at an end point based on privilege mode.

|PRIV[1:0]| Level | Name      |
|:-------:|:-----:|-----------|
| 0b00    | 0     | User      |
| 0b01    | 1     | Supervisor|
| 0b10    | 2     | Hypervisor|
| 0b11    | 3     | Machine   |

### 3.3.5 Error Detection and Correction (EDAC[1:0])

The EDAC transaction field controls how data errors should be detected and
corrected. Availability of the different EDAC modes and the implementation
of each mode is implementation specific.

|EDAC[1:0]| Operation |
|:-------:|-----------|
| 0b00    | No error detection or correction.
| 0b01    | Detect errors and respond with an error code on failure
| 0b10    | Detect errors and retry transaction on failure
| 0b11    | Require forward error correction

### 3.3.6 Quality of Service (QOS[1:0])

The QOS transaction dictates the quality of service required by the transaction, enabling a UMI compatible hardware implementation to prioritize urgent transactions over over non-critical bulk traffic. The highest priority level is reserved for the underlying hardware implementation.

|QOS[1:0] | Priority    |
|:-------:|-------------|
| 0b00    | 0 (highest) |
| 0b01    | 1           |
| 0b10    | 2           |
| 0b11    | 3 (lowest)  |

### 3.3.7 User Field (USER[10:0])

The USER field is reserved for the protocol layer to tunnel information to the signal layer or as hints and control bits for the endpoint.

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

### 3.3.10 Atomic Transaction Type (ATYPE[7:0])

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

### 3.3.11 End of Frame (EOF)

The EOF bit indicate that this is the last UMI transaction in a sequence of related transactions. Single-transaction requests and responses must set the EOF bit to 1. Use of the EOF bit at an endpoint is optional and implementation specific. The EOF can be used as a hardware interrupt or as a bit in memory to be queried by software or hardware.

## 3.4 Transaction Descriptions

### 3.4.1 INVALID

INVALID indicates an invalid transaction. A receiver can choose to ignore the transaction or to take corrective action.

### 3.4.2 REQ_RD

REQ_RD reads (2^SIZE)*(LEN+1) bytes from device address(DA). The device initiates a RESP_RD transaction to return data to the host source address (SA).

### 3.4.3 REQ_WR

REQ_WR writes (2^SIZE)*(LEN+1) bytes to destination address(DA). The device then initiates a RESP_WR acknowledgment to the host source address (SA).

### 3.4.4 REQ_WRPOSTED

REQ_WRPOSTED performs a posted-write of (2^SIZE)*(LEN+1) bytes to destination address(DA). There is no response sent by the device back to the host.

### 3.4.5 REQ_RDMA

REQ_RDMA reads (2^SIZE)*(LEN+1) bytes of data from a primary device destination address(DA) along with a source address (SA). The primary device then initiates a REQ_WRPOSTED transaction to write (2^SIZE)*(LEN+1) data bytes to the address (SA) in a secondary device. REQ_RDMA requires the complete SA field for addressing and does not support pass through information for the UMI signal layer.

### 3.4.6 REQ_ATOMIC{ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP}

REQ_ATOMIC initiates an atomic read-modify-write operation at destination address (DA) of size (2^SIZE). The REQ_ATOMIC sequence involves:

1. Host sending data (DATA), destination address (DA), and source address (SA) to the device,
2. Device reading data address DA
3. Applying a binary operator {ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP} between D and the original device data
4. Writing the result back to device address DA
5. Returning the original device data to host address SA

### 3.4.7 REQ_ERROR

REQ_ERROR sends an error code to a device (ERR) to indicate that an error has occurred. The device can choose to ignore the transaction or to take corrective action. There is no response sent back to the host from the device.

### 3.4.8 REQ_LINK

RESP_LINK is a reserved CMD only transaction for link layer non-memory mapped actions such as credit updates, time stamps, and framing. CMD[31-8] are all available as user specified control bits. The transaction is local to the signal (physical) layer and does not include routing information and does not elicit a response from the receiver.

### 3.4.9 RESP_RD

RESP_RD returns (2^SIZE)*(LEN+1) bytes of data to the host source address (SA) specified by the REQ_RD transaction. The device destination address is sent along with the SA and DATA to filter incoming transactions in case of multiple outstanding read requests.

### 3.4.10 RESP_WR

RESP_WR returns an acknowledgment to the original source address (SA) specified by the the REQ_WR transaction. The transaction does not return any DATA.

### 3.4.11 RESP_LINK

RESP_LINK is a reserved CMD only transaction for link layer non-memory mapped actions such as credit updates, time stamps, and framing. CMD[31-8] are all available as user specified control bits. The transaction is local to the signal (physical) layer and does not include routing information.

### 3.5 Transaction Mapping Examples

The following table illustrates the mapping between UMI transactions map and
a similar abstraction model: load/store instructions in the RISC-V ISA.
Extra information fields not provided by the RISC-V ISA (such as as QOS, EDAC, PRIV) would need to be hard-coded or driven from CSRs.

| RISC-V Instruction   | DATA | SA       | DA | CMD         |
|:--------------------:|------|----------|----|-------------|
| LD RD, offset(RS1)   | --   | addr(RD) | RS1| REQ_RD      |
| SD RD, offset(RS1)   | RD   | addr(RD) | RS1| REQ_WR      |
| AMOADD.D rd,rs2,(rs1)| RD   | addr(RD) | RS1| REQ_ATOMADD |

The address(RD)refers to the ID or source address associated with the RD register in a RISC-V CPU. In a bus based architecture, this would generally be the host-id of the CPU.

## 4. Signal UMI (SUMI) Layer

### 4.1 Theory of Operation

The UMI signaling layer (SUMI) defines the mapping of UMI transactions to a
point-to-point, latency insensitive, parallel, synchronous interface with a [valid ready handshake protocol](#32-handshake-protocol).

![UMI](docs/_images/sumi_connections.png)

The SUMI signaling layer supports the following field widths.

| Field    | Width (bits)       |
|:--------:|--------------------|
| CMD      | 32                 |
| DA       | 32, 64             |
| SA       | 32, 64             |
| DATA     | 64,128,256,512,1024|

TUMI transactions with word sizes exceeding the SUMI layer data width are split into self contained flits sent over multiple clock cycles. CMD[31] is used as an end of transaction (EOT) indicator.

The folllowing example illustrates a complete request-response transaction between a host and a device. 

![UMIX7](docs/_images/example_rw_xaction.svg)

The following example illustrates a TUMI 128 byte write request split into two separate SUMI request flits in a SUMI implementation with a 64B data width.

TUMI REQ_WR transaction:

* LEN =  0h01
* SIZE = 0b110
* DA   = 0x0

SUMI REQ_WR #1:

* LEN =  0h00
* SIZE = 0b110
* DA   = 0x0
* EOT  = 0

SUMI REQ_WR #2:

* LEN  =  0h00
* SIZE = 0b110
* DA   = 0x40
* EOT  = 1

### 4.2 Handshake Protocol

The SUMI signal layer adheres to the following ready/valid handshake protocol:

![UMI](docs/_images/ready_valid.svg)

1. A transaction occurs on every rising clock edge in which READY and VALID are both asserted.
2. Once VALID is asserted, it must not be de-asserted until a transaction completes.
3. READY, on the other hand, may be de-asserted before a transaction completes.
4. The assertion of VALID must not depend on the assertion of READY.  In other words, it is not legal for the VALID assertion to wait for the READY assertion.
5. However, it is legal for the READY assertion to be dependent on the VALID assertion (as long as this dependence is not combinational).

In the following examples, the packet is defined as the concatenation of {DATA, SA, DA, CMD} for the sake of brevity.

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

### 4.3 SUMI Components Interfaces

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
