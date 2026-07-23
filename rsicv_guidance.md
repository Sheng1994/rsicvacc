```yaml
role:
  title: "资深 RISC-V / SystemVerilog / FPGA 验证 / NN 加速器工程师"
  action: "直接修改当前代码仓库；必须创建真实 RTL、测试、软件、脚本和文档"
  forbidden:
    - "只给建议、伪代码或未落地的架构说明"
    - "伪造测试、综合、时序、资源或上板结果"

architecture_decision:
  cpu: "CV32E40X"
  extension_interface: "CV-X-IF"
  accelerator: "自研 INT8 NN 协处理器"
  target: "标准 RV32IM_Zicsr Machine Mode + 紧耦合 NN 指令"
  first_milestone: "CPU 可运行加法、分支和自定义 NN 指令测试"
  do_not_use:
    - "完整 X-HEEP"
    - "完整 CFU Playground"
    - "Chipyard / Rocket / RoCC / Chisel"
    - "完整 RVV / Gemmini / GPU / 浮点"
    - "Xilinx 原语"

platforms:
  stage_a:
    os: "当前 macOS，可能为 Apple Silicon arm64"
    execute:
      - "厂商无关 SystemVerilog RTL"
      - "Verilator lint / 仿真"
      - "cocotb + pytest"
      - "RV32 裸机汇编/C 测试"
      - "FST 波形"
      - "Yosys 综合检查"
      - "可选形式验证"
      - "性能计数和完整文档"
    forbidden:
      - "Vivado / Vitis"
      - "bitstream"
      - "Zynq PS / Block Design"
      - "MicroZed 板级顶层"
      - "DSP48 / RAMB / BUFG / MMCM 等厂商原语"

  stage_b:
    platform: "Ubuntu x86-64 + Vivado + MicroZed XC7Z020-1CLG400"
    current_repo_only:
      - "厂商无关核心接口"
      - "独立 fpga/ 适配层"
      - "MicroZed 部署文档"
      - "Vivado Tcl 模板"
      - "BRAM / AXI 适配方案"
    note: "当前不得声称通过 Vivado、时序、资源分析或上板验证"

environment_check:
  run_before_coding: |
    uname -s
    uname -m
    sw_vers
    which brew || true
    which verilator || true
    which yosys || true
    which iverilog || true
    which python3 || true
    which riscv64-unknown-elf-gcc || true
    which riscv32-unknown-elf-gcc || true
  missing_tools:
    action: "不执行管理员安装；生成 docs/macos_setup.md"
    brew: |
      brew install verilator yosys icarus-verilog python cmake ninja make riscv64-elf-gcc
    python: |
      python3 -m venv .venv
      source .venv/bin/activate
      python -m pip install --upgrade pip
      python -m pip install cocotb pytest pyelftools
  toolchain:
    configurable: |
      RISCV_PREFIX ?= riscv64-unknown-elf-
      RISCV_ARCH   ?= rv32im_zicsr
      RISCV_ABI    ?= ilp32
    rules:
      - "不得写死工具链绝对路径"
      - "RV32 multilib 不可用时记录问题"
      - "缺少交叉编译器不得阻塞 RTL 模块开发"

repository:
  inspect_readonly_references:
    - "references/cv32e40x"
    - "references/xif_copro"
    - "references/x-heep"
    - "references/cfu-playground"
    - "references/ibex"
    - "references/riscv-formal"
  writable_dirs:
    - "rtl/"
    - "sim/"
    - "sw/"
    - "scripts/"
    - "docs/"
    - "fpga/"
  reference_rules:
    - "不得修改 references/"
    - "不得复制、拼接多个处理器 RTL"
    - "保留第三方许可证和署名"
    - "生成 docs/reference_analysis.md"
    - "生成 docs/custom_interface_comparison.md"

cpu:
  baseline: "CV32E40X"
  isa:
    base: "RV32I"
    extensions:
      - "M"
      - "Zicsr"
    privilege: "Machine Mode"
    compile_flags: "-march=rv32im_zicsr -mabi=ilp32"

  required_instructions:
    rv32i:
      - "LUI AUIPC JAL JALR"
      - "BEQ BNE BLT BGE BLTU BGEU"
      - "LB LH LW LBU LHU"
      - "SB SH SW"
      - "ADDI SLTI SLTIU XORI ORI ANDI"
      - "SLLI SRLI SRAI"
      - "ADD SUB SLL SLT SLTU XOR SRL SRA OR AND"
      - "FENCE ECALL EBREAK"
    m:
      - "MUL MULH MULHSU MULHU"
      - "DIV DIVU REM REMU"
    csr:
      - "CSRRW CSRRS CSRRC"
      - "CSRRWI CSRRSI CSRRCI"
      - "MRET"

  correctness:
    - "x0 永远为 0"
    - "JALR 地址 bit0 清零"
    - "移位量仅使用低 5 位"
    - "正确处理 signed/unsigned"
    - "正确处理除零"
    - "正确处理 INT32_MIN / -1"
    - "异常指令不得写回或写存储器"

csr_and_trap:
  standard_csrs:
    - "mstatus"
    - "mie"
    - "mip"
    - "mtvec"
    - "mepc"
    - "mcause"
    - "mtval"
    - "mscratch"
    - "mcycle"
    - "minstret"
  exceptions:
    - "instruction address misaligned"
    - "illegal instruction"
    - "breakpoint"
    - "load/store address misaligned"
    - "instruction/load/store access fault"
    - "environment call from M-mode"
  interrupts:
    - "machine timer interrupt"
    - "machine external interrupt"
  requirements:
    - "异常和中断精确"
    - "正确更新 mepc/mcause/mtval"
    - "跳转 mtvec"
    - "mret 恢复执行"
    - "mcycle 每周期递增"
    - "minstret 仅成功提交时递增"

custom_isa:
  opcode: "custom-0 = 7'b0001011"
  format: "R-type"
  instructions:
    NN_DOTP4:
      operands: "rd, rs1, rs2"
      semantics: |
        rd = Σ signed8(rs1.byte[i]) * signed8(rs2.byte[i]), i=0..3
      state: "无隐藏累加状态"

    NN_RELU:
      operands: "rd, rs1"
      semantics: "rd = signed(rs1) < 0 ? 0 : rs1"

    NN_CLIP8:
      operands: "rd, rs1"
      semantics: "饱和到 [-128,127]，再符号扩展为 32 位"

    NN_MAX4:
      operands: "rd, rs1"
      semantics: "返回 rs1 四个 signed INT8 中最大值并符号扩展"

    NN_REQUANT:
      operands: "rd, rs1"
      csrs:
        - "NN_MULTIPLIER"
        - "NN_SHIFT"
        - "NN_ZERO_POINT"
      semantics: |
        wide    = signed(rs1) * signed(NN_MULTIPLIER)
        rounded = rounding_arithmetic_shift(wide, NN_SHIFT)
        biased  = rounded + signed(NN_ZERO_POINT)
        rd      = sign_extend(saturate_int8(biased))
      document:
        - "中间位宽"
        - "舍入规则"
        - "shift=0"
        - "shift 合法范围"
        - "溢出行为"
        - "zero point 范围"

  invalid_encoding: "未知 funct3/funct7 必须触发 illegal instruction"
  documentation: "docs/custom_isa.md"

xif_accelerator:
  approach: "通过 CV-X-IF 连接独立 NN 协处理器"
  required_channels:
    - "issue"
    - "commit"
    - "result"
  behavior:
    - "支持多周期执行"
    - "支持 backpressure"
    - "支持 kill/flush"
    - "错误路径操作不得写回"
    - "非法 NN 编码返回异常"
    - "请求未握手前输入保持稳定"
    - "响应未握手前结果保持稳定"
    - "复位后不得产生伪响应"
  no_memory_channel_initially: true

nn_unit:
  files:
    - "rtl/nn_execution_unit.sv"
    - "rtl/nn_decoder.sv"
    - "rtl/nn_dotp4_unit.sv"
    - "rtl/nn_quant_unit.sv"
  dotp4_structure: |
    4 × signed 8x8 multiply
      -> balanced adder tree
      -> signed 32-bit result
  vendor_primitives: false

memory:
  core_interfaces:
    - "独立 instruction memory"
    - "独立 data memory"
  rules:
    - "不得假设单周期响应"
    - "请求与响应独立握手"
    - "未握手时请求信号保持稳定"
    - "同一请求不得重复提交"
    - "支持任意等待周期和错误响应"
    - "数据接口支持 4-bit byte strobe"
    - "halfword/word 未对齐直接异常"
    - "未对齐访问不得发起总线请求"
  document: "docs/memory_interface.md"

performance_counters:
  standard:
    - "mcycle"
    - "minstret"
  custom:
    - "nn_instruction_count"
    - "nn_dotp4_count"
    - "nn_requant_count"
    - "memory_stall_cycles"
    - "muldiv_stall_cycles"
    - "nn_stall_cycles"
    - "branch_taken_count"
    - "trap_count"
  document: "docs/csr_map.md"

software:
  layout:
    common:
      - "start.S"
      - "linker.ld"
      - "crt.c"
      - "custom_nn.h"
    tests:
      - "test_rv32i.S"
      - "test_muldiv.S"
      - "test_csr.S"
      - "test_trap.S"
      - "test_dotp4.c"
      - "test_requant.c"
      - "test_small_fc.c"
  benchmarks:
    software_dot_product: "普通 RV32IM signed INT8 点积"
    nn_dot_product: "NN_DOTP4 每次处理 4 个 INT8"
    small_fc:
      input_dim: 16
      output_dim: 4
      weights: "INT8"
      bias: "INT32"
      output: "INT8"
      flow: "dotp + bias + requant + clip"
  result_reporting:
    mechanism: "memory-mapped tohost/mailbox"
    fields:
      - "PASS/FAIL"
      - "error code"
      - "cycles"
      - "retired instructions"
      - "NN instruction count"

verification:
  frameworks:
    - "Verilator"
    - "cocotb"
    - "pytest"
    - "Yosys"
    - "可选 Spike / riscv-formal"
  unit_tests:
    - "ALU"
    - "register file"
    - "immediate generator"
    - "branch"
    - "load/store formatter"
    - "CSR"
    - "mul/div"
    - "所有 NN 指令"
  dotp4_cases:
    - "zero"
    - "all positive / all negative"
    - "mixed signs"
    - "127*127"
    - "-128*-128"
    - "127*-128"
    - "-128*127"
    - "random vectors"
    - "back-to-back requests"
    - "random result backpressure"
    - "reset during request"
  core_cases:
    - "每条已实现指令至少一个定向测试"
    - "branch taken/not-taken"
    - "JAL/JALR"
    - "byte/halfword/word load-store"
    - "x0 write"
    - "divide by zero"
    - "CSR set/clear"
    - "illegal instruction"
    - "misaligned access"
    - "random memory latency"
    - "bus error"
    - "interrupt and mret"
  reference_models:
    - "Python 显式模拟 signed INT8/INT32"
    - "NN_REQUANT 不依赖 Python/C 未定义移位行为"
  trace:
    fields:
      - "cycle"
      - "pc"
      - "instruction"
      - "rd write/address/value"
      - "memory write/address/data"
      - "trap"
    optional_rvfi:
      - "order"
      - "instruction"
      - "trap/halt/interrupt"
      - "rs1/rs2/rd"
      - "pc before/after"
      - "memory masks/data"
  spike:
    policy: "未安装时跳过并明确记录；不得声称已通过差分验证"

assertions:
  - "x0 == 0"
  - "非法指令不得写回"
  - "trap 指令不得正常退休"
  - "请求未握手时总线信号稳定"
  - "响应未消费时结果稳定"
  - "未对齐 load/store 不产生总线请求"
  - "XIF/NN 请求和响应保持协议"
  - "未知 NN 编码触发异常"
  - "minstret 仅在 retire 时递增"
  - "所有测试平台具有超时"

rtl_style:
  language: "SystemVerilog"
  compatibility:
    - "Verilator"
    - "Yosys synthesizable subset"
    - "后续 Vivado"
  mandatory:
    - "`default_nettype none / wire"
    - "always_ff 用于时序"
    - "always_comb 用于组合"
    - "非阻塞时序赋值"
    - "完整组合默认值"
    - "无 latch"
    - "显式 $signed 和中间位宽"
    - "单一寄存器仅一个时序写入源"
  forbidden:
    - "#delay"
    - "force/release"
    - "DPI 实现硬件"
    - "隐式 net"
    - "厂商原语"

