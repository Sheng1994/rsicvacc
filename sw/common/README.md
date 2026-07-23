# Common runtime

`start.S` establishes the stack/global pointer and clears BSS. `linker.ld`
reserves address `0x1000` for the simulation mailbox and places writable data
from `0x2000`. `crt.c` translates `main()` return values into the mailbox
protocol defined by `mailbox.h`: value 1 is PASS; bit 31 set plus a nonzero
status is FAIL.
