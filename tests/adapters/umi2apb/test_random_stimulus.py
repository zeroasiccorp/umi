import os
import math
from random import randint, randbytes, choices

import cocotb
from cocotb.triggers import Event, Combine, ClockCycles

from cocotb_bus.drivers import BitDriver

from env import UMI2APBEnv, create_expected_write_response
from cocotbext.umi.sumi import SumiTransaction, SumiCmdType, SumiCmd
from cocotbext.umi.utils.generators import (
    random_toggle_generator,
    wave_generator
)


@cocotb.test(timeout_time=50, timeout_unit="ms")
@cocotb.parametrize(
    valid_gen=[None, random_toggle_generator(), wave_generator()],
    ready_gen=[None, random_toggle_generator(), wave_generator()],
    test_n_transactions=[int(512 * float(os.getenv("RAND_TEST_LEN_SCALER", default=1)))],
)
async def test_random_stimulus(
    dut,
    valid_gen=None,
    ready_gen=None,
    test_n_transactions=512
):
    """
    Randomized read/write stimulus.

    - Aligned addresses
    - Full-width accesses
    - Memory model checked at the end
    """
    # Grab shared test environment
    env = UMI2APBEnv(dut, umi_valid_gen=valid_gen)
    await env.start()

    if ready_gen is None:
        dut.udev_resp_ready.value = 1
    else:
        BitDriver(signal=dut.udev_resp_ready, clk=env.clk).start(generator=ready_gen)

    data_size = env.data_size
    addr_width = env.addr_width
    umi_size = int(math.log2(data_size))

    mem_size = 2**16

    print(f"=== Randomized Test: {test_n_transactions} transactions ===")

    # Ideal memory model for writes/reads
    memory_model = {}

    send_events = []

    for i in range(test_n_transactions):
        txn_bytes = env.data_size
        max_addr = (mem_size - txn_bytes) // txn_bytes

        # Randomized address and command type
        addr = randint(0, max_addr) * txn_bytes

        cmd_type = choices(
            population=[
                SumiCmdType.UMI_REQ_READ,
                SumiCmdType.UMI_REQ_WRITE,
                SumiCmdType.UMI_REQ_POSTED
            ],
            weights=[0.4, 0.3, 0.3],
        )[0]

        data = randbytes(txn_bytes)
        txn = SumiTransaction(
            cmd=SumiCmd.from_fields(
                cmd_type=int(cmd_type),
                size=umi_size,
                len=0,
            ),
            da=addr,
            sa=0x0,
            data=data,
        )
        if cmd_type == SumiCmdType.UMI_REQ_READ:
            expected_data = memory_model.get(addr, bytearray(txn_bytes))
            expected_resp = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_RESP_READ),
                    size=umi_size,
                    len=0,
                ),
                da=0x0,
                sa=addr,
                data=expected_data,
                addr_width=addr_width,
            )
            env.expected_responses.append(expected_resp)
        elif cmd_type == SumiCmdType.UMI_REQ_WRITE:
            memory_model[addr] = data
            env.expected_responses.append(create_expected_write_response(txn, txn_bytes, addr_width))
        elif cmd_type == SumiCmdType.UMI_REQ_POSTED:
            memory_model[addr] = data

        e = Event()
        env.sumi_driver.append(txn, event=e)
        send_events.append(e)

    # Wait for all transactions to be sent
    await Combine(*(e.wait() for e in send_events))

    await ClockCycles(env.clk, 100)

    # Memory verification
    num_verified = 0
    for addr, expected_data in memory_model.items():
        mem_data = await env.region.read(addr, data_size)
        assert mem_data == expected_data, (
            f"Memory mismatch at 0x{addr:x}: "
            f"expected {expected_data.hex()}, got {mem_data.hex()}"
        )
        num_verified += 1

    print("\n=== Test Statistics ===")
    print(f"    Total transactions: {test_n_transactions}")
    print(f"    Unique addresses written: {len(memory_model)}")
    print(f"    Memory locations verified: {num_verified}")
    print("    All transactions completed")

    raise env.scoreboard.result
