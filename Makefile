SHELL := /usr/bin/env bash

SIM          ?= verilator
RISCV_PREFIX ?= riscv64-unknown-elf-
RISCV_ARCH   ?= rv32im_zicsr
RISCV_ABI    ?= ilp32
TRACE        ?= 0
SEED         ?= 1

BUILD_DIR    := build
RISCV_CC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
VERILATOR    ?= verilator
YOSYS        ?= yosys
RTL_SOURCES  := $(shell sed '/^+incdir/d' scripts/cv32e40x_rtl.f)

RISCV_CFLAGS := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -nostdlib -nostartfiles \
	-ffreestanding -Wl,--build-id=none -T sw/common/minimal_linker.ld
RUNTIME_CFLAGS := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -nostdlib -nostartfiles \
	-ffreestanding -fno-builtin -msmall-data-limit=0 -I sw/common \
	-Wl,--build-id=none -T sw/common/linker.ld

.DEFAULT_GOAL := help

.PHONY: help check-tools lint test-unit test-core test-sw test-mnist regression benchmark wave synth-yosys clean

help:
	@echo "RISC-V CV-X-IF NN accelerator build targets"
	@echo ""
	@echo "  make check-tools  Report host tools and missing dependencies"
	@echo "  make lint         Lint SystemVerilog RTL (available after RTL is added)"
	@echo "  make test-unit    Run currently available module/host unit tests"
	@echo "  make test-core    Run CPU program tests (future milestone)"
	@echo "  make test-sw      Build/run RV32 software tests (future milestone)"
	@echo "  make regression   Run all currently implemented checks"
	@echo "  make benchmark    Compare CPU, instruction NN, array, and DMA datapaths"
	@echo "  make test-mnist   Train/quantize MNIST and run CPU/DMA RTL inference"
	@echo "  make wave         Generate FST waveforms (future milestone)"
	@echo "  make synth-yosys  Run Yosys synthesis check (future milestone)"
	@echo "  make clean        Remove generated files"
	@echo ""
	@echo "Variables: SIM=$(SIM) RISCV_PREFIX=$(RISCV_PREFIX) RISCV_ARCH=$(RISCV_ARCH) RISCV_ABI=$(RISCV_ABI) TRACE=$(TRACE) SEED=$(SEED)"

check-tools:
	@./scripts/check_tools.sh

lint:
	@$(VERILATOR) --lint-only --timing -Wall -Wno-fatal \
		--top-module cv32e40x_subsystem -f scripts/cv32e40x_rtl.f

test-unit:
	@python3 -m unittest discover -s sim/tests -p 'test_*.py' -v
	@$(MAKE) --no-print-directory test-nn-rtl

.PHONY: test-nn-rtl
test-nn-rtl: $(BUILD_DIR)/Vtb_nn_random $(BUILD_DIR)/nn_vectors.txt $(BUILD_DIR)/Vtb_xif_protocol $(BUILD_DIR)/Vtb_nn_mac_array $(BUILD_DIR)/Vtb_nn_dma_mac_array
	@$(BUILD_DIR)/Vtb_nn_random
	@$(BUILD_DIR)/Vtb_xif_protocol
	@$(BUILD_DIR)/Vtb_nn_mac_array
	@$(BUILD_DIR)/Vtb_nn_dma_mac_array

test-core: $(BUILD_DIR)/Vtb_cv32e40x_smoke $(BUILD_DIR)/test_basic.memh \
	$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e $(BUILD_DIR)/fc16x4_dma.memh \
	$(BUILD_DIR)/mnist_dma.memh $(BUILD_DIR)/mnist/expected.txt \
	$(BUILD_DIR)/Vtb_cv32e40x_trap $(BUILD_DIR)/Vtb_cv32e40x_privileged \
	$(BUILD_DIR)/Vtb_cv32e40x_memory_exceptions \
	$(BUILD_DIR)/Vtb_cv32e40x_bus_fault \
	$(BUILD_DIR)/test_privileged.memh $(BUILD_DIR)/test_muldiv.memh \
	$(BUILD_DIR)/test_dotp4.memh $(BUILD_DIR)/test_nn_ops.memh \
	$(BUILD_DIR)/test_runtime.memh $(BUILD_DIR)/test_runtime_fail.memh \
	$(BUILD_DIR)/test_cpu_baseline.memh $(BUILD_DIR)/test_nn_integration.memh \
	$(BUILD_DIR)/fc16x4.memh \
	$(BUILD_DIR)/fc16x4_array.memh \
	$(BUILD_DIR)/test_memory_exceptions.memh \
	$(BUILD_DIR)/test_load_nmi.memh $(BUILD_DIR)/test_store_nmi.memh $(BUILD_DIR)/test_instr_fault.memh
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +MULDIV
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +DOTP4
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +NNOPS
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +RUNTIME
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +RUNTIME_FAIL
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +CPU_BASELINE
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +NN_INTEGRATION
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +FC16X4
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +ARRAY_FC16X4
	@$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e
	@$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e +MNIST
	@$(BUILD_DIR)/Vtb_cv32e40x_trap
	@$(BUILD_DIR)/Vtb_cv32e40x_privileged +BASIC
	@$(BUILD_DIR)/Vtb_cv32e40x_memory_exceptions
	@$(BUILD_DIR)/Vtb_cv32e40x_bus_fault +LOAD_NMI
	@$(BUILD_DIR)/Vtb_cv32e40x_bus_fault +STORE_NMI
	@$(BUILD_DIR)/Vtb_cv32e40x_bus_fault +INSTR_FAULT

