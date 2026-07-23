#ifndef RSICVACC_CUSTOM_NN_H
#define RSICVACC_CUSTOM_NN_H
#include <stdint.h>

static inline int32_t nn_dotp4(uint32_t a, uint32_t b) {
  int32_t out;
  __asm__ volatile (".insn r 0x0b, 0, 0, %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
  return out;
}
static inline int32_t nn_requant(int32_t value) {
  int32_t out;
  __asm__ volatile (".insn r 0x0b, 4, 0, %0, %1, x0" : "=r"(out) : "r"(value));
  return out;
}
static inline void nn_set_multiplier(int32_t value) {
  __asm__ volatile (".insn r 0x0b, 5, 0, x0, %0, x0" :: "r"(value));
}
static inline void nn_set_shift(uint32_t value) {
  __asm__ volatile (".insn r 0x0b, 6, 0, x0, %0, x0" :: "r"(value));
}
static inline void nn_set_zero_point(int32_t value) {
  __asm__ volatile (".insn r 0x0b, 7, 0, x0, %0, x0" :: "r"(value));
}
static inline uint32_t nn_read_count(void) {
  uint32_t out;
  __asm__ volatile (".insn r 0x0b, 0, 1, x10, x0, x0\n\tnop\n\tnop\n\tnop\n\tnop\n\tmv %0, x10"
                    : "=r"(out) :: "x10");
  return out;
}
static inline void nn_array_load_activation(uint32_t block, uint32_t packed) {
  __asm__ volatile (".insn r 0x0b, 0, 2, x0, %0, %1" :: "r"(block), "r"(packed));
}
static inline void nn_array_load_weight(uint32_t row, uint32_t block, uint32_t packed) {
  uint32_t address = (row << 2) | block;
  __asm__ volatile (".insn r 0x0b, 1, 2, x0, %0, %1" :: "r"(address), "r"(packed));
}
static inline void nn_array_start(void) {
  __asm__ volatile (".insn r 0x0b, 2, 2, x0, x0, x0");
}
static inline uint32_t nn_array_status(void) {
  uint32_t out;
  __asm__ volatile (".insn r 0x0b, 3, 2, %0, x0, x0" : "=r"(out));
  return out;
}
static inline int32_t nn_array_read(uint32_t row) {
  int32_t out;
  __asm__ volatile (".insn r 0x0b, 4, 2, %0, %1, x0" : "=r"(out) : "r"(row));
  return out;
}
static inline void nn_array_clear(void) {
  __asm__ volatile (".insn r 0x0b, 5, 2, x0, x0, x0");
}
#endif
