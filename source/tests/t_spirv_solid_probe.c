#include <assert.h>
#include <stdio.h>
#include "../runtime/gfx/kl_spirv_probe.h"
int main(void){uint32_t s[]={0x07230203,0x10000,0,10,0,(3u<<16)|15,4,8,(4u<<16)|71,4,30,0,(3u<<16)|22,1,32,(4u<<16)|23,2,1,4,(4u<<16)|32,3,3,2,(4u<<16)|59,3,4,3,(5u<<16)|54,5,8,0,6,(3u<<16)|62,4,7,(1u<<16)|56};size_t n=sizeof(s)/4,w=0;uint32_t*r=kl_spirv_solid_fragment(s,n,&w);assert(r&&w==n+15&&r[3]==13);int found=0;for(size_t i=5;i<w;i+=r[i]>>16)if((r[i]&65535)==62){assert(r[i+2]==12);found=1;}assert(found);free(r);s[6]=0;assert(!kl_spirv_solid_fragment(s,n,&w));s[0]=0;assert(!kl_spirv_solid_fragment(s,n,&w));puts("PASS: fragment-only color stores replaced; vertex and malformed modules untouched");}
