# UMI Command Decoder for Surfer

This guide explains how to install and use the ```umi_cmd.toml``` UMI decoder to translate 32-bit Universal Memory Interface (UMI) commands into human-readable text within the Surfer waveform viewer.

## Installation
To install the decoder, you must move the umi_cmd.toml configuration file to Surfer's local decoder directory. You may need to create these folders manually if they do not already exist.

Create the decoder directory and move the file into that directory:

```bash
mkdir -p ~/.config/surfer/decoders/umi
cp umi_cmd.toml ~/.config/surfer/decoders/umi/.
```

## Usage in Surfer

1. Open your waveform (e.g., .vcd or .fst) in Surfer

2. Add the UMI CMD trace to the viewer window

2. Right click the trace and select ```umi``` under the ```Format``` dropdown

3. Analyze the Waveform: The raw hex values on the timeline will be replaced with a formatted string

Example:
```0x00400424``` will be displayed as ```OP:RESP_WR SZ:2B LEN:4 Q:0 P:0 EOM:1 EOF:0 EX:0 USR:0 HST:0```