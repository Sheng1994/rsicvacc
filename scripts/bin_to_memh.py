#!/usr/bin/env python3
import argparse
import pathlib


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert a binary to little-endian 32-bit readmemh words")
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    data = args.input.read_bytes()
    if len(data) % 4:
        data += bytes(4 - len(data) % 4)

    words = [data[index:index + 4] for index in range(0, len(data), 4)]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(f"{int.from_bytes(word, 'little'):08x}\n" for word in words),
        encoding="ascii",
    )


if __name__ == "__main__":
    main()
