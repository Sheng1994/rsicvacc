# macOS Stage A setup

## Detected host

The initial inspection on 2026-07-14 detected macOS 26.5.2 on arm64.
`/usr/bin/python3` and `/usr/bin/make` were present as system entry points, but
neither could run without Apple Command Line Tools. Homebrew, Verilator, Yosys,
Icarus Verilog, and both checked RISC-V GCC prefixes were absent.

Apple Command Line Tools were also unavailable, so the system `git` command
could not run. Install them before relying on Git or Homebrew:

```sh
xcode-select --install
```

This is a user action; repository scripts never perform administrator installs.

## Suggested packages

After Command Line Tools and Homebrew are available:

```sh
brew install verilator yosys icarus-verilog python cmake ninja make riscv64-elf-gcc
```

Create an isolated Python environment from the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install cocotb pytest pyelftools
```

The project does not hard-code a Homebrew prefix because Intel and Apple
Silicon installations differ.

## Toolchain configuration

The defaults are configurable at make invocation time:

```sh
make test-sw RISCV_PREFIX=riscv64-unknown-elf- \
  RISCV_ARCH=rv32im_zicsr RISCV_ABI=ilp32
```

The selected compiler must contain an RV32 `ilp32` multilib. A future software
tool check will verify this explicitly.

After `make` becomes usable, run `make check-tools` to print the discovered
tools. Before that, run `./scripts/check_tools.sh` directly. The checker probes
tool executability rather than trusting PATH presence alone. Missing or broken
tools are never treated as completed verification.
