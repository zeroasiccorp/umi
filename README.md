![UMI](docs/_images/hokusai.jpg)

# Universal Memory Interface (UMI)

## 1. Introduction

### 1.1 Architecture:

The Universal Memory Interface (UMI) is a stack of standardized abstractions for reading and writing memory, with the core principle being that "everything is an address". UMI includes four distinct layers:

* **Protocol**: Protocol/application specific payload (Ethernet, PCIe, ...)
* **Transaction**: Address based request/response transactions
* **Link**: Communication integrity (flow control, reliability)
* **Physical**: Electrical signaling (pins, wires, etc.)

![UMI](docs/_images/umi_stack.svg)


### 1.2 Key Features:

  * designed for high bandwidth and low latency
  * separate request and response channels
  * 64b/32b addressing support
  * bursting of up to 256 transfers
  * data sizes up to 1024 bits per transfer
  * atomic transaction support
  * quality of service support
  * error detection and correction support
  * reserved opcodes for users and future expansion

### 1.3 Terminology:

| Word        | Meaning    |
|-------------|------------|
| Transaction | A memory operation
| Message     | Transaction type (write request, read response, ...)
| Host        | Initiates request
| Device      | Responds to request
| SA          | Source address
| DA          | Destination address
| DATA        | Data packet
| MSG         | Transaction message type
| SIZE        | Data size per individual transfer
| LEN         | Number of individual transfers
| EDAC        | Error detect/correction control
| QOS         | Quality of service
| PRIV        | Privilege mode
| EOF         | End of frame indicator
| EXT         | Extended message option
| USER        | User message bits
| ERR         | Error code
| HOSTID      | Host channel ID
| DEVID       | Device channel ID
| MSB         | Most significant bit

## 2. Protocol UMI (PUMI) Layer

Higher level protocols (such as ethernet) can be layered on top of a UMI
transactions by packing protocol headers and payload data in the transaction 
data field. Payload packing is little endian, with the header starting in byte 
0 of the transaction data field. Protocol header and payload data is transparent to the UMI transaction layer.

Protocol overlay examples:

| Protocol  | Payload(Data) |Header(Data)|Source Addr|Dest Addr| message |
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

* **MSG**: Complete control information specifying the transaction type and options.
* **DA**: Device addresses to access 
* **SA**: Host source address/id to return response to
* **DATA**: Data to be written by a write request or data returned by a read response.

UMI transactions pack these four fields in the order below.

| Architecture |MSB-1:128|127:64|63:32|31:0|
|--------------|:-------:|:----:|:---:|:--:|
| 64b          |DATA     |SA    |DA   | MSG|
| 32b          |DATA     |DATA  |SA,DA| MSG|

