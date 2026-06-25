from cocotb.triggers import Timer


async def drive_reset(reset, time_ns=50):
    reset.value = 1
    await Timer(1, unit="step")
    reset.value = 0
    await Timer(time_ns, unit="ns")
    reset.value = 1
    await Timer(1, unit="step")