build:
  root_makefile_targets:
    - "make help"
    - "make lint"
    - "make test-unit"
    - "make test-core"
    - "make test-sw"
    - "make regression"
    - "make wave"
    - "make synth-yosys"
    - "make clean"
  variables: |
    SIM          ?= verilator
    RISCV_PREFIX ?= riscv64-unknown-elf-
    RISCV_ARCH   ?= rv32im_zicsr
    RISCV_ABI    ?= ilp32
    TRACE        ?= 0
    SEED         ?= 1
  regression:
    - "检查工具"
    - "lint RTL"
    - "运行模块测试"
    - "编译软件"
    - "运行程序级测试"
    - "输出汇总"
    - "返回正确退出码"
  portability:
    - "不写死 /opt/homebrew、HOME、Vivado 或 Ubuntu 路径"
    - "不依赖 GNU sed/readlink -f/nproc"
    - "shell 使用 /usr/bin/env bash"
    - "并行数可用 sysctl -n hw.ncpu"
    - "二进制转换使用 Python"
    - "默认波形为 FST"

fpga_stage_b:
  layout:
    - "fpga/README.md"
    - "fpga/common/simple_bram_adapter.sv"
    - "fpga/common/axi_master_adapter.md"
    - "fpga/microzed/README.md"
    - "fpga/microzed/rtl/microzed_riscv_wrapper.sv.template"
    - "fpga/microzed/vivado/build.tcl.template"
  planned_architecture: |
    PS:
      - FCLK
      - DDR 初始化
      - AXI 写共享 BRAM
      - 控制 RISC-V reset
      - 读取 mailbox

    PL:
      - CV32E40X
      - CV-X-IF NN 协处理器
      - 双口 BRAM
      - 总线适配层
      - mailbox/status
  initial_program_memory: "PL BRAM"
  future_upgrade: "NN/CPU AXI Master -> Zynq S_AXI_HP0 -> PS DDR"
  rule: "CPU 和 NN 核心不得直接依赖 AXI 或 Zynq PS"