The source address(SA) field is used to pass control and routing information from the UMI transaction layer to the [UMI signal layer](#UMI-Signal-layer). 

| SA       |63:40   |39:32 | 31:24  |19:0  |
|----------|:------:|:----:|:------:|:-----|
| 64b mode |RESERVED| USER |USER    | USER |
| 32b mode | --     | --   |RESERVED| USER | 

Read and write transactions are burst based. The number of bytes transferred by a transaction is equal to the size of a data word (SIZE) times the number of transfers in the transaction (LEN). It is legal for an UMI signal layer to split a burst into multiple shorter bursts as long as all bytes arrive correctly and in order.

Constraints:

* Bursts must not cross 4KB address boundaries
* Addresses must be aligned to SIZE
* The maximum data field size is 32,768 bytes.
* All transactions must complete (no partial data deliveries)

### 3.2 Transaction Decode

The following table shows the complete set of UMI transaction types. Descriptions of each message is found in the [Message Description Section](#34-message-descriptions).  

|Message     |DATA|SA|DA|31 |30:24|23:22|21:20|19:18|17:16|15:8 |7:4     |3:0|
|------------|:--:|--|--|---|:---:|:---:|:---:|-----|-----|-----|:------:|---|
|INVALID     |    |Y |Y |-- |--   |--   |--   |--   |--   |--   |0x0     |0x0|
|REQ_RD      |    |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOB,SIZE|0x1|
|REQ_WR      |Y   |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOB,SIZE|0x3|
|REQ_WRPOSTED|Y   |Y*|Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOB,SIZE|0x5|
|REQ_RDMA    |    |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOB,SIZE|0x7|
|REQ_ATOMIC  |Y   |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |ATYPE|1,SIZE  |0x9|
|REQ_ERROR   |Y   |Y |Y |EXT|USER |USER |00   |EDAC |PRIV |ERR  |0,0x0   |0xF|
|REQ_LINK    |    |  |  |0  | --  |--   |--   |--   |--   |--   |0,0x1   |0xF|
|RESP_READ   |Y   |Y |Y |EXT|USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOB,SIZE|0x2|
|RESP_WR     |    |Y |Y |EXT|USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOB,SIZE|0x4|
|RESP_LINK   |    |  |  |-- |--   |--   |--   |--   |--   |--   |0, 0x0  |0xE|

Unused MSG opcodes are reserved for user defined messages and future expansion according to the table below.

| MSG[3:0] | Reserved for    |
|----------|-----------------|
| 0x6      | USER RESPONSE   |
| 0x8      | USER RESPONSE   |
| 0xA      | FUTURE RESPONSE |
| 0xC      | FUTURE RESPONSE |  
| 0xB      | USER REQUEST    |
| 0xD      | FUTURE REQUEST  |

### 3.3 Options Decode

### 3.3.1 Transaction Length (LEN[7:0])

The LEN field defines the number of data transfers (beats) to be completed in sequence in the transaction. Each one of the data transfers is the size defined by the SIZE field. The LEN field is 8 bits wide, supporting 1 to 256 transfers (beats) per transaction. 

The address of a transfer number 'i' in a burst of length LEN is defined by:

ADDR_i = START_ADDR + (i-1) * 2^SIZE.

### 3.3.2 Transfer Size (SIZE[2:0])

The SIZE field defines the number of bytes in each data transfer (beat) in a transaction. THe transfer size must not exceed the data bus width of the host or device involved in the transaction.

|SIZE[2:0] |Bytes per transfer|
|:--------:|:----------------:|
| 0b000    | 1
| 0b001    | 2
| 0b010    | 4
| 0b011    | 8
| 0b100    | 16
| 0b101    | 32
| 0b110    | 64
| 0b111    | 128

### 3.3.3 End of Burst (EOB)

The EOB bit is reserved for the UMI signal layer to indicate that the last transfer in a sequence of burst transactions.

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

### 3.3.7 User Field (USER[8:0])

The USER field is reserved for the protocol layer to tunnel information to the signal layer or as hints and control bits for the endpoint.

### 3.3.8 Command Extension (EXT)

The EXT field enables expanding the types of transactions and options
available at the transaction layer by leveraging the lower bits of the data
field. The EXT command can be used to support complex non-UMI protocols that may require a large number features (such as cache coherent protocols).

### 3.3.9 Error Code (ERR[1:0])

The ERR field indicates the transaction error type for the REQ_ERROR and RESP_ERRROR transactions. 

|ERR[1:0]| Meaning                            |
|:------:|------------------------------------|
| 0h00   | OK (no error)                      |
| 0b01   | EXOK (successful exclusive access) |
| 0b10   | DEVERR (device error)              |
| 0b11   | NETERR (network error)             |

DEVERR trigger examples:

* Insufficient privelege level for access
* Write attempted to read-only location
* Unsupported transfer size
* Access attempt to disabled function

DECERR trigger examples:
* Device address unreachable

### 3.3.10 Error Code (ATYPE[7:0])

The ATYPE field indicates the type of the atomic transaction.

|ATYPE[7:0]| Meaning     |
|:--------:|-------------|
| 0h00     | Atomic add  |
| 0h01     | Atomic and  |
| 0h02     | Atomic or   |
| 0h03     | Atomic xor  |
| 0h04     | Atomic max  |
| 0h05     | Atomic min  |
| 0h06     | Atomic maxu |
| 0h07     | Atomic minu |
| 0h08     | Atomic swap |


### 3.3.11 End of Burst (EOF)

The EOF bit indicate that this is the last UMI transaction in a sequence of related transactions. Single-transaction requests and responses must set the EOF bit to 1. Use of the EOF bit at an endpoint is optional and implementation specific. The EOF can be used as a hardware interrupt or as a bit in memory to be queried by software or hardware.

## 3.4 Message Descriptions

### 3.4.1 INVALID

INVALID indicates an invalid transaction. A receiver can choose to ignore the transaction or to take corrective action.

### 3.4.2 REQ_RD

REQ_RD reads SIZE * LEN bytes from device address(DA). The device initiates a RESP_RD transaction to return data to the host source address (SA).  

### 3.4.3 REQ_WR

REQ_WR writes SIZE * LEN bytes to destination address(DA). The device then initiates a RESP_WR acknowledgment to the host source address (SA).

### 3.4.4 REQ_WRPOSTED

REQ_WRPOSTED performs a posted-write of SIZE * LEN bytes to destination address(DA). There is no response sent back to the host from the device.

### 3.4.5 REQ_RDMA

REQ_RDMA reads SIZE * LEN bytes of data from a primary device destination address(DA) along with a source address (SA). The primary device then initiates a REQ_WRPOSTED transaction to write SIZE * LEN data bytes to the address (SA) in a secondary device. REQ_DMA requires the complete SA field so does not support pass through information for the UMI signal layer.

### 3.4.6 REQ_ATOMIC{ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP}

REQ_ATOMIC initiates an atomic read-modify-write operation at destination address (DA). The REQ_ATOMIC sequence involves: 1.) the host sending data (D), destination address (DA), and source address (SA) to the device, 2.) the device reading data address DA 3.) applying a binary operator {ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP} between D and the original device data, 4.) writing the result back to device address DA 4.) returning the original device data to host address SA.

