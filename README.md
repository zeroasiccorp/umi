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
| Transaction | Single memory operation (typically memory reads and writes)
| Message     | Type of transaction (read request, write response, read response, ...)
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

Higher level protocols (such as ethernet) can be layered on top of a
UMI transactions by packing protocol headers and payload data in the transaction data field. Payload packing is little endian, with the header starting in byte 0 of the transaction data field. Protocol header and payload data is transparent to the UMI transaction layer.

Protocol overlay examples:

| Protocol  | Payload(Data) |Header(Data)|Source Addr|Dest Addr| message |
|:---------:|:-------------:|:----------:|:---------:|:-------:|:-------:|
| Ethernet  | 64B - 1,518B  |14B         | 4/8B      | 4/8B    | 4B      |
| CXL-68    | 64B           |2B          | 4/8B      | 4/8B    | 4B      |
| CXL-256   | 254B          |2B          | 4/8B      | 4/8B    | 4B      |

## 3. Transaction UMI (TUMI) Layer

### 3.1 Theory of Operation

The UMI transaction layer is a request/response memory access architecture. Hosts send read and write requests and devices return responses. The figure below illustrates the relationship between hosts, devices, and a network.

![UMI](docs/_images/tumi_connections.png)

Host shall:

* Initiate request transations
* Validate and execute incoming response transactions
* Identify egress interface through which to send request (in case of multiple)


Device shall:

* Validate and execute incoming request transactions
* Initiate response transactions when required
* Identify egress interface through which to send response (in case of multiple)

All transactions include the following fields:

* **MSG**: Complete control information specifying the transaction type and options.
* **DA**: Device address for reading and writing
* **SA**: Host source address/id
* **DATA**: Data to be written by a write request or returned by a read response.

UMI transactions are defined as packets with the following ordering.

| Architecture |MSB-1:128|127:64|63:32|31:0|
|--------------|:-------:|:----:|:---:|:--:|
| 64b          |DATA     |SA    |DA   | MSG|
| 32b          |DATA     |DATA  |SA,DA| MSG|

