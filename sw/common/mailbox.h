#ifndef RSICVACC_MAILBOX_H
#define RSICVACC_MAILBOX_H

#include <stdint.h>

#define MAILBOX_ADDR       0x00001000u
#define MAILBOX_PASS       0x00000001u
#define MAILBOX_FAIL_FLAG  0x80000000u

static inline void mailbox_write(uint32_t value) {
  *(volatile uint32_t *)(uintptr_t)MAILBOX_ADDR = value;
}

__attribute__((noreturn)) void _exit(int status);

#endif
