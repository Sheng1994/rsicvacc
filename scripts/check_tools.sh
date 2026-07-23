#!/usr/bin/env bash
set -u

missing_required=0

check_tool() {
  tool_name="$1"
  requirement="$2"
  version_arg="${3:---version}"
  if command -v "$tool_name" >/dev/null 2>&1; then
    tool_path="$(command -v "$tool_name")"
    if "$tool_name" "$version_arg" >/dev/null 2>&1; then
      printf 'FOUND    %-28s %s\n' "$tool_name" "$tool_path"
    else
      printf '%-9s%-28s %s\n' "$requirement" "$tool_name" "present at $tool_path but not runnable"
      if [ "$requirement" = "REQUIRED" ]; then
        missing_required=$((missing_required + 1))
      fi
    fi
  else
    printf '%-9s%-28s %s\n' "$requirement" "$tool_name" "not found"
    if [ "$requirement" = "REQUIRED" ]; then
      missing_required=$((missing_required + 1))
    fi
  fi
}

printf 'Host system\n'
printf '  OS:           %s\n' "$(uname -s)"
printf '  Architecture: %s\n' "$(uname -m)"
if command -v sw_vers >/dev/null 2>&1; then
  printf '  macOS:        %s\n' "$(sw_vers -productVersion)"
fi

printf '\nStage A tools\n'
check_tool python3 REQUIRED
check_tool make REQUIRED
check_tool verilator REQUIRED
check_tool yosys REQUIRED -V
check_tool iverilog OPTIONAL -V
check_tool brew OPTIONAL
check_tool cmake OPTIONAL
check_tool ninja OPTIONAL

printf '\nRISC-V toolchains (at least one RV32-multilib-capable prefix is needed later)\n'
check_tool riscv64-unknown-elf-gcc OPTIONAL
check_tool riscv32-unknown-elf-gcc OPTIONAL
check_tool riscv64-elf-gcc OPTIONAL

configured_gcc="${RISCV_PREFIX:-riscv64-unknown-elf-}gcc"
if command -v "$configured_gcc" >/dev/null 2>&1 && "$configured_gcc" --version >/dev/null 2>&1; then
  printf 'FOUND    %-28s %s\n' "configured: $configured_gcc" "$(command -v "$configured_gcc")"
else
  printf 'MISSING  %-28s %s\n' "configured: $configured_gcc" "not runnable"
fi

printf '\nRepository configuration\n'
printf '  RISCV_PREFIX: %s\n' "${RISCV_PREFIX:-riscv64-unknown-elf-}"
printf '  RISCV_ARCH:   %s\n' "${RISCV_ARCH:-rv32im_zicsr}"
printf '  RISCV_ABI:    %s\n' "${RISCV_ABI:-ilp32}"

if [ "$missing_required" -ne 0 ]; then
  printf '\nNOTICE: %s required Stage A tool(s) are missing. See docs/macos_setup.md.\n' "$missing_required"
  printf 'Tool discovery completed successfully; build targets that need missing tools will fail or skip explicitly.\n'
else
  printf '\nPASS: required Stage A host tools were found.\n'
fi
