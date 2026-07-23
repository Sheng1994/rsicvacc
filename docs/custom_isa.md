# Custom NN instruction encoding

All NN instructions use the standard R-type bit layout with the `custom-0`
opcode (`0001011`). Arithmetic and configuration operations use
`funct7=0000000`; counter reads use `funct7=0000001`.

| funct3 | Mnemonic | Operands | Status |
|---|---|---|---|
| 000 | NN_DOTP4 | rd, rs1, rs2 | Implemented |
| 001 | NN_RELU | rd, rs1 | Implemented |
| 010 | NN_CLIP8 | rd, rs1 | Implemented |
| 011 | NN_MAX4 | rd, rs1 | Implemented |
| 100 | NN_REQUANT | rd, rs1 | Implemented |
| 101 | NN_SET_MULTIPLIER | -, rs1 | Implemented configuration write |
| 110 | NN_SET_SHIFT | -, rs1 | Implemented configuration write |
| 111 | NN_SET_ZERO_POINT | -, rs1 | Implemented configuration write |

Read-only counter encodings return the low 32 bits in `rd`:

| funct7 | funct3 | Mnemonic |
|---|---|---|
| 0000001 | 000 | NN_READ_COUNT |
| 0000001 | 001 | NN_READ_DOTP4_COUNT |
| 0000001 | 010 | NN_READ_REQUANT_COUNT |

Other `funct7/funct3` combinations are rejected as illegal instructions.

## MAC array commands

The default array has four output rows and four INT8 lanes per row. It contains
four packed activation words, sixteen packed weight words, four signed 32-bit
accumulators, and a 64-bit MAC counter. Commands use `funct7=0000010`.

| funct3 | Mnemonic | Meaning |
|---|---|---|
| 000 | NN_ARRAY_LOAD_ACT | `rs1[1:0]` block; `rs2` has four INT8 activations |
| 001 | NN_ARRAY_LOAD_WEIGHT | `rs1[3:2]` row, `rs1[1:0]` block; `rs2` has four INT8 weights |
| 010 | NN_ARRAY_START | Clear accumulators and launch the four-cycle tile |
| 011 | NN_ARRAY_STATUS | Return `{done,busy}` in `rd[1:0]` |
| 100 | NN_ARRAY_READ | Return accumulator selected by `rs1[1:0]` |
| 101 | NN_ARRAY_CLEAR | Clear done, accumulators, and MAC counter |

State-changing commands take effect only after commit, so killed commands do
not modify array state. Each active cycle performs 4 rows x 4 lanes = 16 MACs;
a 16x4 fully-connected tile performs 64 MACs in four compute cycles. Bias and
requantization use software or the existing `NN_REQUANT` instruction.

`NN_DOTP4` treats each source register as four signed INT8 lanes. It multiplies
corresponding lanes and returns the exact signed 32-bit sum. It has no hidden
accumulator state. Any unknown `funct3`, nonzero `funct7`, or other custom
opcode is rejected by the coprocessor and traps as an illegal instruction.

The initial implementation uses the CV-X-IF issue, commit, and result channels.
It accepts one operation at a time, waits for commit, discards killed work, and
holds its result until the CPU asserts result ready. It does not use XIF memory
channels.

REQUANT uses a signed 32x32 multiply and a signed 64-bit intermediate. Shift is
restricted to the low five bits (0 through 31). Shift zero performs no rounding;
otherwise the magnitude is rounded to nearest with exact ties away from zero,
then the original sign is restored. A signed 32-bit zero point is added in 64
bits and the result is saturated to [-128, 127]. Configuration resets to
multiplier=1, shift=0, zero_point=0.

CV32E40X 0.10.0 has no generic custom-CSR channel on XIF. Therefore the three
configuration values are coprocessor-local registers written by funct3 101-111
rather than architectural `csrw` instructions. Configuration writes complete a
result handshake with integer write enable cleared so consecutive writes remain
ordered.
