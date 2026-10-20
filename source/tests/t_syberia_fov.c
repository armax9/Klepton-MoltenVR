#include <stdint.h>
#include <stdio.h>
#include "kl_ovrp.h"
int main(void) {
 uint64_t(*get)(int*)=(void*)kl_ovrp_sym("ovrp_GetAppAsymmetricFov");
 uint64_t(*set)(int)=(void*)kl_ovrp_sym("ovrp_SetAppAsymmetricFov");
 if(!get||!set)return 2;
 struct {uint32_t before;int value;uint32_t after;} p={0x12345678,(int)0xa5a5a5a5,0x87654321};
 if(set(0)||get(&p.value)||p.value!=0||p.before!=0x12345678||p.after!=0x87654321)return 3;
 p.value=(int)0xa5a5a5a5;if(set(1)||get(&p.value)||p.value!=1)return 4;
 if((int32_t)get(NULL)!=-1001)return 5;
 puts("PASS: asymmetric FOV full 32-bit output, setter state, null and bounds");return 0;
}
