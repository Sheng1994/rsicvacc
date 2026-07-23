# Custom extension interface choice

The accelerator uses CORE-V-XIF because CV32E40X exposes it directly and it
keeps custom decode and execution outside the CPU RTL. Compared with modifying
the core pipeline, this preserves the upstream reference tree and provides
explicit issue, commit/kill, and result handshakes. Compared with a
memory-mapped accelerator, register-register operations avoid address decoding
and software load/store overhead.

The tradeoff is protocol state: an accepted request must retain its ID and
data, observe commit or kill, and keep a result stable under backpressure. The
current single-entry implementation makes these rules explicit before multiple
outstanding operations are introduced. It does not use XIF memory channels.