The source address (SA) field is used to pass control and routing information from the UMI transaction layer to the [UMI signal layer](#UMI-Signal-layer). All bits in the SA is effectively RESERVED for signal layer use.

Read and write transactions are burst based. The number of bytes transferred by a transaction is equal to the size of a data word (SIZE) times the number of transfers in the transaction (LEN). T

Constraints:

* Bursts must not cross 4KB address boundaries
* Addresses must be aligned to SIZE
* The maximum data payload is 32,768 bytes.
* Transactions must complete (no partial data deliveries)

### 3.2 Transaction Decode

The following table shows the complete set of UMI transaction types. Descriotions of each message is found in the Message Description Section.  

|Message     |DATA|SA|DA|31 |30:24|23:22|21:20|19:18|17:16|15:8 |7:4     |3:0|
|------------|:--:|--|--|---|:---:|:---:|:---:|-----|-----|-----|:------:|---|
|INVALID     |    |Y |Y |-- |--   |--   |--   |--   |--   |--   |0x0     |0x0|
|REQ_RD      |    |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOF,SIZE|0x1|
|REQ_WR      |Y   |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOF,SIZE|0x3|
|REQ_WRPOSTED|Y   |Y*|Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOF,SIZE|0x5|
|REQ_RDMA    |    |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |LEN  |EOF,SIZE|0x7|
|REQ_ATOMIC  |Y   |Y |Y |EXT|USER |USER |QOS  |EDAC |PRIV |ATYPE|1,SIZE  |0x9|
|REQ_ERROR   |Y   |Y |Y |EXT|USER |USER |00   |EDAC |PRIV |ERR  |0,0x0   |0xF|
|REQ_LINK    |    |  |  |0  | --  |--   |--   |--   |--   |--   |0,0x1   |0xF|
|RESP_READ   |Y   |Y |Y |EXT|USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF,SIZE|0x2|
|RESP_WR     |    |Y |Y |EXT|USER |ERR  |QOS  |EDAC |PRIV |LEN  |EOF,SIZE|0x4|
|RESP_LINK   |    |  |  |-- |--   |--   |--   |--   |--   |--   |0, 0x0  |0xE|


The following command opcodes are reserved:

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

A transaction starts with a host driving control information and the address of the first byte involved. The LEN field field defines the number of data transfers (beats) to be completed in sequence in the transaction. Each one of the data transfers is the size defined by the SIZE field. The LEN field is 8 bits wide, supporting 1 to 256 transfers(beats) per transaction.

The address of a transfer number 'i' in a burst of length LEN is defined by:

ADDR_i = START_ADDR + (i-1) * 2^SIZE.

### 3.3.2 Transfer Size (SIZE[2:0])

The SIZE field defines the number of bytes in each data transfer (beat) in a transaction. THe transfer size must not exceed the data bus width of the host or device involved in the transaction.

|SIZE[2:0] |Bytes per transfer|
|:--------:|:----------------:|
| 0b000    | 1
| 0b001    | 2
| 0b010    | 4
| 0b100    | 8
| 0b101    | 16
| 0b110    | 32
| 0b111    | 128

### 3.3.3 End of Frame (EOF)

The EOF transaction field indicates that the current transaction is the last in a sequence of related UMI transactions. Single-transaction requests and responses must set the EOF bit to 1. Use of the EOF bit at the end-point
is optional and implementation specific. The EOF can be used as a hardware interrupt or as a bit in memory to be queried by software or hardware.

### 3.3.4 Privilege Mode (PRIV[1:0])

The PRIV transaction field indicates the privilege level of the transaction,
following the RISC-V architecture convention. The information enables
control access to memory at an end point based on privilege mode.

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
| 0b00    | No error detection or correction. Assumes a reliable channel
| 0b01    | Detect errors and respond with an error code on failure
| 0b10    | Detect errors and retry transaction on failure
| 0b11    | Forward error correction

### 3.3.6 Quality of Service (QOS[1:0])

The QOS transaction indicates the quality of service required by the transaction, enabling a UMI compatible hardware implementation to prioritize urgent transactions over over non-critical bulk traffic. The highest priority level is reserved for the underlying hardware implementation.

|QOS[1:0] | Priority    |
|:-------:|-------------|
| 0b00    | 0 (highest) |
| 0b01    | 1           |
| 0b10    | 2           |
| 0b11    | 3 (lowest)  |

### 3.3.7 User Field (USER[8:0])

The USER field can be used by an application or protocol to tunnel
information to the physical layer or as hints and directions to the endpoint.

This field will likely be reduced as more essential command features are
developed.

### 3.3.8 Command Extension (EXT)

The EXT field enables expanding the types of transactions and options
available by leveraging the lower bits of the data and source address fields.
The EXT command can be used to support complex non-UMI protocols that may
require a large number features (such as cache coherent protocols). Bits
39:0 of the source address bits can be used for control information when
EXT = 1. The EXT mode is not available for transactions that do not require
a source address field or in implementations that require all 64 bits of
the source field for operation.

### 3.3.9 Error Code (ERR[1:0])

The ERR field indicates the transaction error type for the REQ_ERROR and RESP_ERRROR transactions.

|ERR[1:0]| Meaning                            |
|:------:|------------------------------------|
| 0h00   | OK (no error)                      |
| 0b01   | EXOK (successful exclusive access) |
| 0b10   | DEVERR (device error)              |
| 0b11   | NETERR (network error)             |

### 3.3.10 Error Code (ATYPE[3:0])

The ATYPE field indicates the type of the atomic transaction.

|ATYPE[3:0]| Meaning     |
|:--------:|-------------|
| 0h00     | Atomic add  |
| 0b01     | Atomic and  |
| 0h02     | Atomic or   |
| 0b03     | Atomic xor  |
| 0h04     | Atomic max  |
| 0b05     | Atomic min  |
| 0h06     | Atomic maxu |
| 0b07     | Atomic minu |
| 0h08     | Atomic swap |

## 3.4 Command Descriptions

### 3.4.1 INVALID

INVALID indicates an invalid transaction. A receiver can choose to ignore the transaction or to take corrective action.

### 3.4.2 REQ_RD

REQ_RD reads SIZE * LEN bytes from destination address(DA). If successful, the device initiates a RESP_RD transaction to return the data to the host source address (SA). If unsuccessful, a RES_ERROR transaction is returned to the host with an error code.  

### 3.4.3 REQ_WR

REQ_WR writes SIZE * LEN bytes to destination address(DA). If successful, the device then initiates a RESP_WR acknowledgment to the host source address (SA). If unsuccessful, a RES_ERROR transaction is returned to the host with an error code.

### 3.4.4 REQ_WRPOSTED

REQ_WRPOSTED performs a posted-write of SIZE * LEN bytes to destination address(DA). There is no response transaction sent back to the host from the device.

### 3.4.5 REQ_RDMA

REQ_RDMA reads SIZE * LEN bytes of data from a primary destination address(DA). If successful, the primary device then initiates a REQ_WRPOSTED transaction to write SIZE * LEN data to an address (SA) in a secondary device. The REQ_DMA message do not support the use of HOSTID and DEVID since all SA bits are used for
memory read/write addressing.

### 3.4.6 REQ_ATOMIC{ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP}

REQ_ATOMIC initiates an atomic read-modify-write operation at destination address (DA). The REQ_ATOMIC sequence involves: 1.) the host sending data (D), destination address (DA), and source address (SA) to the device, 2.) the device reading data address DA 3.) applying a binary operator {ADD,OR,XOR,MAX,MIN,MAXU,MINU,SWAP} between D and the original device data, 4.) writing the result back to device address DA 4.) returning the original device data to host address SA.

