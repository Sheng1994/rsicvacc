# NN configuration and counter map

The current CV-X-IF implementation does not modify the upstream CV32E40X CSR
block. Its requantization configuration is local to the coprocessor:

| Name | Width | Reset | Write mechanism |
|---|---:|---:|---|
| NN_MULTIPLIER | 32 signed | 1 | NN_SET_MULTIPLIER |
| NN_SHIFT | 5 unsigned | 0 | NN_SET_SHIFT (low five bits) |
| NN_ZERO_POINT | 32 signed | 0 | NN_SET_ZERO_POINT |

The coprocessor implements three 64-bit commit-level counters. Their complete
values are exposed from the subsystem, while custom read instructions return
their low 32 bits:

| Counter | Increment rule |
|---|---|
| nn_instruction_count | Successfully committed arithmetic NN instruction |
| nn_dotp4_count | Successfully committed NN_DOTP4 |
| nn_requant_count | Successfully committed NN_REQUANT |

Killed operations, rejected encodings, configuration writes, and counter reads
do not increment these counters. Reset clears all counters. Standard `mcycle`
remains available from the CPU. The other aspirational counters in the original
guidance are not implemented yet.
