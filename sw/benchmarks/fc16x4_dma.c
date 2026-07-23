#include <stdint.h>
#define DMA_BASE 0xF000u
#define REG32(o) (*(volatile uint32_t *)(DMA_BASE+(o)))
static volatile uint32_t *const metrics=(volatile uint32_t *)0x1080u;
static int8_t input[16]={12,-7,3,25,-16,8,4,-2,19,-11,6,1,-5,14,-9,7};
static int8_t weights[4][16]={
 {2,-1,3,1,-2,2,0,1,-1,2,1,-3,2,1,-2,3},
 {-3,2,1,-1,2,-2,3,1,2,-1,2,1,-2,3,1,-1},
 {1,1,-2,3,1,0,-1,2,3,1,-3,2,1,-2,2,1},
 {2,-3,2,-2,1,3,1,-1,0,2,-1,3,-3,1,2,-2}};
static int32_t bias[4]={10,-20,5,0};
static uint32_t tile[20] __attribute__((aligned(16)));
static inline uint32_t cycle(void){uint32_t x;__asm__ volatile("csrr %0,mcycle":"=r"(x));return x;}
static uint32_t pack4(const int8_t*p){return(uint8_t)p[0]|((uint32_t)(uint8_t)p[1]<<8)|
 ((uint32_t)(uint8_t)p[2]<<16)|((uint32_t)(uint8_t)p[3]<<24);}
static int8_t quant(int32_t x){int32_t m=x<0?-x:x;m=(m+4)>>3;if(x<0)m=-m;
 if(m>127)m=127;if(m< -128)m=-128;return(int8_t)m;}
static uint32_t software(void){uint32_t out=0;for(unsigned r=0;r<4;r++){int32_t s=bias[r];
 for(unsigned k=0;k<16;k++)s+=(int32_t)input[k]*weights[r][k];out|=(uint32_t)(uint8_t)quant(s)<<(8*r);}return out;}
int main(void){
 for(unsigned b=0;b<4;b++)tile[b]=pack4(&input[b*4]);
 for(unsigned r=0;r<4;r++)for(unsigned b=0;b<4;b++)tile[4+r*4+b]=pack4(&weights[r][b*4]);
 uint32_t c0=cycle(),sw=software(),c1=cycle();
 uint32_t d0=cycle();REG32(0x00)=(uint32_t)(uintptr_t)tile;REG32(0x04)=1;
 while(!(REG32(0x08)&2u)){} if(REG32(0x08)&4u)return 40;
 REG32(0x04)=4;while(!(REG32(0x08)&16u)){}
 uint32_t dma=0;for(unsigned r=0;r<4;r++){int32_t s=(int32_t)REG32(0x10+4*r)+bias[r];
 dma|=(uint32_t)(uint8_t)quant(s)<<(8*r);}uint32_t d1=cycle();
 metrics[0]=c1-c0;metrics[1]=d1-d0;metrics[2]=sw;metrics[3]=dma;metrics[4]=REG32(0x20);
 return(sw==0xfe05fc10u&&dma==sw&&metrics[4]==64)?0:41;
}