test-sw: $(BUILD_DIR)/test_basic.elf $(BUILD_DIR)/test_basic.memh \
	$(BUILD_DIR)/test_privileged.elf $(BUILD_DIR)/test_privileged.memh \
	$(BUILD_DIR)/test_muldiv.elf $(BUILD_DIR)/test_muldiv.memh \
	$(BUILD_DIR)/test_dotp4.elf $(BUILD_DIR)/test_dotp4.memh \
	$(BUILD_DIR)/test_nn_ops.elf $(BUILD_DIR)/test_nn_ops.memh \
	$(BUILD_DIR)/test_runtime.elf $(BUILD_DIR)/test_runtime.memh \
	$(BUILD_DIR)/test_runtime_fail.elf $(BUILD_DIR)/test_runtime_fail.memh \
	$(BUILD_DIR)/test_cpu_baseline.elf $(BUILD_DIR)/test_cpu_baseline.memh \
	$(BUILD_DIR)/test_nn_integration.elf $(BUILD_DIR)/test_nn_integration.memh \
	$(BUILD_DIR)/fc16x4.elf $(BUILD_DIR)/fc16x4.memh \
	$(BUILD_DIR)/fc16x4_array.elf $(BUILD_DIR)/fc16x4_array.memh \
	$(BUILD_DIR)/fc16x4_dma.elf $(BUILD_DIR)/fc16x4_dma.memh \
	$(BUILD_DIR)/mnist_dma.elf $(BUILD_DIR)/mnist_dma.memh \
	$(BUILD_DIR)/test_memory_exceptions.elf $(BUILD_DIR)/test_memory_exceptions.memh
	@echo "PASS: built RV32, privileged, runtime, and NN programs with $(RISCV_CC)"

regression: check-tools lint test-unit test-sw test-core
	@echo "PASS: all currently implemented regression checks completed"

test-mnist: $(BUILD_DIR)/Vtb_cv32e40x_dma_e2e $(BUILD_DIR)/mnist_dma.memh $(BUILD_DIR)/mnist/expected.txt
	@$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e +MNIST

benchmark: $(BUILD_DIR)/Vtb_cv32e40x_smoke $(BUILD_DIR)/fc16x4.memh \
	$(BUILD_DIR)/fc16x4_array.memh $(BUILD_DIR)/Vtb_nn_dma_mac_array \
	$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e $(BUILD_DIR)/fc16x4_dma.memh \
	$(BUILD_DIR)/mnist_dma.memh $(BUILD_DIR)/mnist/expected.txt
	@echo "Benchmark scope: RTL simulation cycles; DMA model has deterministic AXI stalls"
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +FC16X4
	@$(BUILD_DIR)/Vtb_cv32e40x_smoke +ARRAY_FC16X4
	@$(BUILD_DIR)/Vtb_nn_dma_mac_array
	@$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e
	@$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e +MNIST

wave:
	@echo "Waveform support will be enabled with the cocotb memory-latency tests"

