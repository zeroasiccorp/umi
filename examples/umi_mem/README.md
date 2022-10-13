# UMI Memory Example

This example is a small test of `umi_endpoint` that wires it up to a generic
memory. It is meant to demonstrate how to use a common testbench to write unit
tests for a block that uses UMI.

We use pytest for managing tests, which provides useful functionality for
automatic test discovery and running. To run the tests in this example, install
pytest:

```shell
pip install pytest
```

Next, clone switchboard, compile its umidriver executable, and set an env
variable pointing to it:

```shell
cd /path/to/switchboard/cpp
make umidriver
export SBDIR=/path/to/switchboard
```

Then, simply execute pytest to run the tests:

```shell
pytest
```

By default, pytest will look for and run any Python functions whose names begin
with test_ in Python files whose names begin with test_. We've placed the
example tests in `test_umi_mem.py.`

## pytest tricks

pytest has a variety of command line flags to control how and which tests are
run. Here are some useful ones:

- `pytest -s`: displays live output (pytest usually swallows it, and only prints
on failure)
- `pytest --collect-only`: display test names, but do not execute them (dry-run)
- `pytest -k <test-name>`: run specific test(s), e.g. `pytest -k test_basic`
(`-k` supports fuzzy matching as well)
