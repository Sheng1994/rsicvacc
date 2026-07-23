#!/usr/bin/env python3
import argparse
import random
from pathlib import Path


MASK32 = (1 << 32) - 1


def s32(value: int) -> int:
    value &= MASK32
    return value - (1 << 32) if value & (1 << 31) else value


def s8(value: int) -> int:
    value &= 0xFF
    return value - 256 if value & 0x80 else value


def model(op: int, rs1: int, rs2: int, multiplier: int, shift: int, zero_point: int) -> int:
    if op == 0:
        return sum(s8(rs1 >> (8 * i)) * s8(rs2 >> (8 * i)) for i in range(4)) & MASK32
    if op == 1:
        return (0 if s32(rs1) < 0 else rs1) & MASK32
    if op == 2:
        return max(-128, min(127, s32(rs1))) & MASK32
    if op == 3:
        return max(s8(rs1 >> (8 * i)) for i in range(4)) & MASK32
    if op == 4:
        wide = s32(rs1) * s32(multiplier)
        shift &= 31
        if shift:
            rounded_mag = (abs(wide) + (1 << (shift - 1))) >> shift
            rounded = -rounded_mag if wide < 0 else rounded_mag
        else:
            rounded = wide
        return max(-128, min(127, rounded + s32(zero_point))) & MASK32
    raise ValueError(op)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--per-op", type=int, default=1000)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    rows = []
    boundaries = [0, 1, MASK32, 0x7FFFFFFF, 0x80000000, 127, 128, (-128) & MASK32, (-129) & MASK32]
    for op in range(5):
        for index in range(args.per_op):
            rs1 = boundaries[index] if index < len(boundaries) else rng.getrandbits(32)
            rs2 = rng.getrandbits(32)
            multiplier = boundaries[(index + 3) % len(boundaries)] if index < len(boundaries) else rng.getrandbits(32)
            shift = index % 32 if index < 32 else rng.randrange(32)
            zero_point = boundaries[(index + 5) % len(boundaries)] if index < len(boundaries) else rng.getrandbits(32)
            expected = model(op, rs1, rs2, multiplier, shift, zero_point)
            rows.append(f"{op:x} {rs1:08x} {rs2:08x} {multiplier:08x} {shift:02x} {zero_point:08x} {expected:08x}\n")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(rows), encoding="ascii")


if __name__ == "__main__":
    main()