synth-yosys:
	@$(YOSYS) -Q -p 'read_verilog -sv rtl/nn_dotp4_unit.sv rtl/nn_quant_unit.sv rtl/nn_execution_unit.sv; hierarchy -top nn_execution_unit; proc; opt; check'
	@$(YOSYS) -Q -p 'read_verilog -sv rtl/nn_mac_array.sv; hierarchy -top nn_mac_array; proc; memory; opt; check; stat'
	@$(YOSYS) -Q -p 'read_verilog -sv rtl/nn_axi_read_dma.sv rtl/nn_dma_mac_array.sv; hierarchy -top nn_dma_mac_array; proc; memory; opt; check; stat'
	@$(YOSYS) -Q -p 'read_verilog -sv rtl/nn_axi_read_dma.sv rtl/nn_dma_mac_array.sv rtl/nn_dma_mmio.sv; hierarchy -top nn_dma_mmio; proc; memory; opt; check; stat'

clean:
	@rm -rf build sim_build .pytest_cache
	@find . -type d -name __pycache__ -prune -exec rm -rf {} +
	@find . -type f \( -name '*.pyc' -o -name '*.fst' -o -name '*.vcd' \) -delete

$(BUILD_DIR):
	@mkdir -p $@

$(BUILD_DIR)/nn_vectors.txt: scripts/generate_nn_vectors.py | $(BUILD_DIR)
	python3 $< $@ --seed $(SEED) --per-op 1000

$(BUILD_DIR)/Vtb_nn_random: rtl/nn_dotp4_unit.sv rtl/nn_quant_unit.sv rtl/nn_execution_unit.sv sim/tb_nn_random.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_nn_random \
		-o ../Vtb_nn_random --top-module tb_nn_random \
		rtl/nn_dotp4_unit.sv rtl/nn_quant_unit.sv rtl/nn_execution_unit.sv sim/tb_nn_random.sv

$(BUILD_DIR)/Vtb_xif_protocol: references/cv32e40x/rtl/cv32e40x_if_xif.sv \
	rtl/nn_decoder.sv rtl/nn_dotp4_unit.sv rtl/nn_quant_unit.sv \
	rtl/nn_execution_unit.sv rtl/nn_mac_array.sv rtl/xif_nn_coprocessor.sv sim/tb_xif_protocol.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_xif_protocol \
		-o ../Vtb_xif_protocol --top-module tb_xif_protocol \
		references/cv32e40x/rtl/cv32e40x_if_xif.sv rtl/nn_decoder.sv \
		rtl/nn_dotp4_unit.sv rtl/nn_quant_unit.sv rtl/nn_execution_unit.sv \
		rtl/nn_mac_array.sv rtl/xif_nn_coprocessor.sv sim/tb_xif_protocol.sv

$(BUILD_DIR)/Vtb_nn_mac_array: rtl/nn_mac_array.sv sim/tb_nn_mac_array.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_mac_array \
		-o ../Vtb_nn_mac_array --top-module tb_nn_mac_array rtl/nn_mac_array.sv sim/tb_nn_mac_array.sv

$(BUILD_DIR)/Vtb_nn_dma_mac_array: rtl/nn_axi_read_dma.sv rtl/nn_dma_mac_array.sv sim/tb_nn_dma_mac_array.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_dma_array \
		-o ../Vtb_nn_dma_mac_array --top-module tb_nn_dma_mac_array \
		rtl/nn_axi_read_dma.sv rtl/nn_dma_mac_array.sv sim/tb_nn_dma_mac_array.sv

$(BUILD_DIR)/test_basic.elf: sw/tests/test_basic.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BUILD_DIR)/test_basic.bin: $(BUILD_DIR)/test_basic.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_basic.memh: $(BUILD_DIR)/test_basic.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_privileged.elf: sw/tests/test_privileged.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BUILD_DIR)/test_privileged.bin: $(BUILD_DIR)/test_privileged.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_privileged.memh: $(BUILD_DIR)/test_privileged.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_muldiv.elf: sw/tests/test_muldiv.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BUILD_DIR)/test_muldiv.bin: $(BUILD_DIR)/test_muldiv.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_muldiv.memh: $(BUILD_DIR)/test_muldiv.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_dotp4.elf: sw/tests/test_dotp4.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BUILD_DIR)/test_dotp4.bin: $(BUILD_DIR)/test_dotp4.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_dotp4.memh: $(BUILD_DIR)/test_dotp4.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_nn_ops.elf: sw/tests/test_nn_ops.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BUILD_DIR)/test_nn_ops.bin: $(BUILD_DIR)/test_nn_ops.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_nn_ops.memh: $(BUILD_DIR)/test_nn_ops.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_runtime.elf: sw/common/start.S sw/common/crt.c \
	sw/common/mailbox.h sw/common/linker.ld sw/tests/test_runtime.c | $(BUILD_DIR)
	$(RISCV_CC) $(RUNTIME_CFLAGS) sw/common/start.S sw/common/crt.c sw/tests/test_runtime.c -o $@

