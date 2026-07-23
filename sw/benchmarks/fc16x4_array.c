#include <stdint.h>
#include "custom_nn.h"

static volatile uint32_t *const metrics = (volatile uint32_t *)0x1060u;

static uint32_t pack4(const int8_t *p) {
  return (uint32_t)(uint8_t)p[0] | ((uint32_t)(uint8_t)p[1] << 8) |
         ((uint32_t)(uint8_t)p[2] << 16) | ((uint32_t)(uint8_t)p[3] << 24);
}

int main(void) {
  static const int8_t input[16] = {12,-7,3,25,-16,8,4,-2,19,-11,6,1,-5,14,-9,7};
  static const int8_t weights[4][16] = {
    {2,-1,3,1,-2,2,0,1,-1,2,1,-3,2,1,-2,3},
    {-3,2,1,-1,2,-2,3,1,2,-1,2,1,-2,3,1,-1},
    {1,1,-2,3,1,0,-1,2,3,1,-3,2,1,-2,2,1},
    {2,-3,2,-2,1,3,1,-1,0,2,-1,3,-3,1,2,-2}
  };
  static const int32_t bias[4] = {10,-20,5,0};
  static const int32_t expected_dot[4] = {116,-12,36,-13};
  nn_array_clear();
  for (uint32_t b=0;b<4;b++) nn_array_load_activation(b, pack4(&input[b*4]));
  for (uint32_t r=0;r<4;r++)
    for (uint32_t b=0;b<4;b++) nn_array_load_weight(r,b,pack4(&weights[r][b*4]));
  nn_array_start();
  while ((nn_array_status() & 2u) == 0u) { }
  uint32_t packed = 0;
  for (uint32_t r=0;r<4;r++) {
    int32_t value = nn_array_read(r);
    metrics[r] = (uint32_t)value;
    if (value != expected_dot[r]) return (int)(20+r);
    value += bias[r];
    int32_t q = value >= 0 ? (value + 4) >> 3 : -(((-value) + 4) >> 3);
    if (q > 127) q=127; else if (q < -128) q=-128;
    packed |= (uint32_t)(uint8_t)q << (8*r);
  }
  metrics[4] = packed;
  return packed == 0xfe05fc10u ? 0 : 30;
}
