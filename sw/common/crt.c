#include "mailbox.h"

__attribute__((noreturn)) void _exit(int status) {
  uint32_t report = status == 0
      ? MAILBOX_PASS
      : MAILBOX_FAIL_FLAG | ((uint32_t)status & 0x7fffffffu);
  mailbox_write(report);
  for (;;) {
    __asm__ volatile ("wfi");
  }
}