$(BUILD_DIR)/test_runtime.bin: $(BUILD_DIR)/test_runtime.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_runtime.memh: $(BUILD_DIR)/test_runtime.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_runtime_fail.elf: sw/common/start.S sw/common/crt.c \
	sw/common/mailbox.h sw/common/linker.ld sw/tests/test_runtime_fail.c | $(BUILD_DIR)
	$(RISCV_CC) $(RUNTIME_CFLAGS) sw/common/start.S sw/common/crt.c sw/tests/test_runtime_fail.c -o $@

$(BUILD_DIR)/test_runtime_fail.bin: $(BUILD_DIR)/test_runtime_fail.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_runtime_fail.memh: $(BUILD_DIR)/test_runtime_fail.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_cpu_baseline.elf: sw/tests/test_cpu_baseline.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BUILD_DIR)/test_cpu_baseline.bin: $(BUILD_DIR)/test_cpu_baseline.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_cpu_baseline.memh: $(BUILD_DIR)/test_cpu_baseline.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_nn_integration.elf: sw/tests/test_nn_integration.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@
$(BUILD_DIR)/test_nn_integration.bin: $(BUILD_DIR)/test_nn_integration.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/test_nn_integration.memh: $(BUILD_DIR)/test_nn_integration.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/fc16x4.elf: sw/common/start.S sw/common/crt.c sw/common/mailbox.h \
	sw/common/custom_nn.h sw/common/linker.ld sw/benchmarks/fc16x4.c | $(BUILD_DIR)
	$(RISCV_CC) $(RUNTIME_CFLAGS) -O2 sw/common/start.S sw/common/crt.c sw/benchmarks/fc16x4.c -o $@
$(BUILD_DIR)/fc16x4.bin: $(BUILD_DIR)/fc16x4.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/fc16x4.memh: $(BUILD_DIR)/fc16x4.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/fc16x4_array.elf: sw/common/start.S sw/common/crt.c sw/common/mailbox.h \
	sw/common/custom_nn.h sw/common/linker.ld sw/benchmarks/fc16x4_array.c | $(BUILD_DIR)
	$(RISCV_CC) $(RUNTIME_CFLAGS) -O2 sw/common/start.S sw/common/crt.c sw/benchmarks/fc16x4_array.c -o $@
$(BUILD_DIR)/fc16x4_array.bin: $(BUILD_DIR)/fc16x4_array.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/fc16x4_array.memh: $(BUILD_DIR)/fc16x4_array.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/fc16x4_dma.elf: sw/common/start.S sw/common/crt.c sw/common/mailbox.h \
	sw/common/linker.ld sw/benchmarks/fc16x4_dma.c | $(BUILD_DIR)
	$(RISCV_CC) $(RUNTIME_CFLAGS) -O2 sw/common/start.S sw/common/crt.c sw/benchmarks/fc16x4_dma.c -o $@
$(BUILD_DIR)/fc16x4_dma.bin: $(BUILD_DIR)/fc16x4_dma.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/fc16x4_dma.memh: $(BUILD_DIR)/fc16x4_dma.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/mnist/expected.txt: scripts/prepare_mnist.py data/mnist/train-images-idx3-ubyte.gz \
	data/mnist/train-labels-idx1-ubyte.gz data/mnist/t10k-images-idx3-ubyte.gz \
	data/mnist/t10k-labels-idx1-ubyte.gz
	.venv/bin/python scripts/prepare_mnist.py
$(BUILD_DIR)/mnist/weights.memh $(BUILD_DIR)/mnist/bias.memh $(BUILD_DIR)/mnist/sample.memh: $(BUILD_DIR)/mnist/expected.txt
	@true

$(BUILD_DIR)/mnist_dma.elf: sw/common/start.S sw/common/crt.c sw/common/mailbox.h \
	sw/common/linker.ld sw/benchmarks/mnist_dma.c | $(BUILD_DIR)
	$(RISCV_CC) $(RUNTIME_CFLAGS) -O2 sw/common/start.S sw/common/crt.c sw/benchmarks/mnist_dma.c -o $@