### 3.4.7 REQ_ERROR

REQ_ERROR sends an error code (ERR), data (D), and source address (SA) to  device address (DA) to indicate that an error has occurred. A receiver can choose to ignore the transaction or to take corrective action. There is no response transaction sent back to the host from the device.

### 3.4.8 REQ_LINK

REQ_LINK is a 32 bit control-only message reserved for internal link layer actions such as credit updates, time stamps, and framing. MSG[31-7] are all available as user specified control bits. The message does not include routing information and does not elicit a response from the receiver.

### 3.4.9 RESP_RD

RESP_RD returns SIZE * LEN bytes of data to the host source address (SA) as a response to a REQ_RD transaction. The device destination address is sent along with the SA and DATA to filter incoming transactions in case of multiple outstanding read requests.

### 3.4.10 RESP_WR

RESP_WR returns an acknowledgment to the host source address (SA) as a response to a REQ_WR transaction. The device destination address is sent along with the response transaction to filter incoming transactions in case of multiple outstanding write requests.

### 3.4.11 RESP_LINK

RESP_LINK is a 32 bit control-only message reserved for internal link layer actions such as credit updates, time stamps, and framing. MSG[31-7] are all available as user specified control bits. The message does not include routing information and does not elicit a response from the receiver.

### 3.5 Transaction Mapping Examples

The following table illustrates the mapping between UMI transactions map and 
a similar abstraction model: load/store instructions in the RISC-V ISA.
Extra information fields not provided by the RISC-V ISA (such as as QOS, EDAC, PRIV) would need to be hard-coded or driven from CSRs. 

