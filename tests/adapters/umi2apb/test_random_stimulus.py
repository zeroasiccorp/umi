import math
import cocotb
from random import randint, randbytes
from cocotb.triggers import ClockCycles

from adapters.umi2apb.env import UMI2APBEnv, create_expected_write_response
from cocotblib.umi.sumi import SumiTransaction, SumiCmdType, SumiCmd


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_random_stimulus(dut):
    """
    Randomized read/write stimulus.

    - Aligned addresses
    - Full-width accesses
    - Memory model checked at the end
    """
    # Grab shared test environment
    env = UMI2APBEnv(dut)
    await env.start()

    data_size = env.data_size
    addr_width = env.addr_width
    umi_size = int(math.log2(data_size))

    mem_size = 2**16
    num_random_transactions = 512
    read_probability = 0.5

    print(f"=== Randomized Test: {num_random_transactions} transactions ===")

    # Ideal memory model for writes/reads
    memory_model = {}

    for i in range(num_random_transactions):
        txn_bytes = env.data_size
        max_addr = (mem_size - txn_bytes) // txn_bytes

        # Randomized address and command type
        addr = randint(0, max_addr) * txn_bytes
        is_read = randint(0, 99) < (read_probability * 100)

        if is_read:
            txn = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_REQ_READ),
                    size=umi_size,
                    len=0,
                ),
                da=addr,
                sa=0x0,
                data=bytearray(txn_bytes),
            )

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

        else:
            data = randbytes(txn_bytes)
            memory_model[addr] = data

            txn = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_REQ_WRITE),
                    size=umi_size,
                    len=0,
                ),
                da=addr,
                sa=0x0,
                data=data,
            )

            env.expected_responses.append(
                create_expected_write_response(txn, txn_bytes, addr_width)
            )

        await env.sumi_driver.send(txn)

        if (i + 1) % 100 == 0:
            print(f"    Sent {i+1}/{num_random_transactions} transactions...")
            await ClockCycles(env.clk, 1)

    await env.wait_for_responses(max_cycles=num_random_transactions * 50)

    # Memory verification
    num_verified = 0
    for addr, expected_data in memory_model.items():
        mem_data = await env.region.read(addr, data_size)
        assert mem_data == expected_data, (
            f"Memory mismatch at 0x{addr:x}: "
            f"expected {expected_data.hex()}, got {mem_data.hex()}"
        )
        num_verified += 1

    print(f"\n=== Test Statistics ===")
    print(f"    Total transactions: {num_random_transactions}")
    print(f"    Unique addresses written: {len(memory_model)}")
    print(f"    Memory locations verified: {num_verified}")
    print(f"    All transactions completed")

    raise env.scoreboard.result
