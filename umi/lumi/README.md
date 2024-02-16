# Universal Memory Interface Link Layer (LUMI)

## 1. Introduction

This IP implements UMI link layer protocol based on UMI spec:
* [Universal Memory Interface (UMI)](https://github.com/zeroasiccorp/umi)


### 1.1 Design Philosophy

* Keep it simple
* Low latency, maximum throughput
* Flexible, parametrized design to match application

### 1.2 Architecture

The Universal Memory Interface Link Layer (LUMI) is an implementation of the UMI link layer for multiple speeds and interface width. The design is parametrized for maximum implementation and also configurable at run time for application specific use cases. LUMI includes the following layers:

* Lumi register file for configuration
* Lumi crossbar for side band bus to the phy
* Lumi receive logic (Rx), including clock domain crossing to the phy receive clock
* Lumi transmit logic (Tx), including clock domain crossing to the phy transmit clock

### 1.3 Key Features

  * Parametrized UMI bus interface
  * Parametrized phy interface width
  * Parametrized number of credits and fifo depth
  * Low latency, maximum bandwidth implementation
  * Autonomous, no configuration self boot
  * Run-time reconfigurable support

----
## 2. Design parameters

LUMI block imeplentation exposes the following parameters to the user:

| Parameter      | Default Value | Meaning                       |
|----------------|---------------|-------------------------------|
| TARGET         | DEFAULT       | Design target (for SC)        |
| IDOFFSET       | 40            | Chip ID offset                |
| GRPOFFSET      | 24            | Register group offset         |
| GRPAW          | 8             | Group address width           |
| GRPID          | 0             | Lumi regs group ID            |
| IOW            | 64            | lumi-phy i/f width            |
| ASYNCFIFODEPTH | 8             | Async fifo depth              |
| RXFIFOW        | *             | Rx FIFO width in bits         |
| NFIFO          | *             | Number of receive fifo's      |
| CRDTDEPTH      | *             | Credit fifo depth             |
| CW             | 32            | SUMI command width            |
| AW             | 64            | SUMI address width            |
| DW             | 128           | SUMI data width               |
| RW             | 32            | SUMI register width           |
| IDW            | 16            | chipid width                  |
|----------------|---------------|-------------------------------|

* The parameters for the Rx fifo are calculated based on the sumi parameters and the phy IO width. The default values are calculated for 8b fifo width and the minimum fifo depth required to absorb a full SUMI packet. Increasing the fifo depth will provide better utilization of the bus due to lower credit update interval but will add area.

----
## 3. Interface

The following is the LUMI block interface. All signals are synchronous, active on rising edge and active high unless specified differently. \

| Signal Name        | Width     |   Dir  | Description               |
|--------------------|-----------|--------|---------------------------|
| nreset             |           | input  | Primary reset, active low |
| clk                |           | input  | SUMI clock, active high   |
| deviceready        |           | input  | Device ready              |
| host_linkactive    |           | output | Link active to host       |
| devicemode         |           | input  | Mode: 1-device, 0-host    |
| uhost_req_valid    |           | output | SUMI host port            |
| uhost_req_cmd      | [CW-1:0]  | output | SUMI host port            |
| uhost_req_dstaddr  | [AW-1:0]  | output | SUMI host port            |
| uhost_req_srcaddr  | [AW-1:0]  | output | SUMI host port            |
| uhost_req_data     | [DW-1:0]  | output | SUMI host port            |
| uhost_req_ready    |           | input  | SUMI host port            |
| uhost_resp_valid   |           | input  | SUMI host port            |
| uhost_resp_cmd     | [CW-1:0]  | input  | SUMI host port            |
| uhost_resp_dstaddr | [AW-1:0]  | input  | SUMI host port            |
| uhost_resp_srcaddr | [AW-1:0]  | input  | SUMI host port            |
| uhost_resp_data    | [DW-1:0]  | input  | SUMI host port            |
| uhost_resp_ready   |           | output | SUMI host port            |
| udev_req_valid     |           | input  | SUMI device port          |
| udev_req_cmd       | [CW-1:0]  | input  | SUMI device port          |
| udev_req_dstaddr   | [AW-1:0]  | input  | SUMI device port          |
| udev_req_srcaddr   | [AW-1:0]  | input  | SUMI device port          |
| udev_req_data      | [DW-1:0]  | input  | SUMI device port          |
| udev_req_ready     |           | output | SUMI device port          |
| udev_resp_valid    |           | output | SUMI device port          |
| udev_resp_cmd      | [CW-1:0]  | output | SUMI device port          |
| udev_resp_dstaddr  | [AW-1:0]  | output | SUMI device port          |
| udev_resp_srcaddr  | [AW-1:0]  | output | SUMI device port          |
| udev_resp_data     | [DW-1:0]  | output | SUMI device port          |
| udev_resp_ready    |           | input  | SUMI device port          |
| sb_in_valid        |           | input  | sideband SUMI port        |
| sb_in_cmd          | [CW-1:0]  | input  | sideband SUMI port        |
| sb_in_dstaddr      | [AW-1:0]  | input  | sideband SUMI port        |
| sb_in_srcaddr      | [AW-1:0]  | input  | sideband SUMI port        |
| sb_in_data         | [RW-1:0]  | input  | sideband SUMI port        |
| sb_in_ready        |           | output | sideband SUMI port        |
| sb_out_valid       |           | output | sideband SUMI port        |
| sb_out_cmd         | [CW-1:0]  | output | sideband SUMI port        |
| sb_out_dstaddr     | [AW-1:0]  | output | sideband SUMI port        |
| sb_out_srcaddr     | [AW-1:0]  | output | sideband SUMI port        |
| sb_out_data        | [RW-1:0]  | output | sideband SUMI port        |
| sb_out_ready       |           | input  | sideband SUMI port        |
| phy_clk            |           | input  | phy sb clock              |
| phy_nreset         |           | input  | phy sb reset, active low  |
| phy_in_valid       |           | input  | phy sideband port         |
| phy_in_cmd         | [CW-1:0]  | input  | phy sideband port         |
| phy_in_dstaddr     | [AW-1:0]  | input  | phy sideband port         |
| phy_in_srcaddr     | [AW-1:0]  | input  | phy sideband port         |
| phy_in_data        | [RW-1:0]  | input  | phy sideband port         |
| phy_in_ready       |           | output | phy sideband port         |
| phy_out_valid      |           | output | phy sideband port         |
| phy_out_cmd        | [CW-1:0]  | output | phy sideband port         |
| phy_out_dstaddr    | [AW-1:0]  | output | phy sideband port         |
| phy_out_srcaddr    | [AW-1:0]  | output | phy sideband port         |
| phy_out_data       | [RW-1:0]  | output | phy sideband port         |
| phy_out_ready      |           | input  | phy sideband port         |
| phy_rxdata         | [IOW-1:0] | input  | phy lumi rx data          |
| phy_rxvld          |           | input  | phy lumi rx valid         |
| rxclk              |           | input  | phy lumi rx clk           |
| rxnreset           |           | input  | phy lumi rx reset (low)   |
| phy_txdata         | [IOW-1:0] | output | phy lumi tx data          |
| phy_txvld          |           | output | phy lumi tx valid         |
| txclk              |           | input  | phy lumi tx clk           |
| txnreset           |           | input  | phy lumi tx reset (low)   |
| phy_linkactive     |           | input  | phy link active           |
| phy_iow            | [7:0]     | input  | phy IO width              |

----
## 4. Operation and configuration

The LUMI block is designed to work without any configuration based on the parameters used.
In this mode it will enable the receiver, transmitter and credit mechanism at the rise of linkactive indication from the phy. This allows the phy to initialize and train (if applicable) before lumi is enabled.

### 4.1 Autonomous Flow

In this mode lumi is self-configuring based on the parameters and phy width.

1. nreset deassertion
2. phy layer sets phy_iow
3. phy_linkactive is asserted

### 4.2 Re-configuration Flow

As lumi is self-configured based on the phy width there might be cases where parameters need to be changed. In order to override the configuration the following flow should be followed:
1. Pull on remote and local side link active indication in LUMI_STATUS register and wait for the link to be active on both sides
2. Disable Tx on both sides of the link
3. Disable Rx on both sides of the link
4. Configure required lumi configurations over side band
5. Enable Rx on both sides
6. Enable Tx (and credits if needed) on both sides