| RISC-V Instruction   | DATA | SA       | DA | MSG         |
|:--------------------:|------|----------|----|-------------|
| LD RD, offset(RS1)   | --   | ADDR(CPU)| RS1| REQ_RD      |
| SD RD, offset(RS1)   | RD   | ADDR(CPU)| RS1| REQ_WR      |
| AMOADD.D rd,rs2,(rs1)| RD   | ADDR(CPU)| RS1| REQ_ATOMADD |

## 4. Signal UMI (SUMI) Layer

### 4.1 Theory of Operation

The UMI signaling layer (SUMI) defines the mapping of the UMI transaction fields
to physical signaling. The SUMI layer is a point-to-point latency insensitive synchronous implementation of the UMI transactions with a simple valid/ready [handshake protocol](#32-handshake-protocol).

![UMI](docs/_images/sumi_connections.png)

The SUMI signaling layer supports the following field widths.

| Field    | Width (bits)       |
|:--------:|--------------------|
| MSG      | 32                 |
| DA       | 32, 64             |
| SA       | 32, 64             |
| DATA     | 64,128,256,512,1024| 

UMI with bursts (LEN*SIZE) greater than the DATA width are split into shorter SUMI transfers sent over multiple clock cycles. The EOB bit is used to 
indicate that this is the last transfer of a UMI transaction burst, to be used by a device to return a response. The signal layer implementation must update the addresses, sizes, and lengths appropriately when splitting large bursts to ensure that all UMI transfers can reach the final destinations independent of each other.

The following example illustrates a a TUMI 128 byte write burst split into two 64 byte SUMI transfers for an implementation DW of 512.

TUMI REQ_WR transaction:

* LEN =  0h01
* SIZE = 0b110
* DA   = 0x0

SUMI REQ_WR #1:

* LEN =  0h00
* SIZE = 0b110
* DA   = 0x0
* EOB  = 0

SUMI REQ_WR #2:

* LEN  =  0h00
* SIZE = 0b110
* DA   = 0x40
* EOB  = 1

### 4.2 Handshake Protocol

![UMI](docs/_images/ready_valid.svg)

UMI adheres to the following ready/valid handshake protocol:
1. A transaction occurs on every rising clock edge in which READY and VALID are both asserted.
2. Once VALID is asserted, it must not be de-asserted until a transaction completes.
3. READY, on the other hand, may be de-asserted before a transaction completes.
3. The assertion of VALID must not depend on the assertion of READY.  In other words, it is not legal for the VALID assertion to wait for the READY assertion.
4. However, it is legal for the READY assertion to be dependent on the VALID assertion (as long as this dependence is not combinational).

In the following examples, the packet is defined as the concatenation of {DATA, SA, DA, MSG} for the sake of brevity.

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

### 4.3 SUMI Signal Interfaces

Components in a system can have a UMI host port, device port or both. AW and DW can be any legal value defined by the [SUMI layer](#41-theory-of-operation)  

#### 4.3.1 Host Interface

```verilog
output        uhost_req_valid;
input         uhost_req_ready;
output [31:0] uhost_req_msg;
output [AW:0] uhost_req_dstaddr;
output [AW:0] uhost_req_srcaddr;
output [DW:0] uhost_req_data;
input         uhost_resp_valid;
output        uhost_resp_ready;
input [31:0]  uhost_resp_msg;
input [AW:0]  uhost_resp_dstaddr;
input [AW:0]  uhost_resp_srcaddr;
input [DW:0]  uhost_resp_data;
```
#### 4.3.1 Device Interface

```verilog
input         udev_req_valid;
input [31:0]  udev_req_msg;
input [AW:0]  udev_req_dstaddr;
input [AW:0]  udev_req_srcaddr;
input [DW:0]  udev_req_data;
output        udev_req_ready;
output [31:0] udev_resp_msg;
output [AW:0] udev_resp_dstaddr;
output [AW:0] udev_resp_srcaddr;
output [DW:0] udev_resp_data;
output        udev_resp_valid;
input         udev_resp_ready;
```