required_docs:
  - "README.md"
  - "docs/macos_setup.md"
  - "docs/architecture.md"
  - "docs/microarchitecture.md"
  - "docs/custom_isa.md"
  - "docs/custom_interface_comparison.md"
  - "docs/csr_map.md"
  - "docs/memory_interface.md"
  - "docs/verification.md"
  - "docs/reference_analysis.md"
  - "docs/known_limitations.md"
  - "fpga/microzed/README.md"

workflow:
  milestones:
    1: "环境检测、参考项目分析、目录骨架、Makefile、最小 lint/test"
    2: "集成 CV32E40X 基线并运行基础 RV32I 程序"
    3: "验证 M、CSR、trap、中断和随机存储器等待"
    4: "设计 CV-X-IF NN 协处理器和自定义指令编码"
    5: "实现 DOTP4/RELU/CLIP8/MAX4/REQUANT"
    6: "模块随机测试、backpressure、kill/flush 测试"
    7: "软件点积、自定义点积、小型全连接层"
    8: "全量回归、Yosys、文档和 MicroZed 预留"
  after_each_milestone:
    - "运行测试并修复失败"
    - "列出新增/修改文件"
    - "列出实际执行命令"
    - "报告真实通过/失败数量"
    - "记录未解决问题"
  rule: "按里程碑逐步实现，不一次生成大量未经验证的 RTL"

acceptance:
  stage_a_minimum:
    - "全部自研 RTL 通过 Verilator lint"
    - "模块级测试通过"
    - "CV32E40X 可运行 RV32IM_Zicsr 裸机程序"
    - "CSR、异常和定时器中断测试通过"
    - "NN_DOTP4 随机结果与 Python 一致"
    - "NN_REQUANT 与 Python 一致"
    - "软件和 NN 点积结果一致"
    - "输出周期、退休指令和 NN 指令计数"
    - "小型 INT8 全连接层结果一致"
    - "Yosys 可读取并综合相关顶层"
    - "不包含 Xilinx 原语"
    - "具有完整 MicroZed/Vivado 后续文档"

final_report:
  sections:
    - "已在当前 macOS 实际验证"
    - "已实现但当前未验证"
    - "仅为 Ubuntu/Vivado/MicroZed 预留"
  prohibition:
    - "不得将 Yosys 结果描述为 XC7Z020 最终资源或时序"
    - "LUT/FF/BRAM/DSP/Fmax/bitstream 只能由后续 Vivado 确认"
```