### 3.4.7 REQ_ERROR

REQ_ERROR sends an error code (ERR), data (D), and source address (SA) to  device address (DA) to indicate that an error has occurred. A receiver can choose to ignore the transaction or to take corrective action. There is no response transaction sent back to the host from the device.

### 3.4.8 REQ_LINK

REQ_LINK is a 32 bit control-only request transaction sent from a host to a device reserved for actions such as credit updates, time stamps, and framing. MSG[30-7] are all available as user specified control bits. There is no response transaction sent back to the host from the device.

### 3.4.9 RESP_RD

RESP_RD returns SIZE * LEN bytes of data to the host source address (SA) as a response to a REQ_RD transaction. The device destination address is sent along with the SA and DATA to filter incoming transactions in case of multiple outstanding read requests.

### 3.4.10 RESP_WR

RESP_WR returns an acknowledgment to the host source address (SA) as a response to a REQ_WR transaction. The device destination address is sent along with the response transaction to filter incoming transactions in case of multiple outstanding write requests.

### 3.4.11 RESP_LINK

RESP_LINK returns an acknowledgment to the host source address (SA) as a response to a REQ_WR transaction.

REQ_LINK is a 32 bit control-only point-to-point transaction sent from a host to a device reserved for actions such as credit updates, time stamps, and framing. MSG[30-7] are available as user specified control bits. 


### 3.5 Transaction Mapping Examples

The following table illustrates how the UMI transaction layer maps the RISC-V hardware abstraction layer.
Control bits not available in the RISC-V ISA would be driven by CSRs.

| RISC-V Instruction   | DATA | SA       | DA | MSG         |
|:--------------------:|------|----------|----|-------------|
| LD RD, offset(RS1)   | --   | ADDR(CPU)| RS1| REQ_RD      |
| SD RD, offset(RS1)   | RD   | ADDR(CPU)| RS1| REQ_WR      |
| AMOADD.D rd,rs2,(rs1)| RD   | ADDR(CPU)| RS1| REQ_ATOMADD |


## 4. Signal UMI (SUMI) Layer

### 4.1 Theory of Operation

The native UMI signaling layer (SUMI) is a latency insensitive handshake protocol on the trans

 of a the transaction UMI (TUMI fields)

 valid signal,
ready signal with the following naming convention:



![UMI](docs/_images/tumi_connections.png)



```
u<host|dev>_<req|resp>_<packet|ready|valid>
```

Connections shall only be made between hosts and devices,
per the diagram below.




### 3.2 Handshake Protocol

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


### 4.2 Signal Interface

Components in a system can have a UMI host port, device port, or both.

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
