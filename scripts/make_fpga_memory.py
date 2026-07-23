#!/usr/bin/env python3
"""Combine the RISC-V MNIST firmware/model/sample into one sparse BRAM image."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "build/mnist_fpga.memh"
regions = [
    (0x0000, root / "build/mnist_dma.memh"),
    (0x4000, root / "build/mnist/weights.memh"),
    (0x5f00, root / "build/mnist/bias.memh"),
    (0x6000, root / "build/mnist/sample.memh"),
]
lines = []
for address, source in regions:
    lines.append(f"@{address // 4:04x}")
    lines.extend(source.read_text(encoding="ascii").split())
# Default sample is MNIST test image 0, whose expected label is 7.  Batch hosts
# overwrite this word and the image window through BRAM port B while CPU reset
# is asserted.
lines.extend(["@17ff", "00000007"])
out.write_text("\n".join(lines) + "\n", encoding="ascii")
out.with_suffix(".mem").write_text(out.read_text(encoding="ascii"), encoding="ascii")
print(out)
