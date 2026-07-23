#include <stdint.h>
#include "custom_nn.h"

#define METRICS_ADDR 0x1040u
typedef struct {
  uint32_t sw_cycles, sw_instructions;
  uint32_t nn_cycles, nn_instructions;
  uint32_t expected_nn_custom_instructions;
  uint32_t sw_outputs, nn_outputs;
} metrics_t;

static const int8_t input[16] = {12,-7,3,25,-16,8,4,-2,19,-11,6,1,-5,14,-9,7};
static const int8_t weights[4][16] = {
  {2,-1,3,1,-2,2,0,1,-1,2,1,-3,2,1,-2,3},
  {-3,2,1,-1,2,-2,3,1,2,-1,2,1,-2,3,1,-1},
  {1,1,-2,3,1,0,-1,2,3,1,-3,2,1,-2,2,1},
  {2,-3,2,-2,1,3,1,-1,0,2,-1,3,-3,1,2,-2}
};
static const int32_t bias[4] = {10,-20,5,0};
static const int8_t expected[4] = {16,-4,5,-2};

static inline uint32_t rdcycle32(void) { uint32_t v; __asm__ volatile("csrr %0, mcycle":"=r"(v)); return v; }
static inline uint32_t rdinstret32(void) { uint32_t v; __asm__ volatile("csrr %0, minstret":"=r"(v)); return v; }
static uint32_t pack4(const int8_t *p) {
  return (uint32_t)(uint8_t)p[0] | ((uint32_t)(uint8_t)p[1] << 8) |
         ((uint32_t)(uint8_t)p[2] << 16) | ((uint32_t)(uint8_t)p[3] << 24);
}
static int8_t requant_ref(int32_t value) {
  int32_t mag = value < 0 ? -value : value;
  int32_t rounded = (mag + 4) >> 3;
  if (value < 0) rounded = -rounded;
  if (rounded > 127) return 127;
  if (rounded < -128) return -128;
  return (int8_t)rounded;
}
__attribute__((noinline)) static void fc_software(int8_t out[4]) {
  for (unsigned o=0;o<4;o++) {
    int32_t sum=bias[o];
    for (unsigned i=0;i<16;i++) sum+=(int32_t)input[i]*(int32_t)weights[o][i];
    out[o]=requant_ref(sum);
  }
}
__attribute__((noinline)) static void fc_nn(int8_t out[4]) {
  uint32_t packed_input[4];
  for (unsigned k=0;k<4;k++) packed_input[k]=pack4(&input[k*4]);
  for (unsigned o=0;o<4;o++) {
    int32_t sum=bias[o];
    for (unsigned k=0;k<4;k++) sum+=nn_dotp4(packed_input[k],pack4(&weights[o][k*4]));
    out[o]=(int8_t)nn_requant(sum);
  }
}
static uint32_t pack_outputs(const int8_t out[4]) { return pack4(out); }

int main(void) {
  int8_t sw_out[4], nn_out[4];
  volatile metrics_t *m=(volatile metrics_t *)(uintptr_t)METRICS_ADDR;
  uint32_t c0=rdcycle32(), i0=rdinstret32();
  fc_software(sw_out);
  uint32_t i1=rdinstret32(), c1=rdcycle32();
  nn_set_multiplier(1); nn_set_shift(3); nn_set_zero_point(0);
  uint32_t c2=rdcycle32(), i2=rdinstret32();
  fc_nn(nn_out);
  uint32_t i3=rdinstret32(), c3=rdcycle32();
  for(unsigned i=0;i<4;i++) if(sw_out[i]!=expected[i]||nn_out[i]!=expected[i]||sw_out[i]!=nn_out[i]) return (int)(10+i);
  m->sw_cycles=c1-c0; m->sw_instructions=i1-i0;
  m->nn_cycles=c3-c2; m->nn_instructions=i3-i2;
  m->expected_nn_custom_instructions=20;
  m->sw_outputs=pack_outputs(sw_out); m->nn_outputs=pack_outputs(nn_out);
  return 0;
}
