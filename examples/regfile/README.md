# Register File Example

This example shows how to connect UMI to a simple register file. The `testbench.sv` instantiates `umi_regif` and a an array of registers. Transactions are driven using `switchboard` UMI transactors instantiated within the `testbench.sv`.

To run the example, execute test.py from the command line:

```bash
./test.py
```

You'll see a Verilator based build, followed by output like this. A simulation waveform is recorded in `testbench.vcd`

```text
Read addr=0 data=[0xef 0x0 0x0 0x0]
Read addr=0 data=[0xef 0xbe 0x0 0x0]
Read addr=0 data=[0xef 0xbe 0xad 0xde]
Read addr=200 data=[0xa0 0xa0 0xa0 0xa0]
Read addr=0 data=[0xef 0xbe 0xad 0xde]
```