$(BUILD_DIR)/mnist_dma.bin: $(BUILD_DIR)/mnist_dma.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/mnist_dma.memh: $(BUILD_DIR)/mnist_dma.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_memory_exceptions.elf: sw/tests/test_memory_exceptions.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BUILD_DIR)/test_memory_exceptions.bin: $(BUILD_DIR)/test_memory_exceptions.elf
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUILD_DIR)/test_memory_exceptions.memh: $(BUILD_DIR)/test_memory_exceptions.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/test_load_nmi.elf: sw/tests/test_bus_fault.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) -DTEST_LOAD_NMI $< -o $@
$(BUILD_DIR)/test_store_nmi.elf: sw/tests/test_bus_fault.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) -DTEST_STORE_NMI $< -o $@
$(BUILD_DIR)/test_instr_fault.elf: sw/tests/test_bus_fault.S sw/common/minimal_linker.ld | $(BUILD_DIR)
	$(RISCV_CC) $(RISCV_CFLAGS) -DTEST_INSTR_FAULT $< -o $@
$(BUILD_DIR)/test_load_nmi.bin: $(BUILD_DIR)/test_load_nmi.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/test_store_nmi.bin: $(BUILD_DIR)/test_store_nmi.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/test_instr_fault.bin: $(BUILD_DIR)/test_instr_fault.elf
	$(RISCV_OBJCOPY) -O binary $< $@
$(BUILD_DIR)/test_load_nmi.memh: $(BUILD_DIR)/test_load_nmi.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@
$(BUILD_DIR)/test_store_nmi.memh: $(BUILD_DIR)/test_store_nmi.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@
$(BUILD_DIR)/test_instr_fault.memh: $(BUILD_DIR)/test_instr_fault.bin scripts/bin_to_memh.py
	python3 scripts/bin_to_memh.py $< $@

$(BUILD_DIR)/Vtb_cv32e40x_smoke: scripts/cv32e40x_rtl.f $(RTL_SOURCES) sim/tb_cv32e40x_smoke.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_tb \
		-o ../Vtb_cv32e40x_smoke --top-module tb_cv32e40x_smoke \
		-f scripts/cv32e40x_rtl.f sim/tb_cv32e40x_smoke.sv

$(BUILD_DIR)/Vtb_cv32e40x_dma_e2e: scripts/cv32e40x_rtl.f $(RTL_SOURCES) \
	rtl/nn_axi_read_dma.sv rtl/nn_dma_mac_array.sv rtl/nn_dma_mmio.sv sim/tb_cv32e40x_dma_e2e.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_dma_e2e \
		-o ../Vtb_cv32e40x_dma_e2e --top-module tb_cv32e40x_dma_e2e \
		-f scripts/cv32e40x_rtl.f rtl/nn_axi_read_dma.sv rtl/nn_dma_mac_array.sv \
		rtl/nn_dma_mmio.sv sim/tb_cv32e40x_dma_e2e.sv

$(BUILD_DIR)/Vtb_cv32e40x_privileged: scripts/cv32e40x_rtl.f $(RTL_SOURCES) sim/tb_cv32e40x_privileged.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_priv \
		-o ../Vtb_cv32e40x_privileged --top-module tb_cv32e40x_privileged \
		-f scripts/cv32e40x_rtl.f sim/tb_cv32e40x_privileged.sv

$(BUILD_DIR)/Vtb_cv32e40x_trap: scripts/cv32e40x_rtl.f $(RTL_SOURCES) sim/tb_cv32e40x_trap.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_trap \
		-o ../Vtb_cv32e40x_trap --top-module tb_cv32e40x_trap \
		-f scripts/cv32e40x_rtl.f sim/tb_cv32e40x_trap.sv

$(BUILD_DIR)/Vtb_cv32e40x_memory_exceptions: scripts/cv32e40x_rtl.f $(RTL_SOURCES) sim/tb_cv32e40x_memory_exceptions.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_memexc \
		-o ../Vtb_cv32e40x_memory_exceptions --top-module tb_cv32e40x_memory_exceptions \
		-f scripts/cv32e40x_rtl.f sim/tb_cv32e40x_memory_exceptions.sv

$(BUILD_DIR)/Vtb_cv32e40x_bus_fault: scripts/cv32e40x_rtl.f $(RTL_SOURCES) sim/tb_cv32e40x_bus_fault.sv | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wno-fatal --Mdir $(BUILD_DIR)/obj_busfault \
		-o ../Vtb_cv32e40x_bus_fault --top-module tb_cv32e40x_bus_fault \
		-f scripts/cv32e40x_rtl.f sim/tb_cv32e40x_bus_fault.sv
