#include <stdint.h>

static uint32_t initialized_data = 0x13579bdfu;
static uint32_t zero_initialized;

int main(void) {
  if (initialized_data != 0x13579bdfu) return 1;
  if (zero_initialized != 0u) return 2;

  zero_initialized = initialized_data ^ 0xffffffffu;
  if (zero_initialized != 0xeca86420u) return 3;
  return 0;
}
